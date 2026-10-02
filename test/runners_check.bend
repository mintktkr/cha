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

def main() -> IO(Unit):
  do IO<Unit>:
    expect(Runners.url.of(Ctx.Repo{Ctx.GitHub{}, "github.com", "sample", "repo"}, "", 1), "repos/sample/repo/actions/runners?per_page=100&page=1")
    expect(Runners.url.of(Ctx.Repo{Ctx.GitHub{}, "github.com", "sample", "repo"}, "sample-org", 2), "orgs/sample-org/actions/runners?per_page=100&page=2")
    expect(Runners.url.of(Ctx.Repo{Ctx.Gitea{}, "example.org", "sample", "repo"}, "", 1), "repos/sample/repo/actions/runners?page=1&limit=50")
    expect(Runners.url.of(Ctx.Repo{Ctx.Gitea{}, "example.org", "sample", "repo"}, "sample-org", 3), "orgs/sample-org/actions/runners?page=3&limit=50")
    +xs : List<&2, Map<&2, String>> = gh.rows()
    expect(Nat.show(List.length(&2, Map<&2, String>, xs)), "2")
    gh.check(xs)
    line.check(xs)
    +gitea : Map<&2, String> = gitea.row()
    gitea.check(gitea)
    expect(Runners.line(False{}, gitea), "#7  local  online  ubuntu-latest")
    expect(Cli.json.rows(xs, Runners.fields()), "[{\"id\":\"23\",\"name\":\"gpu-runner\",\"status\":\"online\",\"busy\":\"true\",\"labels\":\"self-hosted,linux,x64\",\"os\":\"linux\"},\n{\"id\":\"24\",\"name\":\"spare\",\"status\":\"offline\",\"busy\":\"false\",\"labels\":\"\",\"os\":\"windows\"}]")
    expect(Runners.endpoint("a/../b", "o", "r"), "orgs/a%2F..%2Fb/actions/runners")
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
