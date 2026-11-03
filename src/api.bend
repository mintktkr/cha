# api: requests to a forge's REST API, decoded replies, and pagination.
import Base
import ../lib/chaki/utf8.bend as Utf8
import ../lib/chaki/json.bend as Json
import ../lib/chaki/url.bend as Url
import ../lib/chaki/http1.bend as Http1
import ../lib/chaki/http.bend as Http
import ./ctx.bend as Ctx
import ./clean.bend as Clean

# A finished request: the status, the next page's URL ("" when last) and the body.
# Broke is a request that never got a status; why never holds the token.
type Reply is Type:
  Reply{status: U32, next: String, body: List<&2, U32>}
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

# repos/<owner>/<name>/ + rest
def path(repo: Ctx.Repo, +rest: String) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      "repos/" ++ o ++ "/" ++ n ++ Ctx.or.if("/" ++ rest, "", String.is_empty(rest))

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

# Requests
# --------

def auth.if(f: Ctx.Forge, +tok: String, rest: List<&2, Http1.Field()>, none: Bool) -> List<&2, Http1.Field()>:
  match none:
    case True{}:
      rest
    case False{}:
      ("authorization", scheme(f) ++ tok) <> rest

# what every request carries, then the caller's own headers
def headers(+repo: Ctx.Repo, +tok: String, +accept: String, extra: List<&2, Http1.Field()>) -> List<&2, Http1.Field()>:
  match repo:
    case Ctx.Repo{+f, h, o, n}:
      ("accept", accept) <> (("user-agent", "cha") <> auth.if(f, tok, extra, String.is_empty(tok)))

# one request header, as send.raw takes them
def header.one(+k: String, +v: String) -> List<&2, Http1.Field()>:
  [(k, v)]

def target.of(m: Maybe<&2, Url.Url>, +url: String) -> String:
  match m:
    case Some{u}:
      Url.show(u)
    case None{}:
      url

def target.at(b: Maybe<&2, Url.Url>, +url: String) -> String:
  match b:
    case Some{u}:
      target.of(Url.resolve(u, url), url)
    case None{}:
      url

# url resolved against the forge's API root (an absolute url stays as it is)
def target(+repo: Ctx.Repo, +url: String) -> String:
  match repo:
    case Ctx.Repo{+f, +h, o, n}:
      target.at(Url.parse(base(f, h)), url)

# https goes through the system's OpenSSL unless CHA_TLS=bend picks chaki's own TLS 1.3
def transport.of(+v: String) -> Http.Transport:
  Bool.pick(Http.Transport, String.eq(v, "bend"), Http.Bend{}, Http.Ossl{})

def reply.of(got: Result<&1, &1, String, Http.Res>) -> Reply:
  match got:
    case Done{Http.Res{+status, +hs, body, url}}:
      Reply{status, link.next(Http1.header(Http1.Head{status, hs}, "link")), body}
    case Fail{w}:
      Broke{w}

def fetch.with(c: Result<&1, &1, U32 & String, Http.Client>, +method: String, +url: String, hs: List<&2, Http1.Field()>, body: List<&2, U32>) -> IO(Reply):
  match c:
    case Done{cl}:
      do IO<Reply>:
        got : Result<&1, &1, String, Http.Res> <- Http.fetch(cl, method, url, hs, body)
        return reply.of(got)
    case Fail{(code, w)}:
      IO.pure(Reply, Broke{w})

# one request; url is relative to the forge's API root, or absolute. Two minutes bound it
# whole: dial, handshake and the body (a job log can be large).
def request(+repo: Ctx.Repo, +tok: String, +method: String, +url: String, +accept: String, extra: List<&2, Http1.Field()>, body: List<&2, U32>) -> IO(Reply):
  do IO<Reply>:
    t : String <- Ctx.env("CHA_TLS")
    c : Result<&1, &1, U32 & String, Http.Client> <- Http.client(transport.of(t), 120000)
    fetch.with(c, method, target(repo, url), headers(repo, tok, accept, extra), body)

# a JSON request; the body, when there is one, goes as UTF-8 JSON
def send(+repo: Ctx.Repo, +tok: String, +method: String, +url: String, body: Maybe<&1, Json.Val>) -> IO(Reply):
  match body:
    case None{}:
      request(repo, tok, method, url, "application/json", Nil{}, Nil{})
    case Some{v}:
      request(repo, tok, method, url, "application/json", [("content-type", "application/json")], Utf8.encode(Json.encode(v)))

# one request whose body is bytes the caller framed, and whose headers are its own
# (uploads: GitHub takes the file raw, Gitea a multipart form)
def send.raw(+repo: Ctx.Repo, +tok: String, +method: String, +url: String, hs: List<&2, Http1.Field()>, body: List<&2, U32>) -> IO(Reply):
  request(repo, tok, method, url, "application/json", hs, body)

def get(+repo: Ctx.Repo, +tok: String, +url: String) -> IO(Reply):
  send(repo, tok, "GET", url, None{})

# a GET asking for another media type: a diff, a raw file
def get.accept(+repo: Ctx.Repo, +tok: String, +url: String, +accept: String) -> IO(Reply):
  request(repo, tok, "GET", url, accept, Nil{}, Nil{})

# Decoding
# --------

def ok(+status: U32) -> Bool:
  (status >= 200 : U32) && (status < 300 : U32)

# a reply's body as the forge sent it, for callers that write it to a file
def raw.text(b: List<&2, U32>) -> String:
  Utf8.decode(b)

# a reply's body as text safe for a terminal. A CI job log is full of ANSI colour, so
# every command that prints a body reads it here; raw.text keeps the bytes byte-exact.
def text(b: List<&2, U32>) -> String:
  Clean.text(raw.text(b))

# a JSON string
def utf8(s: String) -> Json.Val:
  Json.Str{s}

# true/false the way JSON spells them, not Bool.show's True/False
def json.bool(on: Bool) -> String:
  match on:
    case True{}:
      "true"
    case False{}:
      "false"

# Flat objects
# ------------
# A JSON body flattened once into text fields, so a command can read as many as it likes:
# {"user": {"login": "a"}, "labels": [{"name": "x"}]} has user.login = a,
# labels.0.name = x and labels.# = 1. Strings are decoded UTF-8; null is "". chaki's
# json.bend reads the bytes straight into these rows, with no tree in between.
def Row() -> Type:
  Map<&2, String>

# a flat key: prefix.k, or k at the root
def key(+prefix: String, +k: String) -> String:
  Ctx.or.if(prefix ++ "." ++ k, k, String.is_empty(prefix))

# the objects of a JSON array body, flattened; none when it isn't an array
def rows(b: List<&2, U32>) -> List<&2, Map<&2, String>>:
  Json.rows(b)

# a JSON object body, flattened; empty when it isn't JSON
def obj(b: List<&2, U32>) -> Map<&2, String>:
  Json.obj(b)

def f.of(r: Map<&2, String> & String) -> String:
  (m, v) = r
  v

# a field of a row as the forge sent it, "" when missing; --json prints it this way
def raw.f(+row: Map<&2, String>, k: String) -> String:
  f.of(Map.get(String, "", row, k))

# a field of a row as text safe for one line of a terminal, "" when missing. This is the
# one door a command reads a forge field through, so a title, a label, a branch name or a
# job name is cleaned once here instead of at every print, and can't start a fake row.
def f(+row: Map<&2, String>, k: String) -> String:
  Clean.line(raw.f(row, k))

# a field whose lines are its content (a body, a comment, release notes), safe to print
def f.lines(+row: Map<&2, String>, k: String) -> String:
  Clean.text(raw.f(row, k))

def join.go(n: Nat, +row: Map<&2, String>, +list: String, +field: String, +sep: String, +i: U32, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+k:
      join.go(k, row, list, field, sep, (i + 1 : U32), acc ++ Ctx.or.if(sep, "", U32.is_eq(i, 0)) ++ raw.f(row, list ++ "." ++ U32.show(i) ++ Ctx.or.if("." ++ field, "", String.is_empty(field))))

def count.of(m: Maybe<&2, U32>) -> Nat:
  match m:
    case Some{n}:
      U32.to_nat(n)
    case None{}:
      0n

def count(+row: Map<&2, String>, +list: String) -> Nat:
  count.of(U32.read(f(row, list ++ ".#")))

# field of every item of a list field, joined, as the forge sent it: the field it builds
# is a row field, which a command reads back through f or raw.f
def raw.join(+row: Map<&2, String>, +list: String, +field: String, +sep: String) -> String:
  join.go(count(row, list), row, list, field, sep, 0, "")

# the same join, safe to print
def join(+row: Map<&2, String>, +list: String, +field: String, +sep: String) -> String:
  Clean.line(raw.join(row, list, field, sep))

def message.text(+s: String) -> String:
  Ctx.or.if(": " ++ s, "", String.is_empty(s))

# the error message a forge put in a failed reply's body
def message(+status: U32, b: List<&2, U32>) -> String:
  "HTTP " ++ U32.show(status) ++ message.text(f(obj(b), "message"))

# Pagination
# ----------

def all.step.ok(+status: U32, +next: String, body: List<&2, U32>, acc: List<&2, Map<&2, String>>, good: Bool) -> Result<&1, &1, String, List<&2, Map<&2, String>> & String>:
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
