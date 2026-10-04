# lane: ossl

TLS through the system's OpenSSL 3, loaded with dlopen at run time, so the binary links
nothing extra. This is chaki's fallback transport, and today's safety net while the pure
Bend TLS (`tls.bend`) matures. It is a small, careful effect, not a framework.

## Files you own

`lib/chaki/ossl.bend`, `lib/chaki/effs/ossl.c`, `lib/chaki/effs/ossl.js`,
`test/chaki_ossl_check.bend`, `test/chaki_ossl_live.bend`.

## API (exact)

```python
# whether libssl 3 loads (CHAKI_LIBSSL overrides its path)
def available() -> IO(Bool)

# a TLS client handshake on a connected socket. Always verifies the chain against the
# system's trust store and the certificate against host, sends SNI, offers ALPN
# "http/1.1" only, and refuses anything below TLS 1.2. ms bounds the handshake.
def connect(sock: Socket, host: String, ms: U32) -> IO(Socket & Result<&1, &1, U32 & String, Unit>)

def send(sock: Socket, data: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, Unit>)

# up to max plaintext bytes, waiting at most ms. Done{[]} once the peer closed (close_notify
# or a clean EOF after one).
def recv(sock: Socket, max: U32, ms: U32) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>)

# close_notify, free the session, close the socket
def close(sock: Socket) -> IO(Unit)
```

## How

- Read `~/.bend/guide/EFFECTS.md` and Base's socket effects in `~/.bend/bend2/effs/`. The
  socket is Base's non-blocking fd. Keep the SSL object in a table keyed by fd (a static
  array in C, a Map in JS).
- C: `dlopen` libssl.so.3 (libssl.3.dylib on macOS, or `$CHAKI_LIBSSL`), `dlsym` only the
  functions you use. Use `TLS_client_method`, `SSL_CTX_set_default_verify_paths`,
  `SSL_CTX_set_verify(SSL_VERIFY_PEER)`, min proto TLS1_2 (via `SSL_CTX_ctrl`, since the
  macro isn't a symbol), `SSL_set1_host`, SNI (`SSL_ctrl` with
  `SSL_CTRL_SET_TLSEXT_HOSTNAME`), and `SSL_set_alpn_protos`. On WANT_READ/WANT_WRITE, park
  with `io_wait_on` until the fd is ready, with the deadline. After a handshake, check
  `SSL_get_verify_result` is X509_V_OK. An error names the verify failure
  (`X509_verify_cert_error_string`), never key material.
- JS: the same calls through bun:ffi, parking with `io_park_on`.
- Write it yourself from OpenSSL's man pages. Don't copy any hub package's effects.

## Checks

`test/chaki_ossl_check.bend` (offline): `available()` is true here. Then connect to a local
plain-TCP listener that answers garbage, and the handshake fails cleanly with an error, not a
crash or a hang.

`test/chaki_ossl_live.bend` (by hand, but run it and report): to get a socket, resolve with
`Process.run("getent", ["ahostsv4", host], ..)` and Base `TCP.connect` (the `sys` lane's
`dial` lands later; leave a comment saying so).

- example.com:443: handshake, `GET / HTTP/1.1` with `Host` and `Connection: close`, and the
  reply starts with `HTTP/1.1 200`.
- api.github.com:443: `GET /zen` with a `User-Agent: chaki` header answers 200.
- Each of these must FAIL the handshake: expired.badssl.com, wrong.host.badssl.com,
  self-signed.badssl.com, untrusted-root.badssl.com. Also tls-v1-0.badssl.com on port 1010.

Both lanes: the JS lane and native (`rr bend --run ./out/x`; the container has OpenSSL 3).
