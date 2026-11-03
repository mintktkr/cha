// sys, JS side: the same dial, recv, clock and terminal calls as the C side. libc comes
// through bun:ffi, and io_sys already has the socket calls. The dial blocks the loop while
// it resolves and connects, which this lane allows; recv parks with io_park_on.

// libc through bun:ffi, bound once. getaddrinfo's addrinfo is read field by field; the mac
// layout puts ai_canonname before ai_addr.
function chaki_sys_ffi() {
  if (globalThis.CHAKI_SYS_FFI === undefined) {
    const ffi = require("bun:ffi");
    const mac = process.platform === "darwin";
    const T = { i: "i32", u: "u32", U: "u64", I: "i64", p: "ptr", c: "cstring",
      v: "void" };
    const calls = "getaddrinfo:ccpp>i freeaddrinfo:p>v gai_strerror:i>c"
      + " isatty:i>i ioctl:iUp>i poll:pUi>i";
    const defs = {};
    for (const s of calls.split(" ")) {
      const [name, args, ret] = s.split(/[:>]/);
      defs[name] = { args: [...args].map((a) => T[a]), returns: T[ret] };
    }
    globalThis.CHAKI_SYS_FFI = {
      ffi,
      lib: ffi.dlopen(mac ? "libSystem.dylib" : "libc.so.6", defs).symbols,
      mac
    };
  }
  return globalThis.CHAKI_SYS_FFI;
}

// a failure with our own text, the shape io_fail builds from a code and strerror
function chaki_sys_fail(code, text) {
  return { $: "Fail", error: { $: "Tuple", fst: code >>> 0, snd: String(text) } };
}

// libc wants a NUL-terminated C string, and this lane's ffi takes a buffer for one
function chaki_sys_cstr(text) {
  const raw = new TextEncoder().encode(text);
  const out = new Uint8Array(raw.length + 1);
  out.set(raw);
  return out;
}

// the order to try: getaddrinfo's answer with its families alternating, so a black-holed
// v6 address costs at most its share before the v4 one gets its turn (RFC 8305 4). Each
// family keeps the order getaddrinfo gave it, the first address's family leads, and a third
// family counts as the other.
function chaki_sys_plan(ffi, first, family) {
  const same = [];
  const other = [];
  for (let ai = first; ai !== 0; ai = Number(ffi.read.u64(ai, 40))) {
    (ffi.read.i32(ai, 4) === family ? same : other).push(ai);
  }
  const plan = [];
  let a = 0;
  let b = 0;
  while (plan.length < same.length + other.length) {
    if (a < same.length) {
      plan.push(same[a++]);
    }
    if (b < other.length) {
      plan.push(other[b++]);
    }
  }
  return plan;
}

// poll the fd until it is writable or its share of the dial passes; SO_ERROR then says how
// the connect ended. 0 when it connected, else an errno.
function chaki_sys_wait(fd, share) {
  const { ffi, lib, mac } = chaki_sys_ffi();
  const sys = io_sys();
  if (share <= 0) {
    return mac ? 60 : 110;
  }
  const fds = new Int32Array([fd, 4, 0]);
  const n = lib.poll(ffi.ptr(fds), 1, share);
  if (n === 0) {
    return mac ? 60 : 110;
  }
  if (n < 0) {
    return sys.errno();
  }
  const err = new Int32Array([0]);
  const len = new Uint32Array([4]);
  sys.getsockopt(fd, mac ? 0xffff : 1, mac ? 0x1007 : 4, sys.ptr(err), sys.ptr(len));
  return err[0] === 0 ? 0 : err[0];
}

// resolve with getaddrinfo (AF_UNSPEC), reorder its answer so the families alternate, then
// a non-blocking connect per address, each waited on for its fair share of what is left of
// the dial, so no one address can eat another family's turn. The loop is blocked while it
// waits: this lane allows that, and the fd comes back non-blocking.
function chaki_sys_dial(host, port, ms, k) {
  const { ffi, lib, mac } = chaki_sys_ffi();
  const sys = io_sys();
  const at = performance.now() + Number(ms);
  const hints = new Uint8Array(48);
  const dv = new DataView(hints.buffer);
  dv.setInt32(4, 0, true); // AF_UNSPEC
  dv.setInt32(8, 1, true); // SOCK_STREAM
  const res = new BigUint64Array(1);
  const name = chaki_sys_cstr(host);
  const service = chaki_sys_cstr(String(Number(port)));
  const rc = lib.getaddrinfo(ffi.ptr(name), ffi.ptr(service), ffi.ptr(hints),
    ffi.ptr(res));
  if (rc !== 0) {
    return chaki_sys_fail(rc, host + ": " + lib.gai_strerror(rc));
  }
  const head = Number(res[0]);
  const plan = head === 0 ? [] : chaki_sys_plan(ffi, head, ffi.read.i32(head, 4));
  let last = 0;
  for (let i = 0; i < plan.length; i += 1) {
    const ai = plan[i];
    const family = ffi.read.i32(ai, 4);
    const socktype = ffi.read.i32(ai, 8);
    const protocol = ffi.read.i32(ai, 12);
    const addrlen = ffi.read.u32(ai, 16);
    const addr = Number(ffi.read.u64(ai, mac ? 32 : 24));
    const share = Math.max(0,
      Math.floor((at - performance.now()) / (plan.length - i)));
    const fd = sys.socket(family, socktype, protocol);
    if (fd < 0) {
      last = sys.errno();
      continue;
    }
    if (sys.fcntl(fd, 4, sys.fcntl(fd, 3, 0) | (mac ? 4 : 0x800)) < 0) {
      last = sys.errno();
      sys.close(fd);
      continue;
    }
    let code = sys.connect(fd, addr, addrlen) < 0 ? sys.errno() : 0;
    if (code === (mac ? 36 : 115)) {
      code = chaki_sys_wait(fd, share);
    }
    if (code === 0) {
      lib.freeaddrinfo(head);
      return io_done(fd);
    }
    last = code;
    sys.close(fd);
  }
  lib.freeaddrinfo(head);
  return io_fail(last !== 0 ? last : mac ? 60 : 110);
}

// a recv that finds nothing (the fd is non-blocking) parks on the socket and on the
// deadline, whichever comes first. 0 bytes is Done{[]}, the peer's close.
function chaki_sys_recv_go(sock, max, at, k) {
  const { mac } = chaki_sys_ffi();
  const sys = io_sys();
  const b = new Uint8Array(max);
  const n = Number(sys.recv(sock, sys.ptr(b), max, 0));
  if (n >= 0) {
    return io_tup(sock, io_done(io_list(b, n)));
  }
  const code = sys.errno();
  if (code !== (mac ? 35 : 11) && code !== 4) {
    return io_tup(sock, io_fail(code));
  }
  if (performance.now() >= at) {
    return io_tup(sock, io_fail(mac ? 60 : 110));
  }
  io_park_on(sock, false, k, () => chaki_sys_recv_go(sock, max, at, k), at);
  return undefined;
}

function chaki_sys_recv(sock, max, ms, k) {
  if (Number(max) === 0) {
    return io_tup(sock, io_fail(22));
  }
  return chaki_sys_recv_go(sock, Number(max), performance.now() + Number(ms), k);
}

function chaki_sys_now() {
  return Math.floor(Date.now() / 1000) >>> 0;
}

function chaki_sys_isatty(fd) {
  return chaki_sys_ffi().lib.isatty(Number(fd)) > 0 ? 1 : 0;
}

function chaki_sys_cols() {
  const { ffi, lib, mac } = chaki_sys_ffi();
  const ws = new Uint16Array(4);
  const rc = lib.ioctl(1, mac ? 0x40087468 : 0x5413, ffi.ptr(ws));
  return rc === 0 ? ws[1] : 0;
}

function chaki_sys_rows() {
  const { ffi, lib, mac } = chaki_sys_ffi();
  const ws = new Uint16Array(4);
  const rc = lib.ioctl(1, mac ? 0x40087468 : 0x5413, ffi.ptr(ws));
  return rc === 0 ? ws[0] : 0;
}

io_eff(CID(dial), chaki_sys_dial);
io_eff(CID(recv), chaki_sys_recv);
io_eff(CID(now), chaki_sys_now);
io_eff(CID(isatty.raw), chaki_sys_isatty);
io_eff(CID(cols), chaki_sys_cols);
io_eff(CID(rows), chaki_sys_rows);
