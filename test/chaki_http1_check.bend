# offline checks for lib/chaki/http1.bend. Every canned response is parsed three ways —
# whole, one byte at a time, and seven bytes at a time — and the three answers must be the
# same Step, because that is what an incremental parser promises.
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/http1.bend as H
import ../lib/chaki/check.bend as T

# Rendering
# ---------

# the headers of a head as " | name=value" each, in the order they arrived
def show.hs(+hs: List<&2, H.Field()>, acc: String) -> String:
  match hs:
    case Nil{}:
      acc
    case Con{(n, +v), t}:
      show.hs(t, acc ++ " | " ++ n ++ "=" ++ v)

def show.head(+h: H.Head) -> String:
  match h:
    case H.Head{status, headers}:
      "status " ++ U32.show(status) ++ show.hs(headers, "")

def show.resp(+r: H.Resp) -> String:
  match r:
    case H.Resp{h, body}:
      show.head(h) ++ " | body " ++ Bytes.to_hex(body)

# a Step as one line: the whole answer, status, every header, and the body in hex
def show.step(+s: H.Step) -> String:
  match s:
    case H.More{}:
      "more"
    case H.Bad{why}:
      "bad " ++ why
    case H.Got{r}:
      show.resp(r)

def show.len.resp(+r: H.Resp) -> String:
  match r:
    case H.Resp{h, body}:
      U32.show(Bytes.len(body))

# the body's length, for a body too big to print
def show.len(+s: H.Step) -> String:
  match s:
    case H.More{}:
      "more"
    case H.Bad{why}:
      "bad " ++ why
    case H.Got{r}:
      show.len.resp(r)

def resp.head.show(+r: H.Resp) -> String:
  match r:
    case H.Resp{h, body}:
      show.head(h)

# the parsed head as one line, or why there is none
def head.show(+s: H.Step) -> String:
  match s:
    case H.Got{r}:
      resp.head.show(r)
    case H.More{}:
      "more"
    case H.Bad{why}:
      "bad " ++ why

def resp.header(+r: H.Resp, +name: String) -> String:
  match r:
    case H.Resp{h, body}:
      H.header(h, name)

# one header's values, joined; "" when the response didn't parse
def head.header(+s: H.Step, +name: String) -> String:
  match s:
    case H.Got{r}:
      resp.header(r, name)
    case _:
      ""

# Feeding
# -------

# the step after feeding the response whole
def whole(one: Bool, resp: String) -> String:
  show.step(H.step(H.feed(H.parser(one), Bytes.of_ascii(resp))))

# the same, for a response whose bytes a string literal can't spell (a NUL)
def whole.bytes(one: Bool, bs: List<&2, U32>) -> String:
  show.step(H.step(H.feed(H.parser(one), bs)))

# the step after feeding it one byte at a time
def drip.go(xs: List<&2, U32>, p: H.Parser) -> H.Parser:
  match xs:
    case Nil{}:
      p
    case h <> t:
      drip.go(t, H.feed(p, [h]))

def drip(one: Bool, resp: String) -> String:
  show.step(H.step(drip.go(Bytes.of_ascii(resp), H.parser(one))))

# the step after feeding it seven bytes at a time
def seven.go(fuel: Nat, xs: List<&2, U32>, p: H.Parser) -> H.Parser:
  match fuel xs:
    case 0n _:
      p
    case 1n+k Nil{}:
      p
    case 1n+k +s:
      seven.go(k, Bytes.drop(s, 7n), H.feed(p, Bytes.take(s, 7n)))

def seven(one: Bool, resp: String) -> String:
  +b = Bytes.of_ascii(resp)
  show.step(H.step(seven.go(U32.to_nat(Bytes.len(b)), b, H.parser(one))))

# the step after feeding the response whole and then closing the connection
def closed(one: Bool, resp: String) -> String:
  p = H.feed(H.parser(one), Bytes.of_ascii(resp))
  show.step(H.step(H.eof(p)))

# the same, one byte at a time, and seven bytes at a time
def closed.drip(one: Bool, resp: String) -> String:
  p = drip.go(Bytes.of_ascii(resp), H.parser(one))
  show.step(H.step(H.eof(p)))

def closed.seven(one: Bool, resp: String) -> String:
  +b = Bytes.of_ascii(resp)
  p = seven.go(U32.to_nat(Bytes.len(b)), b, H.parser(one))
  show.step(H.step(H.eof(p)))

# The request writer
# ------------------

def req.show(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case None{}:
      "none"
    case Some{b}:
      Bytes.to_hex(b)

# Repeats
# -------

def fill.go(n: Nat, +s: String, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+k:
      fill.go(k, s, s ++ acc)

def fill(n: Nat, s: String) -> String:
  fill.go(n, s, "")

def fill.bytes.go(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+k:
      fill.bytes.go(k, 97 <> acc)

def fill.bytes(n: Nat) -> List<&2, U32>:
  fill.bytes.go(n, Nil{})

# Canned responses
# ----------------

# 200 with a content-length of 5 and "hello"
def resp.len() -> String:
  "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello"

# chunked, with a chunk extension and a trailer
def resp.chunked() -> String:
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5;name=value\r\nhello\r\n6\r\n world\r\n0\r\nX-Trailer: yes\r\n\r\n"

# no content-length and no chunked coding: everything to eof
def resp.close() -> String:
  "HTTP/1.1 200 OK\r\n\r\nhello there"

# a HEAD response, whose head promises a body the response never carries
def resp.head() -> String:
  "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n"

# 200 with a body, for a HEAD request: the body is not read
def resp.head.body() -> String:
  "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello"

# an interim 100, then the real 200
def resp.head.cont() -> String:
  "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n"

def resp.cont() -> String:
  "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"

def resp.nc() -> String:
  "HTTP/1.1 204 No Content\r\nDate: Mon, 01 Jan 2024 00:00:00 GMT\r\n\r\n"

def resp.nm() -> String:
  "HTTP/1.1 304 Not Modified\r\nContent-Length: 5\r\n\r\n"

# two link headers, for joining
def resp.link() -> String:
  "HTTP/1.1 200 OK\r\nLink: <a>; rel=\"next\"\r\nLink: <b>; rel=\"prev\"\r\nContent-Length: 0\r\n\r\n"

# 101 is not skipped: it hands the connection to another protocol
def resp.switch() -> String:
  "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n"

# the last coding of transfer-encoding isn't chunked, so the body runs to eof
def resp.gzip() -> String:
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\nzipped"

# a chunk-size line that isn't hex
def resp.bad.chunk() -> String:
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nxyz\r\n"

# a header line folded onto the next one (obs-fold)
def resp.fold() -> String:
  "HTTP/1.1 200 OK\r\nx: a\r\n\tb\r\n\r\n"

# a header name with a space before its colon
def resp.bad.name() -> String:
  "HTTP/1.1 200 OK\r\ncontent-length : 5\r\n\r\n"

# a head over 64 KiB
def resp.big.head() -> String:
  "HTTP/1.1 200 OK\r\nx: " ++ fill(70000n, "a") ++ "\r\n\r\n"

# A 2 MB chunked body, 16 KB at a time
# ------------------------------------

# one piece: a whole chunk whose wire bytes are exactly 16384, "3ff8\r\n" and 16376 body
def big.piece() -> List<&2, U32>:
  Bytes.cat(Bytes.of_ascii("3ff8\r\n"), Bytes.cat(fill.bytes(16376n), Bytes.of_ascii("\r\n")))

def big.go(n: Nat, p: H.Parser) -> H.Parser:
  match n:
    case 0n:
      p
    case 1n+k:
      big.go(k, H.feed(p, big.piece()))

def big() -> String:
  p0 = H.feed(H.parser(False{}), Bytes.of_ascii("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"))
  p1 = big.go(128n, p0)
  show.len(H.step(H.feed(p1, Bytes.of_ascii("0\r\n\r\n"))))

def main() -> IO(Unit):
  do IO<Unit>:
    # the request writer: exact bytes, and the cases that must not be sent at all
    IO.print(T.eq("request GET", req.show(H.request("GET", "example.com", "/index.html", Nil{}, Nil{})), "474554202f696e6465782e68746d6c20485454502f312e310d0a486f73743a206578616d706c652e636f6d0d0a436f6e6e656374696f6e3a20636c6f73650d0a0d0a"))
    IO.print(T.eq("request POST with a body", req.show(H.request("POST", "api.example.com", "/v1/items", [("Content-Type", "application/json")], Bytes.of_ascii("{\"a\":1,\"b\":2}"))), "504f5354202f76312f6974656d7320485454502f312e310d0a486f73743a206170692e6578616d706c652e636f6d0d0a436f6e74656e742d547970653a206170706c69636174696f6e2f6a736f6e0d0a436f6e74656e742d4c656e6774683a2031330d0a436f6e6e656374696f6e3a20636c6f73650d0a0d0a7b2261223a312c2262223a327d"))
    IO.print(T.eq("request PUT with an empty body", req.show(H.request("PUT", "example.com", "/x", Nil{}, Nil{})), "505554202f7820485454502f312e310d0a486f73743a206578616d706c652e636f6d0d0a436f6e74656e742d4c656e6774683a20300d0a436f6e6e656374696f6e3a20636c6f73650d0a0d0a"))
    IO.print(T.eq("request GET with a body", req.show(H.request("GET", "h", "/x", Nil{}, Bytes.of_ascii("hi"))), "474554202f7820485454502f312e310d0a486f73743a20680d0a436f6e74656e742d4c656e6774683a20320d0a436f6e6e656374696f6e3a20636c6f73650d0a0d0a6869"))
    IO.print(T.eq("request header value with CRLF", req.show(H.request("GET", "example.com", "/x", [("x", "a\r\nb")], Nil{})), "none"))
    IO.print(T.eq("request header name with CRLF", req.show(H.request("GET", "example.com", "/x", [("a\r\nb", "v")], Nil{})), "none"))
    IO.print(T.eq("request method that isn't a token", req.show(H.request("GE T", "example.com", "/x", Nil{}, Nil{})), "none"))
    IO.print(T.eq("request target with LF", req.show(H.request("GET", "example.com", "/x\nHost: evil", Nil{}, Nil{})), "none"))
    IO.print(T.eq("request host with a CR", req.show(H.request("GET", "exa\rmple", "/x", Nil{}, Nil{})), "none"))

    # content-length
    IO.print(T.eq("200 with content-length, whole", whole(False{}, resp.len()), "status 200 | content-length=5 | body 68656c6c6f"))
    IO.print(T.eq("bytes after a complete response are ignored", whole(False{}, resp.len() ++ "HTTP/1.1 200 OK\r\n\r\n"), "status 200 | content-length=5 | body 68656c6c6f"))
    IO.print(T.eq("200 with content-length, whole = drip", whole(False{}, resp.len()), drip(False{}, resp.len())))
    IO.print(T.eq("200 with content-length, drip = seven", drip(False{}, resp.len()), seven(False{}, resp.len())))

    # chunked, with extensions and trailers
    IO.print(T.eq("chunked with an extension and a trailer, whole", whole(False{}, resp.chunked()), "status 200 | transfer-encoding=chunked | body 68656c6c6f20776f726c64"))
    IO.print(T.eq("chunked, whole = drip", whole(False{}, resp.chunked()), drip(False{}, resp.chunked())))
    IO.print(T.eq("chunked, drip = seven", drip(False{}, resp.chunked()), seven(False{}, resp.chunked())))

    # close-delimited: more until eof
    IO.print(T.eq("close-delimited, whole", whole(False{}, resp.close()), "more"))
    IO.print(T.eq("close-delimited, drip", drip(False{}, resp.close()), "more"))
    IO.print(T.eq("close-delimited + eof, whole", closed(False{}, resp.close()), "status 200 | body 68656c6c6f207468657265"))
    IO.print(T.eq("close-delimited + eof, whole = drip", closed(False{}, resp.close()), closed.drip(False{}, resp.close())))
    IO.print(T.eq("close-delimited + eof, drip = seven", closed.drip(False{}, resp.close()), closed.seven(False{}, resp.close())))

    # HEAD: no body, whatever the headers say
    IO.print(T.eq("HEAD with a content-length", whole(True{}, resp.head()), "status 200 | content-length=5 | body "))
    IO.print(T.eq("HEAD, whole = drip", whole(True{}, resp.head()), drip(True{}, resp.head())))
    IO.print(T.eq("HEAD, drip = seven", drip(True{}, resp.head()), seven(True{}, resp.head())))
    IO.print(T.eq("HEAD ignores a body that arrived", whole(True{}, resp.head.body()), "status 200 | content-length=5 | body "))
    IO.print(T.eq("HEAD skips an interim 100", whole(True{}, resp.head.cont()), "status 200 | content-length=5 | body "))

    # 100 Continue, then the real response
    IO.print(T.eq("100 then 200, whole", whole(False{}, resp.cont()), "status 200 | content-length=2 | body 6869"))
    IO.print(T.eq("100 then 200, whole = drip", whole(False{}, resp.cont()), drip(False{}, resp.cont())))
    IO.print(T.eq("100 then 200, drip = seven", drip(False{}, resp.cont()), seven(False{}, resp.cont())))

    # 204, 304 with a content-length, and 101
    IO.print(T.eq("204", whole(False{}, resp.nc()), "status 204 | date=Mon, 01 Jan 2024 00:00:00 GMT | body "))
    IO.print(T.eq("204, whole = drip", whole(False{}, resp.nc()), drip(False{}, resp.nc())))
    IO.print(T.eq("304 with a content-length", whole(False{}, resp.nm()), "status 304 | content-length=5 | body "))
    IO.print(T.eq("304, whole = drip", whole(False{}, resp.nm()), drip(False{}, resp.nm())))
    IO.print(T.eq("101 is not skipped", whole(False{}, resp.switch()), "status 101 | upgrade=websocket | body "))

    # a transfer-encoding whose last coding isn't chunked runs to eof
    IO.print(T.eq("transfer-encoding gzip, whole", whole(False{}, resp.gzip()), "more"))
    IO.print(T.eq("transfer-encoding gzip + eof", closed(False{}, resp.gzip()), "status 200 | transfer-encoding=gzip | body 7a6970706564"))

    # two link headers, joined
    IO.print(T.eq("two link headers, whole", whole(False{}, resp.link()), "status 200 | link=<a>; rel=\"next\" | link=<b>; rel=\"prev\" | content-length=0 | body "))
    IO.print(T.eq("two link headers, whole = drip", whole(False{}, resp.link()), drip(False{}, resp.link())))
    IO.print(T.eq("two link headers, drip = seven", drip(False{}, resp.link()), seven(False{}, resp.link())))
    IO.print(T.eq("two link headers joined by header", head.header(H.step(H.feed(H.parser(False{}), Bytes.of_ascii(resp.link()))), "link"), "<a>; rel=\"next\", <b>; rel=\"prev\""))
    IO.print(T.eq("header looks up a missing name", head.header(H.step(H.feed(H.parser(False{}), Bytes.of_ascii(resp.link()))), "x-missing"), ""))
    IO.print(T.eq("header looks up a name in any case", head.header(H.step(H.feed(H.parser(False{}), Bytes.of_ascii(resp.link()))), "LINK"), "<a>; rel=\"next\", <b>; rel=\"prev\""))
    IO.print(T.eq("field names are lowercased", head.show(H.step(H.feed(H.parser(False{}), Bytes.of_ascii(resp.nc())))), "status 204 | date=Mon, 01 Jan 2024 00:00:00 GMT"))

    # smaller edges
    IO.print(T.eq("bare LF line endings", whole(False{}, "HTTP/1.1 200 OK\nContent-Length: 2\n\nhi"), "status 200 | content-length=2 | body 6869"))
    IO.print(T.eq("an empty content-length", whole(False{}, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"), "status 200 | content-length=0 | body "))
    IO.print(T.eq("an empty chunked body", whole(False{}, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"), "status 200 | transfer-encoding=chunked | body "))
    IO.print(T.eq("a zero chunk with no trailers", whole(False{}, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nx\r\n0\r\n\r\n"), "status 200 | transfer-encoding=chunked | body 78"))
    IO.print(T.eq("an upper case chunk size", whole(False{}, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nA\r\naaaaaaaaaa\r\n0\r\n\r\n"), "status 200 | transfer-encoding=chunked | body 61616161616161616161"))
    IO.print(T.eq("a bare LF ends a chunk size line", whole(False{}, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\nx\n0\n\n"), "status 200 | transfer-encoding=chunked | body 78"))

    # the edges: nothing, one byte, eof before anything
    IO.print(T.eq("a fresh parser", show.step(H.step(H.parser(False{}))), "more"))
    IO.print(T.eq("nothing fed", whole(False{}, ""), "more"))
    IO.print(T.eq("one byte fed", whole(False{}, "H"), "more"))
    IO.print(T.eq("eof with nothing", closed(False{}, ""), "bad eof with the response unfinished"))

    # Bad cases
    IO.print(T.eq("bad status line", whole(False{}, "HTTP/1.1 20 OK\r\n\r\n"), "bad bad status line"))
    IO.print(T.eq("status line without a version", whole(False{}, "200 OK\r\n\r\n"), "bad bad status line"))
    IO.print(T.eq("content-length -1", whole(False{}, "HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\n"), "bad bad content-length"))
    IO.print(T.eq("content-length 5x", whole(False{}, "HTTP/1.1 200 OK\r\nContent-Length: 5x\r\n\r\n"), "bad bad content-length"))
    IO.print(T.eq("two content-lengths that differ", whole(False{}, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\n"), "bad content-length headers differ"))
    IO.print(T.eq("two content-lengths that agree", whole(False{}, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello"), "status 200 | content-length=5 | content-length=5 | body 68656c6c6f"))
    IO.print(T.eq("a head over 64 KiB", whole(False{}, resp.big.head()), "bad head over 64 KiB"))
    IO.print(T.eq("a chunk-size that isn't hex", whole(False{}, resp.bad.chunk()), "bad bad chunk size"))
    IO.print(T.eq("a chunk-size with too many digits", whole(False{}, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1ffffffff\r\n"), "bad chunk size is too large"))
    IO.print(T.eq("a bad chunk end", whole(False{}, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nxZ\r\n"), "bad bad chunk end"))
    IO.print(T.eq("eof in the middle of a body", closed(False{}, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nab"), "bad eof with the response unfinished"))
    IO.print(T.eq("eof in the middle of a head", closed(False{}, "HTTP/1.1 200 OK\r\nContent-Len"), "bad eof with the response unfinished"))
    IO.print(T.eq("eof in a chunked body", closed(False{}, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nab"), "bad eof with the response unfinished"))
    IO.print(T.eq("a folded header", whole(False{}, resp.fold()), "bad folded header"))
    IO.print(T.eq("a header name with a space", whole(False{}, resp.bad.name()), "bad bad header name"))
    IO.print(T.eq("a header without a colon", whole(False{}, "HTTP/1.1 200 OK\r\nnocolon\r\n\r\n"), "bad header without a colon"))
    IO.print(T.eq("a header value with a NUL", whole.bytes(False{}, Bytes.cat(Bytes.of_ascii("HTTP/1.1 200 OK\r\nx: a"), Bytes.cat([0], Bytes.of_ascii("b\r\n\r\n")))), "bad bad header value"))

    # a 2 MB chunked body, 16 KB at a time
    IO.print(T.eq("2 MB of chunked body in 16 KB pieces", big(), "2096128"))
