# api: requests to a forge's REST API, decoded replies, and pagination.
import Base
import bend-kit-hairpin@0.1.0.0/hairpin.bend as Hairpin
import bend-kit-http@0.23.0.1/http.bend as Http
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import 0xcfc8be7b076f41f95c8e118383892d55/encoding.bend as Enc
import ./ctx.bend as Ctx

# A finished request: the status, the next page's URL ("" when last) and the body.
# Broke is a request that never got a status; why never holds the token.
type Reply is Type:
  Reply{status: U32, next: String, body: Bytes.Bytes}
  Broke{why: String}

def base(f: Ctx.Forge, +host: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "https://" ++ host ++ "/api/v1/"
    case Ctx.GitHub{}:
      "https://api.github.com/"

def scheme(f: Ctx.Forge) -> String:
  match f:
    case Ctx.Gitea{}:
      "token "
    case Ctx.GitHub{}:
      "Bearer "

def authed(c: Hairpin.Client, f: Ctx.Forge, +tok: String, none: Bool) -> Hairpin.Client:
  match none:
    case True{}:
      c
    case False{}:
      Hairpin.header(c, "authorization", scheme(f) ++ tok)

def client(repo: Ctx.Repo, +tok: String) -> Hairpin.Client:
  match repo:
    case Ctx.Repo{+f, +h, o, n}:
      c = Hairpin.header(Hairpin.header(Hairpin.base(Hairpin.new(), base(f, h)), "accept", "application/json"), "user-agent", "cha")
      authed(c, f, tok, String.is_empty(tok))

# repos/<owner>/<name>/ + rest
def path(repo: Ctx.Repo, +rest: String) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      "repos/" ++ o ++ "/" ++ n ++ "/" ++ rest

# Link headers
# ------------

def link.part.if(+p: String, next: Bool) -> String:
  match next:
    case True{}:
      Ctx.first(String.split(Ctx.last(String.split(p, '<')), '>'))
    case False{}:
      ""

def link.scan(ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{+p, rest}:
      Ctx.or(link.part.if(p, String.contains(p, "rel=\"next\"")), link.scan(rest))

# the rel="next" URL of a Link header, "" when there is none
def link.next(+h: String) -> String:
  link.scan(String.split(h, ','))

# Errors
# ------

def why(e: Http.Err) -> String:
  match e:
    case Http.ErrUrl{}:
      "bad url"
    case Http.ErrDns{}:
      "dns lookup failed"
    case Http.ErrConnect{c, w}:
      "can't connect: " ++ w
    case Http.ErrTls{c, w}:
      "tls failed: " ++ w
    case Http.ErrRead{c, w}:
      "read failed: " ++ w
    case Http.ErrWrite{c, w}:
      "write failed: " ++ w
    case Http.ErrTimeout{}:
      "timed out"
    case Http.ErrRedirect{}:
      "too many redirects"
    case Http.ErrBad{}:
      "malformed response"

def reply.of(got: Result<&1, &1, Http.Err, Http.Res>) -> Reply:
  match got:
    case Done{Http.Res{+status, +headers, body}}:
      Reply{status, link.next(Http.header(headers, "link")), body}
    case Fail{e}:
      Broke{why(e)}

def reply(r: Hairpin.Client & Result<&1, &1, Http.Err, Http.Res>) -> IO(Reply):
  (c, got) = r
  do IO<Reply>:
    Hairpin.close(c)
    return reply.of(got)

# Requests
# --------

def json.headers() -> Map<&2, List<&2, String>>:
  Map.set(&2, List<&2, String>, Map.new(&2, List<&2, String>), "content-type", ["application/json"])

# one request; url is relative to the forge's API root, or absolute
def send(repo: Ctx.Repo, +tok: String, +method: String, url: String, body: Maybe<&1, Json.Val>) -> IO(Reply):
  match body:
    case None{}:
      do IO<Reply>:
        r : Hairpin.Client & Result<&1, &1, Http.Err, Http.Res> <- Hairpin.request(client(repo, tok), method, url, Map.new(&2, List<&2, String>), Http.from_string(""))
        reply(r)
    case Some{v}:
      do IO<Reply>:
        r : Hairpin.Client & Result<&1, &1, Http.Err, Http.Res> <- Hairpin.request(client(repo, tok), method, url, json.headers(), Json.encode.bytes(v))
        reply(r)

def get(repo: Ctx.Repo, +tok: String, url: String) -> IO(Reply):
  send(repo, tok, "GET", url, None{})

# Decoding
# --------

def ok(+status: U32) -> Bool:
  (status >= 200 : U32) && (status < 300 : U32)

def text(b: Bytes.Bytes) -> String:
  Enc.utf8.decode(b)

# a JSON string as text
def utf8(s: String) -> Json.Val:
  Json.Str{Json.utf8(s)}

def str.of(m: Maybe<&1, Json.Val>) -> String:
  match m:
    case Some{Json.Str{s}}:
      Enc.utf8.decode(s)
    case Some{Json.Num{s}}:
      Bytes.to_string(s)
    case Some{Json.Flag{on}}:
      Bool.show(on)
    case x:
      ""

# a string, number or bool field of an object, as text; "" when missing
def str(v: Json.Val, k: String) -> String:
  str.of(Json.get(v, k))

# Flat objects
# ------------
# A JSON object flattened once into text fields, so a command can read as many as it likes:
# {"user": {"login": "a"}, "labels": [{"name": "x"}]} has user.login = a,
# labels.0.name = x and labels.# = 1. Strings are decoded UTF-8; null is "".
def Row() -> Type:
  Map<&2, String>

def key(+prefix: String, +k: String) -> String:
  Ctx.or.if(prefix ++ "." ++ k, k, String.is_empty(prefix))

def push.obj(kvs: List<&1, Bytes.Bytes & Json.Val>, +prefix: String, work: List<&1, String & Json.Val>) -> List<&1, String & Json.Val>:
  match kvs:
    case Nil{}:
      work
    case (k, v) <> t:
      Con{(key(prefix, Enc.utf8.decode(k)), v), push.obj(t, prefix, work)}

def push.arr(xs: List<&1, Json.Val>, +prefix: String, +i: U32, work: List<&1, String & Json.Val>) -> List<&1, String & Json.Val>:
  match xs:
    case Nil{}:
      Con{(key(prefix, "#"), Json.Num{Bytes.from_string(U32.show(i))}), work}
    case Con{x, t}:
      Con{(key(prefix, U32.show(i)), x), push.arr(t, prefix, (i + 1 : U32), work)}

# one step per value, so fuel = the body's byte count always finishes
def flat.go(fuel: Nat, work: List<&1, String & Json.Val>, acc: Map<&2, String>) -> Map<&2, String>:
  match fuel work:
    case 0n w:
      acc
    case 1n+p Nil{}:
      acc
    case 1n+p Con{(+k, Json.Null{}), t}:
      flat.go(p, t, Map.set(&2, String, acc, k, ""))
    case 1n+p Con{(+k, Json.Flag{on}), t}:
      flat.go(p, t, Map.set(&2, String, acc, k, Bool.show(on)))
    case 1n+p Con{(+k, Json.Num{n}), t}:
      flat.go(p, t, Map.set(&2, String, acc, k, Bytes.to_string(n)))
    case 1n+p Con{(+k, Json.Str{s}), t}:
      flat.go(p, t, Map.set(&2, String, acc, k, Enc.utf8.decode(s)))
    case 1n+p Con{(+k, Json.Arr{xs}), t}:
      flat.go(p, push.arr(xs, k, 0, t), acc)
    case 1n+p Con{(+k, Json.Obj{kvs}), t}:
      flat.go(p, push.obj(kvs, k, t), acc)

def flat(+fuel: Nat, v: Json.Val) -> Map<&2, String>:
  flat.go(fuel, Con{("", v), Nil{}}, Map.new(&2, String))

def rows.go(+fuel: Nat, xs: List<&1, Json.Val>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      flat(fuel, x) <> rows.go(fuel, t)

def rows.of(+fuel: Nat, m: Maybe<&1, Json.Val>) -> List<&2, Map<&2, String>>:
  match m:
    case Some{Json.Arr{xs}}:
      rows.go(fuel, xs)
    case x:
      Nil{}

def obj.of(+fuel: Nat, m: Maybe<&1, Json.Val>) -> Map<&2, String>:
  match m:
    case Some{v}:
      flat(fuel, v)
    case None{}:
      Map.new(&2, String)

def fuel.of(r: Bytes.Bytes & U32) -> Bytes.Bytes & Nat:
  (b, +n) = r
  (b, U32.to_nat((n + 1 : U32)))

def fuel(b: Bytes.Bytes) -> Bytes.Bytes & Nat:
  fuel.of(Bytes.length(b))

def rows.fueled(r: Bytes.Bytes & Nat) -> List<&2, Map<&2, String>>:
  (b, +n) = r
  rows.of(n, Json.parse.bytes(b))

def obj.fueled(r: Bytes.Bytes & Nat) -> Map<&2, String>:
  (b, +n) = r
  obj.of(n, Json.parse.bytes(b))

# the objects of a JSON array body, flattened; none when it isn't an array
def rows(b: Bytes.Bytes) -> List<&2, Map<&2, String>>:
  rows.fueled(fuel(b))

# a JSON object body, flattened; empty when it isn't JSON
def obj(b: Bytes.Bytes) -> Map<&2, String>:
  obj.fueled(fuel(b))

# a field of a row, "" when missing
def f.of(r: Map<&2, String> & String) -> String:
  (m, v) = r
  v

def f(+row: Map<&2, String>, k: String) -> String:
  f.of(Map.get(String, "", row, k))

def join.go(n: Nat, +row: Map<&2, String>, +list: String, +field: String, +sep: String, +i: U32, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+k:
      join.go(k, row, list, field, sep, (i + 1 : U32), acc ++ Ctx.or.if(sep, "", U32.is_eq(i, 0)) ++ f(row, list ++ "." ++ U32.show(i) ++ Ctx.or.if("." ++ field, "", String.is_empty(field))))

def count.of(m: Maybe<&2, U32>) -> Nat:
  match m:
    case Some{n}:
      U32.to_nat(n)
    case None{}:
      0n

def count(+row: Map<&2, String>, +list: String) -> Nat:
  count.of(U32.read(f(row, list ++ ".#")))

# field of every item of a list field, joined: join(issue, "labels", "name", ", ")
def join(+row: Map<&2, String>, +list: String, +field: String, +sep: String) -> String:
  join.go(count(row, list), row, list, field, sep, 0, "")

def message.text(+s: String) -> String:
  Ctx.or.if(": " ++ s, "", String.is_empty(s))

def message.of(m: Maybe<&1, Json.Val>) -> String:
  match m:
    case Some{v}:
      message.text(str(v, "message"))
    case None{}:
      ""

# the error message a forge put in a failed reply's body
def message(+status: U32, b: Bytes.Bytes) -> String:
  "HTTP " ++ U32.show(status) ++ message.of(Json.parse.bytes(b))

# Pagination
# ----------

def all.step.ok(+status: U32, +next: String, body: Bytes.Bytes, acc: List<&2, Map<&2, String>>, good: Bool) -> Result<&1, &1, String, List<&2, Map<&2, String>> & String>:
  match good:
    case True{}:
      Done{(List.append(&2, Map<&2, String>, acc, rows(body)), next)}
    case False{}:
      Fail{message(status, body)}

def all.step(r: Reply, acc: List<&2, Map<&2, String>>) -> Result<&1, &1, String, List<&2, Map<&2, String>> & String>:
  match r:
    case Broke{w}:
      Fail{w}
    case Reply{+status, +next, body}:
      all.step.ok(status, next, body, acc, ok(status))

# where a paginated walk is: about to fetch, holding a page's result, or deciding to go on
type Pg is Type:
  Fetch{url: String, acc: List<&2, Map<&2, String>>}
  Check{r: Result<&1, &1, String, List<&2, Map<&2, String>> & String>}
  Next{last: Bool, got: List<&2, Map<&2, String>>, next: String}

def pg.acc(st: Pg) -> Result<&1, &1, String, List<&2, Map<&2, String>>>:
  match st:
    case Fetch{u, acc}:
      Done{acc}
    case Check{Fail{w}}:
      Fail{w}
    case Check{Done{(got, next)}}:
      Done{got}
    case Next{l, got, n}:
      Done{got}

# every item of a paginated list, following Link: rel="next".
# each step costs one fuel and a page takes three, so 3n*pages bounds the walk.
def all.go(fuel: Nat, +repo: Ctx.Repo, +tok: String, st: Pg) -> IO(Result<&1, &1, String, List<&2, Map<&2, String>>>):
  match fuel st:
    case 0n s:
      IO.pure(Result<&1, &1, String, List<&2, Map<&2, String>>>, pg.acc(s))
    case 1n+p Fetch{url, acc}:
      IO.bind(Reply, Result<&1, &1, String, List<&2, Map<&2, String>>>, get(repo, tok, url), r => all.go(p, repo, tok, Check{all.step(r, acc)}))
    case 1n+p Check{Fail{w}}:
      IO.pure(Result<&1, &1, String, List<&2, Map<&2, String>>>, Fail{w})
    case 1n+p Check{Done{(got, +next)}}:
      all.go(p, repo, tok, Next{String.is_empty(next), got, next})
    case 1n+p Next{True{}, got, n}:
      IO.pure(Result<&1, &1, String, List<&2, Map<&2, String>>>, Done{got})
    case 1n+p Next{False{}, got, next}:
      all.go(p, repo, tok, Fetch{next, got})

def all(pages: Nat, +repo: Ctx.Repo, +tok: String, url: String) -> IO(Result<&1, &1, String, List<&2, Map<&2, String>>>):
  all.go(Nat.mul(3n, pages), repo, tok, Fetch{url, Nil{}})
