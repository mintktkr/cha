# offline checks for the packages command's pure pieces: URLs, rows and the delete guard.
import Base
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../src/ctx.bend as Ctx
import ../src/cli.bend as Cli
import ../src/api.bend as Api
import ../src/cmd/packages.bend as Packages

def expect.if(+got: String, +want: String, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      IO.print("ok  " ++ got)
    case False{}:
      do IO<Unit>:
        IO.print("bad " ++ got ++ " != " ++ want)
        IO.die(Unit, 1, "")

def expect(+got: String, +want: String) -> IO(Unit):
  expect.if(got, want, String.eq(got, want))

# a Gitea owner's packages: one row per version, the type and the version on each
def gitea.page() -> String:
  "[{\"id\":11,\"name\":\"cha\",\"type\":\"arch\",\"version\":\"0.1.0-1\",\"created_at\":\"2026-10-02T19:37:26-03:00\"},{\"id\":12,\"name\":\"cha\",\"type\":\"arch\",\"version\":\"0.0.9-1\",\"created_at\":\"2026-09-30T10:00:00-03:00\"}]"

# Gitea's q is a name filter: it answers "cha" and "cha-tools" for the name "cha"
def gitea.q() -> String:
  "[{\"id\":11,\"name\":\"cha\",\"type\":\"arch\",\"version\":\"0.1.0-1\",\"created_at\":\"2026-10-02T19:37:26-03:00\"},{\"id\":13,\"name\":\"cha-tools\",\"type\":\"arch\",\"version\":\"2.0\",\"created_at\":\"2026-09-29T10:00:00-03:00\"}]"

# GitHub's list is one row per package, with no version
def github.page() -> String:
  "[{\"id\":1,\"name\":\"cha\",\"package_type\":\"container\",\"version_count\":2,\"created_at\":\"2026-10-02T19:37:26Z\"},{\"id\":2,\"name\":\"tea\",\"package_type\":\"npm\",\"version_count\":1,\"created_at\":\"2026-10-01T00:00:00Z\"}]"

# GitHub's versions list carries the version in the row's name, and the id a delete needs
def github.versions() -> String:
  "[{\"id\":402,\"name\":\"0.1.0\",\"created_at\":\"2026-10-02T19:37:26Z\"},{\"id\":401,\"name\":\"0.0.9\",\"created_at\":\"2026-09-30T10:00:00Z\"}]"

def gitea.repo() -> Ctx.Repo:
  Ctx.Repo{Ctx.Gitea{}, "tea.example.org", "sample", "sandbox"}

def github.repo() -> Ctx.Repo:
  Ctx.Repo{Ctx.GitHub{}, "github.com", "sample", "sandbox"}

def q.gitea.list() -> Packages.Query:
  Packages.Query{Ctx.Gitea{}, "", "sample", "arch", Packages.Packages{}}

def q.gitea.versions() -> Packages.Query:
  Packages.Query{Ctx.Gitea{}, "", "sample", "arch", Packages.Versions{"cha"}}

def q.github.list() -> Packages.Query:
  Packages.Query{Ctx.GitHub{}, "orgs/", "sample", "container", Packages.Packages{}}

def q.github.versions() -> Packages.Query:
  Packages.Query{Ctx.GitHub{}, "orgs/", "sample", "container", Packages.Versions{"cha"}}

def rows.of(+src: String, +q: Packages.Query) -> List<&2, Map<&2, String>>:
  Packages.rows.of(Api.rows(Bytes.from_string(src)), q)

def one(xs: List<&2, Map<&2, String>>) -> Map<&2, String>:
  match xs:
    case Con{+x, t}:
      x
    case x:
      Map.new(&2, String)

def count(xs: List<&2, Map<&2, String>>) -> String:
  Nat.show(List.length(&2, Map<&2, String>, xs))

def joined(xs: List<&2, String>) -> String:
  String.join(xs, ",")

def url.check() -> IO(Unit):
  do IO<Unit>:
    expect(Packages.url.of(q.gitea.list(), 1), "packages/sample?page=1&limit=50&type=arch")
    expect(Packages.url.of(Packages.Query{Ctx.Gitea{}, "", "sample", "", Packages.Packages{}}, 1), "packages/sample?page=1&limit=50")
    expect(Packages.url.of(q.gitea.versions(), 3), "packages/sample?page=3&limit=50&type=arch&q=cha")
    expect(Packages.url.of(Packages.Query{Ctx.Gitea{}, "", "sample org", "", Packages.Packages{}}, 2), "packages/sample%20org?page=2&limit=50")
    expect(Packages.url.of(q.github.list(), 1), "orgs/sample/packages?package_type=container&per_page=100&page=1")
    expect(Packages.url.of(q.github.versions(), 2), "orgs/sample/packages/container/cha/versions?per_page=100&page=2")
    expect(Packages.url.of(Packages.Query{Ctx.GitHub{}, "users/", "memu", "npm", Packages.Versions{"a/b"}}, 1), "users/memu/packages/npm/a%2Fb/versions?per_page=100&page=1")
    expect(Packages.delete.url(Ctx.Gitea{}, "", "sample", "arch", "cha", "0.1.0-1"), "packages/sample/arch/cha/0.1.0-1")
    expect(Packages.delete.url(Ctx.GitHub{}, "orgs/", "sample", "container", "cha", "402"), "orgs/sample/packages/container/cha/versions/402")

def row.check() -> IO(Unit):
  do IO<Unit>:
    +arch : List<&2, Map<&2, String>> = rows.of(gitea.page(), q.gitea.list())
    expect(count(arch), "2")
    +a : Map<&2, String> = one(arch)
    expect(Api.f(a, "name"), "cha")
    expect(Api.f(a, "type"), "arch")
    expect(Api.f(a, "version"), "0.1.0-1")
    expect(Api.f(a, "created"), "2026-10-02T19:37:26-03:00")
    expect(Api.raw.f(a, "id"), "11")
    expect(Packages.line(False{}, a), "cha  arch  0.1.0-1  2026-10-02T19:37:26-03:00")
    expect(Cli.json.row(a, Packages.fields()), "{\"name\":\"cha\",\"type\":\"arch\",\"version\":\"0.1.0-1\",\"created\":\"2026-10-02T19:37:26-03:00\"}")
    +pkgs : List<&2, Map<&2, String>> = rows.of(github.page(), q.github.list())
    +b : Map<&2, String> = one(pkgs)
    expect(Api.f(b, "name"), "cha")
    expect(Api.f(b, "type"), "container")
    expect(Api.f(b, "version"), "")
    expect(Packages.line(False{}, b), "cha  container  2026-10-02T19:37:26Z")
    +vers : List<&2, Map<&2, String>> = rows.of(github.versions(), q.github.versions())
    +c : Map<&2, String> = one(vers)
    expect(Api.f(c, "name"), "cha")
    expect(Api.f(c, "type"), "container")
    expect(Api.f(c, "version"), "0.1.0")
    expect(Api.raw.f(c, "id"), "402")
    expect(Packages.line(False{}, c), "cha  container  0.1.0  2026-10-02T19:37:26Z")
    expect(joined(Packages.fields()), "name,type,version,created")

# Gitea's q filter matches "cha-tools" too: only the rows named exactly are versions of it
def keep.check() -> IO(Unit):
  do IO<Unit>:
    expect(count(rows.of(gitea.q(), q.gitea.versions())), "1")
    expect(count(rows.of(gitea.q(), q.gitea.list())), "2")

def delete.check() -> IO(Unit):
  do IO<Unit>:
    +vs : List<&2, Map<&2, String>> = rows.of(github.versions(), q.github.versions())
    expect(Packages.id.of(vs, "0.1.0"), "402")
    expect(Packages.id.of(vs, "0.0.9"), "401")
    expect(Packages.id.of(vs, "9.9.9"), "")
    expect(Packages.refusal("cha", "0.1.0", False{}), "packages delete: would remove cha 0.1.0 for good; rerun with --yes")
    expect(Packages.refusal("cha", "0.1.0", True{}), "")

def scope.check() -> IO(Unit):
  do IO<Unit>:
    expect(Packages.scope.kind("Organization"), "orgs/")
    expect(Packages.scope.kind("User"), "users/")
    expect(Packages.scope.kind(""), "users/")
    expect(Bool.show(Packages.gh.empty(Ctx.Gitea{}, True{})), "False")
    expect(Bool.show(Packages.gh.empty(Ctx.GitHub{}, True{})), "True")
    expect(Bool.show(Packages.gh.empty(Ctx.GitHub{}, False{})), "False")

def page.check() -> IO(Unit):
  do IO<Unit>:
    expect(Nat.show(Packages.page.size(Ctx.Gitea{})), "50")
    expect(Nat.show(Packages.page.size(Ctx.GitHub{})), "100")
    expect(Packages.next.url("/packages/sample?page=2", False{}, "built"), "/packages/sample?page=2")
    expect(Packages.next.url("", True{}, "built"), "built")
    expect(Packages.next.url("", False{}, "built"), "")
    expect(Bool.show(Packages.full.page(q.github.list(), rows.of(github.page(), q.github.list()))), "False")

def unauthorized() -> String:
  "{\"message\":\"Bad credentials\"}"

def error.check() -> IO(Unit):
  do IO<Unit>:
    expect(Packages.message.of(q.github.list(), 401, Bytes.from_string(unauthorized())), "HTTP 401: Bad credentials; GitHub packages need a token with read:packages")
    expect(Packages.message.of(q.github.list(), 403, Bytes.from_string(unauthorized())), "HTTP 403: Bad credentials; GitHub packages need a token with read:packages")
    expect(Packages.message.of(q.gitea.list(), 401, Bytes.from_string(unauthorized())), "HTTP 401: Bad credentials")
    expect(Packages.message.of(q.github.list(), 404, Bytes.from_string(unauthorized())), "HTTP 404: Bad credentials")

def main() -> IO(Unit):
  do IO<Unit>:
    url.check()
    row.check()
    keep.check()
    delete.check()
    scope.check()
    page.check()
    error.check()
