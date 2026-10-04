# http: the HTTP client cha calls. One request per connection (connection: close), over a
# plain socket for http:// and over TLS for https:// (chaki's own TLS 1.3, or the system's
# OpenSSL), following redirects safely: a hop to another origin drops the credentials, and
# an https -> http hop is refused.
import Base
import ./bytes.bend as Bytes
import ./url.bend as Url
import ./http1.bend as Http1
import ./sys.bend as Sys
import ./ossl.bend as Ssl
import ./x509.bend as X509
import ./x509v.bend as X509v
import ./tlsio.bend as Tlsio

type Transport is Data:
  Bend{}
  Ossl{}

type Client is Data:
  Client{tls: Transport, anchors: List<&2, X509.Cert>, ms: U32}

type Res is Data:
  Res{status: U32, headers: List<&2, Http1.Field()>, body: List<&2, U32>, url: String}

def client.loaded(+ms: U32, r: Result<&1, &1, U32 & String, List<&2, X509.Cert>>) -> Result<&1, &1, U32 & String, Client>:
  match r:
    case Done{anchors}:
      Done{Client{Bend{}, anchors, ms}}
    case Fail{e}:
      Fail{e}

# a client. Bend{} reads the system's trust anchors once, here; Ossl{} needs nothing up
# front, OpenSSL finds them itself.
def client(t: Transport, +ms: U32) -> IO(Result<&1, &1, U32 & String, Client>):
  match t:
    case Bend{}:
      do IO<Result<&1, &1, U32 & String, Client>>:
        r : Result<&1, &1, U32 & String, List<&2, X509.Cert>> <- X509v.load()
        return client.loaded(ms, r)
    case Ossl{}:
      IO.pure(Result<&1, &1, U32 & String, Client>, Done{Client{Ossl{}, Nil{}, ms}})

# Time
# ----
# Deadlines are whole seconds of the wall clock: Sys.now is cheap and a U32, and a request's
# bound is minutes, not milliseconds.

def deadline(+now: U32, +ms: U32) -> U32:
  (now + ((ms + 999 : U32) / 1000 : U32) : U32)

# what's left of a deadline, in ms; 1 once it has passed, so the next wait fails at once
def left.ms(+deadline: U32, +now: U32) -> U32:
  Bool.pick(U32, U32.is_lt(now, deadline), ((deadline - now : U32) * 1000 : U32), 1)

# The connection
# --------------

# a plain socket, an OpenSSL session on one, or chaki's own TLS connection
type Wire is Type:
  Plain{sock: Socket}
  Ssl{sock: Socket}
  Own{c: Tlsio.Conn}

def plain.back(r: Socket & Result<&1, &1, U32 & String, Unit>) -> Wire & Result<&1, &1, U32 & String, Unit>:
  (s, g) = r
  (Plain{s}, g)

def ssl.back(r: Socket & Result<&1, &1, U32 & String, Unit>) -> Wire & Result<&1, &1, U32 & String, Unit>:
  (s, g) = r
  (Ssl{s}, g)

def own.back(r: Tlsio.Conn & Result<&1, &1, U32 & String, Unit>) -> Wire & Result<&1, &1, U32 & String, Unit>:
  (c, g) = r
  (Own{c}, g)

def io.send(w: Wire, data: List<&2, U32>) -> IO(Wire & Result<&1, &1, U32 & String, Unit>):
  match w:
    case Plain{sock}:
      IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Wire & Result<&1, &1, U32 & String, Unit>, Sys.send(sock, data), r => IO.pure(Wire & Result<&1, &1, U32 & String, Unit>, plain.back(r)))
    case Ssl{sock}:
      IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Wire & Result<&1, &1, U32 & String, Unit>, Ssl.send(sock, data), r => IO.pure(Wire & Result<&1, &1, U32 & String, Unit>, ssl.back(r)))
    case Own{c}:
      IO.bind(Tlsio.Conn & Result<&1, &1, U32 & String, Unit>, Wire & Result<&1, &1, U32 & String, Unit>, Tlsio.send(c, data), r => IO.pure(Wire & Result<&1, &1, U32 & String, Unit>, own.back(r)))

def plain.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> Wire & Result<&1, &1, U32 & String, List<&2, U32>>:
  (s, g) = r
  (Plain{s}, g)

def ssl.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> Wire & Result<&1, &1, U32 & String, List<&2, U32>>:
  (s, g) = r
  (Ssl{s}, g)

def own.got(r: Tlsio.Conn & Result<&1, &1, U32 & String, List<&2, U32>>) -> Wire & Result<&1, &1, U32 & String, List<&2, U32>>:
  (c, g) = r
  (Own{c}, g)

def io.recv(w: Wire, +max: U32, +ms: U32) -> IO(Wire & Result<&1, &1, U32 & String, List<&2, U32>>):
  match w:
    case Plain{sock}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Wire & Result<&1, &1, U32 & String, List<&2, U32>>, Sys.recv(sock, max, ms), r => IO.pure(Wire & Result<&1, &1, U32 & String, List<&2, U32>>, plain.got(r)))
    case Ssl{sock}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Wire & Result<&1, &1, U32 & String, List<&2, U32>>, Ssl.recv(sock, max, ms), r => IO.pure(Wire & Result<&1, &1, U32 & String, List<&2, U32>>, ssl.got(r)))
    case Own{c}:
      IO.bind(Tlsio.Conn & Result<&1, &1, U32 & String, List<&2, U32>>, Wire & Result<&1, &1, U32 & String, List<&2, U32>>, Tlsio.recv(c, max, ms), r => IO.pure(Wire & Result<&1, &1, U32 & String, List<&2, U32>>, own.got(r)))

def io.close(w: Wire) -> IO(Unit):
  match w:
    case Plain{sock}:
      Socket.close(sock)
    case Ssl{sock}:
      Ssl.close(sock)
    case Own{c}:
      Tlsio.close(c)

# Reading a response
# ------------------

type Rd is Type:
  Reading{w: Wire, p: Http1.Parser}
  Ended{w: Wire, r: Result<&1, &1, String, Http1.Resp>}

def rd.judge(w: Wire, p: Http1.Parser, st: Http1.Step) -> Rd:
  match st:
    case Http1.More{}:
      Reading{w, p}
    case Http1.Got{r}:
      Ended{w, Done{r}}
    case Http1.Bad{e}:
      Ended{w, Fail{"malformed response: " ++ e}}

def rd.after(w: Wire, +p: Http1.Parser) -> Rd:
  rd.judge(w, p, Http1.step(p))

# an empty read is the peer closing
def rd.fed.if(p: Http1.Parser, bs: List<&2, U32>, empty: Bool) -> Http1.Parser:
  match empty:
    case True{}:
      Http1.eof(p)
    case False{}:
      Http1.feed(p, bs)

def rd.why(+c: U32, +m: String) -> String:
  Bool.pick(String, U32.is_eq(c, 110), "timed out", "read failed: " ++ m)

def rd.got.of(p: Http1.Parser, w: Wire, g: Result<&1, &1, U32 & String, List<&2, U32>>) -> Rd:
  match g:
    case Done{+bs}:
      rd.after(w, rd.fed.if(p, bs, List.is_empty(&2, U32, bs)))
    case Fail{(c, m)}:
      Ended{w, Fail{rd.why(c, m)}}

def rd.got(p: Http1.Parser, r: Wire & Result<&1, &1, U32 & String, List<&2, U32>>) -> Rd:
  (w, g) = r
  rd.got.of(p, w, g)

# read until the parser has a whole response, it fails, or the deadline passes
def rd.go(fuel: Nat, +deadline: U32, st: Rd) -> IO(Wire & Result<&1, &1, String, Http1.Resp>):
  match fuel st:
    case 0n Reading{w, p}:
      IO.pure(Wire & Result<&1, &1, String, Http1.Resp>, (w, Fail{"response too long"}))
    case 0n Ended{w, r}:
      IO.pure(Wire & Result<&1, &1, String, Http1.Resp>, (w, r))
    case 1n+k Ended{w, r}:
      IO.pure(Wire & Result<&1, &1, String, Http1.Resp>, (w, r))
    case 1n+k Reading{w, p}:
      do IO<Wire & Result<&1, &1, String, Http1.Resp>>:
        now : U32 <- Sys.now()
        r : Wire & Result<&1, &1, U32 & String, List<&2, U32>> <- io.recv(w, 65536, left.ms(deadline, now))
        rd.go(k, deadline, rd.got(p, r))

# One exchange
# ------------

def once.done(x: Wire & Result<&1, &1, String, Http1.Resp>) -> IO(Result<&1, &1, String, Http1.Resp>):
  (w, r) = x
  do IO<Result<&1, &1, String, Http1.Resp>>:
    io.close(w)
    return r

def once.sent.of(+deadline: U32, +method: String, w: Wire, g: Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, String, Http1.Resp>):
  match g:
    case Fail{(c, m)}:
      do IO<Result<&1, &1, String, Http1.Resp>>:
        io.close(w)
        return Fail{"write failed: " ++ m}
    case Done{u}:
      do IO<Result<&1, &1, String, Http1.Resp>>:
        x : Wire & Result<&1, &1, String, Http1.Resp> <- rd.go(200000n, deadline, Reading{w, Http1.parser(String.eq(method, "HEAD"))})
        once.done(x)

def once.sent(+deadline: U32, +method: String, r: Wire & Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, String, Http1.Resp>):
  (w, g) = r
  once.sent.of(deadline, method, w, g)

def once.send.of(+deadline: U32, +method: String, w: Wire, m: Maybe<&2, List<&2, U32>>) -> IO(Result<&1, &1, String, Http1.Resp>):
  match m:
    case None{}:
      do IO<Result<&1, &1, String, Http1.Resp>>:
        io.close(w)
        return Fail{"a header or the target can't go on the wire"}
    case Some{bs}:
      do IO<Result<&1, &1, String, Http1.Resp>>:
        r : Wire & Result<&1, &1, U32 & String, Unit> <- io.send(w, bs)
        once.sent(deadline, method, r)

def once.send(+deadline: U32, +method: String, +hh: String, +target: String, hs: List<&2, Http1.Field()>, body: List<&2, U32>, w: Wire) -> IO(Result<&1, &1, String, Http1.Resp>):
  once.send.of(deadline, method, w, Http1.request(method, hh, target, hs, body))

def once.shook.of(+deadline: U32, +method: String, +host: String, +hh: String, +target: String, hs: List<&2, Http1.Field()>, body: List<&2, U32>, sock: Socket, g: Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, String, Http1.Resp>):
  match g:
    case Fail{(c, m)}:
      do IO<Result<&1, &1, String, Http1.Resp>>:
        Ssl.close(sock)
        return Fail{"tls with " ++ host ++ ": " ++ m}
    case Done{u}:
      once.send(deadline, method, hh, target, hs, body, Ssl{sock})

def once.shook(+deadline: U32, +method: String, +host: String, +hh: String, +target: String, hs: List<&2, Http1.Field()>, body: List<&2, U32>, r: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, String, Http1.Resp>):
  (sock, g) = r
  once.shook.of(deadline, method, host, hh, target, hs, body, sock, g)

def once.owned(+deadline: U32, +method: String, +host: String, +hh: String, +target: String, hs: List<&2, Http1.Field()>, body: List<&2, U32>, r: Result<&1, &1, U32 & String, Tlsio.Conn>) -> IO(Result<&1, &1, String, Http1.Resp>):
  match r:
    case Fail{(c, m)}:
      IO.pure(Result<&1, &1, String, Http1.Resp>, Fail{"tls with " ++ host ++ ": " ++ m})
    case Done{conn}:
      once.send(deadline, method, hh, target, hs, body, Own{conn})

def is.bend(t: Transport) -> Bool:
  match t:
    case Bend{}:
      True{}
    case Ossl{}:
      False{}

# how the bytes travel: in the clear, through OpenSSL, or through chaki's own TLS
type Way is Data:
  Clear{}
  Openssl{}
  Bendtls{}

def way.of(t: Transport, tls: Bool) -> Way:
  match tls:
    case False{}:
      Clear{}
    case True{}:
      Bool.pick(Way, is.bend(t), Bendtls{}, Openssl{})

def once.secure(way: Way, +anchors: List<&2, X509.Cert>, +deadline: U32, +method: String, +host: String, +hh: String, +target: String, hs: List<&2, Http1.Field()>, body: List<&2, U32>, sock: Socket) -> IO(Result<&1, &1, String, Http1.Resp>):
  match way:
    case Openssl{}:
      do IO<Result<&1, &1, String, Http1.Resp>>:
        now : U32 <- Sys.now()
        r : Socket & Result<&1, &1, U32 & String, Unit> <- Ssl.connect(sock, host, left.ms(deadline, now))
        once.shook(deadline, method, host, hh, target, hs, body, r)
    case Bendtls{}:
      do IO<Result<&1, &1, String, Http1.Resp>>:
        now : U32 <- Sys.now()
        r : Result<&1, &1, U32 & String, Tlsio.Conn> <- Tlsio.connect(sock, host, anchors, left.ms(deadline, now))
        once.owned(deadline, method, host, hh, target, hs, body, r)
    case Clear{}:
      once.send(deadline, method, hh, target, hs, body, Plain{sock})

def once.dialed(way: Way, +anchors: List<&2, X509.Cert>, +deadline: U32, +method: String, +host: String, +hh: String, +target: String, hs: List<&2, Http1.Field()>, body: List<&2, U32>, d: Result<&1, &1, U32 & String, Socket>) -> IO(Result<&1, &1, String, Http1.Resp>):
  match d:
    case Fail{(c, m)}:
      IO.pure(Result<&1, &1, String, Http1.Resp>, Fail{"can't connect to " ++ host ++ ": " ++ m})
    case Done{sock}:
      once.secure(way, anchors, deadline, method, host, hh, target, hs, body, sock)

def once.at(way: Way, +anchors: List<&2, X509.Cert>, +deadline: U32, +method: String, +host: String, +port: U32, +hh: String, +target: String, hs: List<&2, Http1.Field()>, body: List<&2, U32>) -> IO(Result<&1, &1, String, Http1.Resp>):
  do IO<Result<&1, &1, String, Http1.Resp>>:
    now : U32 <- Sys.now()
    d : Result<&1, &1, U32 & String, Socket> <- Sys.dial(host, port, left.ms(deadline, now))
    once.dialed(way, anchors, deadline, method, host, hh, target, hs, body, d)

# one request on one connection: dial, maybe a TLS handshake, write, read to the end
def once(t: Transport, +anchors: List<&2, X509.Cert>, +deadline: U32, +method: String, +u: Url.Url, hs: List<&2, Http1.Field()>, body: List<&2, U32>) -> IO(Result<&1, &1, String, Http1.Resp>):
  match u:
    case Url.Url{+scheme, +host, +port, target}:
      once.at(way.of(t, String.eq(scheme, "https")), anchors, deadline, method, host, port, Url.host_header(u), target, hs, body)

# Redirects
# ---------

type Hop is Data:
  Hop{method: String, url: String, headers: List<&2, Http1.Field()>, body: List<&2, U32>}

type St is Type:
  Go{h: Hop}
  Got{h: Hop, u: Url.Url, r: Result<&1, &1, String, Http1.Resp>}
  Out{r: Result<&1, &1, String, Res>}

def redirect.code(+s: U32) -> Bool:
  Bool.or(Bool.or(U32.is_eq(s, 301), U32.is_eq(s, 302)), Bool.or(U32.is_eq(s, 303), Bool.or(U32.is_eq(s, 307), U32.is_eq(s, 308))))

def drop.has(+name: String, names: List<&2, String>) -> Bool:
  match names:
    case Nil{}:
      False{}
    case Con{+n, t}:
      Bool.or(String.eq(n, name), drop.has(name, t))

def drop.keep(+k: String, +v: String, acc: List<&2, Http1.Field()>, gone: Bool) -> List<&2, Http1.Field()>:
  match gone:
    case True{}:
      acc
    case False{}:
      (k, v) <> acc

def drop.go(+names: List<&2, String>, hs: List<&2, Http1.Field()>, acc: List<&2, Http1.Field()>) -> List<&2, Http1.Field()>:
  match hs:
    case Nil{}:
      List.reverse(&2, Http1.Field(), acc)
    case Con{(+k, +v), t}:
      drop.go(names, t, drop.keep(k, v, acc, drop.has(String.to_lower(k), names)))

# the headers but those named (names lowercase; header names compare case-insensitively)
def drop(+names: List<&2, String>, hs: List<&2, Http1.Field()>) -> List<&2, Http1.Field()>:
  drop.go(names, hs, Nil{})

def scheme.of(u: Url.Url) -> String:
  match u:
    case Url.Url{scheme, h, p, t}:
      scheme

# the next hop, as RFC 9110 15.4 and WHATWG fetch apply it: 307 and 308 keep the method and
# body; 301, 302 and 303 become a GET without them (a HEAD stays a HEAD); another origin
# loses authorization and cookie
def judge.go(h: Hop, +u: Url.Url, +v: Url.Url, +status: U32) -> St:
  match h:
    case Hop{+method, url, +hs, +body}:
      +keep = Bool.or(U32.is_eq(status, 307), U32.is_eq(status, 308))
      +head = String.eq(method, "HEAD")
      +hs1 = Bool.pick(List<&2, Http1.Field()>, keep, hs, drop(["content-type", "content-length"], hs))
      +cross = Bool.not(String.eq(Url.origin(u), Url.origin(v)))
      Go{Hop{Bool.pick(String, Bool.or(keep, head), method, "GET"), Url.show(v), Bool.pick(List<&2, Http1.Field()>, cross, drop(["authorization", "cookie"], hs1), hs1), Bool.pick(List<&2, U32>, keep, body, Nil{})}}

def judge.hop(h: Hop, +u: Url.Url, +v: Url.Url, +status: U32, down: Bool) -> St:
  match down:
    case True{}:
      Out{Fail{"refused a redirect from https to http"}}
    case False{}:
      judge.go(h, u, v, status)

def judge.next(h: Hop, +u: Url.Url, +status: U32, m: Maybe<&2, Url.Url>) -> St:
  match m:
    case None{}:
      Out{Fail{"a redirect to a location that isn't a url"}}
    case Some{+v}:
      judge.hop(h, u, v, status, Bool.and(String.eq(scheme.of(u), "https"), String.eq(scheme.of(v), "http")))

def judge.answer(h: Hop, +status: U32, rhs: List<&2, Http1.Field()>, rbody: List<&2, U32>) -> St:
  match h:
    case Hop{m, url, hs, b}:
      Out{Done{Res{status, rhs, rbody, url}}}

def judge.resp(h: Hop, +u: Url.Url, +status: U32, +rhs: List<&2, Http1.Field()>, rbody: List<&2, U32>, +loc: String, follow: Bool) -> St:
  match follow:
    case False{}:
      judge.answer(h, status, rhs, rbody)
    case True{}:
      judge.next(h, u, status, Url.resolve(u, loc))

# what a response means for the walk: the answer, or the next hop
def judge(h: Hop, +u: Url.Url, r: Result<&1, &1, String, Http1.Resp>) -> St:
  match r:
    case Fail{w}:
      Out{Fail{w}}
    case Done{Http1.Resp{Http1.Head{+status, +rhs}, rbody}}:
      +loc = Http1.header(Http1.Head{status, rhs}, "location")
      judge.resp(h, u, status, rhs, rbody, loc, Bool.and(redirect.code(status), Bool.not(String.is_empty(loc))))

def step.at(t: Transport, +anchors: List<&2, X509.Cert>, +deadline: U32, +method: String, +url: String, +hs: List<&2, Http1.Field()>, +body: List<&2, U32>, m: Maybe<&2, Url.Url>) -> IO(St):
  match m:
    case None{}:
      IO.pure(St, Out{Fail{"not an http or https url: " ++ url}})
    case Some{+u}:
      do IO<St>:
        r : Result<&1, &1, String, Http1.Resp> <- once(t, anchors, deadline, method, u, hs, body)
        return Got{Hop{method, url, hs, body}, u, r}

def step(t: Transport, +anchors: List<&2, X509.Cert>, +deadline: U32, h: Hop) -> IO(St):
  match h:
    case Hop{+method, +url, hs, body}:
      step.at(t, anchors, deadline, method, url, hs, body, Url.parse(url))

# a hop is two steps (request, judge), so 10 redirects fit in 23
def walk(fuel: Nat, +t: Transport, +anchors: List<&2, X509.Cert>, +deadline: U32, st: St) -> IO(Result<&1, &1, String, Res>):
  match fuel st:
    case 0n Out{r}:
      IO.pure(Result<&1, &1, String, Res>, r)
    case 0n Go{h}:
      IO.pure(Result<&1, &1, String, Res>, Fail{"too many redirects"})
    case 0n Got{h, u, r}:
      IO.pure(Result<&1, &1, String, Res>, Fail{"too many redirects"})
    case 1n+k Out{r}:
      IO.pure(Result<&1, &1, String, Res>, r)
    case 1n+k Go{h}:
      IO.bind(St, Result<&1, &1, String, Res>, step(t, anchors, deadline, h), s => walk(k, t, anchors, deadline, s))
    case 1n+k Got{h, +u, r}:
      walk(k, t, anchors, deadline, judge(h, u, r))

# one request, following up to 10 redirects. headers are lowercase names. Fail{reason} for
# anything that isn't an HTTP response; a reason never holds a header value.
def fetch(c: Client, method: String, url: String, headers: List<&2, Http1.Field()>, body: List<&2, U32>) -> IO(Result<&1, &1, String, Res>):
  match c:
    case Client{+t, +anchors, +ms}:
      do IO<Result<&1, &1, String, Res>>:
        now : U32 <- Sys.now()
        walk(23n, t, anchors, deadline(now, ms), Go{Hop{method, url, headers, body}})
