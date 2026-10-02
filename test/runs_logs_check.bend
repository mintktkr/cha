import Base
import ../src/api.bend as Api
import ../src/ctx.bend as Ctx
import ../src/cmd/runs.bend as Runs
import ../src/runlogs.bend as Runlogs

def expect.if(+label: String, +got: String, +want: String, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      IO.print("ok  " ++ label)
    case False{}:
      do IO<Unit>:
        IO.print("bad " ++ label ++ ": " ++ got ++ " != " ++ want)
        IO.die(Unit, 1, "")

def expect(+label: String, +got: String, +want: String) -> IO(Unit):
  expect.if(label, got, want, String.eq(got, want))

def jobs() -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "jobs.#", "2")
  m = Map.set(&2, String, m, "jobs.0.id", "21")
  m = Map.set(&2, String, m, "jobs.0.name", "Run Tests")
  m = Map.set(&2, String, m, "jobs.0.status", "completed")
  m = Map.set(&2, String, m, "jobs.0.conclusion", "success")
  m = Map.set(&2, String, m, "jobs.0.steps.#", "2")
  m = Map.set(&2, String, m, "jobs.0.steps.0.name", "Install Dependencies")
  m = Map.set(&2, String, m, "jobs.0.steps.0.number", "1")
  m = Map.set(&2, String, m, "jobs.0.steps.1.name", "Post Cleanup")
  m = Map.set(&2, String, m, "jobs.0.steps.1.number", "8")
  m = Map.set(&2, String, m, "jobs.1.id", "22")
  m = Map.set(&2, String, m, "jobs.1.name", "Run Tests (Windows)")
  m = Map.set(&2, String, m, "jobs.1.status", "in_progress")
  m

def step.position(xs: List<&2, Runlogs.Step>) -> String:
  match xs:
    case Con{Runlogs.Step{p, n, s, c, a, b}, rest}:
      U32.show(p)
    case Nil{}:
      "missing"

def summary(s: Runs.LogSummary) -> String:
  match s:
    case Runs.LogSummary{m, p, i}:
      U32.show(m) ++ "/" ++ U32.show(p) ++ "/" ++ Bool.show(i)

def body() -> String:
  "\u{feff}2026-01-01T02:59:59.9999999Z previous\n" ++
  "2026-01-01T03:00:00.0000000Z ##[group]a command unrelated to the step name\n" ++
  "2026-01-01T03:00:01.9999999Z last selected line\n" ++
  "2026-01-01T03:00:02.0000000Z next step\n"

def main() -> IO(Unit):
  do IO<Unit>:
    expect("job name ignores case", Bool.show(Runs.want.job.named("21", "Run Tests", "success", "run TESTS", False{})), "True")
    expect("job id remains accepted", Bool.show(Runs.want.job.named("21", "Run Tests", "success", "21", False{})), "True")
    expect("name is exact", Bool.show(Runs.want.job.named("22", "Run Tests (Windows)", "success", "Run Tests", False{})), "False")
    expect("failed intersects name", Bool.show(Runs.want.job.named("21", "Run Tests", "success", "Run Tests", True{})), "False")
    expect("failed job selected by name", Bool.show(Runs.want.job.named("21", "Run Tests", "failure", "run tests", True{})), "True")
    expect("job name selection", Nat.show(List.length(&2, Map<&2, String>, Runs.keep.go(2n, 0, jobs(), "RUN TESTS", False{}))), "1")
    expect("unknown job", Bool.show(Runs.logs.miss(Runs.keep.go(2n, 0, jobs(), "missing", False{}), "missing")), "True")
    expect("BOM removed", Runlogs.strip.bom("\u{feff}timestamp\n"), "timestamp\n")
    expect("interior BOM retained", Runlogs.strip.bom("a\u{feff}b"), "a\u{feff}b")
    expect("empty body", Runlogs.strip.bom(""), "")
    expect("GitHub pending", Bool.show(Runs.logs.pending(Ctx.GitHub{}, "in_progress")), "True")
    expect("GitHub queued", Bool.show(Runs.logs.pending(Ctx.GitHub{}, "queued")), "True")
    expect("GitHub completed", Bool.show(Runs.logs.pending(Ctx.GitHub{}, "completed")), "False")
    expect("Gitea live logs retained", Bool.show(Runs.logs.pending(Ctx.Gitea{}, "in_progress")), "False")
    expect("watch hint", Bool.show(String.contains(Runs.logs.pending.message("42", "build", "queued"), "cha runs watch 42")), "True")
    expect("partial logs summary", summary(Runs.logs.sum(Runs.LogSummary{0, 0, True{}}, Runs.LogSummary{1, 1, False{}})), "1/1/True")
    expect("step name ignores case", Nat.show(List.length(&2, Runlogs.Step, Runlogs.steps.of(jobs(), "jobs.0.steps", "install DEPENDENCIES"))), "1")
    expect("step name is exact", Nat.show(List.length(&2, Runlogs.Step, Runlogs.steps.of(jobs(), "jobs.0.steps", "Install"))), "0")
    expect("step endpoint uses zero-based position", step.position(Runlogs.steps.of(jobs(), "jobs.0.steps", "Post Cleanup")), "1")
    expect("step endpoint", Runs.logs.step.path("21", 1), "actions/jobs/21/steps/1/logs")
    expect("Gitea timing uses parsed offsets and includes final second", Maybe.default(&2, String, Runlogs.window(body(), "2026-01-01T00:00:00-03:00", "2026-01-01T00:00:01-03:00"), "missing"), "2026-01-01T03:00:00.0000000Z ##[group]a command unrelated to the step name\n2026-01-01T03:00:01.9999999Z last selected line\n")
    expect("missing timing does not return entire log", Maybe.default(&2, String, Runlogs.window(body(), "", ""), "missing"), "missing")
    expect("invalid interval", Maybe.default(&2, String, Runlogs.window(body(), "2026-01-01T00:00:02Z", "2026-01-01T00:00:01Z"), "missing"), "missing")
    +one : List<&2, Map<&2, String>> = [Map.new(&2, String)]
    expect("no failed job is not a missing step", Bool.show(Runs.logs.no.step(Nil{}, "Test", 0)), "False")
    expect("a selected job without the step is", Bool.show(Runs.logs.no.step(one, "Test", 0)), "True")
    expect("a matched step is not missing", Bool.show(Runs.logs.no.step(one, "Test", 1)), "False")
    expect("no --step is never missing", Bool.show(Runs.logs.no.step(one, "", 0)), "False")
