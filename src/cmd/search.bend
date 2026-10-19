# cha search: issues, pull requests, repos and code, over one repo, one owner or a forge.
import Base
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli
import ../url.bend as Url
import ./issue.bend as Issue
import ./repo.bend as Repo

# kinds
# -----

def pick(eq: Bool, k: Nat, later: Nat) -> Nat:
  match eq:
    case True{}:
      k
    case False{}:
      later

# 0 issues, 1 prs, 2 repos, 3 code; 4 is none of them
def kind.of(+w: String) -> Nat:
  pick(String.eq(w, "issues"), 0n,
  pick(String.eq(w, "prs"), 1n,
  pick(String.eq(w, "repos"), 2n,
  pick(String.eq(w, "code"), 3n, 4n))))

def kind.name(+k: Nat) -> String:
  match k:
    case 0n:
      "issues"
    case 1n:
      "prs"
    case 2n:
      "repos"
    case j:
      "code"

def issues.flags() -> List<&2, String>:
  ["--state", "--owner", "--limit", "--json"]

def repos.flags() -> List<&2, String>:
  ["--owner", "--limit", "--json"]

def flags.of(+k: Nat) -> List<&2, String>:
  match k:
    case 0n:
      issues.flags()
    case 1n:
      issues.flags()
    case j:
      repos.flags()

def kind.msg(+w: String, empty: Bool) -> String:
  match empty:
    case True{}:
      "usage: cha search issues|prs|repos|code QUERY [flags]"
    case False{}:
      "search: unknown kind " ++ w ++ "; use issues, prs, repos or code"

def kind.check(+env: Cli.Env, +w: String, k: Nat) -> IO(Unit):
  match k:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n:
      IO.pure(Unit, Unit{})
    case 2n:
      IO.pure(Unit, Unit{})
    case 3n:
      IO.pure(Unit, Unit{})
    case j:
      Cli.fail(Unit, env, kind.msg(w, String.is_empty(w)))

# queries
# -------

# a qualifier, "" when its value is empty: qual("is", "open") is " is:open"
def qual(+pre: String, +v: String) -> String:
  Ctx.or.if(" " ++ pre ++ ":" ++ v, "", String.is_empty(v))

def name.q(+o: String, +n: String) -> String:
  Ctx.or.if(o ++ "/" ++ n, "", String.is_empty(o) || String.is_empty(n))

# the repo or the owner a github query narrows to; "" searches the whole forge
def repo.q(+repo: Ctx.Repo, +owner: String) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      Ctx.or(qual("user", owner), qual("repo", name.q(o, n)))

# gitea's issue search filters by owner but has no repo filter, so one repo is searched
# through that repo's own issue list, which takes q as well
def gitea.issues.path(+repo: Ctx.Repo, +owner: String) -> String:
  match repo:
    case Ctx.Repo{f, h, +o, +n}:
      Ctx.or.if("repos/" ++ o ++ "/" ++ n ++ "/issues", "repos/issues/search", Bool.not(String.is_empty(owner)) || String.is_empty(o) || String.is_empty(n))

# gitea takes an owner scope as a parameter instead
def gitea.scope.q(+owner: String) -> String:
  Ctx.or.if("&owner=" ++ Url.encode(owner), "", String.is_empty(owner))

def prs.word(prs: Bool) -> String:
  match prs:
    case True{}:
      " is:pr"
    case False{}:
      " is:issue"

def type.q(prs: Bool) -> String:
  match prs:
    case True{}:
      "&type=pulls"
    case False{}:
      "&type=issues"

# a github search url: its qualifiers live inside q, which is encoded once
def gh.url(+path: String, +q: String, size: Nat) -> String:
  "search/" ++ path ++ "?q=" ++ Url.encode(q) ++ "&per_page=" ++ Nat.show(size)

# issues and prs: github needs is:issue or is:pr in every query, and spells the state as
# another qualifier; gitea has a parameter for each
def issue.url(+f: Ctx.Forge, +repo: Ctx.Repo, +owner: String, +q: String, +state: String, size: Nat, prs: Bool) -> String:
  match f:
    case Ctx.GitHub{}:
      gh.url("issues", q ++ prs.word(prs) ++ qual("is", state) ++ repo.q(repo, owner), size)
    case Ctx.Gitea{}:
      gitea.issues.path(repo, owner) ++ "?limit=" ++ Nat.show(size) ++ "&state=" ++ Url.encode(Ctx.or(state, "all")) ++ type.q(prs) ++ Issue.param.q("&q=", q) ++ gitea.scope.q(owner)

# repos ignore the repo scope: --owner narrows them, or the whole forge is searched
def repo.url(+f: Ctx.Forge, +owner: String, +q: String, size: Nat) -> String:
  match f:
    case Ctx.GitHub{}:
      gh.url("repositories", q ++ qual("user", owner), size)
    case Ctx.Gitea{}:
      "repos/search?limit=" ++ Nat.show(size) ++ Issue.param.q("&q=", q)

def code.url(+f: Ctx.Forge, +repo: Ctx.Repo, +owner: String, +q: String, size: Nat) -> String:
  match f:
    case Ctx.GitHub{}:
      gh.url("code", q ++ repo.q(repo, owner), size)
    case Ctx.Gitea{}:
      ""

def min.at(+limit: Nat, +n: Nat, over: Bool) -> Nat:
  match over:
    case True{}:
      n
    case False{}:
      limit

# a page as each forge caps it
def size.of(+f: Ctx.Forge, +limit: Nat) -> Nat:
  match f:
    case Ctx.Gitea{}:
      min.at(limit, 50n, Nat.is_gt(limit, 50n))
    case Ctx.GitHub{}:
      min.at(limit, 100n, Nat.is_gt(limit, 100n))

# the url one search asks, relative to the forge's API root
def url.of(+k: Nat, +f: Ctx.Forge, +repo: Ctx.Repo, +owner: String, +q: String, +state: String, +limit: Nat) -> String:
  match k:
    case 0n:
      issue.url(f, repo, owner, q, state, size.of(f, limit), False{})
    case 1n:
      issue.url(f, repo, owner, q, state, size.of(f, limit), True{})
    case 2n:
      repo.url(f, owner, q, size.of(f, limit))
    case j:
      code.url(f, repo, owner, q, size.of(f, limit))

# rows
# ----
# Both search endpoints that matter answer an object holding an array (github's "items",
# gitea's repo search "data"), which Api.all's array walker cannot read, so each item is
# built into a row field by field from the flattened body, the way runs does with
# workflow_runs. A command never walks JSON itself.

# root.i, the prefix of the i-th item of an array held by the body
def prefix.of(+root: String, i: U32) -> String:
  root ++ "." ++ U32.show(i)

# a field of the item at prefix, as the forge sent it
def g(+src: Map<&2, String>, +prefix: String, +k: String) -> String:
  Api.f(src, Api.key(prefix, k))

def g.raw(+src: Map<&2, String>, +prefix: String, +k: String) -> String:
  Api.raw.f(src, Api.key(prefix, k))

# github names a hit's repo in repository_url, code hits and gitea in repository.full_name
def repo.from.url(+u: String) -> String:
  Ctx.strip_prefix(u, "https://api.github.com/repos/")

def repo.name(+src: Map<&2, String>, +at: String) -> String:
  Ctx.or(g.raw(src, at, "repository.full_name"), repo.from.url(g.raw(src, at, "repository_url")))

# an issue or a pr at at: the fields issue list prints, its labels joined, its repo
def row.issue(+src: Map<&2, String>, +at: String) -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "number", g.raw(src, at, "number"))
  m = Map.set(&2, String, m, "state", g.raw(src, at, "state"))
  m = Map.set(&2, String, m, "title", g.raw(src, at, "title"))
  m = Map.set(&2, String, m, "user.login", g.raw(src, at, "user.login"))
  m = Map.set(&2, String, m, "html_url", g.raw(src, at, "html_url"))
  m = Map.set(&2, String, m, "repo", repo.name(src, at))
  Map.set(&2, String, m, "labels", Api.raw.join(src, Api.key(at, "labels"), "name", ","))

# a searched repo, as the row repo view prints: both forges spell its fields differently
def row.repo(+src: Map<&2, String>, +at: String, +f: Ctx.Forge) -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "full_name", g.raw(src, at, "full_name"))
  m = Map.set(&2, String, m, "description", g.raw(src, at, "description"))
  m = Map.set(&2, String, m, "html_url", g.raw(src, at, "html_url"))
  m = Map.set(&2, String, m, "default_branch", g.raw(src, at, "default_branch"))
  m = Map.set(&2, String, m, "visibility", g.raw(src, at, "visibility"))
  m = Map.set(&2, String, m, "private", g.raw(src, at, "private"))
  m = Map.set(&2, String, m, "internal", g.raw(src, at, "internal"))
  m = Map.set(&2, String, m, "stars_count", g.raw(src, at, "stars_count"))
  m = Map.set(&2, String, m, "forks_count", g.raw(src, at, "forks_count"))
  m = Map.set(&2, String, m, "open_issues_count", g.raw(src, at, "open_issues_count"))
  m = Map.set(&2, String, m, "stargazers_count", g.raw(src, at, "stargazers_count"))
  Repo.view.row(f, m)

# a code hit at at: the file, and the repo it sits in
def row.code(+src: Map<&2, String>, +at: String) -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "name", g.raw(src, at, "name"))
  m = Map.set(&2, String, m, "path", g.raw(src, at, "path"))
  m = Map.set(&2, String, m, "html_url", g.raw(src, at, "html_url"))
  Map.set(&2, String, m, "repo", repo.name(src, at))

def row.of(+k: Nat, +src: Map<&2, String>, +at: String, +f: Ctx.Forge) -> Map<&2, String>:
  match k:
    case 0n:
      row.issue(src, at)
    case 1n:
      row.issue(src, at)
    case 2n:
      row.repo(src, at, f)
    case j:
      row.code(src, at)

def rows.go(+k: Nat, n: Nat, +src: Map<&2, String>, +root: String, +i: U32, +f: Ctx.Forge) -> List<&2, Map<&2, String>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      row.of(k, src, prefix.of(root, i), f) <> rows.go(k, p, src, root, (i + 1 : U32), f)

# the items of the array root in a search body, one row each
def rows.of(+k: Nat, +src: Map<&2, String>, +root: String, +f: Ctx.Forge) -> List<&2, Map<&2, String>>:
  rows.go(k, Api.count(src, root), src, root, 0, f)

# a row from a bare array body (gitea's issue search) needs its labels joined and its repo
def with_repo(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      Map.set(&2, String, x, "repo", repo.name(x, "")) <> with_repo(rest)

# gitea answers issues and prs as a bare array, so those rows are already flat
def shape(+k: Nat, xs: List<&2, Map<&2, String>>, github: Bool) -> List<&2, Map<&2, String>>:
  match k github:
    case 2n x:
      xs
    case j True{}:
      xs
    case x False{}:
      with_repo(Issue.with_labels(xs))

# output
# ------

# the repo a row belongs to, indented before it, only when the search was wider than one repo
def pre.if(on: Bool, +x: Map<&2, String>, wide: Bool) -> String:
  match wide:
    case True{}:
      +r = Api.f(x, "repo")
      Ctx.or.if(Ui.dim(on, r) ++ "  ", "", String.is_empty(r))
    case False{}:
      ""

def line.issue(+on: Bool, +x: Map<&2, String>, +wide: Bool) -> String:
  pre.if(on, x, wide) ++ Issue.line(on, x)

def repo.line(+on: Bool, +x: Map<&2, String>) -> String:
  +desc = Api.f(x, "description")
  Ui.bold(on, Api.f(x, "full_name")) ++ "  " ++ Repo.vis.text(on, Api.f(x, "visibility")) ++ "  stars " ++ Api.f(x, "stars") ++ "  forks " ++ Api.f(x, "forks") ++ Ctx.or.if("  " ++ Ui.dim(on, desc), "", String.is_empty(desc))

def code.line(+on: Bool, +x: Map<&2, String>) -> String:
  Ui.bold(on, Api.f(x, "path")) ++ "  " ++ Ui.dim(on, Api.f(x, "repo"))

def line.of(+k: Nat, +on: Bool, +x: Map<&2, String>, +wide: Bool) -> String:
  match k:
    case 0n:
      line.issue(on, x, wide)
    case 1n:
      line.issue(on, x, wide)
    case 2n:
      repo.line(on, x)
    case j:
      code.line(on, x)

def lines(+k: Nat, xs: List<&2, Map<&2, String>>, +on: Bool, +wide: Bool) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      line.of(k, on, x, wide) ++ "\n" ++ lines(k, rest, on, wide)

def json.fields(+k: Nat) -> List<&2, String>:
  match k:
    case 0n:
      ["repo", "number", "title", "state", "user.login", "labels", "html_url"]
    case 1n:
      ["repo", "number", "title", "state", "user.login", "labels", "html_url"]
    case 2n:
      ["full_name", "forge", "description", "default_branch", "visibility", "stars", "forks", "open_issues", "html_url"]
    case j:
      ["repo", "name", "path", "html_url"]

def print.rows(+on: Bool, json: Cli.Json, xs: List<&2, Map<&2, String>>, +k: Nat, +wide: Bool) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(lines(k, xs, on, wide))
    case j:
      Cli.json.emit(on, j, xs, json.fields(k))

# replies
# -------

def reply.rows.if(+status: U32, body: Bytes.Bytes, +k: Nat, +root: String, +f: Ctx.Forge, good: Bool) -> Result<&1, &1, String, List<&2, Map<&2, String>>>:
  match good:
    case True{}:
      Done{rows.of(k, Api.obj(body), root, f)}
    case False{}:
      Fail{Api.message(status, body)}

def reply.rows(r: Api.Reply, +k: Nat, +root: String, +f: Ctx.Forge) -> Result<&1, &1, String, List<&2, Map<&2, String>>>:
  match r:
    case Api.Broke{w}:
      Fail{w}
    case Api.Reply{+status, next, body}:
      reply.rows.if(status, body, k, root, f, Api.ok(status))

# github wraps a search's hits in items
def gh.rows(+f: Ctx.Forge, +repo: Ctx.Repo, +tok: String, +k: Nat, url: String) -> IO(Result<&1, &1, String, List<&2, Map<&2, String>>>):
  do IO<Result<&1, &1, String, List<&2, Map<&2, String>>>>:
    r : Api.Reply <- Api.get(repo, tok, url)
    return reply.rows(r, k, "items", f)

# gitea's issue search answers a bare array, which Api.all walks; its repo search an object
def gitea.rows(+f: Ctx.Forge, +repo: Ctx.Repo, +tok: String, +k: Nat, url: String) -> IO(Result<&1, &1, String, List<&2, Map<&2, String>>>):
  match k:
    case 2n:
      do IO<Result<&1, &1, String, List<&2, Map<&2, String>>>>:
        r : Api.Reply <- Api.get(repo, tok, url)
        return reply.rows(r, 2n, "data", f)
    case j:
      Api.all(1n, repo, tok, url)

def fetch(+f: Ctx.Forge, +repo: Ctx.Repo, +tok: String, +k: Nat, url: String) -> IO(Result<&1, &1, String, List<&2, Map<&2, String>>>):
  match f:
    case Ctx.GitHub{}:
      gh.rows(f, repo, tok, k, url)
    case Ctx.Gitea{}:
      gitea.rows(f, repo, tok, k, url)

def show(+env: Cli.Env, +k: Nat, +f: Ctx.Forge, r: Result<&1, &1, String, List<&2, Map<&2, String>>>, wide: Bool) -> IO(Unit):
  match env r:
    case Cli.Env{repo, tok, +on, json, args} Done{xs}:
      print.rows(on, json, shape(k, xs, Issue.is.github(f)), k, wide)
    case e Fail{w}:
      Cli.fail(Unit, e, w)

# checks
# ------

def state.bad(+s: String) -> Bool:
  Bool.not(String.is_empty(s) || String.eq(s, "all") || String.eq(s, "open") || String.eq(s, "closed"))

def state.if(+env: Cli.Env, bad: Bool) -> IO(Unit):
  match bad:
    case True{}:
      Cli.fail(Unit, env, "search: --state takes open, closed or all")
    case False{}:
      IO.pure(Unit, Unit{})

def state.check(+env: Cli.Env, +s: String) -> IO(Unit):
  state.if(env, state.bad(s))

# "all" is every state, which the query leaves out
def state.norm(+s: String) -> String:
  Ctx.or.if(s, "", String.eq(s, "all") || String.is_empty(s))

def code.if(+env: Cli.Env, code: Bool, github: Bool, anon: Bool) -> IO(Unit):
  match code github anon:
    case True{} True{} True{}:
      Cli.fail(Unit, env, "search code: GitHub code search needs a token")
    case True{} False{} x:
      Cli.fail(Unit, env, "search code: this forge has no code search API")
    case x y z:
      IO.pure(Unit, Unit{})

# gitea can search issues by owner but not repos, so the flag would silently search the forge
def owner.if(+env: Cli.Env, repos: Bool, github: Bool, empty: Bool) -> IO(Unit):
  match repos github empty:
    case True{} False{} False{}:
      Cli.fail(Unit, env, "search repos: --owner is GitHub-only")
    case x y z:
      IO.pure(Unit, Unit{})

def limit.check(+env: Cli.Env, v: U32, ok: Bool) -> IO(Nat):
  match ok:
    case True{}:
      IO.pure(Nat, U32.to_nat(v))
    case False{}:
      Cli.fail(Nat, env, "search: --limit must be an integer from 1 to 100")

def limit.got(+env: Cli.Env, m: Maybe<&2, U32>) -> IO(Nat):
  match m:
    case Some{+v}:
      limit.check(env, v, (v > 0 : U32) && (v <= 100 : U32))
    case None{}:
      Cli.fail(Nat, env, "search: --limit must be an integer from 1 to 100")

def limit.of(+env: Cli.Env, +v: String) -> IO(Nat):
  limit.got(env, U32.read(v))

def query.if(+env: Cli.Env, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      Cli.fail(Unit, env, "search: no query; usage: cha search issues|prs|repos|code QUERY [flags]")
    case False{}:
      IO.pure(Unit, Unit{})

def query.check(+env: Cli.Env, +q: String) -> IO(Unit):
  query.if(env, String.is_empty(q))

# the query: every word after the kind, so a phrase needs no quotes
def query.of(+args: List<&2, String>) -> String:
  String.join(List.drop(&2, String, Cli.positional(args), 1n), " ")

# a search is wider than one repo when it is narrowed by an owner, or by no repo at all
def wide.of(+repo: Ctx.Repo, +owner: String) -> Bool:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      Bool.not(String.is_empty(owner)) || String.is_empty(o)

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +w : String = Cli.arg(args, 0n)
        +k : Nat = kind.of(w)
        kind.check(env, w, k)
        Cli.check(env, "search " ++ kind.name(k), args, flags.of(k))
        +q : String = query.of(args)
        +given : String = Cli.flag(args, "--state", "")
        state.check(env, given)
        +state : String = state.norm(given)
        +owner : String = Cli.flag(args, "--owner", "")
        +f : Ctx.Forge = Issue.forge.of(repo)
        +limit : Nat <- limit.of(env, Cli.flag(args, "--limit", "20"))
        code.if(env, Nat.is_eq(k, 3n), Issue.is.github(f), String.is_empty(tok))
        owner.if(env, Nat.is_eq(k, 2n), Issue.is.github(f), String.is_empty(owner))
        query.check(env, q)
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- fetch(f, repo, tok, k, url.of(k, f, repo, owner, q, state, limit))
        show(env, k, f, r, wide.of(repo, owner))
