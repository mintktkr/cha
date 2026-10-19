import Base
import ../src/ctx.bend as Ctx
import ../src/api.bend as Api
import ../src/cmd/runs.bend as Runs
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time
import 0x4eed9d7ac6ece61523d747a9d804e4f0/int.bend as Int

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
  m = Map.set(&2, String, m, "workflow_runs.0.run_attempt", "2")
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
  "{\"workflow_runs\":[{\"id\":\"7448154\",\"title\":\"merge forgejo\",\"workflow_id\":\"merge-requirements.yml\",\"index_in_repo\":\"204056\",\"prettyref\":\"#14633\",\"commit_sha\":\"43cd3108ca5755ecd8958f51706dfd9bec0bc33b\",\"event\":\"pull_request\",\"status\":\"success\",\"started\":\"2026-01-02T10:00:00Z\",\"stopped\":\"2026-01-02T10:00:02Z\",\"updated\":\"2026-01-02T10:00:02Z\",\"html_url\":\"https://codeberg.org/forgejo/forgejo/actions/runs/204056\"},{\"id\":\"7448151\",\"workflow_id\":\"release-notes-assistant.yml\",\"index_in_repo\":\"204055\",\"prettyref\":\"#14633\",\"commit_sha\":\"43cd3108ca5755ecd8958f51706dfd9bec0bc33b\",\"event\":\"pull_request\",\"status\":\"skipped\",\"started\":\"1970-01-01T01:00:00+01:00\",\"stopped\":\"2026-01-02T10:00:35Z\",\"updated\":\"2026-01-02T10:00:35Z\"},{\"id\":\"7448149\",\"title\":\"push to forgejo\",\"workflow_id\":\"testing.yml\",\"index_in_repo\":\"204053\",\"prettyref\":\"forgejo\",\"commit_sha\":\"3a81b293b09618b12a10bb25cc8d8b447c6561b7\",\"event\":\"push\",\"status\":\"running\",\"started\":\"2026-01-02T10:00:00Z\",\"updated\":\"2026-01-02T10:00:01Z\"},{\"id\":\"7448152\",\"workflow_id\":\"testing.yml\",\"index_in_repo\":\"204054\",\"prettyref\":\"#14569\",\"commit_sha\":\"83ff810a1a3fa81a8bd6cb2ea5e0f8e2a2f2a3b1\",\"event\":\"pull_request\",\"status\":\"blocked\",\"started\":\"1970-01-01T01:00:00+01:00\",\"stopped\":\"1970-01-01T01:00:00+01:00\",\"updated\":\"2026-01-02T10:00:45Z\"}]}"

def fj.check.finished(+row: Map<&2, String>) -> IO(Unit):
  do IO<Unit>:
    expect(Api.f(row, "workflow"), "merge-requirements.yml")
    expect(Api.f(row, "path"), "merge-requirements.yml")
    expect(Api.f(row, "name"), "merge-requirements.yml")
    expect(Api.f(row, "run_number"), "204056")
    expect(Api.f(row, "attempt"), "")
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

# a blocked run waits for approval: it has not started, and none of its
# timestamps are real
def fj.check.approval(+row: Map<&2, String>) -> IO(Unit):
  do IO<Unit>:
    expect(Api.f(row, "status"), "blocked")
    expect(Api.f(row, "conclusion"), "")
    expect(Api.f(row, "state"), "blocked")
    expect(Api.f(row, "started_at"), "")
    expect(Api.f(row, "completed_at"), "")
    expect(Api.f(row, "duration"), "")
    expect(Api.f(row, "age"), "")
    expect(Api.f(row, "updated_at"), "2026-01-02T10:00:45Z")

# a page of Gitea runs around a dispatch: an older dispatch of the same workflow
# first (the trap), a push, another workflow, another ref, then the run the
# dispatch made. Gitea 1.25 sends no creation time, so a run is placed by its start.
def gitea.page() -> String:
  "{\"total_count\":5,\"workflow_runs\":[{\"id\":\"41\",\"event\":\"workflow_dispatch\",\"path\":\"ci.yml@refs/heads/main\",\"head_branch\":\"main\",\"html_url\":\"https://example.org/runs/41\",\"started_at\":\"2026-01-02T09:00:00Z\"},{\"id\":\"42\",\"event\":\"push\",\"path\":\"ci.yml@refs/heads/main\",\"head_branch\":\"main\",\"html_url\":\"https://example.org/runs/42\",\"started_at\":\"2026-01-02T10:00:05Z\"},{\"id\":\"43\",\"event\":\"workflow_dispatch\",\"path\":\"slow.yml@refs/heads/main\",\"head_branch\":\"main\",\"html_url\":\"https://example.org/runs/43\",\"started_at\":\"2026-01-02T10:00:06Z\"},{\"id\":\"44\",\"event\":\"workflow_dispatch\",\"path\":\"ci.yml@refs/heads/dev\",\"head_branch\":\"dev\",\"html_url\":\"https://example.org/runs/44\",\"started_at\":\"2026-01-02T10:00:07Z\"},{\"id\":\"45\",\"event\":\"workflow_dispatch\",\"path\":\"ci.yml@refs/heads/main\",\"head_branch\":\"main\",\"html_url\":\"https://example.org/runs/45\",\"started_at\":\"2026-01-02T10:00:08Z\"}]}"

# a Gitea stamp carries the forge's own offset: 07:00:08-03:00 is 10:00:08Z, at or
# after the dispatch at 10:00:00Z even though it reads as the earlier string
def offset.page() -> String:
  "{\"workflow_runs\":[{\"id\":\"51\",\"event\":\"workflow_dispatch\",\"path\":\"ci.yml@refs/heads/main\",\"head_branch\":\"main\",\"html_url\":\"https://example.org/runs/51\",\"started_at\":\"2026-01-02T07:00:08-03:00\"}]}"

# GitHub stamps created_at on a run, which is the first field cha looks for
def github.page() -> String:
  "{\"total_count\":2,\"workflow_runs\":[{\"id\":\"71\",\"event\":\"workflow_dispatch\",\"path\":\"ci.yml@refs/heads/main\",\"head_branch\":\"main\",\"html_url\":\"https://example.org/runs/71\",\"created_at\":\"2026-01-02T09:00:00Z\"},{\"id\":\"72\",\"event\":\"workflow_dispatch\",\"path\":\"ci.yml@refs/heads/main\",\"head_branch\":\"main\",\"html_url\":\"https://example.org/runs/72\",\"created_at\":\"2026-01-02T10:00:04Z\"}]}"

# a dispatch that has created no run yet: one still queued (Gitea's zero start) and
# one with no timestamp at all are both uncountable
def queued.page() -> String:
  "{\"workflow_runs\":[{\"id\":\"61\",\"event\":\"workflow_dispatch\",\"path\":\"ci.yml@refs/heads/main\",\"head_branch\":\"main\",\"html_url\":\"https://example.org/runs/61\",\"started_at\":\"0001-01-01T00:00:00Z\"},{\"id\":\"60\",\"event\":\"workflow_dispatch\",\"path\":\"ci.yml@refs/heads/main\",\"head_branch\":\"main\",\"html_url\":\"https://example.org/runs/60\"}]}"

# the url dispatch.scan names for a page, with a fixed clock
def picked.for(+forge: Ctx.Forge, +src: Map<&2, String>, +wf: String, +ref: String, +t0: Time.Instant) -> String:
  Runs.dispatch.url.of(Runs.dispatch.scan(Api.count(src, "workflow_runs"), 0, src, forge, Time.Instant.of_unix(Int.I64.from_u32(1767348100)), wf, ref, t0))

def picked(+src: Map<&2, String>, +wf: String, +ref: String, +t0: Time.Instant) -> String:
  picked.for(Ctx.Gitea{}, src, wf, ref, t0)

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
    expect(Api.f(row, "attempt"), "2")
    expect(Api.f(row, "html_url"), "https://example.org/runs/7")
    expect(Bool.show(String.ends_with(Api.f(row, "age"), " ago")), "True")
    +xs : List<&2, Map<&2, String>> = Runs.rows.of(src, "workflow_runs", Ctx.Gitea{}, now)
    expect(Nat.show(List.length(&2, Map<&2, String>, xs)), "2")
    expect(Nat.show(Api.count(src, "workflow_runs")), "2")
    +fsrc : Map<&2, String> = Api.obj(Bytes.from_string(fj.body()))
    fj.check.finished(Runs.run.row(fsrc, "workflow_runs.0", Ctx.Gitea{}, now))
    fj.check.skipped(Runs.run.row(fsrc, "workflow_runs.1", Ctx.Gitea{}, now))
    fj.check.running(Runs.run.row(fsrc, "workflow_runs.2", Ctx.Gitea{}, now))
    fj.check.approval(Runs.run.row(fsrc, "workflow_runs.3", Ctx.Gitea{}, now))
    # the run a dispatch made is the only run of its workflow, event and ref that
    # appeared at or after the instant noted before the POST
    +t0 : Time.Instant = Time.Instant.of_unix(Int.I64.from_u32(1767348000))
    +gpage : Map<&2, String> = Api.obj(Bytes.from_string(gitea.page()))
    expect(picked(gpage, "ci.yml", "main", t0), "https://example.org/runs/45")
    expect(picked(gpage, "slow.yml", "main", t0), "https://example.org/runs/43")
    expect(picked(gpage, "ci.yml", "dev", t0), "https://example.org/runs/44")
    expect(picked(gpage, "ci.yml", "refs/heads/main", t0), "https://example.org/runs/45")
    expect(picked(gpage, "other.yml", "main", t0), "")
    +later : Time.Instant = Time.Instant.of_unix(Int.I64.from_u32(1767348100))
    expect(picked(gpage, "ci.yml", "main", later), "")
    is_true(Runs.dispatch.hit(Runs.run.row(gpage, "workflow_runs.0", Ctx.Gitea{}, now), Runs.created.at(gpage, "workflow_runs.0"), "ci.yml", "main", Time.Instant.of_unix(Int.I64.from_u32(1767300000))))
    expect(Bool.show(Runs.dispatch.hit(Runs.run.row(gpage, "workflow_runs.0", Ctx.Gitea{}, now), Runs.created.at(gpage, "workflow_runs.0"), "ci.yml", "main", t0)), "False")
    +opage : Map<&2, String> = Api.obj(Bytes.from_string(offset.page()))
    expect(picked(opage, "ci.yml", "main", t0), "https://example.org/runs/51")
    +ghpage : Map<&2, String> = Api.obj(Bytes.from_string(github.page()))
    expect(picked.for(Ctx.GitHub{}, ghpage, "ci.yml", "main", t0), "https://example.org/runs/72")
    expect(Runs.created.at(ghpage, "workflow_runs.1"), "2026-01-02T10:00:04Z")
    +qpage : Map<&2, String> = Api.obj(Bytes.from_string(queued.page()))
    expect(picked(qpage, "ci.yml", "main", t0), "")
    is_true(Runs.ref.same("main", "refs/heads/main"))
    is_true(Runs.ref.same("refs/tags/v1", "v1"))
    expect(Bool.show(Runs.ref.same("dev", "main")), "False")
    expect(Runs.dispatch.runs(Ctx.Gitea{}), "actions/runs?page=1&limit=20&event=workflow_dispatch")
    expect(Runs.dispatch.runs(Ctx.GitHub{}), "actions/runs?page=1&per_page=20&event=workflow_dispatch")
    expect(Runs.dispatch.page(Ctx.Gitea{}, "ci.yml"), "actions?workflow=ci.yml")
    expect(Runs.dispatch.page(Ctx.GitHub{}, "ci.yml"), "actions/workflows/ci.yml")
    expect(Api.str(Runs.dispatch.body("main", Nil{}, True{}), "ref"), "main")
    expect(Api.str(Runs.dispatch.body("main", Nil{}, True{}), "return_run_details"), "true")
    expect(Api.str(Runs.dispatch.body("main", Nil{}, False{}), "return_run_details"), "")
