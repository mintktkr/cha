import Base
import ../src/ctx.bend as Ctx
import ../src/cli.bend as Cli
import ../src/api.bend as Api
import ../src/url.bend as Url
import ../src/cmd/runs.bend as Runs
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time

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

def env() -> Cli.Env:
  Cli.Env{Ctx.Repo{Ctx.Gitea{}, "example.org", "sample", "repo"}, "", False{}, Cli.All{}, Nil{}}

def page.one() -> String:
  "{\"workflow_runs\":[{\"id\":\"3\",\"path\":\"other.yml@refs/heads/main\"},{\"id\":\"2\",\"path\":\"ci.yml@refs/heads/main\"}]}"

def page.two() -> String:
  "{\"workflow_runs\":[{\"id\":\"1\",\"path\":\"ci.yml@refs/heads/main\"},{\"id\":\"0\",\"path\":\"ci.yml@refs/heads/main\"}]}"

def page.done(st: Runs.RunPages) -> IO(Unit):
  match st:
    case Runs.NextRuns{True{}, next, n, Con{+a, Con{+b, Nil{}}}}:
      do IO<Unit>:
        expect(Api.f(a, "id"), "2")
        expect(Api.f(b, "id"), "1")
    case _:
      IO.die(Unit, 1, "filtered limit must count matches across pages")

def page.continue(st: Runs.RunPages, +now: Time.Instant) -> IO(Unit):
  match st:
    case Runs.NextRuns{False{}, +next, n, +acc}:
      do IO<Unit>:
        expect(next, "page-2")
        expect(Nat.show(List.length(&2, Map<&2, String>, acc)), "1")
        page.done(Runs.list.page(env(), Ctx.Gitea{}, now, ["ci.yml"], 2n, "page-3", "", n, Bytes.from_string(page.two()), acc))
    case _:
      IO.die(Unit, 1, "nonmatching runs must not consume the limit")

# Gitea sends total_count and no Link header.
def page.counted(+total: String) -> String:
  "{\"total_count\":" ++ total ++ ",\"workflow_runs\":[{\"id\":\"3\"},{\"id\":\"2\"}]}"

def gitea.more(st: Runs.RunPages) -> IO(Unit):
  match st:
    case Runs.NextRuns{False{}, +next, n, acc}:
      do IO<Unit>:
        expect(next, "fallback-2")
        expect(Nat.show(n), "2")
    case _:
      IO.die(Unit, 1, "short of total_count, a page without a Link must ask for the next page")

def gitea.last(st: Runs.RunPages) -> IO(Unit):
  match st:
    case Runs.NextRuns{True{}, next, n, acc}:
      expect(Nat.show(n), "5")
    case _:
      IO.die(Unit, 1, "at total_count the walk must stop")

def named.check(xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Con{a, Con{b, Nil{}}}:
      do IO<Unit>:
        expect(a, "ci-two.yml")
        expect(b, "ci.yml")
    case _:
      IO.die(Unit, 1, "duplicate workflow display names must resolve all matching files")

def main() -> IO(Unit):
  do IO<Unit>:
    expect(Url.encode("topic/a & b"), "topic%2Fa%20%26%20b")
    expect(Url.encode("茶"), "%E8%8C%B6")
    expect(Runs.runs.url(Ctx.Gitea{}, "a&status=success", "in_progress", "2"), "actions/runs?page=1&limit=2&branch=a%26status%3Dsuccess&status=in_progress")
    expect(Runs.branch.of(Api.obj(Bytes.from_string("{\"head_branch\":\"main\",\"path\":\"ci.yml@refs/heads/other\"}")), ""), "main")
    expect(Runs.branch.of(Api.obj(Bytes.from_string("{\"path\":\"ci.yml@refs/heads/topic/a\"}")), ""), "topic/a")
    expect(Runs.branch.of(Api.obj(Bytes.from_string("{\"path\":\"ci.yml@refs/tags/v1\"}")), ""), "refs/tags/v1")
    expect(Runs.branch.of(Api.obj(Bytes.from_string("{\"path\":\"ci.yml@refs/pull/42/head\"}")), ""), "refs/pull/42/head")
    expect(Runs.branch.of(Api.obj(Bytes.from_string("{\"ref\":\"refs/heads/develop\",\"path\":\"ci.yml@refs/heads/main\"}")), ""), "develop")
    expect(Runs.branch.of(Map.new(&2, String), ""), "")
    +now : Time.Instant <- Time.now()
    +row : Map<&2, String> = Runs.run.row(Api.obj(Bytes.from_string("{\"name\":\"CI\",\"path\":\".github/workflows/ci.yml@main\",\"status\":\"completed\",\"updated_at\":\"2026-01-02T13:10:00Z\",\"run_started_at\":\"2026-01-02T10:00:00-03:00\",\"completed_at\":\"2026-01-02T13:01:30Z\"}")), "", Ctx.GitHub{}, now)
    expect(Api.f(row, "kind"), "run")
    expect(Api.f(row, "updated_at"), "2026-01-02T13:10:00Z")
    expect(Api.f(row, "completed_at"), "2026-01-02T13:01:30Z")
    expect(Api.f(row, "duration"), "90")
    expect(Bool.show(Runs.workflow.matches(row, "ci.yml")), "True")
    expect(Bool.show(Runs.workflow.matches(row, "CI")), "True")
    expect(Bool.show(Runs.workflow.matches(row, ".github/workflows/ci.yml")), "True")
    expect(Bool.show(Runs.workflow.matches(row, "ci")), "False")
    +missing : Map<&2, String> = Runs.run.row(Api.obj(Bytes.from_string("{\"status\":\"completed\",\"updated_at\":\"2026-01-02T13:10:00Z\"}")), "", Ctx.GitHub{}, now)
    expect(Api.f(missing, "completed_at"), "")
    expect(Api.f(missing, "duration"), "")
    +active : Map<&2, String> = Runs.run.row(Api.obj(Bytes.from_string("{\"status\":\"in_progress\",\"completed_at\":\"2026-01-02T13:10:00Z\"}")), "", Ctx.Gitea{}, now)
    expect(Api.f(active, "completed_at"), "")
    page.continue(Runs.list.page(env(), Ctx.Gitea{}, now, ["ci.yml"], 2n, "page-2", "", 0n, Bytes.from_string(page.one()), Nil{}), now)
    gitea.more(Runs.list.page(env(), Ctx.Gitea{}, now, Nil{}, 20n, "", "fallback-2", 0n, Bytes.from_string(page.counted("5")), Nil{}))
    gitea.last(Runs.list.page(env(), Ctx.Gitea{}, now, Nil{}, 20n, "", "fallback-3", 3n, Bytes.from_string(page.counted("5")), Nil{}))
    expect(Runs.runs.at("&limit=50", 2), "actions/runs?page=2&limit=50")
    +workflows : Map<&2, String> = Api.obj(Bytes.from_string("{\"workflows\":[{\"id\":\"ci.yml\",\"name\":\"CI\",\"path\":\".gitea/workflows/ci.yml\"},{\"id\":\"ci-two.yml\",\"name\":\"CI\",\"path\":\".gitea/workflows/ci-two.yml\"},{\"id\":\"other.yml\",\"name\":\"Other\"}]}"))
    named.check(Runs.workflow.named(Api.count(workflows, "workflows"), 0, workflows, "CI", Nil{}))
    expect(Runs.rerun.path("7", "", False{}, False{}), "actions/runs/7/rerun")
    expect(Runs.rerun.path("7", "", True{}, False{}), "actions/runs/7/rerun-failed-jobs")
    expect(Runs.rerun.path("7", "42", False{}, True{}), "actions/jobs/42/rerun")
