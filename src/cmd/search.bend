# cha search: issues, pull requests, repos and code, over one repo, one owner or a forge.
import Base
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

# gitea's repo search filters by the owner's numeric id, not its name
def uid.q(+uid: String) -> String:
  Ctx.or.if("&uid=" ++ Url.encode(uid), "", String.is_empty(uid))

# repos ignore the repo scope: --owner narrows them, or the whole forge is searched
def repo.url(+f: Ctx.Forge, +owner: String, +uid: String, +q: String, size: Nat) -> String:
  match f:
    case Ctx.GitHub{}:
      gh.url("repositories", q ++ qual("user", owner), size)
    case Ctx.Gitea{}:
      "repos/search?limit=" ++ Nat.show(size) ++ Issue.param.q("&q=", q) ++ uid.q(uid)

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

# the url one search asks, relative to the forge's API root. uid is the owner's numeric id
# where the forge takes one and "" everywhere else
def url.of(+k: Nat, +f: Ctx.Forge, +repo: Ctx.Repo, +owner: String, +uid: String, +q: String, +state: String, +limit: Nat) -> String:
  match k:
    case 0n:
      issue.url(f, repo, owner, q, state, size.of(f, limit), False{})
    case 1n:
      issue.url(f, repo, owner, q, state, size.of(f, limit), True{})
    case 2n:
      repo.url(f, owner, uid, q, size.of(f, limit))
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

# paging
# ------
# A search answers an object holding its hits (github: items, gitea's repo search: data),
# which Api.all's array walker cannot read, so the object-bodied walk below reads them a
# page at a time and stops at --limit rows. Github pages through its Link header; gitea's
# repo search takes a page parameter and never says where its pages end. Gitea's issue and
# pr search answers a bare array, which Api.all walks.

# the rows the pages read so far hold plus one page's, cut to --limit
def page.take(+acc: List<&2, Map<&2, String>>, +rows: List<&2, Map<&2, String>>, +limit: Nat) -> List<&2, Map<&2, String>>:
  List.take(&2, Map<&2, String>, List.append(&2, Map<&2, String>, acc, rows), limit)

# how many rows the pages read so far hold, before --limit cuts them
def page.seen(+acc: List<&2, Map<&2, String>>, +rows: List<&2, Map<&2, String>>) -> Nat:
  Nat.add(List.length(&2, Map<&2, String>, acc), List.length(&2, Map<&2, String>, rows))

# github's next page is its Link header's, until --limit rows are in, a page comes back
# empty, or the Link is gone: the last page, or the search's last hit.
def gh.next.url(+next: String, +got: Nat, +limit: Nat, empty: Bool) -> String:
  Ctx.or.if(next, "", empty || Nat.is_ge(got, limit))

# gitea's repo search names a page by parameter, and reads limit only when it gets one
def at.page(+base: String, +page: U32) -> String:
  base ++ "&page=" ++ U32.show(page)

# Gitea's repo search never says where its pages end, so the next is one further while the
# page came back full and --limit rows aren't in yet.
def gitea.next.url(+base: String, +page: U32, +got: Nat, +limit: Nat, short: Bool) -> String:
  Ctx.or.if(at.page(base, (page + 1 : U32)), "", short || Nat.is_ge(got, limit))

# the hits one search page holds, under the field its forge wraps them in
def page.rows(+k: Nat, body: List<&2, U32>, +f: Ctx.Forge, github: Bool) -> List<&2, Map<&2, String>>:
  match github:
    case True{}:
      rows.of(k, Api.obj(body), "items", f)
    case False{}:
      rows.of(k, Api.obj(body), "data", f)

# --limit rows of the pages read so far, and the url of the page after this one, "" when
# the walk is done
def page.next(+acc: List<&2, Map<&2, String>>, +rows: List<&2, Map<&2, String>>, +f: Ctx.Forge, +next: String, +base: String, +page: U32, +limit: Nat, github: Bool) -> List<&2, Map<&2, String>> & String:
  match github:
    case True{}:
      (page.take(acc, rows, limit), gh.next.url(next, page.seen(acc, rows), limit, Nat.is_eq(List.length(&2, Map<&2, String>, rows), 0n)))
    case False{}:
      (page.take(acc, rows, limit), gitea.next.url(base, page, page.seen(acc, rows), limit, Nat.is_lt(List.length(&2, Map<&2, String>, rows), size.of(f, limit))))

# where a paged search is: about to ask a page, holding one page's rows and next url, or
# holding the page it just finished
type Pages is Type:
  FetchPage{url: String, acc: List<&2, Map<&2, String>>}
  ReadPage{got: Result<&1, &1, String, List<&2, Map<&2, String>> & String>}
  NextPage{last: Bool, got: List<&2, Map<&2, String>>, next: String}

def pages.done(st: Pages) -> Result<&1, &1, String, List<&2, Map<&2, String>>>:
  match st:
    case FetchPage{u, acc}:
      Done{acc}
    case ReadPage{Fail{w}}:
      Fail{w}
    case ReadPage{Done{(got, next)}}:
      Done{got}
    case NextPage{l, got, n}:
      Done{got}

def page.step.ok(+status: U32, +next: String, +k: Nat, +f: Ctx.Forge, +limit: Nat, +base: String, +page: U32, body: List<&2, U32>, +acc: List<&2, Map<&2, String>>, +github: Bool, good: Bool) -> Result<&1, &1, String, List<&2, Map<&2, String>> & String>:
  match good:
    case True{}:
      +rows = page.rows(k, body, f, github)
      Done{page.next(acc, rows, f, next, base, page, limit, github)}
    case False{}:
      Fail{Api.message(status, body)}

def page.step(r: Api.Reply, +k: Nat, +f: Ctx.Forge, +limit: Nat, +base: String, +page: U32, +acc: List<&2, Map<&2, String>>, github: Bool) -> Result<&1, &1, String, List<&2, Map<&2, String>> & String>:
  match r:
    case Api.Broke{w}:
      Fail{w}
    case Api.Reply{+status, +next, body}:
      page.step.ok(status, next, k, f, limit, base, page, body, acc, github, Api.ok(status))

# how many pages --limit rows can take: a page holds the forge's cap at most, plus the one
# short page that ends the walk
def pages.of(+f: Ctx.Forge, +limit: Nat) -> Nat:
  Nat.add(Nat.div(Nat.add(limit, Nat.sub(size.of(f, limit), 1n)), size.of(f, limit)), 1n)

# every hit of a search, a page at a time, until --limit rows or the forge's last page.
# A page costs three steps, so pages.of bounds the walk.
def search.walk(fuel: Nat, +repo: Ctx.Repo, +tok: String, +k: Nat, +f: Ctx.Forge, +limit: Nat, +base: String, +page: U32, +github: Bool, st: Pages) -> IO(Result<&1, &1, String, List<&2, Map<&2, String>>>):
  match fuel st:
    case 0n s:
      IO.pure(Result<&1, &1, String, List<&2, Map<&2, String>>>, pages.done(s))
    case 1n+p FetchPage{url, acc}:
      IO.bind(Api.Reply, Result<&1, &1, String, List<&2, Map<&2, String>>>, Api.get(repo, tok, url), r => search.walk(p, repo, tok, k, f, limit, base, page, github, ReadPage{page.step(r, k, f, limit, base, page, acc, github)}))
    case 1n+p ReadPage{Fail{w}}:
      IO.pure(Result<&1, &1, String, List<&2, Map<&2, String>>>, Fail{w})
    case 1n+p ReadPage{Done{(got, +next)}}:
      search.walk(p, repo, tok, k, f, limit, base, page, github, NextPage{String.is_empty(next), got, next})
    case 1n+p NextPage{True{}, got, n}:
      IO.pure(Result<&1, &1, String, List<&2, Map<&2, String>>>, Done{got})
    case 1n+p NextPage{False{}, got, next}:
      search.walk(p, repo, tok, k, f, limit, base, (page + 1 : U32), github, FetchPage{next, got})

# at most --limit rows, whatever the forge listed
def capped(r: Result<&1, &1, String, List<&2, Map<&2, String>>>, +limit: Nat) -> Result<&1, &1, String, List<&2, Map<&2, String>>>:
  match r:
    case Done{xs}:
      Done{List.take(&2, Map<&2, String>, xs, limit)}
    case Fail{w}:
      Fail{w}

# gitea's issue and pr search answers a bare array, which Api.all walks; its repo search
# an object, which the walk above reads
def gitea.fetch(+f: Ctx.Forge, +repo: Ctx.Repo, +tok: String, +k: Nat, +limit: Nat, +url: String) -> IO(Result<&1, &1, String, List<&2, Map<&2, String>>>):
  match k:
    case 2n:
      search.walk(Nat.mul(3n, pages.of(f, limit)), repo, tok, k, f, limit, url, 0, False{}, FetchPage{at.page(url, 1), Nil{}})
    case j:
      do IO<Result<&1, &1, String, List<&2, Map<&2, String>>>>:
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(pages.of(f, limit), repo, tok, url)
        return capped(r, limit)

def fetch(+f: Ctx.Forge, +repo: Ctx.Repo, +tok: String, +k: Nat, +limit: Nat, +url: String, +github: Bool) -> IO(Result<&1, &1, String, List<&2, Map<&2, String>>>):
  match github:
    case True{}:
      search.walk(Nat.mul(3n, pages.of(f, limit)), repo, tok, k, f, limit, url, 0, github, FetchPage{url, Nil{}})
    case False{}:
      gitea.fetch(f, repo, tok, k, limit, url)

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

# github narrows a repo search with user:NAME in the query; gitea's takes the owner's
# numeric id, so a name costs one request first. A user and an organization answer alike at
# GET /users/{name} on gitea: organizations are users there.
def uid.path(+owner: String) -> String:
  "users/" ++ Url.encode(owner)

def uid.id.if(+i: String, +owner: String, empty: Bool) -> Result<&1, &1, String, String>:
  match empty:
    case True{}:
      Fail{"search repos: no such owner: " ++ owner}
    case False{}:
      Done{i}

def uid.reply(+status: U32, body: List<&2, U32>, +owner: String, good: Bool) -> Result<&1, &1, String, String>:
  match good:
    case True{}:
      +i = Api.f(Api.obj(body), "id")
      uid.id.if(i, owner, String.is_empty(i))
    case False{}:
      Fail{Api.message(status, body)}

def uid.of(r: Api.Reply, +owner: String) -> Result<&1, &1, String, String>:
  match r:
    case Api.Broke{w}:
      Fail{w}
    case Api.Reply{+status, next, body}:
      uid.reply(status, body, owner, Api.ok(status))

def uid.take(+env: Cli.Env, r: Result<&1, &1, String, String>) -> IO(String):
  match r:
    case Done{+i}:
      IO.pure(String, i)
    case Fail{w}:
      Cli.fail(String, env, w)

def gitea.uid(+env: Cli.Env, +owner: String) -> IO(String):
  match env:
    case Cli.Env{+repo, +tok, on, json, args}:
      do IO<String>:
        r : Api.Reply <- Api.get(repo, tok, uid.path(owner))
        uid.take(env, uid.of(r, owner))

def owner.uid.if(+env: Cli.Env, want: Bool, +owner: String) -> IO(String):
  match want:
    case True{}:
      gitea.uid(env, owner)
    case False{}:
      IO.pure(String, "")

# the owner's id where the forge filters by one, "" everywhere else. Gitea searches issues
# by owner name but filters repos by uid only, so a repo search narrowed by an owner
# resolves the name first.
def owner.uid(+env: Cli.Env, +f: Ctx.Forge, +k: Nat, +owner: String) -> IO(String):
  match f:
    case Ctx.Gitea{}:
      owner.uid.if(env, Nat.is_eq(k, 2n) && Bool.not(String.is_empty(owner)), owner)
    case Ctx.GitHub{}:
      IO.pure(String, "")

def limit.check(+env: Cli.Env, v: U32, ok: Bool) -> IO(Nat):
  match ok:
    case True{}:
      IO.pure(Nat, U32.to_nat(v))
    case False{}:
      Cli.fail(Nat, env, "search: --limit must be an integer from 1 to 1000")

def limit.got(+env: Cli.Env, m: Maybe<&2, U32>) -> IO(Nat):
  match m:
    case Some{+v}:
      limit.check(env, v, (v > 0 : U32) && (v <= 1000 : U32))
    case None{}:
      Cli.fail(Nat, env, "search: --limit must be an integer from 1 to 1000")

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
        query.check(env, q)
        +uid : String <- owner.uid(env, f, k, owner)
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- fetch(f, repo, tok, k, limit, url.of(k, f, repo, owner, uid, q, state, limit), Issue.is.github(f))
        show(env, k, f, r, wide.of(repo, owner))
