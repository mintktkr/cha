# lane: url

http and https URLs: parse, resolve a reference against a base, and percent-encode.

## Files you own

`lib/chaki/url.bend`, `test/chaki_url_check.bend`.

## API (exact)

```python
# scheme "http" or "https"; host lowercase, an IPv6 literal without its brackets; port
# always set (80/443 by default); target is the path ("/" when empty) plus "?query" when
# there is one. The fragment is dropped.
type Url is Data:
  Url{scheme: String, host: String, port: U32, target: String}

# None for other schemes, userinfo (user@host), an empty host, a port past 65535, or any
# space or control character
def parse(s: String) -> Maybe<&2, Url>

# RFC 3986 §5.2: ref may be absolute, scheme-relative ("//h/p"), an absolute path, a
# relative path, query-only ("?q") or empty. Dot segments are removed.
def resolve(base: Url, ref: String) -> Maybe<&2, Url>

# the URL as text, without the default port, with brackets around an IPv6 host
def show(u: Url) -> String

# "scheme://host:port", port always shown: compare these to tell same-origin hops
def origin(u: Url) -> String

# the Host header: host, plus ":port" when it isn't the default
def host_header(u: Url) -> String

# percent-encode everything but A-Z a-z 0-9 - . _ ~ (for one path segment or query value),
# uppercase hex
def pct(b: List<&2, U32>) -> String
```

cha today has `src/url.bend` with one `encode`; `pct` replaces it, on UTF-8 bytes the caller
produces.

## Checks

`test/chaki_url_check.bend`:

- Parse: the defaults, an explicit port, `HTTPS://Example.COM/`, `[::1]:8080`, a query, a
  fragment dropped, an empty path. Rejects: `ftp://`, `https://u@h/`, `https://h:99999/`,
  `https:///x`, a space.
- Every "normal" example of RFC 3986 §5.4.1 and every "abnormal" one of §5.4.2, against the
  base `http://a/b/c/d;p?q`, compared through `show` (the RFC's expected text, minus
  fragments, which this module drops).
- cha's case: base `https://gitea.example/api/v1/` with `repos/o/n/issues?limit=50` gives
  `https://gitea.example/api/v1/repos/o/n/issues?limit=50`, and with an absolute URL gives
  that URL.
- `origin`: `https://a/x` and `https://a:443/y` share an origin; `http://a/` doesn't.
- `pct`: unreserved kept, space as `%20`, `/` as `%2F`, and the UTF-8 bytes of `茶` as
  `%E8%8C%B6`.
