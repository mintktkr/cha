# cha runners: self-hosted runners at the repo, org, user or site scope, and deleting one.
import Base
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli
import ../url.bend as Url

# Scopes
# ------
# A runner belongs to a repo, an org, the token owner's user, or the whole site. Gitea and
# Forgejo serve all four; GitHub serves the first two, so it refuses the other two before
# any request.

type Scope is Data:
  Repo{}
  Org{name: String}
  User{}
  Admin{}

def forge.of(r: Ctx.Repo) -> Ctx.Forge:
  match r:
    case Ctx.Repo{f, h, o, n}:
      f

# --org named one
def org.named(+org: String) -> Bool:
  Bool.not(String.is_empty(org))

# two scope flags name two places, and no request can honour both
def scope.both(+org: String, +user: Bool, +admin: Bool) -> Bool:
  (user && admin) || ((user || admin) && org.named(org))

def scope.both.msg() -> String:
  "runners: --org, --user and --admin name one place; pick one"

# the place a scope names, as a message reads it
def scope.where(scope: Scope) -> String:
  match scope:
    case Repo{}:
      "the repo"
    case Org{+o}:
      "org " ++ o
    case User{}:
      "your user"
    case Admin{}:
      "the site"

def scope.pick.org(+org: String, empty: Bool) -> Scope:
  match empty:
    case True{}:
      Repo{}
    case False{}:
      Org{org}

def scope.pick.rest(+org: String, admin: Bool) -> Scope:
  match admin:
    case True{}:
      Admin{}
    case False{}:
      scope.pick.org(org, String.is_empty(org))

# the scope the flags name, once they are known to name one place
def scope.pick(+org: String, user: Bool, admin: Bool) -> Scope:
  match user:
    case True{}:
      User{}
    case False{}:
      scope.pick.rest(org, admin)

def refuse.admin(admin: Bool) -> String:
  match admin:
    case True{}:
      "runners: github has no admin scope; runners live on a repo or an org"
    case False{}:
      ""

def refuse.of(user: Bool, admin: Bool) -> String:
  match user:
    case True{}:
      "runners: github has no user scope; runners live on a repo or an org"
    case False{}:
      refuse.admin(admin)

# why a forge can't answer for these flags, "" when it can
def refuse(f: Ctx.Forge, user: Bool, admin: Bool) -> String:
  match f:
    case Ctx.Gitea{}:
      ""
    case Ctx.GitHub{}:
      refuse.of(user, admin)

# the scope the flags name. Every check here runs before the first request: two scope
# flags, or one the forge doesn't serve.
def scope.resolve(+env: Cli.Env, +repo: Ctx.Repo, +args: List<&2, String>) -> IO(Scope):
  do IO<Scope>:
    +org : String = Cli.flag(args, "--org", "")
    +user : Bool = Cli.has(args, "--user")
    +admin : Bool = Cli.has(args, "--admin")
    Cli.check.if(env, scope.both.msg(), Bool.not(scope.both(org, user, admin)))
    +why : String = refuse(forge.of(repo), user, admin)
    Cli.check.if(env, why, String.is_empty(why))
    return scope.pick(org, user, admin)

# Endpoints
# ---------

# the path a scope's runners live at. an org name is encoded, so "a/../b" can't climb to
# another endpoint.
def path.of(scope: Scope, +owner: String, +name: String) -> String:
  match scope:
    case Repo{}:
      "repos/" ++ owner ++ "/" ++ name ++ "/actions/runners"
    case Org{+o}:
      "orgs/" ++ Url.encode(o) ++ "/actions/runners"
    case User{}:
      "user/actions/runners"
    case Admin{}:
      "admin/actions/runners"

def path(+repo: Ctx.Repo, scope: Scope) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      path.of(scope, o, n)

# where one runner lives, for a delete. the id is digits only, checked before it gets here
def delete.path(+repo: Ctx.Repo, scope: Scope, +id: String) -> String:
  path(repo, scope) ++ "/" ++ id

# one page's query. GitHub pages with per_page and links the next page itself.
# Gitea 1.25 ignores limit unless page is sent, and counts the rest in total_count.
def query(+forge: Ctx.Forge, +page: U32) -> String:
  match forge:
    case Ctx.Gitea{}:
      "?page=" ++ U32.show(page) ++ "&limit=50"
    case Ctx.GitHub{}:
      "?per_page=100&page=" ++ U32.show(page)

def url.of(+repo: Ctx.Repo, scope: Scope, +page: U32) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      path.of(scope, o, n) ++ query(f, page)

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

# a failed admin-scoped request is usually a token that isn't a site admin
def error.admin(+status: U32, body: List<&2, U32>, forbidden: Bool) -> String:
  match forbidden:
    case True{}:
      "HTTP 403: admin runners need a site-admin token"
    case False{}:
      Api.message(status, body)

# the message a failed request prints
def error.of(scope: Scope, +status: U32, body: List<&2, U32>) -> String:
  match scope:
    case Admin{}:
      error.admin(status, body, U32.is_eq(status, 403))
    case x:
      Api.message(status, body)

# a reply's body, or the command fails with the forge's error
def ok.body(+env: Cli.Env, scope: Scope, +status: U32, body: List<&2, U32>, good: Bool) -> IO(List<&2, U32>):
  match good:
    case True{}:
      IO.pure(List<&2, U32>, body)
    case False{}:
      Cli.fail(List<&2, U32>, env, error.of(scope, status, body))

type Pages is Type:
  FetchRunners{url: String, acc: List<&2, Map<&2, String>>}
  ReadRunners{reply: Api.Reply, acc: List<&2, Map<&2, String>>}
  NextRunners{done: Bool, url: String, seen: Nat, acc: List<&2, Map<&2, String>>}

def page.of(+repo: Ctx.Repo, scope: Scope, +page: U32, +next: String, +seen: Nat, body: List<&2, U32>, acc: List<&2, Map<&2, String>>) -> Pages:
  +src = Api.obj(body)
  +rows = rows.of(src)
  +count = Nat.add(seen, List.length(&2, Map<&2, String>, rows))
  +url = page.next(next, url.of(repo, scope, (page + 1 : U32)), count, Api.f(src, "total_count"), Nat.is_eq(List.length(&2, Map<&2, String>, rows), 0n))
  NextRunners{String.is_empty(url), url, count, List.append(&2, Map<&2, String>, acc, rows)}

def walk(fuel: Nat, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +scope: Scope, +page: U32, +seen: Nat, st: Pages) -> IO(List<&2, Map<&2, String>>):
  match fuel st:
    case 0n s:
      Cli.fail(List<&2, Map<&2, String>>, env, "runners: too many pages")
    case 1n+p FetchRunners{url, acc}:
      do IO<List<&2, Map<&2, String>>>:
        r : Api.Reply <- Api.get(repo, tok, url)
        walk(p, env, repo, tok, scope, page, seen, ReadRunners{r, acc})
    case 1n+p ReadRunners{Api.Broke{w}, acc}:
      Cli.fail(List<&2, Map<&2, String>>, env, w)
    case 1n+p ReadRunners{Api.Reply{+status, +next, body}, acc}:
      do IO<List<&2, Map<&2, String>>>:
        b : List<&2, U32> <- ok.body(env, scope, status, body, Api.ok(status))
        walk(p, env, repo, tok, scope, page, seen, page.of(repo, scope, page, next, seen, b, acc))
    case 1n+p NextRunners{True{}, url, n, acc}:
      IO.pure(List<&2, Map<&2, String>>, acc)
    case 1n+p NextRunners{False{}, url, n, acc}:
      walk(p, env, repo, tok, scope, (page + 1 : U32), n, FetchRunners{url, acc})

# Delete
# ------

# an id of digits only. it goes into a path, so "1/registration-token" must not.
def digit.ok(cs: List<&2, Char>) -> Bool:
  match cs:
    case Nil{}:
      True{}
    case Con{c, rest}:
      Char.is_digit(c) && digit.ok(rest)

def digits(+s: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(s)), digit.ok(String.to_list(s)))

# the message a delete without --yes prints, naming what it would remove
def yes.msg(+id: String, scope: Scope) -> String:
  "runners delete: would delete runner " ++ id ++ " from " ++ scope.where(scope) ++ "; pass --yes to delete it"

def yes.want(+env: Cli.Env, +id: String, scope: Scope, yes: Bool) -> IO(Unit):
  match yes:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Cli.fail(Unit, env, yes.msg(id, scope))

# a runner id: given, and digits only
def id.need(+env: Cli.Env, +id: String) -> IO(Unit):
  do IO<Unit>:
    Cli.check.if(env, "runners delete: a runner ID is required", Bool.not(String.is_empty(id)))
    Cli.check.if(env, "runners delete: a runner ID is digits only, got '" ++ id ++ "'", digits(id))

def delete.reply.at(+env: Cli.Env, +on: Bool, scope: Scope, +id: String, +status: U32, body: List<&2, U32>, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      Ui.done(on, "deleted runner " ++ id)
    case False{}:
      Cli.fail(Unit, env, error.of(scope, status, body))

def delete.reply(+env: Cli.Env, +on: Bool, scope: Scope, +id: String, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      delete.reply.at(env, on, scope, id, status, body, Api.ok(status))

def delete.send(+env: Cli.Env, +on: Bool, +repo: Ctx.Repo, +tok: String, +scope: Scope, +id: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.send(repo, tok, "DELETE", delete.path(repo, scope, id), None{})
    delete.reply(env, on, scope, id, r)

# Commands
# --------

def list(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "runners list", args, ["--org", "--user", "--admin", "--json"])
        +scope : Scope <- scope.resolve(env, repo, args)
        xs : List<&2, Map<&2, String>> <- walk(301n, env, repo, tok, scope, 1, 0n, FetchRunners{url.of(repo, scope, 1), Nil{}})
        emit(on, json, xs)

def delete(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "runners delete", args, ["--org", "--user", "--admin", "--yes"])
        +id : String = Cli.arg(args, 1n)
        id.need(env, id)
        +scope : Scope <- scope.resolve(env, repo, args)
        yes.want(env, id, scope, Cli.has(args, "--yes"))
        delete.send(env, on, repo, tok, scope, id)

# Dispatch
# --------

def names() -> List<&2, String>:
  ["list", "delete"]

def index.at(eq: Bool, +i: Nat, +later: Nat) -> Nat:
  match eq:
    case True{}:
      i
    case False{}:
      later

# the subcommand's index in names(), or the list's length when unknown
def index(xs: List<&2, String>, +w: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case Con{x, rest}:
      index.at(String.eq(x, w), i, index(rest, w, 1n+i))

def run.at(+env: Cli.Env, n: Nat) -> IO(Unit):
  match n:
    case 0n:
      list(env)
    case 1n:
      delete(env)
    case 2n+k:
      Cli.fail(Unit, env, "runners: unknown subcommand, try cha help")

def run.sub(+env: Cli.Env, +sub: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      list(env)
    case False{}:
      run.at(env, index(names(), sub, 0n))

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      +sub : String = Cli.arg(args, 0n)
      run.sub(env, sub, String.is_empty(sub))
