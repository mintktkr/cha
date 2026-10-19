import Base
import ../src/ctx.bend as Ctx
import ../src/cli.bend as Cli
import ../src/cmd/runners.bend as Runners
import ../src/api.bend as Api
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes

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

# a Bool as "true" or "false", so a check reads like the others
def check.bool(+got: Bool, +want: Bool) -> IO(Unit):
  expect(Api.json.bool(got), Api.json.bool(want))

def gh() -> Ctx.Repo:
  Ctx.Repo{Ctx.GitHub{}, "github.com", "sample", "repo"}

def gitea() -> Ctx.Repo:
  Ctx.Repo{Ctx.Gitea{}, "example.org", "sample", "repo"}

# a synthetic GitHub page: one busy linux runner with three labels, one idle windows
# runner with none
def gh.page() -> String:
  "{\"total_count\":2,\"runners\":[{\"id\":23,\"name\":\"gpu-runner\",\"os\":\"linux\",\"status\":\"online\",\"busy\":true,\"labels\":[{\"id\":1,\"name\":\"self-hosted\"},{\"id\":2,\"name\":\"linux\"},{\"id\":3,\"name\":\"x64\"}]},{\"id\":24,\"name\":\"spare\",\"os\":\"windows\",\"status\":\"offline\",\"busy\":false,\"labels\":[]}]}"

# Gitea 1.25 answers the same wrapper, with no os on a runner
def gitea.page() -> String:
  "{\"total_count\":1,\"runners\":[{\"id\":7,\"name\":\"local\",\"status\":\"online\",\"busy\":false,\"ephemeral\":false,\"labels\":[{\"id\":0,\"name\":\"ubuntu-latest\",\"type\":\"custom\"}]}]}"

def gh.rows() -> List<&2, Map<&2, String>>:
  Runners.rows.of(Api.obj(Bytes.from_string(gh.page())))

def gitea.row() -> Map<&2, String>:
  Runners.runner.row(Api.obj(Bytes.from_string(gitea.page())), "runners.0")

def gh.check(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Con{+a, Con{+b, Nil{}}}:
      do IO<Unit>:
        expect(Api.f(a, "id"), "23")
        expect(Api.f(a, "name"), "gpu-runner")
        expect(Api.f(a, "status"), "online")
        expect(Api.f(a, "busy"), "true")
        expect(Api.f(a, "os"), "linux")
        expect(Api.f(a, "labels"), "self-hosted,linux,x64")
        expect(Api.f(b, "id"), "24")
        expect(Api.f(b, "busy"), "false")
        expect(Api.f(b, "os"), "windows")
        expect(Api.f(b, "labels"), "")
    case x:
      IO.die(Unit, 1, "a GitHub page of two runners must map to two rows")

def gitea.check(+row: Map<&2, String>) -> IO(Unit):
  do IO<Unit>:
    expect(Api.f(row, "status"), "online")
    expect(Api.f(row, "labels"), "ubuntu-latest")
    expect(Api.f(row, "os"), "")

def line.check(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Con{+a, Con{+b, Nil{}}}:
      do IO<Unit>:
        expect(Runners.line(False{}, a), "#23  gpu-runner  online  busy  self-hosted,linux,x64")
        expect(Runners.line(False{}, b), "#24  spare  offline")
    case x:
      IO.die(Unit, 1, "expected two runners")

# one page's URL at each scope, on both forges
def url.check() -> IO(Unit):
  do IO<Unit>:
    expect(Runners.url.of(gh(), Runners.Repo{}, 1), "repos/sample/repo/actions/runners?per_page=100&page=1")
    expect(Runners.url.of(gh(), Runners.Org{"sample-org"}, 2), "orgs/sample-org/actions/runners?per_page=100&page=2")
    expect(Runners.url.of(gh(), Runners.User{}, 1), "user/actions/runners?per_page=100&page=1")
    expect(Runners.url.of(gh(), Runners.Admin{}, 1), "admin/actions/runners?per_page=100&page=1")
    expect(Runners.url.of(gitea(), Runners.Repo{}, 1), "repos/sample/repo/actions/runners?page=1&limit=50")
    expect(Runners.url.of(gitea(), Runners.Org{"sample-org"}, 3), "orgs/sample-org/actions/runners?page=3&limit=50")
    expect(Runners.url.of(gitea(), Runners.User{}, 2), "user/actions/runners?page=2&limit=50")
    expect(Runners.url.of(gitea(), Runners.Admin{}, 1), "admin/actions/runners?page=1&limit=50")

# a delete names one runner under the same scope path
def delete.path.check() -> IO(Unit):
  do IO<Unit>:
    expect(Runners.delete.path(gh(), Runners.Repo{}, "23"), "repos/sample/repo/actions/runners/23")
    expect(Runners.delete.path(gh(), Runners.Org{"sample-org"}, "23"), "orgs/sample-org/actions/runners/23")
    expect(Runners.delete.path(gitea(), Runners.User{}, "7"), "user/actions/runners/7")
    expect(Runners.delete.path(gitea(), Runners.Admin{}, "7"), "admin/actions/runners/7")
    expect(Runners.path.of(Runners.Org{"a/../b"}, "o", "r"), "orgs/a%2F..%2Fb/actions/runners")

# GitHub serves a repo's and an org's runners only
def refuse.check() -> IO(Unit):
  do IO<Unit>:
    expect(Runners.refuse(Ctx.GitHub{}, True{}, False{}), "runners: github has no user scope; runners live on a repo or an org")
    expect(Runners.refuse(Ctx.GitHub{}, False{}, True{}), "runners: github has no admin scope; runners live on a repo or an org")
    expect(Runners.refuse(Ctx.GitHub{}, False{}, False{}), "")
    expect(Runners.refuse(Ctx.GitHub{}, False{}, False{}), "")
    expect(Runners.refuse(Ctx.Gitea{}, True{}, False{}), "")
    expect(Runners.refuse(Ctx.Gitea{}, False{}, True{}), "")
    expect(Runners.refuse(Ctx.Gitea{}, True{}, True{}), "")

# two scope flags name one place each, so they can't be combined
def both.check() -> IO(Unit):
  do IO<Unit>:
    check.bool(Runners.scope.both("", True{}, False{}), False{})
    check.bool(Runners.scope.both("", False{}, True{}), False{})
    check.bool(Runners.scope.both("", False{}, False{}), False{})
    check.bool(Runners.scope.both("sample-org", False{}, False{}), False{})
    check.bool(Runners.scope.both("", True{}, True{}), True{})
    check.bool(Runners.scope.both("sample-org", True{}, False{}), True{})
    check.bool(Runners.scope.both("sample-org", False{}, True{}), True{})
    expect(Runners.scope.both.msg(), "runners: --org, --user and --admin name one place; pick one")

# cha never prompts, so a delete without --yes says what it would remove
def yes.check() -> IO(Unit):
  do IO<Unit>:
    expect(Runners.yes.msg("7", Runners.Repo{}), "runners delete: would delete runner 7 from the repo; pass --yes to delete it")
    expect(Runners.yes.msg("7", Runners.Org{"sample-org"}), "runners delete: would delete runner 7 from org sample-org; pass --yes to delete it")
    expect(Runners.yes.msg("7", Runners.User{}), "runners delete: would delete runner 7 from your user; pass --yes to delete it")
    expect(Runners.yes.msg("7", Runners.Admin{}), "runners delete: would delete runner 7 from the site; pass --yes to delete it")

# a runner id goes into a path, so only digits may pass
def digits.check() -> IO(Unit):
  do IO<Unit>:
    check.bool(Runners.digits("23"), True{})
    check.bool(Runners.digits(""), False{})
    check.bool(Runners.digits("2/3"), False{})
    check.bool(Runners.digits("23x"), False{})
    check.bool(Runners.digits("1/registration-token"), False{})
    check.bool(Runners.digits(" 23"), False{})

# an admin-scoped 403 is a token without site admin
def error.check() -> IO(Unit):
  do IO<Unit>:
    expect(Runners.error.of(Runners.Admin{}, 403, Bytes.from_string("{\"message\":\"nope\"}")), "HTTP 403: admin runners need a site-admin token")
    expect(Runners.error.of(Runners.Admin{}, 404, Bytes.from_string("{\"message\":\"gone\"}")), "HTTP 404: gone")
    expect(Runners.error.of(Runners.Repo{}, 403, Bytes.from_string("{\"message\":\"nope\"}")), "HTTP 403: nope")

def main() -> IO(Unit):
  do IO<Unit>:
    url.check()
    delete.path.check()
    refuse.check()
    both.check()
    yes.check()
    digits.check()
    error.check()
    +xs : List<&2, Map<&2, String>> = gh.rows()
    expect(Nat.show(List.length(&2, Map<&2, String>, xs)), "2")
    gh.check(xs)
    line.check(xs)
    +gitea : Map<&2, String> = gitea.row()
    gitea.check(gitea)
    expect(Runners.line(False{}, gitea), "#7  local  online  ubuntu-latest")
    expect(Cli.json.rows(xs, Runners.fields()), "[{\"id\":\"23\",\"name\":\"gpu-runner\",\"status\":\"online\",\"busy\":\"true\",\"labels\":\"self-hosted,linux,x64\",\"os\":\"linux\"},\n{\"id\":\"24\",\"name\":\"spare\",\"status\":\"offline\",\"busy\":\"false\",\"labels\":\"\",\"os\":\"windows\"}]")
    expect(Runners.status(False{}, "online"), "online")
    expect(Runners.status(False{}, "offline"), "offline")
    expect(Runners.status(True{}, "online"), "\u{1b}[38;2;110;242;184monline\u{1b}[39m")
    expect(Runners.status(True{}, "offline"), "\u{1b}[2moffline\u{1b}[22m")
    expect(Runners.busy.text(False{}, "busy", True{}), "  busy")
    expect(Runners.busy.text(False{}, "busy", False{}), "")
    expect(Runners.busy.text(True{}, "busy", True{}), "  \u{1b}[38;2;255;225;77mbusy\u{1b}[39m")
    expect(Runners.page.next("", "next-page", 2n, "5", False{}), "next-page")
    expect(Runners.page.next("", "next-page", 5n, "5", False{}), "")
    expect(Runners.page.next("", "next-page", 0n, "5", True{}), "")
    expect(Runners.page.next("link-page", "next-page", 2n, "5", False{}), "link-page")
