# hop: what a redirect means for the next request, RFC 9110 15.4's method, body and
# credential rules.
import Base
import ./url.bend as Url
import ./http1.bend as Http1

# one request in a walk of redirects: the method, the url as text, the headers (lowercase
# names) and the body
type Hop is Data:
  Hop{method: String, url: String, headers: List<&2, Http1.Field()>, body: List<&2, U32>}

# what a response means for the walk: another request, the response itself (nothing to
# follow), or a refusal
type Next is Data:
  Follow{h: Hop}
  Answer{h: Hop}
  Refuse{why: String}

# the statuses RFC 9110 15.4 calls redirects
def redirect.code(+s: U32) -> Bool:
  Bool.or(Bool.or(U32.is_eq(s, 301), U32.is_eq(s, 302)), Bool.or(U32.is_eq(s, 303), Bool.or(U32.is_eq(s, 307), U32.is_eq(s, 308))))

# whether the status sends the method and the body again: 307 and 308
def redirect.keeps(+s: U32) -> Bool:
  Bool.or(U32.is_eq(s, 307), U32.is_eq(s, 308))

# Dropping headers
# ----------------

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

# The next request
# ----------------

# the method it uses: the request's own when the status sends it again or it was a HEAD;
# 301, 302 and 303 turn everything else into a GET
def move.method(+method: String, keep: Bool, head: Bool) -> String:
  Bool.pick(String, Bool.or(keep, head), method, "GET")

# the headers it carries: a dropped body takes its framing with it
def move.headers(+hs: List<&2, Http1.Field()>, keep: Bool) -> List<&2, Http1.Field()>:
  Bool.pick(List<&2, Http1.Field()>, keep, hs, drop(["content-type", "content-length"], hs))

# the body it carries: sent again only when the status keeps it
def move.body(+body: List<&2, U32>, keep: Bool) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, keep, body, Nil{})

# the credentials it carries: another origin gets none
def move.creds(+hs: List<&2, Http1.Field()>, cross: Bool) -> List<&2, Http1.Field()>:
  Bool.pick(List<&2, Http1.Field()>, cross, drop(["authorization", "cookie"], hs), hs)

# the next hop, as RFC 9110 15.4 and WHATWG fetch apply it: 301, 302 and 303 drop the body
# and its framing headers and turn anything but a HEAD into a GET, 307 and 308 send it again,
# and another origin loses authorization and cookie
def judge.go(h: Hop, +u: Url.Url, +v: Url.Url, +status: U32) -> Hop:
  match h:
    case Hop{+method, url, +hs, +body}:
      +keep = redirect.keeps(status)
      +head = String.eq(method, "HEAD")
      +cross = Bool.not(String.eq(Url.origin(u), Url.origin(v)))
      Hop{move.method(method, keep, head), Url.show(v), move.creds(move.headers(hs, keep), cross), move.body(body, keep)}

# whether the hop leaves https for http, where the request would travel in the clear
def judge.down(+u: Url.Url, +v: Url.Url) -> Bool:
  Bool.and(String.eq(scheme.of(u), "https"), String.eq(scheme.of(v), "http"))

def judge.hop(h: Hop, +u: Url.Url, +v: Url.Url, +status: U32, down: Bool) -> Next:
  match down:
    case True{}:
      Refuse{"refused a redirect from https to http"}
    case False{}:
      Follow{judge.go(h, u, v, status)}

def judge.next(h: Hop, +u: Url.Url, +status: U32, m: Maybe<&2, Url.Url>) -> Next:
  match m:
    case None{}:
      Refuse{"a redirect to a location that isn't a url"}
    case Some{+v}:
      judge.hop(h, u, v, status, judge.down(u, v))

# whether the status and the Location ask for another request
def judge.follows(+status: U32, +loc: String) -> Bool:
  Bool.and(redirect.code(status), Bool.not(String.is_empty(loc)))

# what a response means for the walk: another request, the answer itself, or a refusal
def judge.resp(h: Hop, +u: Url.Url, +status: U32, +loc: String, follow: Bool) -> Next:
  match follow:
    case False{}:
      Answer{h}
    case True{}:
      judge.next(h, u, status, Url.resolve(u, loc))
