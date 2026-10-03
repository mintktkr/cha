import Base
import ../src/ctx.bend as Ctx
import ../src/api.bend as Api
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

# Forgejo serves its own run schema: one status field, commit_sha, prettyref,
# started and stopped, and index_in_repo for the run number. The skipped run
# never started, so its started is the epoch.
def fj.body() -> String:
  "{\"workflow_runs\":[{\"id\":\"7448154\",\"title\":\"merge forgejo\",\"workflow_id\":\"merge-requirements.yml\",\"index_in_repo\":\"204056\",\"prettyref\":\"#14633\",\"commit_sha\":\"43cd3108ca5755ecd8958f51706dfd9bec0bc33b\",\"event\":\"pull_request\",\"status\":\"success\",\"started\":\"2026-01-02T10:00:00Z\",\"stopped\":\"2026-01-02T10:00:02Z\",\"updated\":\"2026-01-02T10:00:02Z\",\"html_url\":\"https://codeberg.org/forgejo/forgejo/actions/runs/204056\"},{\"id\":\"7448151\",\"workflow_id\":\"release-notes-assistant.yml\",\"index_in_repo\":\"204055\",\"prettyref\":\"#14633\",\"commit_sha\":\"43cd3108ca5755ecd8958f51706dfd9bec0bc33b\",\"event\":\"pull_request\",\"status\":\"skipped\",\"started\":\"1970-01-01T01:00:00+01:00\",\"stopped\":\"2026-01-02T10:00:35Z\",\"updated\":\"2026-01-02T10:00:35Z\"},{\"id\":\"7448149\",\"title\":\"push to forgejo\",\"workflow_id\":\"testing.yml\",\"index_in_repo\":\"204053\",\"prettyref\":\"forgejo\",\"commit_sha\":\"3a81b293b09618b12a10bb25cc8d8b447c6561b7\",\"event\":\"push\",\"status\":\"running\",\"started\":\"2026-01-02T10:00:00Z\",\"updated\":\"2026-01-02T10:00:01Z\"}]}"

def fj.check.finished(+row: Map<&2, String>) -> IO(Unit):
  do IO<Unit>:
    expect(Api.f(row, "workflow"), "merge-requirements.yml")
    expect(Api.f(row, "path"), "merge-requirements.yml")
    expect(Api.f(row, "name"), "merge-requirements.yml")
    expect(Api.f(row, "run_number"), "204056")
    expect(Api.f(row, "status"), "completed")
    expect(Api.f(row, "conclusion"), "success")
    expect(Api.f(row, "state"), "success")
    expect(Api.f(row, "branch"), "#14633")
    expect(Api.f(row, "sha"), "43cd3108ca5755ecd8958f51706dfd9bec0bc33b")
    expect(Api.f(row, "title"), "merge forgejo")
    expect(Api.f(row, "event"), "pull_request")
    expect(Api.f(row, "started_at"), "2026-01-02T10:00:00Z")
    expect(Api.f(row, "updated_at"), "2026-01-02T10:00:02Z")
    expect(Api.f(row, "completed_at"), "2026-01-02T10:00:02Z")
    expect(Api.f(row, "duration"), "2")
    expect(Api.f(row, "html_url"), "https://codeberg.org/forgejo/forgejo/actions/runs/204056")
    expect(Bool.show(String.ends_with(Api.f(row, "age"), " ago")), "True")

def fj.check.skipped(+row: Map<&2, String>) -> IO(Unit):
  do IO<Unit>:
    expect(Api.f(row, "status"), "completed")
    expect(Api.f(row, "conclusion"), "skipped")
    expect(Api.f(row, "state"), "skipped")
    expect(Api.f(row, "started_at"), "")
    expect(Api.f(row, "age"), "")
    expect(Api.f(row, "duration"), "")
    expect(Api.f(row, "title"), "release-notes-assistant.yml")

def fj.check.running(+row: Map<&2, String>) -> IO(Unit):
  do IO<Unit>:
    expect(Api.f(row, "status"), "running")
    expect(Api.f(row, "conclusion"), "")
    expect(Api.f(row, "state"), "running")
    expect(Api.f(row, "branch"), "forgejo")
    expect(Api.f(row, "completed_at"), "")
    expect(Api.f(row, "duration"), "")

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
    +fsrc : Map<&2, String> = Api.obj(Bytes.from_string(fj.body()))
    fj.check.finished(Runs.run.row(fsrc, "workflow_runs.0", Ctx.Gitea{}, now))
    fj.check.skipped(Runs.run.row(fsrc, "workflow_runs.1", Ctx.Gitea{}, now))
    fj.check.running(Runs.run.row(fsrc, "workflow_runs.2", Ctx.Gitea{}, now))
