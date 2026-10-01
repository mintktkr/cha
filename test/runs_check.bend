import Base
import ../src/ctx.bend as Ctx
import ../src/api.bend as Api
import ../src/cmd/runs.bend as Runs
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

def is_true(+got: Bool) -> IO(Unit):
  expect(Bool.show(got), "True")

# one run object as Api.obj flattens it
def fake() -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "workflow_runs.#", "2")
  m = Map.set(&2, String, m, "workflow_runs.0.id", "7")
  m = Map.set(&2, String, m, "workflow_runs.0.run_number", "1")
  m = Map.set(&2, String, m, "workflow_runs.0.status", "completed")
  m = Map.set(&2, String, m, "workflow_runs.0.conclusion", "failure")
  m = Map.set(&2, String, m, "workflow_runs.0.path", "ci.yml@refs/heads/main")
  m = Map.set(&2, String, m, "workflow_runs.0.head_branch", "main")
  m = Map.set(&2, String, m, "workflow_runs.0.head_sha", "0123456789abcdef")
  m = Map.set(&2, String, m, "workflow_runs.0.display_title", "one happy job")
  m = Map.set(&2, String, m, "workflow_runs.0.html_url", "https://example.org/runs/7")
  m = Map.set(&2, String, m, "workflow_runs.0.started_at", "2020-01-01T00:00:00Z")
  m = Map.set(&2, String, m, "workflow_runs.1.id", "8")
  m = Map.set(&2, String, m, "workflow_runs.1.status", "in_progress")
  m = Map.set(&2, String, m, "workflow_runs.1.path", "ci.yml@refs/heads/main")
  m

def main() -> IO(Unit):
  do IO<Unit>:
    expect(Runs.runs.url(Ctx.Gitea{}, "main", "failure", "5"), "actions/runs?page=1&limit=5&branch=main&status=failure")
    expect(Runs.runs.url(Ctx.Gitea{}, "", "", "20"), "actions/runs?page=1&limit=20")
    expect(Runs.runs.url(Ctx.GitHub{}, "main", "", "3"), "actions/runs?page=1&per_page=3&branch=main")
    expect(Runs.short.sha("0123456789abcdef"), "0123456")
    expect(Runs.short.sha("abc"), "abc")
    expect(Runs.age.of(30), "30s ago")
    expect(Runs.age.of(90), "1m ago")
    expect(Runs.age.of(7200), "2h ago")
    expect(Runs.age.of(172800), "2d ago")
    expect(Runs.state.of("completed", "failure", True{}), "failure")
    expect(Runs.state.of("in_progress", "", False{}), "in_progress")
    expect(Runs.input.key("a=1"), "a")
    expect(Runs.input.val("a=1=2"), "1=2")
    is_true(Runs.failed.labels("failure"))
    is_true(Runs.failed.labels("cancelled"))
    expect(Bool.show(Runs.failed.labels("success")), "False")
    is_true(Runs.want.job("1", "failure", "", False{}))
    expect(Bool.show(Runs.want.job("1", "success", "", True{})), "False")
    is_true(Runs.want.job("2", "success", "2", False{}))
    is_true(Runs.want.job("2", "success", "", False{}))
    expect(Bool.show(Runs.want.job("2", "success", "3", False{})), "False")
    +now : Time.Instant <- Time.now()
    +src : Map<&2, String> = fake()
    +row : Map<&2, String> = Runs.run.row(src, "workflow_runs.0", Ctx.Gitea{}, now)
    expect(Api.f(row, "workflow"), "ci.yml")
    expect(Api.f(row, "state"), "failure")
    expect(Api.f(row, "branch"), "main")
    expect(Api.f(row, "title"), "one happy job")
    expect(Api.f(row, "html_url"), "https://example.org/runs/7")
    expect(Bool.show(String.ends_with(Api.f(row, "age"), " ago")), "True")
    +xs : List<&2, Map<&2, String>> = Runs.rows.of(src, "workflow_runs", Ctx.Gitea{}, now)
    expect(Nat.show(List.length(&2, Map<&2, String>, xs)), "2")
    expect(Nat.show(Api.count(src, "workflow_runs")), "2")
