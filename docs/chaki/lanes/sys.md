# lane: sys

The only foreign code in chaki besides `ossl`: sockets with name resolution and deadlines,
the wall clock, and the terminal. Mongoose's OS layer is the model: thin, one file per side.

## Files you own

`lib/chaki/sys.bend`, `lib/chaki/effs/sys.c`, `lib/chaki/effs/sys.js`,
`test/chaki_sys_check.bend`, `test/chaki_sys_live.bend`.

## API (exact)

```python
# a TCP connection to host:port. host is a name or an IPv4/IPv6 literal; every address
# getaddrinfo answers (AF_UNSPEC, in its order) is tried until one connects. ms bounds the
# whole dial. The Socket is Base's, non-blocking, so Base's TCP effects and Socket.close
# work on it too.
def dial(host: String, port: U32, ms: U32) -> IO(Result<&1, &1, U32 & String, Socket>)

# up to max bytes, waiting at most ms. Done{[]} means the peer closed. A miss is
# Fail{(ETIMEDOUT, ..)}.
def recv(sock: Socket, max: U32, ms: U32) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>)

# all of data, or a failure
def send(sock: Socket, data: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, Unit>)

# Unix time in seconds (wall clock, not monotonic)
def now() -> IO(U32)

# whether fd (0, 1, 2) is a terminal
def isatty(fd: U32) -> IO(Bool)

# the terminal's columns on stdout, 0 when it isn't a terminal or won't say
def cols() -> IO(U32)
```

An effect def's body can only be the two imports, so where a public def needs Bend logic
(for example turning a U32 into a Bool), make the effect a private def (`isatty.raw`) and
wrap it. `send` may simply be Base's `TCP.send_bytes` if that already sends everything;
check `~/.bend/bend2/effs/tcp_send.{c,js}` and say which in your report.

## How

- Read `~/.bend/guide/EFFECTS.md` and Base's own socket effects in `~/.bend/bend2/effs/`
  (`tcp_connect`, `tcp_recv`, `tcp_send`, `now`) first. Your C and JS sockets must be the same
  kind of handle Base uses (a file descriptor), so Base's effects keep working on them.
- C, dial: getaddrinfo blocks, so run the whole dial on a helper thread with `io_work`
  (getaddrinfo, then a non-blocking connect per address waited on with `poll` up to what's
  left of the deadline), and set `O_NONBLOCK` on the fd you hand back. Free everything on
  every path.
- C, recv: `io_wait_on(w, fd, POLLIN, deadline, more)` with an absolute `io_tick()` deadline.
- JS: `io_sys()` gives libc through bun:ffi. Resolve with getaddrinfo through bun:ffi
  (`dlopen` libc.so.6, or libSystem.dylib on macOS). Blocking the loop during a dial is
  acceptable on the JS lane. recv parks with `io_park_on(fd, false, k, more, deadline)`.
- Errors carry `(errno, text)`. A resolve failure says `<host>: <gai_strerror text>`.
- Write it yourself from the guides, man pages and Base's effects. Don't copy any hub package.

## Checks

`test/chaki_sys_check.bend` (offline):

- Base `TCP.listen("127.0.0.1", port)` plus an `IO.fork` that accepts. Then:
  - `dial("localhost", port, 2000)` connects, even if localhost answers ::1 first.
  - an echo: send the bytes 0..255 (not valid UTF-8), and they come back identical through `recv`.
  - `recv` on a connection where the server sends nothing fails with ETIMEDOUT after
    about the deadline (300 ms).
  - `recv` after the server closes answers `Done{[]}`.
- `dial("127.0.0.1", <a closed port>, 1000)` fails fast with ECONNREFUSED.
- `dial("no-such-host.invalid", 80, 2000)` fails, and the text names the host.
- `now()` is between 1790000000 and 2000000000.
- `isatty(99)` is false.

`test/chaki_sys_live.bend` (by hand): dial example.com:80, send `GET / HTTP/1.0\r\nHost:
example.com\r\n\r\n`, read until close; the reply starts with `HTTP/1.`.

Both must pass on the JS lane and natively. `./out/x` runs the native binary
in a container with host networking.
