# lane: http

The HTTP client cha calls: one `fetch`, over a socket, OpenSSL, or chaki's own TLS, with
redirects done safely.

## Builds on

`http1.bend` (wire format), `url.bend`, `sys.bend` (dial, recv, send), `ossl.bend`, `tls.bend`
(the `connect`/`send`/`recv`/`close` shell exactly as `docs/chaki/lanes/tls.md` specifies;
if it hasn't landed yet, build and test against `ossl` and plain http first), and
`x509v.bend` (`load`).

## Files you own

`lib/chaki/http.bend`, `test/chaki_http_check.bend`, `test/chaki_http_live.bend`.

## API (exact)

```python
type Transport is Data:
  Bend{}    # chaki's TLS 1.3
  Ossl{}    # the system's OpenSSL

type Client is Data:
  Client{tls: Transport, anchors: List<&2, X509.Cert>, ms: U32}

# a client; for Bend it loads the trust anchors once (X509v.load)
def client(t: Transport, ms: U32) -> IO(Result<&1, &1, U32 & String, Client>)

type Res is Data:
  Res{status: U32, headers: List<&2, String & String>, body: List<&2, U32>, url: String}

# one request, following redirects. headers are lowercase names. Fail{reason} for anything
# that isn't an HTTP response: dns, connect, tls, timeout, too many redirects, malformed.
def fetch(c: Client, method: String, url: String, headers: List<&2, String & String>, body: List<&2, U32>) -> IO(Result<&1, &1, String, Res>)
```

## Rules

- `http://` uses a plain socket. `https://` uses the client's transport. One connection per
  request, `connection: close`, and no Accept-Encoding (so the body comes back as identity).
- `ms` bounds each request as a whole: dial, handshake and the read loop, which recvs with
  the time that's left.
- Redirects: at most 10.
  - 301, 302 and 303 become GET with no body (dropping content-type and content-length), except
    a 301 or 302 after a HEAD, which stays a HEAD.
  - 307 and 308 keep the method and body.
  - Location resolves against the current URL.
  - A hop to another origin drops `authorization` and `cookie`.
  - An https → http hop is refused.
- A Fail reason never includes header values (the authorization header holds a token).
- `Res.url` is the final URL after redirects.

## Checks

- `test/chaki_http_check.bend` (offline, plain http). Serve canned responses from local
  listeners (Base `TCP.listen` + `IO.fork`) on two ports, which are two origins:
  - a 200 with content-length; a chunked one; a close-delimited one; a 404 passed through
    as a Res;
  - a 302 to a relative Location on the same server, where authorization is kept (the
    server echoes whether it got one);
  - a 302 to the other port, where authorization is dropped;
  - a 303 after a POST, which becomes a GET with no body;
  - 307, which keeps the POST;
  - a redirect loop, which fails after 10;
  - a server that never answers, which fails at the deadline;
  - a refused port.
- `test/chaki_http_live.bend` (by hand, run it and report): with both `Bend{}` and `Ossl{}`,
  GET https://api.github.com/zen (with a user-agent) answers 200. So does
  https://codeberg.org/api/v1/version, and a redirect that crosses origins (for example
  http://github.com/ → https). Report times.
