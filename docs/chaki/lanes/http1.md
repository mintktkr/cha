# lane: http1

The HTTP/1.1 wire format, with no IO: a request writer and an incremental response parser
you feed chunks as they arrive. picohttpparser is the model: strict, small, never quadratic.

## Files you own

`lib/chaki/http1.bend`, `test/chaki_http1_check.bend`.

## API (exact)

```python
# the request's bytes: "METHOD target HTTP/1.1", host, the given headers in order,
# content-length (whenever the body isn't empty, and always for POST, PUT and PATCH),
# "connection: close", a blank line and the body. None when the method isn't a token, or
# any name or value holds CR, LF or NUL (header injection).
def request(method: String, host: String, target: String, headers: List<&2, String & String>, body: List<&2, U32>) -> Maybe<&2, List<&2, U32>>

# header names lowercased, in order, values trimmed
type Head is Data:
  Head{status: U32, headers: List<&2, String & String>}

type Resp is Data:
  Resp{head: Head, body: List<&2, U32>}

type Step is Data:
  More{}
  Got{r: Resp}
  Bad{why: String}

# Parser is your own Data type, opaque to callers
# a fresh parser; head_only for a HEAD request (no body, whatever the headers say)
def parser(head_only: Bool) -> Parser
def feed(p: Parser, chunk: List<&2, U32>) -> Parser
# the peer closed the connection
def eof(p: Parser) -> Parser
def step(p: Parser) -> Step

# every value of a header, joined with ", "; "" when there's none
def header(h: Head, name: String) -> String
```

## Parser rules

- Status line `HTTP/1.0` or `HTTP/1.1`, a three-digit status, then an optional reason.
- Lines end in CRLF, but a bare LF is accepted. Folded headers (obs-fold) are Bad, and so is
  a head over 64 KiB.
- Interim 1xx responses (other than 101) are skipped, and parsing goes on to the next one.
- Body framing, in RFC 9112 §6.3 order: none for head_only, 1xx, 204 and 304. Then
  `transfer-encoding` whose last coding is chunked (chunk extensions ignored, trailers
  skipped). Then `content-length` (digits only; several that differ are Bad). Otherwise
  everything until `eof`.
- Bytes after a complete response are ignored. A response cut short by `eof` is Bad.
- Never rescan what's already parsed: keep a cursor or state. Feeding a 5 MB body in 16 KB
  chunks must take time linear in its size. Accumulate the body reversed, then reverse it
  once.

## Checks

`test/chaki_http1_check.bend`:

- `request`: exact bytes for a GET with no body, for a POST with a JSON body, and for a PUT
  with an empty body (`content-length: 0`). None for a header value with `\r\n`.
- Each canned response gives the same Step fed whole, fed one byte at a time, and fed in
  7-byte chunks:
  - content-length;
  - chunked with extensions and trailers;
  - close-delimited (needs `eof`);
  - HEAD with a content-length;
  - 100 Continue then 200;
  - 204, and 304 with a content-length;
  - two `link` headers joined by `header`.
- Bad cases: a malformed status line, `content-length: -1`, two different content-lengths, an
  oversized head, a chunk-size that isn't hex, and eof in the middle of a body.
- A 2 MB chunked body fed in 16 KB pieces finishes.
