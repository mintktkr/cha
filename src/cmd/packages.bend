# cha packages: a forge's packages and their versions, and deleting one version.
import Base
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli
import ../url.bend as Url

# which list a page belongs to: every package the owner has, or one package's versions
type Which is Data:
  Packages{}
  Versions{name: String}

# what a page URL is built from. GitHub lists a user's and an org's packages at different
# paths, so scope is "users/" or "orgs/" there, and empty on Gitea.
type Query is Data:
  Query{forge: Ctx.Forge, scope: String, owner: String, kind: String, which: Which}

# where a paginated walk stands: about to fetch, holding a page's reply, going on, done,
# or stopped with the error to report
type Pg is Type:
  Fetch{url: String, acc: List<&2, Map<&2, String>>}
  Read{reply: Api.Reply, acc: List<&2, Map<&2, String>>}
  Next{url: String, acc: List<&2, Map<&2, String>>}
  Last{acc: List<&2, Map<&2, String>>}
  Bad{why: String}

def forge.of(+r: Ctx.Repo) -> Ctx.Forge:
  match r:
    case Ctx.Repo{f, h, o, n}:
      f

# a field of a source row as the forge sent it. A row holds what the forge sent, so the
# text printers read it back through Api.f and --json through Api.raw.f.
def g(+src: Map<&2, String>, +k: String) -> String:
  Api.raw.f(src, k)

# Rows
# ----
# name, type, version and created are the fields every output reads. Gitea's list is one
# row per version; GitHub's list is one row per package and has no version, so that field
# stays empty there, and its versions list carries the version in the row's name.

def row.name.of(+src: Map<&2, String>, +f: Ctx.Forge, +w: Which) -> String:
  match f w:
    case Ctx.Gitea{} Packages{}:
      g(src, "name")
    case Ctx.Gitea{} Versions{v}:
      g(src, "name")
    case Ctx.GitHub{} Packages{}:
      g(src, "name")
    case Ctx.GitHub{} Versions{v}:
      v

def row.kind.of(+src: Map<&2, String>, +f: Ctx.Forge, +w: Which, +kind: String) -> String:
  match f w:
    case Ctx.Gitea{} Packages{}:
      g(src, "type")
    case Ctx.Gitea{} Versions{v}:
      g(src, "type")
    case Ctx.GitHub{} Packages{}:
      g(src, "package_type")
    case Ctx.GitHub{} Versions{v}:
      kind

def row.version.of(+src: Map<&2, String>, +f: Ctx.Forge, +w: Which) -> String:
  match f w:
    case Ctx.Gitea{} Packages{}:
      g(src, "version")
    case Ctx.Gitea{} Versions{v}:
      g(src, "version")
    case Ctx.GitHub{} Packages{}:
      ""
    case Ctx.GitHub{} Versions{v}:
      g(src, "name")

# id is the forge's version id, which GitHub's delete needs; it is not a --json field
def row.of(+src: Map<&2, String>, +f: Ctx.Forge, +w: Which, +kind: String) -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "name", row.name.of(src, f, w))
  m = Map.set(&2, String, m, "type", row.kind.of(src, f, w, kind))
  m = Map.set(&2, String, m, "version", row.version.of(src, f, w))
  m = Map.set(&2, String, m, "created", g(src, "created_at"))
  Map.set(&2, String, m, "id", g(src, "id"))

def rows.row(+src: Map<&2, String>, +q: Query) -> Map<&2, String>:
  match q:
    case Query{f, s, o, k, w}:
      row.of(src, f, w, k)

def rows.map(xs: List<&2, Map<&2, String>>, +q: Query) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      rows.row(x, q) <> rows.map(t, q)

def keep.if(+x: Map<&2, String>, later: List<&2, Map<&2, String>>, same: Bool) -> List<&2, Map<&2, String>>:
  match same:
    case True{}:
      Con{x, later}
    case False{}:
      later

# Gitea's q is a name filter, not an exact name: keep the rows that are this package
def keep.named(xs: List<&2, Map<&2, String>>, +name: String) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      keep.if(x, keep.named(t, name), String.eq(g(x, "name"), name))

def rows.kept.of(+src: List<&2, Map<&2, String>>, +f: Ctx.Forge, +name: String) -> List<&2, Map<&2, String>>:
  match f:
    case Ctx.Gitea{}:
      keep.named(src, name)
    case Ctx.GitHub{}:
      src

def rows.kept(+src: List<&2, Map<&2, String>>, +q: Query) -> List<&2, Map<&2, String>>:
  match q:
    case Query{f, s, o, k, Versions{name}}:
      rows.kept.of(src, f, name)
    case y:
      src

# the rows a page answers with, as the fields every output reads
def rows.of(+src: List<&2, Map<&2, String>>, +q: Query) -> List<&2, Map<&2, String>>:
  rows.map(rows.kept(src, q), q)

# Text
# ----

def fields() -> List<&2, String>:
  ["name", "type", "version", "created"]

# s ++ v, or nothing when v is empty
def sep.if(+v: String, +s: String, empty: Bool) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      s ++ v

def line(+on: Bool, +row: Map<&2, String>) -> String:
  +ty = Api.f(row, "type")
  +v = Api.f(row, "version")
  +c = Api.f(row, "created")
  Ui.bold(on, Ui.fg(on, Ui.aqua(), Api.f(row, "name"))) ++
  sep.if(ty, "  ", String.is_empty(ty)) ++
  sep.if(Ui.fg(on, Ui.mint(), v), "  ", String.is_empty(v)) ++
  sep.if(Ui.dim(on, c), "  ", String.is_empty(c))

def lines(+on: Bool, +xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, rest}:
      line(on, x) ++ "\n" ++ lines(on, rest)

def emit(+on: Bool, json: Cli.Json, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(lines(on, xs))
    case j:
      Cli.json.emit(on, j, xs, fields())

# URLs
# ----
# Gitea filters the owner's packages by type in the query. GitHub takes the type in the
# query for a list and in the path for versions, and requires it either way.

def kind.param(+kind: String, empty: Bool) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      "&type=" ++ Url.encode(kind)

def url.list(+f: Ctx.Forge, +scope: String, +owner: String, +kind: String, +page: U32) -> String:
  match f:
    case Ctx.Gitea{}:
      "packages/" ++ Url.encode(owner) ++ "?page=" ++ U32.show(page) ++ "&limit=50" ++ kind.param(kind, String.is_empty(kind))
    case Ctx.GitHub{}:
      scope ++ Url.encode(owner) ++ "/packages?package_type=" ++ Url.encode(kind) ++ "&per_page=100&page=" ++ U32.show(page)

def url.versions(+f: Ctx.Forge, +scope: String, +owner: String, +kind: String, +name: String, +page: U32) -> String:
  match f:
    case Ctx.Gitea{}:
      "packages/" ++ Url.encode(owner) ++ "?page=" ++ U32.show(page) ++ "&limit=50" ++ kind.param(kind, String.is_empty(kind)) ++ "&q=" ++ Url.encode(name)
    case Ctx.GitHub{}:
      scope ++ Url.encode(owner) ++ "/packages/" ++ Url.encode(kind) ++ "/" ++ Url.encode(name) ++ "/versions?per_page=100&page=" ++ U32.show(page)

def url.of(+q: Query, +page: U32) -> String:
  match q:
    case Query{f, scope, owner, kind, Packages{}}:
      url.list(f, scope, owner, kind, page)
    case Query{f, scope, owner, kind, Versions{name}}:
      url.versions(f, scope, owner, kind, name, page)

# Gitea deletes the version it names; GitHub deletes by the id its version list gave
def delete.url(+f: Ctx.Forge, +scope: String, +owner: String, +kind: String, +name: String, +v: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "packages/" ++ Url.encode(owner) ++ "/" ++ Url.encode(kind) ++ "/" ++ Url.encode(name) ++ "/" ++ Url.encode(v)
    case Ctx.GitHub{}:
      scope ++ Url.encode(owner) ++ "/packages/" ++ Url.encode(kind) ++ "/" ++ Url.encode(name) ++ "/versions/" ++ v

# Pagination
# ----------

def page.size(+f: Ctx.Forge) -> Nat:
  match f:
    case Ctx.Gitea{}:
      50n
    case Ctx.GitHub{}:
      100n

def full.page(+q: Query, +got: List<&2, Map<&2, String>>) -> Bool:
  match q:
    case Query{f, s, o, k, w}:
      Nat.is_eq(List.length(&2, Map<&2, String>, got), page.size(f))

# the next page, when the Link header names one or the page came back full: Gitea's
# package list carries neither a total nor a Link, so a full page is its only sign of more
def next.url.if(+next: String, +full: Bool, +url: String, linked: Bool) -> String:
  match linked:
    case True{}:
      next
    case False{}:
      Bool.pick(String, full, url, "")

def next.url(+next: String, +full: Bool, +url: String) -> String:
  next.url.if(next, full, url, Bool.not(String.is_empty(next)))

# Errors
# ------

# GitHub's package endpoints need a token with read:packages: an anonymous 401 or 403 says so
def hint(+f: Ctx.Forge, +status: U32) -> String:
  match f:
    case Ctx.Gitea{}:
      ""
    case Ctx.GitHub{}:
      Bool.pick(String, Bool.or(U32.is_eq(status, 401), U32.is_eq(status, 403)), "; GitHub packages need a token with read:packages", "")

def message.of(+q: Query, +status: U32, body: Bytes.Bytes) -> String:
  match q:
    case Query{f, s, o, k, w}:
      Api.message(status, body) ++ hint(f, status)

# Scopes
# ------
# GitHub lists a user's packages under users/ and an org's under orgs/. GET /users/{owner}
# answers for both and names its kind, so one call picks the path; a reply cha can't read
# leaves users/, and the list call then reports the forge's own error.

def scope.kind(+kind: String) -> String:
  Bool.pick(String, String.eq(kind, "Organization"), "orgs/", "users/")

def scope.if(+status: U32, body: Bytes.Bytes, good: Bool) -> String:
  match good:
    case True{}:
      scope.kind(Api.f(Api.obj(body), "type"))
    case False{}:
      "users/"

def scope.reply(r: Api.Reply) -> String:
  match r:
    case Api.Broke{w}:
      "users/"
    case Api.Reply{+status, +next, body}:
      scope.if(status, body, Api.ok(status))

def scope.of(+f: Ctx.Forge, +repo: Ctx.Repo, +tok: String, +owner: String) -> IO(String):
  match f:
    case Ctx.Gitea{}:
      IO.pure(String, "")
    case Ctx.GitHub{}:
      do IO<String>:
        r : Api.Reply <- Api.get(repo, tok, "users/" ++ Url.encode(owner))
        return scope.reply(r)

# Walking pages
# -------------

def read.done(acc: List<&2, Map<&2, String>>, +url: String, last: Bool) -> Pg:
  match last:
    case True{}:
      Last{acc}
    case False{}:
      Next{url, acc}

# a page's rows join the accumulator; the next URL is the Link header's, or the next page
# number while pages keep coming back full
def read.rows(+q: Query, +page: U32, acc: List<&2, Map<&2, String>>, +next: String, src: List<&2, Map<&2, String>>) -> Pg:
  +got : List<&2, Map<&2, String>> = rows.of(src, q)
  +url : String = next.url(next, full.page(q, got), url.of(q, (page + 1 : U32)))
  read.done(List.append(&2, Map<&2, String>, acc, got), url, String.is_empty(url))

def read.state(+q: Query, +page: U32, acc: List<&2, Map<&2, String>>, +status: U32, +next: String, body: Bytes.Bytes, good: Bool) -> Pg:
  match good:
    case True{}:
      read.rows(q, page, acc, next, Api.rows(body))
    case False{}:
      Bad{message.of(q, status, body)}

# every page, one fuel per fetch, so a forge that keeps answering full pages can't loop
# forever. The state carries the walk, so nothing here recurses into anything but itself.
def walk(fuel: Nat, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +q: Query, +page: U32, st: Pg) -> IO(List<&2, Map<&2, String>>):
  match fuel st:
    case 0n s:
      Cli.fail(List<&2, Map<&2, String>>, env, "packages: too many pages")
    case 1n+p Fetch{url, acc}:
      do IO<List<&2, Map<&2, String>>>:
        r : Api.Reply <- Api.get(repo, tok, url)
        walk(p, env, repo, tok, q, page, Read{r, acc})
    case 1n+p Read{Api.Broke{why}, acc}:
      Cli.fail(List<&2, Map<&2, String>>, env, why)
    case 1n+p Read{Api.Reply{+status, +next, body}, acc}:
      walk(p, env, repo, tok, q, page, read.state(q, page, acc, status, next, body, Api.ok(status)))
    case 1n+p Next{url, acc}:
      walk(p, env, repo, tok, q, (page + 1 : U32), Fetch{url, acc})
    case 1n+p Last{acc}:
      IO.pure(List<&2, Map<&2, String>>, acc)
    case 1n+p Bad{why}:
      Cli.fail(List<&2, Map<&2, String>>, env, why)

# Command pieces
# --------------

# a value the command can't work without
def need(+env: Cli.Env, +msg: String, +v: String, missing: Bool) -> IO(String):
  match missing:
    case True{}:
      Cli.fail(String, env, msg)
    case False{}:
      IO.pure(String, v)

# the error a delete without --yes gives, "" when it may go ahead. It names the version it
# would remove, so a pipeline that forgot --yes learns what it almost deleted.
def refusal(+name: String, +version: String, +yes: Bool) -> String:
  match yes:
    case True{}:
      ""
    case False{}:
      "packages delete: would remove " ++ name ++ " " ++ version ++ " for good; rerun with --yes"

def kind.msg(+cmd: String) -> String:
  cmd ++ ": GitHub needs --type (npm, maven, rubygems, nuget, container)"

# --type is required on GitHub and optional on Gitea
def gh.empty(+f: Ctx.Forge, empty: Bool) -> Bool:
  match f:
    case Ctx.Gitea{}:
      False{}
    case Ctx.GitHub{}:
      empty

def owner.of(+repo: Ctx.Repo, +flag: String) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      Ctx.or(flag, o)

def deleted(+env: Cli.Env, +name: String, +version: String) -> IO(Unit):
  match env:
    case Cli.Env{r, t, +on, j, a}:
      Ui.done(on, "deleted " ++ name ++ " " ++ version)

def id.row(+x: Map<&2, String>, +version: String) -> String:
  Bool.pick(String, String.eq(g(x, "version"), version), g(x, "id"), "")

def id.of(xs: List<&2, Map<&2, String>>, +version: String) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, t}:
      Ctx.or(id.row(x, version), id.of(t, version))

# a delete prints no rows, so --json takes no field list
def json.check(+env: Cli.Env, j: Cli.Json) -> IO(Unit):
  match j:
    case Cli.Only{fs}:
      Cli.fail(Unit, env, "packages delete prints no rows; --json takes no field list")
    case x:
      IO.pure(Unit, Unit{})

def remove.status(+env: Cli.Env, +name: String, +version: String, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      deleted(env, name, version)
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def remove.read(+env: Cli.Env, +name: String, +version: String, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{why}:
      Cli.fail(Unit, env, why)
    case Api.Reply{+status, +next, body}:
      remove.status(env, name, version, status, body, Api.ok(status))

def remove(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, url: String, +name: String, +version: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.send(repo, tok, "DELETE", url, None{})
    remove.read(env, name, version, r)

# the id of a version: GitHub deletes by it, and its version list is where it comes from
def resolve(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +q: Query, +version: String) -> IO(String):
  do IO<String>:
    +xs : List<&2, Map<&2, String>> <- walk(300n, env, repo, tok, q, 1, Fetch{url.of(q, 1), Nil{}})
    return id.of(xs, version)

def delete.at(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +f: Ctx.Forge, +scope: String, +owner: String, +kind: String, +name: String, +version: String) -> IO(Unit):
  match f:
    case Ctx.Gitea{}:
      remove(env, repo, tok, delete.url(f, scope, owner, kind, name, version), name, version)
    case Ctx.GitHub{}:
      do IO<Unit>:
        +q : Query = Query{f, scope, owner, kind, Versions{name}}
        +id : String <- resolve(env, repo, tok, q, version)
        Cli.check.if(env, "packages delete: no version " ++ version ++ " of " ++ name, Bool.not(String.is_empty(id)))
        remove(env, repo, tok, delete.url(f, scope, owner, kind, name, id), name, version)

# Commands
# --------

def list(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "packages list", args, ["--type", "--owner", "--json"])
        +ty : String = Cli.flag(args, "--type", "")
        +kind : String <- need(env, kind.msg("packages list"), ty, gh.empty(forge.of(repo), String.is_empty(ty)))
        +owner : String = owner.of(repo, Cli.flag(args, "--owner", ""))
        scope : String <- scope.of(forge.of(repo), repo, tok, owner)
        +q : Query = Query{forge.of(repo), scope, owner, kind, Packages{}}
        xs : List<&2, Map<&2, String>> <- walk(300n, env, repo, tok, q, 1, Fetch{url.of(q, 1), Nil{}})
        emit(on, json, xs)

def versions(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "packages versions", args, ["--type", "--owner", "--json"])
        +name : String <- need(env, "packages versions: a package name is required", Cli.arg(args, 1n), String.is_empty(Cli.arg(args, 1n)))
        +ty : String = Cli.flag(args, "--type", "")
        +kind : String <- need(env, kind.msg("packages versions"), ty, gh.empty(forge.of(repo), String.is_empty(ty)))
        +owner : String = owner.of(repo, Cli.flag(args, "--owner", ""))
        scope : String <- scope.of(forge.of(repo), repo, tok, owner)
        +q : Query = Query{forge.of(repo), scope, owner, kind, Versions{name}}
        xs : List<&2, Map<&2, String>> <- walk(300n, env, repo, tok, q, 1, Fetch{url.of(q, 1), Nil{}})
        emit(on, json, xs)

def delete(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "packages delete", args, ["--type", "--owner", "--yes"])
        json.check(env, json)
        +name : String <- need(env, "packages delete: a package name is required", Cli.arg(args, 1n), String.is_empty(Cli.arg(args, 1n)))
        +version : String <- need(env, "packages delete: a version is required", Cli.arg(args, 2n), String.is_empty(Cli.arg(args, 2n)))
        +ty : String = Cli.flag(args, "--type", "")
        +kind : String <- need(env, "packages delete: --type is required", ty, String.is_empty(ty))
        +bad : String = refusal(name, version, Cli.has(args, "--yes"))
        Cli.check.if(env, bad, String.is_empty(bad))
        +owner : String = owner.of(repo, Cli.flag(args, "--owner", ""))
        scope : String <- scope.of(forge.of(repo), repo, tok, owner)
        delete.at(env, repo, tok, forge.of(repo), scope, owner, kind, name, version)

# Dispatch
# --------

def names() -> List<&2, String>:
  ["list", "versions", "delete"]

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
      versions(env)
    case 2n:
      delete(env)
    case 3n+k:
      Cli.fail(Unit, env, "packages: unknown subcommand, try cha help")

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
