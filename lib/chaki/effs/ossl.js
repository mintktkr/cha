// Ossl
// ====
// JS twin of ossl.c: the same OpenSSL 3 calls, through bun:ffi, parking the computation
// on the socket while OpenSSL wants more of it.

const OSSL_TLS1_2 = 0x0303;
const OSSL_MIN_PROTO = 123; // SSL_CTRL_SET_MIN_PROTO_VERSION
const OSSL_SNI = 55; // SSL_CTRL_SET_TLSEXT_HOSTNAME
const OSSL_SNI_HOST = 0; // TLSEXT_NAMETYPE_host_name
const OSSL_PEER = 1; // SSL_VERIFY_PEER
const OSSL_OK = 0; // X509_V_OK
const OSSL_E_SSL = 1;
const OSSL_E_WANT_READ = 2;
const OSSL_E_WANT_WRITE = 3;
const OSSL_E_SYSCALL = 5;
const OSSL_E_ZERO_RETURN = 6;
const OSSL_EOF_REASON = 294; // SSL_R_UNEXPECTED_EOF_WHILE_READING
const OSSL_EPROTO = process.platform === "darwin" ? 100 : 71;
const OSSL_EALREADY = process.platform === "darwin" ? 37 : 114;
const OSSL_ALPN = Uint8Array.of(8, 104, 116, 116, 112, 47, 49, 46, 49); // "\x08http/1.1"

// libssl 3 (CHAKI_LIBSSL overrides its path) and its context; null when it does not
// load. dlopen resolves every symbol at once, so a loaded library is a whole one.
function ossl_lib() {
  const cache = (globalThis.CHAKI_OSSL ??= { state: undefined });
  if (cache.state !== undefined) {
    return cache.state;
  }
  cache.state = null;
  const ffi = require("bun:ffi");
  const syms = {
    TLS_client_method: { args: [], returns: "ptr" },
    SSL_CTX_new: { args: ["ptr"], returns: "ptr" },
    SSL_CTX_set_default_verify_paths: { args: ["ptr"], returns: "i32" },
    SSL_CTX_ctrl: { args: ["ptr", "i32", "i64", "ptr"], returns: "i64" },
    SSL_CTX_set_verify: { args: ["ptr", "i32", "ptr"], returns: "void" },
    SSL_CTX_free: { args: ["ptr"], returns: "void" },
    SSL_new: { args: ["ptr"], returns: "ptr" },
    SSL_set_fd: { args: ["ptr", "i32"], returns: "i32" },
    SSL_set1_host: { args: ["ptr", "cstring"], returns: "i32" },
    SSL_ctrl: { args: ["ptr", "i32", "i64", "ptr"], returns: "i64" },
    SSL_set_alpn_protos: { args: ["ptr", "ptr", "u32"], returns: "i32" },
    SSL_connect: { args: ["ptr"], returns: "i32" },
    SSL_get_error: { args: ["ptr", "i32"], returns: "i32" },
    SSL_get_verify_result: { args: ["ptr"], returns: "i64" },
    X509_verify_cert_error_string: { args: ["i64"], returns: "cstring" },
    ERR_peek_last_error: { args: [], returns: "u64" },
    ERR_get_error: { args: [], returns: "u64" },
    ERR_error_string_n: { args: ["u64", "ptr", "u64"], returns: "void" },
    SSL_read: { args: ["ptr", "ptr", "i32"], returns: "i32" },
    SSL_write: { args: ["ptr", "ptr", "i32"], returns: "i32" },
    SSL_shutdown: { args: ["ptr"], returns: "i32" },
    SSL_free: { args: ["ptr"], returns: "void" },
  };
  for (const p of [process.env.CHAKI_LIBSSL, "libssl.so.3", "libssl.3.dylib",
    "/opt/homebrew/lib/libssl.3.dylib", "/usr/local/lib/libssl.3.dylib", "/usr/lib/libssl.so.3"]) {
    if (!p) {
      continue;
    }
    try {
      cache.state = { s: ffi.dlopen(p, syms).symbols, ffi };
      return cache.state;
    } catch {
      continue;
    }
  }
  return null;
}

// The system's trust store, a peer certificate that must verify, and TLS 1.2 as the
// floor. A half-built context is dropped, so the next call tries again.
function ossl_ctx() {
  const lib = ossl_lib();
  if (lib === null) {
    return null;
  }
  if (lib.ctx === undefined) {
    lib.ctx = null;
    const { s } = lib;
    const ctx = s.SSL_CTX_new(s.TLS_client_method());
    if (ctx) {
      s.SSL_CTX_set_verify(ctx, OSSL_PEER, null);
      if (s.SSL_CTX_set_default_verify_paths(ctx)
        && Number(s.SSL_CTX_ctrl(ctx, OSSL_MIN_PROTO, OSSL_TLS1_2, null)) > 0) {
        lib.ctx = ctx;
      } else {
        s.SSL_CTX_free(ctx);
      }
    }
  }
  return lib.ctx;
}

// One session per connected socket.
function ossl_socks() {
  return (globalThis.CHAKI_OSSL_SOCKS ??= new Map());
}

// The socket, then the failure: a Result's error is an errno with its text.
function ossl_fail(sock, code, why) {
  return io_tup(sock, why === undefined ? io_fail(code)
    : { $: CID(Fail), error: io_tup(code, why) });
}

// The error queue's oldest entry, as text, and the queue emptied. OpenSSL's own words:
// never key material.
function ossl_ssl_text(lib) {
  const { s, ffi } = lib;
  const er = s.ERR_get_error();
  const buf = Buffer.alloc(256);
  s.ERR_error_string_n(er, ffi.ptr(buf), 256);
  while (Number(s.ERR_get_error()) !== 0) {
  }
  return buf.toString().replace(/\0.*/, "");
}

// Why the peer's certificate did not verify (expired, wrong host, unknown issuer), or
// null when it did.
function ossl_verify_why(lib, ssl) {
  const v = Number(lib.s.SSL_get_verify_result(ssl));
  return v === OSSL_OK ? null : lib.s.X509_verify_cert_error_string(BigInt(v)).toString();
}

// The text for a failed TLS call: the chain's reason when it did not verify, else the
// error queue's, else the socket's errno for a syscall one.
function ossl_why(lib, ssl, err) {
  const why = ossl_verify_why(lib, ssl);
  if (why !== null) {
    return "certificate verify failed: " + why;
  }
  if (err === OSSL_E_SYSCALL) {
    const sys = io_sys();
    return sys.errno() !== 0 ? "socket error " + sys.errno() : ossl_ssl_text(lib);
  }
  return ossl_ssl_text(lib);
}

// The errno an effect reports: the deadline when the wait ran out, EPROTO for anything
// else a TLS call can answer.
function ossl_code(err, ran_out) {
  return ran_out ? (io_sys().mac ? 60 : 110) : OSSL_EPROTO;
}

// OpenSSL 3 answers a peer that closed without close_notify with a TLS error whose last
// entry says unexpected EOF. TLS cannot tell that from a truncated stream; a client that
// has read what it asked for has to accept it as the end.
function ossl_eof(lib) {
  const er = lib.s.ERR_peek_last_error();
  return Number(er) !== 0 && Number(er & 0x7fffffn) === OSSL_EOF_REASON;
}

function ossl_available() {
  return ossl_ctx() !== null;
}

function ossl_connect(sock, host, ms, k) {
  const lib = ossl_lib();
  const ctx = lib === null ? null : ossl_ctx();
  if (ctx === null) {
    return ossl_fail(sock, 2, "libssl 3 did not load; set CHAKI_LIBSSL to its path");
  }
  const { s, ffi } = lib;
  const fd = sock;
  const at = performance.now() + Number(ms);
  if (ossl_socks().has(fd)) {
    return ossl_fail(sock, OSSL_EALREADY, "this socket already has a TLS session");
  }
  const ssl = s.SSL_new(ctx);
  if (!ssl) {
    return ossl_fail(sock, 12, "SSL_new failed");
  }
  ossl_socks().set(fd, ssl);
  const drop = (code, why) => {
    ossl_socks().delete(fd);
    s.SSL_free(ssl);
    return ossl_fail(sock, code, why);
  };
  // The host is read before the call returns, so these copies are only alive for it.
  const name = Buffer.from(host + "\0");
  const set = s.SSL_set_fd(ssl, fd) === 1 && s.SSL_set1_host(ssl, name) === 1
    && Number(s.SSL_ctrl(ssl, OSSL_SNI, OSSL_SNI_HOST, ffi.ptr(name))) === 1
    && s.SSL_set_alpn_protos(ssl, ffi.ptr(OSSL_ALPN), OSSL_ALPN.length) === 0;
  if (!set) {
    return drop(OSSL_EPROTO, ossl_ssl_text(lib));
  }
  const go = () => {
    const rc = s.SSL_connect(ssl);
    if (rc === 1) {
      const why = ossl_verify_why(lib, ssl);
      return why === null ? io_tup(sock, io_done({ $: CID(Unit) }))
        : drop(OSSL_EPROTO, "certificate verify failed: " + why);
    }
    const err = s.SSL_get_error(ssl, rc);
    if ((err === OSSL_E_WANT_READ || err === OSSL_E_WANT_WRITE) && performance.now() < at) {
      io_park_on(fd, err === OSSL_E_WANT_WRITE, k, go, at);
      return undefined;
    }
    return drop(ossl_code(err, err === OSSL_E_WANT_READ || err === OSSL_E_WANT_WRITE),
      ossl_why(lib, ssl, err));
  };
  return go();
}

function ossl_send(sock, data, k) {
  const lib = ossl_lib();
  const ssl = lib === null ? undefined : ossl_socks().get(sock);
  if (ssl === undefined) {
    return ossl_fail(sock, 9, "this socket has no TLS session");
  }
  const { s, ffi } = lib;
  const fd = sock;
  // A byte past 255 fails with EINVAL before anything is sent.
  const b = io_unlist(data);
  if (b === null) {
    return ossl_fail(sock, 22);
  }
  const go = (at) => {
    while (at < b.length) {
      const n = s.SSL_write(ssl, ffi.ptr(b.subarray(at)), b.length - at);
      if (n > 0) {
        at += n;
        continue;
      }
      const err = s.SSL_get_error(ssl, n);
      if (err !== OSSL_E_WANT_READ && err !== OSSL_E_WANT_WRITE) {
        return ossl_fail(sock, OSSL_EPROTO, ossl_why(lib, ssl, err));
      }
      io_park_on(fd, err === OSSL_E_WANT_WRITE, k, () => go(at));
      return undefined;
    }
    return io_tup(sock, io_done({ $: CID(Unit) }));
  };
  return go(0);
}

function ossl_recv(sock, max, ms, k) {
  const lib = ossl_lib();
  // A max of 0 fails with EINVAL before the socket is looked at.
  if (Number(max) === 0) {
    return ossl_fail(sock, 22);
  }
  const ssl = lib === null ? undefined : ossl_socks().get(sock);
  if (ssl === undefined) {
    return ossl_fail(sock, 9, "this socket has no TLS session");
  }
  const { s, ffi } = lib;
  const fd = sock;
  const b = new Uint8Array(Number(max));
  const at = performance.now() + Number(ms);
  const go = () => {
    const n = s.SSL_read(ssl, ffi.ptr(b), Number(max));
    if (n > 0) {
      return io_tup(sock, io_done(io_list(b, n)));
    }
    const err = s.SSL_get_error(ssl, n);
    if (err === OSSL_E_ZERO_RETURN || ossl_eof(lib)) {
      return io_tup(sock, io_done(io_list(b, 0)));
    }
    if (err !== OSSL_E_WANT_READ && err !== OSSL_E_WANT_WRITE) {
      return ossl_fail(sock, OSSL_EPROTO, ossl_why(lib, ssl, err));
    }
    if (performance.now() >= at) {
      return ossl_fail(sock, ossl_code(err, true), "the wait ran out");
    }
    io_park_on(fd, err === OSSL_E_WANT_WRITE, k, go, at);
    return undefined;
  };
  return go();
}

function ossl_close(sock) {
  const lib = ossl_lib();
  const ssl = lib === null ? undefined : ossl_socks().get(sock);
  if (ssl !== undefined) {
    ossl_socks().delete(sock);
    // The peer's answering close_notify is not waited for.
    lib.s.SSL_shutdown(ssl);
    lib.s.SSL_free(ssl);
  }
  io_sys().close(sock);
  return { $: CID(Unit) };
}

io_eff(CID(available), ossl_available);
io_eff(CID(connect), ossl_connect);
io_eff(CID(send), ossl_send);
io_eff(CID(recv), ossl_recv);
io_eff(CID(close), ossl_close);
