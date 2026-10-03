# cha runners: a repo's or an org's self-hosted runners. Read-only.
import Base
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli
import ../url.bend as Url

# Endpoints
# ---------

# the path a runner list lives at: an org's when --org named one, else the repo's.
# --org is encoded, so "a/../b" can't climb to another endpoint.
def endpoint(+org: String, +owner: String, +name: String) -> String:
  Ctx.or.if("orgs/" ++ Url.encode(org) ++ "/actions/runners", "repos/" ++ owner ++ "/" ++ name ++ "/actions/runners", String.is_empty(org))

# one page's query. GitHub pages with per_page and links the next page itself.
# Gitea 1.25 ignores limit unless page is sent, and counts the rest in total_count.
def query(+forge: Ctx.Forge, +page: U32) -> String:
  match forge:
    case Ctx.Gitea{}:
      "?page=" ++ U32.show(page) ++ "&limit=50"
    case Ctx.GitHub{}:
      "?per_page=100&page=" ++ U32.show(page)

def url.of(+repo: Ctx.Repo, +org: String, +page: U32) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      endpoint(org, o, n) ++ query(f, page)

# Rows
# ----

# field k of an object flattened under prefix; "" when missing. Raw: this reads only to
# build a row, which holds what the forge sent, so the text printer reads the row back
# through Api.f (clean) and --json through Api.raw.f (exact).
def g(+src: Map<&2, String>, +prefix: String, +k: String) -> String:
  Api.raw.f(src, Api.key(prefix, k))

def prefix.of(+root: String, i: U32) -> String:
  root ++ "." ++ U32.show(i)

# one runner as the flat row every output reads. Gitea 1.25 has no os on a runner,
# so that field is empty there.
def runner.row(+src: Map<&2, String>, +prefix: String) -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "id", g(src, prefix, "id"))
  m = Map.set(&2, String, m, "name", g(src, prefix, "name"))
  m = Map.set(&2, String, m, "status", g(src, prefix, "status"))
  m = Map.set(&2, String, m, "busy", g(src, prefix, "busy"))
  m = Map.set(&2, String, m, "os", g(src, prefix, "os"))
  Map.set(&2, String, m, "labels", Api.raw.join(src, Api.key(prefix, "labels"), "name", ","))

def rows.go(n: Nat, +i: U32, +src: Map<&2, String>) -> List<&2, Map<&2, String>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      runner.row(src, prefix.of("runners", i)) <> rows.go(p, (i + 1 : U32), src)

# both forges wrap the list in runners
def rows.of(+src: Map<&2, String>) -> List<&2, Map<&2, String>>:
  rows.go(Api.count(src, "runners"), 0, src)

# Text
# ----

# a flattened JSON bool, which Api renders as "true" or "false"
def bool.f(+x: Map<&2, String>, +k: String) -> Bool:
  String.eq(Api.f(x, k), "true")

def status.of(+on: Bool, +s: String, online: Bool) -> String:
  match online:
    case True{}:
      Ui.fg(on, Ui.mint(), s)
    case False{}:
      Ui.dim(on, s)

# online mint, anything else (offline) dim
def status(+on: Bool, +s: String) -> String:
  status.of(on, s, String.eq(s, "online"))

# "  busy" in lemon while the runner is busy, nothing otherwise
def busy.text(+on: Bool, +v: String, busy: Bool) -> String:
  match busy:
    case True{}:
      "  " ++ Ui.fg(on, Ui.lemon(), v)
    case False{}:
      ""

# s with pre in front of it, unless s is empty
def prefixed(+s: String, +pre: String) -> String:
  Ctx.or.if(pre ++ s, "", String.is_empty(s))

def line(+on: Bool, +row: Map<&2, String>) -> String:
  Ui.bold(on, Ui.fg(on, Ui.aqua(), "#" ++ Api.f(row, "id"))) ++ "  " ++
  Api.f(row, "name") ++ "  " ++
  status(on, Api.f(row, "status")) ++
  busy.text(on, "busy", bool.f(row, "busy")) ++
  prefixed(Api.f(row, "labels"), "  ")

def lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, rest}:
      line(on, x) ++ "\n" ++ lines(on, rest)

def fields() -> List<&2, String>:
  ["id", "name", "status", "busy", "labels", "os"]

def emit(+on: Bool, json: Cli.Json, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(lines(on, xs))
    case j:
      Cli.json.emit(on, j, xs, fields())

# Pagination
# ----------

# Gitea 1.25 answers runner lists with total_count but no Link header. Until the
# rows seen reach total_count, ask for the next page ourselves.
def page.next(+next: String, +fallback: String, +seen: Nat, +total: String, empty: Bool) -> String:
  Ctx.or(next, Ctx.or.if(fallback, "", empty || Bool.not(Nat.is_gt(Api.count.of(U32.read(total)), seen))))

# a reply's body, or the command fails with the forge's error
def ok.body(+env: Cli.Env, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Bytes.Bytes):
  match good:
    case True{}:
      IO.pure(Bytes.Bytes, body)
    case False{}:
      Cli.fail(Bytes.Bytes, env, Api.message(status, body))

type Pages is Type:
  FetchRunners{url: String, acc: List<&2, Map<&2, String>>}
  ReadRunners{reply: Api.Reply, acc: List<&2, Map<&2, String>>}
  NextRunners{done: Bool, url: String, seen: Nat, acc: List<&2, Map<&2, String>>}

def page.of(+repo: Ctx.Repo, +org: String, +page: U32, +next: String, +seen: Nat, body: Bytes.Bytes, acc: List<&2, Map<&2, String>>) -> Pages:
  +src = Api.obj(body)
  +rows = rows.of(src)
  +count = Nat.add(seen, List.length(&2, Map<&2, String>, rows))
  +url = page.next(next, url.of(repo, org, (page + 1 : U32)), count, Api.f(src, "total_count"), Nat.is_eq(List.length(&2, Map<&2, String>, rows), 0n))
  NextRunners{String.is_empty(url), url, count, List.append(&2, Map<&2, String>, acc, rows)}

def walk(fuel: Nat, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +org: String, +page: U32, +seen: Nat, st: Pages) -> IO(List<&2, Map<&2, String>>):
  match fuel st:
    case 0n s:
      Cli.fail(List<&2, Map<&2, String>>, env, "runners: too many pages")
    case 1n+p FetchRunners{url, acc}:
      do IO<List<&2, Map<&2, String>>>:
        r : Api.Reply <- Api.get(repo, tok, url)
        walk(p, env, repo, tok, org, page, seen, ReadRunners{r, acc})
    case 1n+p ReadRunners{Api.Broke{w}, acc}:
      Cli.fail(List<&2, Map<&2, String>>, env, w)
    case 1n+p ReadRunners{Api.Reply{+status, +next, body}, acc}:
      do IO<List<&2, Map<&2, String>>>:
        b : Bytes.Bytes <- ok.body(env, status, body, Api.ok(status))
        walk(p, env, repo, tok, org, page, seen, page.of(repo, org, page, next, seen, b, acc))
    case 1n+p NextRunners{True{}, url, n, acc}:
      IO.pure(List<&2, Map<&2, String>>, acc)
    case 1n+p NextRunners{False{}, url, n, acc}:
      walk(p, env, repo, tok, org, (page + 1 : U32), n, FetchRunners{url, acc})

# Command
# -------

def list(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +org : String = Cli.flag(args, "--org", "")
        xs : List<&2, Map<&2, String>> <- walk(301n, env, repo, tok, org, 1, 0n, FetchRunners{url.of(repo, org, 1), Nil{}})
        emit(on, json, xs)

def run(+env: Cli.Env) -> IO(Unit):
  list(env)
