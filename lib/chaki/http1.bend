# http1: the HTTP/1.1 wire format, with no IO. request writes a request's bytes; the
# parser (parser, feed, eof, step) is handed a response as it arrives and answers More,
# Got or Bad. picohttpparser is the model: strict, small, never quadratic. A head line is
# scanned once, with its bytes kept in the parser's state until its LF arrives, and a body
# is consumed as it arrives and accumulated backwards, so a 5 MB body fed in 16 KB chunks
# costs time linear in its size.
import Base
import ./bytes.bend as Bytes

# The header list is (lowercase name, trimmed value) pairs, in the order the peer sent
# them. bend's `String & String` pair is affine, so a `List<&2, ..>` of pairs needs the
# quantity spelled out: this is the Data pair the lane's signatures mean, and it is built
# and taken apart like any tuple.
def Field() -> Data:
  Sigma<&2, &2, String, _ => String>

# A response head: the status, and every header as (lowercase name, trimmed value), in
# the order the peer sent them.
type Head is Data:
  Head{status: U32, headers: List<&2, Field()>}

type Resp is Data:
  Resp{head: Head, body: List<&2, U32>}

type Step is Data:
  More{}
  Got{r: Resp}
  Bad{why: String}

# one header line as it will be sent, and whether its name or its value held CR, LF or NUL
type Sent is Data:
  Sent{line: List<&2, U32>, bad: Bool}

# every value of one header, joined with ", "
type Val is Data:
  Val{seen: Bool, text: String}

# a content-length value: the number, or why it can't be read
type Cl is Data:
  ClSome{n: Nat}
  ClBad{why: String}

# the walk over a content-length value: the digits since the last comma, the number the
# one before held, and whether any has been read
type ClWalk is Data:
  CW{seg: List<&2, U32>, prev: Nat, seen: Bool}
  CWBad{why: String}

# a status line
type Stat is Data:
  SpOk{code: U32}
  SpBad{why: String}

# one header line: its lowercase name and its trimmed value
type Hd is Data:
  HdOk{name: String, value: String}
  HdBad{why: String}

# the walk over a chunk size line: its value, its digit count, and whether the extensions
# after the digits have begun
type Cs is Data:
  CsOk{n: Nat}
  CsBad{why: String}
  CsGo{n: Nat, digits: Nat, ext: Bool}

# the bytes of one line, without its LF, what follows it, and the head's remaining 64 KiB
type Line is Data:
  LEnd{body: List<&2, U32>, rest: List<&2, U32>, room: Nat}
  LNeed{part: List<&2, U32>, room: Nat}
  LBad{why: String}

# bytes taken from the front of a buffer: they are reversed onto the accumulator behind
# them, the buffer's rest follows, and left is what the body still needs
type Part is Data:
  Part{rev: List<&2, U32>, rest: List<&2, U32>, left: Nat}

# where the parser is between chunks. A head line's bytes and a chunk size line's wait in
# part, so no line is scanned twice; a body is accumulated backwards in acc.
type St is Data:
  StHead{room: Nat, one: Bool, part: List<&2, U32>}
  StHdr{room: Nat, status: U32, hs: List<&2, Field()>, one: Bool, part: List<&2, U32>}
  StLen{n: Nat, acc: List<&2, U32>, head: Head}
  StChunkSize{room: Nat, acc: List<&2, U32>, head: Head, part: List<&2, U32>}
  StChunk{n: Nat, acc: List<&2, U32>, head: Head}
  StChunkEnd{acc: List<&2, U32>, head: Head}
  StTrailer{room: Nat, acc: List<&2, U32>, head: Head, part: List<&2, U32>}
  StTillEof{acc: List<&2, U32>, head: Head}
  StDone{resp: Resp}
  StBad{why: String}

# what one step did: made progress, needs more bytes, or ended
type Mv is Data:
  Cont{st: St, buf: List<&2, U32>}
  Hold{st: St, buf: List<&2, U32>}
  End{st: St}

type Parser is Data:
  P{st: St, buf: List<&2, U32>}

# Character classes
# -----------------

# ! # $ % & ' * + - . ^ _ ` | ~ — the tchar punctuation of RFC 9110
def is.punct(+c: U32) -> Bool:
  match c:
    case 33:
      True{}
    case 35:
      True{}
    case 36:
      True{}
    case 37:
      True{}
    case 38:
      True{}
    case 39:
      True{}
    case 42:
      True{}
    case 43:
      True{}
    case 45:
      True{}
    case 46:
      True{}
    case 94:
      True{}
    case 95:
      True{}
    case 96:
      True{}
    case 124:
      True{}
    case 126:
      True{}
    case _:
      False{}

def is.alpha(+c: U32) -> Bool:
  Bool.or(U32.is_le(65, c) && U32.is_le(c, 90), U32.is_le(97, c) && U32.is_le(c, 122))

# an RFC 9110 token character: a method, or the name of a header
def is.tchar(+c: U32) -> Bool:
  Bool.or(U32.is_le(48, c) && U32.is_le(c, 57), Bool.or(is.alpha(c), is.punct(c)))

# SP or HTAB
def ws.ch(+c: U32) -> Bool:
  U32.is_eq(c, 32) || U32.is_eq(c, 9)

# a byte a field value may hold: VCHAR or obs-text, and HTAB and SP
def vchar.ch(+c: U32) -> Bool:
  Bool.or(U32.is_le(33, c) && U32.is_ne(c, 127), ws.ch(c))

# CR, LF or NUL: the bytes that would cut one line into two
def ctl.ch(+c: U32) -> Bool:
  match c:
    case 13:
      True{}
    case 10:
      True{}
    case 0:
      True{}
    case _:
      False{}

# the ASCII lowercase of one byte
def low.ch(+c: U32) -> U32:
  Bool.pick(U32, U32.is_le(65, c) && U32.is_le(c, 90), (c + 32 : U32), c)

# the ASCII lowercase of a string
def lower.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{+c}, t}:
      lower.go(t, SCon{Chr{low.ch(c)}, acc})

def lower(s: String) -> String:
  lower.go(s, SNil{})

def low.bytes.go(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Bytes.rev(acc)
    case Con{h, t}:
      low.bytes.go(t, low.ch(h) <> acc)

def low.bytes(xs: List<&2, U32>) -> List<&2, U32>:
  low.bytes.go(xs, Nil{})

# the bytes with their leading SP and HTAB dropped
def ws.drop(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      match h:
        case 32:
          ws.drop(t)
        case 9:
          ws.drop(t)
        case c:
          c <> t

# the bytes with their leading and trailing SP and HTAB dropped
def ws.trim(xs: List<&2, U32>) -> List<&2, U32>:
  Bytes.rev(ws.drop(Bytes.rev(ws.drop(xs))))

# the bytes of a list, and how many there are, in one pass
def len.keep.go(xs: List<&2, U32>, acc: List<&2, U32>, n: Nat) -> List<&2, U32> & Nat:
  match xs:
    case Nil{}:
      (Bytes.rev(acc), n)
    case Con{h, t}:
      len.keep.go(t, h <> acc, Nat.add(n, 1n))

def len.keep(xs: List<&2, U32>) -> List<&2, U32> & Nat:
  len.keep.go(xs, Nil{}, 0n)

# whether the bytes are empty
def line.empty(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      False{}

# whether the bytes start with SP or HTAB: a folded (obs-fold) header line
def line.blank(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      ws.ch(h)

# True when the bytes hold one that a field value may not
def val.bad(xs: List<&2, U32>, bad: Bool) -> Bool:
  match xs:
    case Nil{}:
      bad
    case Con{h, t}:
      val.bad(t, Bool.or(bad, Bool.not(vchar.ch(h))))

# up to n bytes from the front of xs, reversed onto acc, and what the body still needs: one
# pass, and a count of zero means the slice is complete
def take.rev(xs: List<&2, U32>, n: Nat, acc: List<&2, U32>) -> Part:
  match xs n:
    case rest 0n:
      Part{acc, rest, 0n}
    case Nil{} 1n+k:
      Part{acc, Nil{}, Nat.add(k, 1n)}
    case Con{h, t} 1n+k:
      take.rev(t, k, h <> acc)

# The request writer
# ------------------

# the bytes of a method, None unless it is a token
def req.token.go(xs: List<&2, U32>, st: U32, acc: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match xs st:
    case Nil{} 1:
      Some{Bytes.rev(acc)}
    case Nil{} _:
      None{}
    case _ 0:
      None{}
    case Con{+h, t} _:
      req.token.go(t, Bool.to_u32(is.tchar(h)), h <> acc)

def req.token(s: String) -> Maybe<&2, List<&2, U32>>:
  req.token.go(Bytes.of_ascii(s), 2, Nil{})

# the bytes of a target, a host, or a header name or value, and whether it holds CR, LF or
# NUL: those bytes would cut the request line or start a header of someone else's choosing
def req.bytes.go(s: String, acc: List<&2, U32>, bad: Bool) -> List<&2, U32> & Bool:
  match s:
    case SNil{}:
      (Bytes.rev(acc), bad)
    case SCon{Chr{+c}, t}:
      req.bytes.go(t, U32.and(c, 255) <> acc, Bool.or(bad, ctl.ch(c)))

def req.bytes.ok(b: List<&2, U32>, bad: Bool) -> Maybe<&2, List<&2, U32>>:
  match bad:
    case True{}:
      None{}
    case False{}:
      Some{b}

def req.bytes.m(r: List<&2, U32> & Bool) -> Maybe<&2, List<&2, U32>>:
  (b, bad) = r
  req.bytes.ok(b, bad)

def req.bytes(s: String) -> Maybe<&2, List<&2, U32>>:
  req.bytes.m(req.bytes.go(s, Nil{}, False{}))

# one header's "name: value\r\n", with whether the name or the value held CR, LF or NUL
def req.field.go(r: List<&2, U32> & Bool, nb: List<&2, U32>, nbad: Bool) -> Sent:
  (vb, vbad) = r
  Sent{Bytes.cat(Bytes.cat(Bytes.cat(nb, Bytes.of_ascii(": ")), vb), Bytes.of_ascii("\r\n")), Bool.or(nbad, vbad)}

def req.field.m(r: List<&2, U32> & Bool, v: String) -> Sent:
  (nb, nbad) = r
  req.field.go(req.bytes.go(v, Nil{}, False{}), nb, nbad)

def req.field(n: String, v: String) -> Sent:
  req.field.m(req.bytes.go(n, Nil{}, False{}), v)

def req.sent.bytes(r: Sent) -> List<&2, U32>:
  match r:
    case Sent{line, bad}:
      line

def req.sent.bad(r: Sent) -> Bool:
  match r:
    case Sent{line, bad}:
      bad

def req.hdrs.end(acc: List<&2, List<&2, U32>>, bad: Bool) -> Maybe<&2, List<&2, List<&2, U32>>>:
  match bad:
    case True{}:
      None{}
    case False{}:
      Some{List.reverse(&2, List<&2, U32>, acc)}

# each header's bytes, prepended to acc in reverse
def req.hdrs.rev(hs: List<&2, List<&2, U32>>, acc: List<&2, U32>) -> List<&2, U32>:
  match hs:
    case Nil{}:
      acc
    case h <> t:
      req.hdrs.rev(t, Bytes.rev.onto(h, acc))

# the given headers in order, each "name: value\r\n": None when one can't be sent
def req.hdrs.go(hs: List<&2, Field()>, acc: List<&2, List<&2, U32>>, bad: Bool) -> Maybe<&2, List<&2, List<&2, U32>>>:
  match hs:
    case Nil{}:
      req.hdrs.end(acc, bad)
    case Con{(n, v), t}:
      +r = req.field(n, v)
      req.hdrs.go(t, req.sent.bytes(r) <> acc, Bool.or(bad, req.sent.bad(r)))

# "METHOD target HTTP/1.1\r\n"
def req.line(m: List<&2, U32>, t: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(Bytes.cat(Bytes.cat(m, Bytes.of_ascii(" ")), t), Bytes.of_ascii(" HTTP/1.1\r\n"))

# "Host: host\r\n"
def req.host.line(h: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(Bytes.cat(Bytes.of_ascii("Host: "), h), Bytes.of_ascii("\r\n"))

def req.meth.is(m: List<&2, U32>, +s: String) -> Bool:
  Bytes.eq(m, Bytes.of_ascii(s))

# POST, PUT and PATCH carry a content-length even when the body is empty
def req.meth.cl(+m: List<&2, U32>) -> Bool:
  Bool.or(req.meth.is(m, "POST"), Bool.or(req.meth.is(m, "PUT"), req.meth.is(m, "PATCH")))

def req.cl.if(need: Bool, n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match need:
    case True{}:
      Bytes.rev.onto(Bytes.of_ascii("Content-Length: " ++ Nat.show(n) ++ "\r\n"), acc)
    case False{}:
      acc

# the whole request, built backwards piece by piece and reversed once
def req.pack(+m: List<&2, U32>, h: List<&2, U32>, t: List<&2, U32>, hs: List<&2, List<&2, U32>>, r: List<&2, U32> & Nat) -> List<&2, U32>:
  (body, +n) = r
  need = Bool.or(Bool.not(Nat.is_eq(n, 0n)), req.meth.cl(m))
  acc = Bytes.rev.onto(req.line(m, t), Nil{})
  acc = Bytes.rev.onto(req.host.line(h), acc)
  acc = req.hdrs.rev(hs, acc)
  acc = req.cl.if(need, n, acc)
  acc = Bytes.rev.onto(Bytes.of_ascii("Connection: close\r\n\r\n"), acc)
  acc = Bytes.rev.onto(body, acc)
  Bytes.rev(acc)

# the request's bytes: "METHOD target HTTP/1.1", the host, the given headers in order,
# content-length (whenever the body isn't empty, and always for POST, PUT and PATCH),
# "connection: close", a blank line, and the body. None when the method isn't a token, or
# when the target, the host, a header name or a header value holds CR, LF or NUL.
def request(method: String, host: String, target: String, headers: List<&2, Field()>, body: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  do Maybe<&2, List<&2, U32>>:
    m : List<&2, U32> <- req.token(method)
    h : List<&2, U32> <- req.bytes(host)
    t : List<&2, U32> <- req.bytes(target)
    hs : List<&2, List<&2, U32>> <- req.hdrs.go(headers, Nil{}, False{})
    return req.pack(m, h, t, hs, len.keep(body))

# Header lookup
# -------------

def hdr.same(n: String, +name: String) -> Bool:
  String.eq(n, name)

def hdr.val.sep(seen: Bool, v: String, acc: List<&2, U32>) -> List<&2, U32>:
  match seen:
    case False{}:
      Bytes.rev.onto(Bytes.of_ascii(v), acc)
    case True{}:
      Bytes.rev.onto(Bytes.of_ascii(v), Bytes.rev.onto(Bytes.of_ascii(", "), acc))

# one value onto the joined bytes, which are held backwards, with ", " once one is there
def hdr.val.join(hit: Bool, seen: Bool, v: String, acc: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case False{}:
      acc
    case True{}:
      hdr.val.sep(seen, v, acc)

def hdr.val.go(hs: List<&2, Field()>, +name: String, acc: List<&2, U32>, +seen: Bool) -> Val:
  match hs:
    case Nil{}:
      Val{seen, Bytes.to_ascii(Bytes.rev(acc))}
    case Con{(+n, v), t}:
      hdr.val.go(t, name, hdr.val.join(hdr.same(n, name), seen, v, acc), Bool.or(hdr.same(n, name), seen))

def hdr.val.val(hs: List<&2, Field()>, name: String) -> Val:
  hdr.val.go(hs, lower(name), Nil{}, False{})

def val.text(v: Val) -> String:
  match v:
    case Val{seen, text}:
      text

# every value of a header, joined with ", "; "" when the header didn't arrive
def header(h: Head, name: String) -> String:
  match h:
    case Head{status, headers}:
      val.text(hdr.val.val(headers, name))

# Content-length
# --------------

# one number: digits only, and nothing else
def cl.num.go(xs: List<&2, U32>, n: Nat) -> Cl:
  match xs:
    case Nil{}:
      ClSome{n}
    case Con{h, t}:
      match h:
        case 48:
          cl.num.go(t, Nat.mul(n, 10n))
        case 49:
          cl.num.go(t, Nat.add(Nat.mul(n, 10n), 1n))
        case 50:
          cl.num.go(t, Nat.add(Nat.mul(n, 10n), 2n))
        case 51:
          cl.num.go(t, Nat.add(Nat.mul(n, 10n), 3n))
        case 52:
          cl.num.go(t, Nat.add(Nat.mul(n, 10n), 4n))
        case 53:
          cl.num.go(t, Nat.add(Nat.mul(n, 10n), 5n))
        case 54:
          cl.num.go(t, Nat.add(Nat.mul(n, 10n), 6n))
        case 55:
          cl.num.go(t, Nat.add(Nat.mul(n, 10n), 7n))
        case 56:
          cl.num.go(t, Nat.add(Nat.mul(n, 10n), 8n))
        case 57:
          cl.num.go(t, Nat.add(Nat.mul(n, 10n), 9n))
        case _:
          ClBad{"bad content-length"}

def cl.num(xs: List<&2, U32>) -> Cl:
  cl.num.go(ws.trim(xs), 0n)

def cl.step.eq(same: Bool, n: Nat) -> ClWalk:
  match same:
    case True{}:
      CW{Nil{}, n, True{}}
    case False{}:
      CWBad{"content-length headers differ"}

def cl.step.same(seen: Bool, +n: Nat, prev: Nat) -> ClWalk:
  match seen:
    case False{}:
      CW{Nil{}, n, True{}}
    case True{}:
      cl.step.eq(Nat.is_eq(n, prev), n)

# one number is in: carry it on as the last one, or fail when it differs from that one
def cl.step(c: Cl, prev: Nat, seen: Bool) -> ClWalk:
  match c:
    case ClBad{why}:
      CWBad{why}
    case ClSome{n}:
      cl.step.same(seen, n, prev)

def cl.answer.seen(seen: Bool, prev: Nat) -> Cl:
  match seen:
    case False{}:
      ClBad{"bad content-length"}
    case True{}:
      ClSome{prev}

def cl.answer(s: ClWalk) -> Cl:
  match s:
    case CW{seg, prev, seen}:
      cl.answer.seen(seen, prev)
    case CWBad{why}:
      ClBad{why}

# the numbers of a content-length value, comma separated, and all the same
def cl.go(xs: List<&2, U32>, st: ClWalk) -> Cl:
  match xs st:
    case Nil{} CW{seg, prev, seen}:
      cl.answer(cl.step(cl.num(Bytes.rev(seg)), prev, seen))
    case Con{44, t} CW{seg, prev, seen}:
      cl.go(t, cl.step(cl.num(Bytes.rev(seg)), prev, seen))
    case Con{h, t} CW{seg, prev, seen}:
      cl.go(t, CW{h <> seg, prev, seen})
    case _ CWBad{why}:
      ClBad{why}

def cl.parse(v: String) -> Cl:
  cl.go(Bytes.of_ascii(v), CW{Nil{}, 0n, False{}})

# Body framing
# ------------

# a status whose response has no body: 1xx, 204, 304 (and every HEAD response)
def body.none(+status: U32) -> Bool:
  Bool.or(U32.is_le(100, status) && U32.is_le(status, 199), Bool.or(U32.is_eq(status, 204), U32.is_eq(status, 304)))

# an interim 1xx response: skipped, and the response after it is parsed. 101 is not: it
# hands the connection to another protocol.
def body.interim(+status: U32) -> Bool:
  U32.is_le(100, status) && U32.is_le(status, 199) && U32.is_ne(status, 101)

# the text after the last comma of s
def te.last.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{+c}, t}:
      match c:
        case 44:
          te.last.go(t, SNil{})
        case d:
          te.last.go(t, SCon{Chr{d}, acc})

# transfer-encoding whose last coding is chunked
def body.chunked(v: String) -> Bool:
  Bytes.eq(low.bytes(ws.trim(Bytes.of_ascii(te.last.go(v, SNil{})))), Bytes.of_ascii("chunked"))

def head.framed.cl.parse(head: Head, rest: List<&2, U32>, c: Cl) -> Mv:
  match c:
    case ClBad{why}:
      End{StBad{why}}
    case ClSome{n}:
      Cont{StLen{n, Nil{}, head}, rest}

def head.framed.cl.seen(head: Head, rest: List<&2, U32>, text: String, seen: Bool) -> Mv:
  match seen:
    case False{}:
      Cont{StTillEof{Nil{}, head}, rest}
    case True{}:
      head.framed.cl.parse(head, rest, cl.parse(text))

def head.framed.cl.go(head: Head, rest: List<&2, U32>, v: Val) -> Mv:
  match v:
    case Val{seen, text}:
      head.framed.cl.seen(head, rest, text, seen)

def head.framed.cl(+head: Head, rest: List<&2, U32>) -> Mv:
  match head:
    case Head{status, +headers}:
      head.framed.cl.go(Head{status, headers}, rest, hdr.val.val(headers, "content-length"))

def head.framed.te.go(head: Head, rest: List<&2, U32>, chunked: Bool) -> Mv:
  match chunked:
    case True{}:
      Cont{StChunkSize{65536n, Nil{}, head, Nil{}}, rest}
    case False{}:
      head.framed.cl(head, rest)

def head.framed.te(+head: Head, rest: List<&2, U32>) -> Mv:
  match head:
    case Head{status, +headers}:
      head.framed.te.go(Head{status, headers}, rest, body.chunked(val.text(hdr.val.val(headers, "transfer-encoding"))))

# the body's framing, in RFC 9112 6.3 order: an interim 1xx is skipped and the response
# after it is parsed, then no body for HEAD, 204 and 304, then transfer-encoding whose last
# coding is chunked, then content-length, then everything to eof
def head.framed.none(none: Bool, head: Head, rest: List<&2, U32>) -> Mv:
  match none:
    case True{}:
      End{StDone{Resp{head, Nil{}}}}
    case False{}:
      head.framed.te(head, rest)

def head.framed.skip(skip: Bool, one: Bool, +status: U32, head: Head, rest: List<&2, U32>) -> Mv:
  match skip:
    case True{}:
      Cont{StHead{65536n, one, Nil{}}, rest}
    case False{}:
      head.framed.none(Bool.or(one, body.none(status)), head, rest)

def head.framed(one: Bool, +status: U32, head: Head, rest: List<&2, U32>) -> Mv:
  head.framed.skip(body.interim(status), one, status, head, rest)

# The head's lines
# ----------------

def line.end(acc: List<&2, U32>, rest: List<&2, U32>, room: Nat) -> Line:
  match acc:
    case Con{13, t}:
      LEnd{Bytes.rev(t), rest, room}
    case a:
      LEnd{Bytes.rev(a), rest, room}

# the next line: its bytes without the terminator, what follows it, and the head's
# remaining 64 KiB of room. A line is scanned once: what it has so far waits in the state
# until its LF arrives. A CR just before its LF is dropped; any other CR or an embedded NUL
# lands in a field name or value and is refused there.
def line.go(xs: List<&2, U32>, acc: List<&2, U32>, room: Nat) -> Line:
  match xs room:
    case Nil{} 0n:
      LNeed{acc, 0n}
    case _ 0n:
      LBad{"head over 64 KiB"}
    case Nil{} 1n+r:
      LNeed{acc, r}
    case Con{10, t} 1n+r:
      line.end(acc, t, r)
    case Con{h, t} 1n+r:
      line.go(t, h <> acc, r)

# "HTTP/1.0" or "HTTP/1.1", a space, three digits, then an optional reason
def status.digit(+c: U32) -> Bool:
  U32.is_le(48, c) && U32.is_le(c, 57)

def status.num(a: U32, b: U32, c: U32) -> U32:
  U32.add(U32.mul(U32.sub(a, 48), 100), U32.add(U32.mul(U32.sub(b, 48), 10), U32.sub(c, 48)))

def status.rest(code: U32, rest: List<&2, U32>) -> Stat:
  match rest:
    case Nil{}:
      SpOk{code}
    case Con{32, t}:
      SpOk{code}
    case _:
      SpBad{"bad status line"}

def status.code.go(v: U32, a: U32, b: U32, c: U32, rest: List<&2, U32>, ok: Bool) -> Stat:
  match ok:
    case False{}:
      SpBad{"bad status line"}
    case True{}:
      status.rest(status.num(a, b, c), rest)

def status.code(+v: U32, +a: U32, +b: U32, +c: U32, rest: List<&2, U32>) -> Stat:
  status.code.go(v, a, b, c, rest, (U32.is_eq(v, 48) || U32.is_eq(v, 49)) && status.digit(a) && status.digit(b) && status.digit(c))

# the version digit, the space, and the three status digits
def status.ver(xs: List<&2, U32>) -> Stat:
  match xs:
    case Con{+v, Con{32, Con{a, Con{b, Con{c, rest}}}}}:
      status.code(v, a, b, c, rest)
    case _:
      SpBad{"bad status line"}

def status.parse(xs: List<&2, U32>) -> Stat:
  match xs:
    case Con{72, Con{84, Con{84, Con{80, Con{47, Con{49, Con{46, rest}}}}}}}:
      status.ver(rest)
    case _:
      SpBad{"bad status line"}

def hdr.value.go(name: String, vb: List<&2, U32>, bad: Bool) -> Hd:
  match bad:
    case True{}:
      HdBad{"bad header value"}
    case False{}:
      HdOk{name, Bytes.to_ascii(ws.trim(vb))}

# the value: SP and HTAB trimmed, and a byte that isn't a field value is Bad
def hdr.value(name: String, +vb: List<&2, U32>) -> Hd:
  hdr.value.go(name, vb, val.bad(vb, False{}))

def hdr.name.go(xs: List<&2, U32>, st: U32, acc: String, vb: List<&2, U32>) -> Hd:
  match xs st:
    case Nil{} 1:
      hdr.value(String.reverse(acc), vb)
    case Nil{} _:
      HdBad{"bad header name"}
    case _ 0:
      HdBad{"bad header name"}
    case Con{+h, t} _:
      hdr.name.go(t, Bool.to_u32(is.tchar(h)), SCon{Chr{low.ch(h)}, acc}, vb)

# the name: token characters only, at least one, lowercased
def hdr.name(nb: List<&2, U32>, vb: List<&2, U32>) -> Hd:
  hdr.name.go(nb, 2, SNil{}, vb)

# "name: value", the name lowercased and the value trimmed
def hdr.split.go(xs: List<&2, U32>, acc: List<&2, U32>) -> Hd:
  match xs:
    case Nil{}:
      HdBad{"header without a colon"}
    case Con{58, t}:
      hdr.name(Bytes.rev(acc), t)
    case Con{h, t}:
      hdr.split.go(t, h <> acc)

def hdr.split(body: List<&2, U32>) -> Hd:
  hdr.split.go(body, Nil{})

# Chunk sizes
# -----------

def chunk.step.room(over: Bool, n: Nat, +digits: Nat, v: U32) -> Cs:
  match over:
    case True{}:
      CsBad{"chunk size is too large"}
    case False{}:
      CsGo{Nat.add(Nat.mul(n, 16n), U32.to_nat(v)), Nat.add(digits, 1n), False{}}

def chunk.step.ext(bad: Bool, n: Nat, digits: Nat) -> Cs:
  match bad:
    case True{}:
      CsBad{"bad chunk size"}
    case False{}:
      CsGo{n, digits, True{}}

def chunk.step.hex(hex: Bool, n: Nat, +digits: Nat, v: U32, h: U32) -> Cs:
  match hex:
    case True{}:
      chunk.step.room(Nat.is_le(8n, digits), n, digits, v)
    case False{}:
      chunk.step.ext(Nat.is_eq(digits, 0n) || Bool.not(U32.is_eq(h, 59)), n, digits)

def chunk.step.go(n: Nat, digits: Nat, ext: Bool, +v: U32, h: U32) -> Cs:
  match ext:
    case True{}:
      CsGo{n, digits, True{}}
    case False{}:
      chunk.step.hex(U32.is_lt(v, 16), n, digits, v, h)

# one byte of a chunk size line: 0-9 a-f A-F make a hex digit, ';' begins the extensions,
# and anything else is Bad
def chunk.step(v: U32, h: U32, st: Cs) -> Cs:
  match st:
    case CsGo{n, digits, ext}:
      chunk.step.go(n, digits, ext, v, h)
    case x:
      x

def chunk.size.end(none: Bool, n: Nat) -> Cs:
  match none:
    case True{}:
      CsBad{"bad chunk size"}
    case False{}:
      CsOk{n}

def chunk.size.go(xs: List<&2, U32>, st: Cs) -> Cs:
  match xs st:
    case _ CsBad{why}:
      CsBad{why}
    case Nil{} CsGo{n, digits, ext}:
      chunk.size.end(Nat.is_eq(digits, 0n), n)
    case Con{+h, t} CsGo{+n, +digits, +ext}:
      chunk.size.go(t, chunk.step(Bytes.hex.val(h), h, CsGo{n, digits, ext}))
    case _ x:
      x

# the size of one chunk: its hex digits, and the extensions after them, which are ignored
def chunk.size(body: List<&2, U32>) -> Cs:
  chunk.size.go(body, CsGo{0n, 0n, False{}})

# One step per state
# ------------------

def head.status(one: Bool, room: Nat, rest: List<&2, U32>, r: Stat) -> Mv:
  match r:
    case SpBad{why}:
      End{StBad{why}}
    case SpOk{code}:
      Cont{StHdr{room, code, Nil{}, one, Nil{}}, rest}

def head.status.line(one: Bool, l: Line) -> Mv:
  match l:
    case LBad{why}:
      End{StBad{why}}
    case LNeed{part, room}:
      Hold{StHead{room, one, part}, Nil{}}
    case LEnd{body, rest, room}:
      head.status(one, room, rest, status.parse(body))

def head.hdr.put(one: Bool, status: U32, hs: List<&2, Field()>, room: Nat, rest: List<&2, U32>, hd: Hd) -> Mv:
  match hd:
    case HdBad{why}:
      End{StBad{why}}
    case HdOk{name, value}:
      Cont{StHdr{room, status, (name, value) <> hs, one, Nil{}}, rest}

def head.hdr.field(one: Bool, status: U32, hs: List<&2, Field()>, room: Nat, rest: List<&2, U32>, body: List<&2, U32>, folded: Bool) -> Mv:
  match folded:
    case True{}:
      End{StBad{"folded header"}}
    case False{}:
      head.hdr.put(one, status, hs, room, rest, hdr.split(body))

def head.fin(+status: U32, hs: List<&2, Field()>, one: Bool, rest: List<&2, U32>) -> Mv:
  head.framed(one, status, Head{status, List.reverse(&2, Field(), hs)}, rest)

def head.hdr.empty(one: Bool, status: U32, hs: List<&2, Field()>, room: Nat, rest: List<&2, U32>, +body: List<&2, U32>, empty: Bool) -> Mv:
  match empty:
    case True{}:
      head.fin(status, hs, one, rest)
    case False{}:
      head.hdr.field(one, status, hs, room, rest, body, line.blank(body))

def head.hdr(one: Bool, status: U32, hs: List<&2, Field()>, room: Nat, rest: List<&2, U32>, +body: List<&2, U32>) -> Mv:
  head.hdr.empty(one, status, hs, room, rest, body, line.empty(body))

def head.hdr.line(one: Bool, status: U32, hs: List<&2, Field()>, l: Line) -> Mv:
  match l:
    case LBad{why}:
      End{StBad{why}}
    case LNeed{part, room}:
      Hold{StHdr{room, status, hs, one, part}, Nil{}}
    case LEnd{body, rest, room}:
      head.hdr(one, status, hs, room, rest, body)

def resp.len.left(left: Nat, rev: List<&2, U32>, rest: List<&2, U32>, head: Head) -> Mv:
  match left:
    case 0n:
      End{StDone{Resp{head, Bytes.rev(rev)}}}
    case _:
      Hold{StLen{left, rev, head}, Nil{}}

# content-length bytes: all of them, then the response is complete
def resp.len(head: Head, p: Part) -> Mv:
  match p:
    case Part{rev, rest, left}:
      resp.len.left(left, rev, rest, head)

def resp.chunk.left(left: Nat, rev: List<&2, U32>, rest: List<&2, U32>, head: Head) -> Mv:
  match left:
    case 0n:
      Cont{StChunkEnd{rev, head}, rest}
    case _:
      Hold{StChunk{left, rev, head}, Nil{}}

# one chunk's bytes
def resp.chunk(head: Head, p: Part) -> Mv:
  match p:
    case Part{rev, rest, left}:
      resp.chunk.left(left, rev, rest, head)

# the CRLF after a chunk's bytes
def resp.cend(acc: List<&2, U32>, head: Head, buf: List<&2, U32>) -> Mv:
  match buf:
    case Nil{}:
      Hold{StChunkEnd{acc, head}, Nil{}}
    case Con{13, Nil{}}:
      Hold{StChunkEnd{acc, head}, Con{13, Nil{}}}
    case Con{13, Con{10, t}}:
      Cont{StChunkSize{65536n, acc, head, Nil{}}, t}
    case Con{10, t}:
      Cont{StChunkSize{65536n, acc, head, Nil{}}, t}
    case _:
      End{StBad{"bad chunk end"}}

def resp.csize.size(n: Nat, acc: List<&2, U32>, head: Head, rest: List<&2, U32>) -> Mv:
  match n:
    case 0n:
      Cont{StTrailer{65536n, acc, head, Nil{}}, rest}
    case _:
      Cont{StChunk{n, acc, head}, rest}

def resp.csize.at(acc: List<&2, U32>, head: Head, room: Nat, rest: List<&2, U32>, c: Cs) -> Mv:
  match c:
    case CsBad{why}:
      End{StBad{why}}
    case CsOk{n}:
      resp.csize.size(n, acc, head, rest)
    case CsGo{n, digits, ext}:
      End{StBad{"bad chunk size"}}

def resp.csize(acc: List<&2, U32>, head: Head, l: Line) -> Mv:
  match l:
    case LBad{why}:
      End{StBad{why}}
    case LNeed{part, room}:
      Hold{StChunkSize{room, acc, head, part}, Nil{}}
    case LEnd{body, rest, room}:
      resp.csize.at(acc, head, room, rest, chunk.size(body))

def resp.trailer.at(acc: List<&2, U32>, head: Head, room: Nat, rest: List<&2, U32>, body: List<&2, U32>, empty: Bool) -> Mv:
  match empty:
    case True{}:
      End{StDone{Resp{head, Bytes.rev(acc)}}}
    case False{}:
      Cont{StTrailer{room, acc, head, Nil{}}, rest}

# the trailers after the last chunk: lines until a blank one, and they are ignored
def resp.trailer(acc: List<&2, U32>, head: Head, l: Line) -> Mv:
  match l:
    case LBad{why}:
      End{StBad{why}}
    case LNeed{part, room}:
      Hold{StTrailer{room, acc, head, part}, Nil{}}
    case LEnd{+body, rest, room}:
      resp.trailer.at(acc, head, room, rest, body, line.empty(body))

def resp.till.go(acc: List<&2, U32>, head: Head, buf: List<&2, U32>, empty: Bool) -> Mv:
  match empty:
    case True{}:
      Hold{StTillEof{acc, head}, Nil{}}
    case False{}:
      Cont{StTillEof{Bytes.rev.onto(buf, acc), head}, Nil{}}

# a body with no content-length and no chunked coding: everything until eof
def resp.till(acc: List<&2, U32>, head: Head, +buf: List<&2, U32>) -> Mv:
  resp.till.go(acc, head, buf, line.empty(buf))

# one step of the machine: hand the state its bytes, and say what happened
def take.step(st: St, buf: List<&2, U32>) -> Mv:
  match st:
    case StHead{r, o, p}:
      head.status.line(o, line.go(buf, p, r))
    case StHdr{r, s, hs, o, p}:
      head.hdr.line(o, s, hs, line.go(buf, p, r))
    case StLen{n, acc, head}:
      resp.len(head, take.rev(buf, n, acc))
    case StChunkSize{r, acc, head, p}:
      resp.csize(acc, head, line.go(buf, p, r))
    case StChunk{n, acc, head}:
      resp.chunk(head, take.rev(buf, n, acc))
    case StChunkEnd{acc, head}:
      resp.cend(acc, head, buf)
    case StTrailer{r, acc, head, p}:
      resp.trailer(acc, head, line.go(buf, p, r))
    case StTillEof{acc, head}:
      resp.till(acc, head, buf)
    case StDone{resp}:
      Hold{StDone{resp}, Nil{}}
    case StBad{why}:
      Hold{StBad{why}, Nil{}}

# the machine: one fuel per step, and every step that makes progress eats a byte, so the
# bytes fed bound the steps. A step that needs more bytes ends the run.
def run(fuel: Nat, m: Mv) -> St & List<&2, U32>:
  match fuel m:
    case _ Hold{st, buf}:
      (st, buf)
    case _ End{st}:
      (st, Nil{})
    case 0n Cont{st, buf}:
      (st, buf)
    case 1n+f Cont{st, buf}:
      run(f, take.step(st, buf))

# The parser
# ----------

# a fresh parser. head_only is a HEAD request: no body is read, whatever the headers say.
def parser(head_only: Bool) -> Parser:
  P{StHead{65536n, head_only, Nil{}}, Nil{}}

def feed.p(r: St & List<&2, U32>) -> Parser:
  match r:
    case (s, b):
      P{s, b}

def feed.run(st: St, fuel: Nat, buf: List<&2, U32>) -> Parser:
  feed.p(run(fuel, Cont{st, buf}))

def feed.go(st: St, b: List<&2, U32> & Nat, c: List<&2, U32> & Nat) -> Parser:
  (buf, nb) = b
  (chunk, nc) = c
  feed.run(st, Nat.add(Nat.add(nb, nc), 1n), Bytes.rev.onto(Bytes.rev(buf), chunk))

# hand the parser the next bytes of the response
def feed(p: Parser, chunk: List<&2, U32>) -> Parser:
  match p:
    case P{st, buf}:
      feed.go(st, len.keep(buf), len.keep(chunk))

def eof.of(st: St, buf: List<&2, U32>) -> St:
  match st:
    case StTillEof{acc, head}:
      StDone{Resp{head, Bytes.rev(Bytes.rev.onto(buf, acc))}}
    case StDone{resp}:
      StDone{resp}
    case StBad{why}:
      StBad{why}
    case _:
      StBad{"eof with the response unfinished"}

# the peer closed the connection
def eof(p: Parser) -> Parser:
  match p:
    case P{st, buf}:
      P{eof.of(st, buf), Nil{}}

def step.of(st: St) -> Step:
  match st:
    case StDone{resp}:
      Got{resp}
    case StBad{why}:
      Bad{why}
    case _:
      More{}

# what the parser has so far: More, Got, or Bad
def step(p: Parser) -> Step:
  match p:
    case P{st, buf}:
      step.of(st)
