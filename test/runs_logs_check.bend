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


# GitHub sections
# ---------------
# One real job's log, cut down: the runner's own steps, a composite action's inner
# group, a step the runner gave no group, and the line that closes the run steps.

def frames() -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "steps.#", "8")
  m = Map.set(&2, String, m, "steps.0.name", "Set up job")
  m = Map.set(&2, String, m, "steps.1.name", "Run actions/checkout@v4")
  m = Map.set(&2, String, m, "steps.2.name", "install deps")
  m = Map.set(&2, String, m, "steps.3.name", "Pull alpine")
  m = Map.set(&2, String, m, "steps.4.name", "Run scripts/check.sh")
  m = Map.set(&2, String, m, "steps.5.name", "Run mypy (fully)")
  m = Map.set(&2, String, m, "steps.6.name", "Post Run actions/checkout@v4")
  m = Map.set(&2, String, m, "steps.7.name", "Complete job")
  m = Map.set(&2, String, m, "steps.0.started_at", "2026-01-01T00:00:01Z")
  m = Map.set(&2, String, m, "steps.0.completed_at", "2026-01-01T00:00:02Z")
  m = Map.set(&2, String, m, "steps.1.started_at", "2026-01-01T00:00:02Z")
  m = Map.set(&2, String, m, "steps.1.completed_at", "2026-01-01T00:00:03Z")
  m = Map.set(&2, String, m, "steps.2.started_at", "2026-01-01T00:00:03Z")
  m = Map.set(&2, String, m, "steps.2.completed_at", "2026-01-01T00:00:04Z")
  m = Map.set(&2, String, m, "steps.3.started_at", "2026-01-01T00:00:04Z")
  m = Map.set(&2, String, m, "steps.3.completed_at", "2026-01-01T00:00:05Z")
  m = Map.set(&2, String, m, "steps.4.started_at", "2026-01-01T00:00:05Z")
  m = Map.set(&2, String, m, "steps.4.completed_at", "2026-01-01T00:00:06Z")
  m = Map.set(&2, String, m, "steps.5.started_at", "2026-01-01T00:00:06Z")
  m = Map.set(&2, String, m, "steps.5.completed_at", "2026-01-01T00:00:06Z")
  m = Map.set(&2, String, m, "steps.5.conclusion", "skipped")
  m = Map.set(&2, String, m, "steps.6.started_at", "2026-01-01T00:00:06Z")
  m = Map.set(&2, String, m, "steps.6.completed_at", "2026-01-01T00:00:06Z")
  m = Map.set(&2, String, m, "steps.7.started_at", "2026-01-01T00:00:06Z")
  m = Map.set(&2, String, m, "steps.7.completed_at", "2026-01-01T00:00:06Z")
  m

def frames.log() -> String:
  "2026-01-01T00:00:02.0000000Z ##[group]Run actions/checkout@v4\n" ++
  "2026-01-01T00:00:02.1000000Z with:\n" ++
  "2026-01-01T00:00:02.2000000Z ##[endgroup]\n" ++
  "2026-01-01T00:00:02.3000000Z checked out\n" ++
  "2026-01-01T00:00:03.0000000Z ##[group]Run npm install\n" ++
  "2026-01-01T00:00:03.1000000Z ##[endgroup]\n" ++
  "2026-01-01T00:00:03.2000000Z ##[group]Run setup-uv@v1\n" ++
  "2026-01-01T00:00:03.3000000Z ##[endgroup]\n" ++
  "2026-01-01T00:00:03.4000000Z installed\n" ++
  "2026-01-01T00:00:05.0000000Z ##[group]Run scripts/check.sh\n" ++
  "2026-01-01T00:00:05.1000000Z ##[endgroup]\n" ++
  "2026-01-01T00:00:05.2000000Z ok\n" ++
  "2026-01-01T00:00:06.0000000Z Post job cleanup.\n" ++
  "2026-01-01T00:00:06.1000000Z post output\n"

def pair.log() -> String:
  "2026-01-01T00:00:08.0000000Z ##[group]Run actions/cache@v4\n" ++
  "2026-01-01T00:00:08.1000000Z ##[endgroup]\n" ++
  "2026-01-01T00:00:08.2000000Z cache restored\n" ++
  "2026-01-01T00:00:08.3000000Z ##[group]Run scripts/check.sh\n" ++
  "2026-01-01T00:00:08.4000000Z ##[endgroup]\n" ++
  "2026-01-01T00:00:08.5000000Z ok\n" ++
  "2026-01-01T00:00:09.0000000Z Post job cleanup.\n" ++
  "2026-01-01T00:00:09.1000000Z post output\n"

# A step whose group line the runner only wrote in the second after its start: the
# later step opens its own window in that same second, so the group text is what
# tells the two apart.
def pair() -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "steps.#", "2")
  m = Map.set(&2, String, m, "steps.0.name", "Run actions/cache@v4")
  m = Map.set(&2, String, m, "steps.0.started_at", "2026-01-01T00:00:07Z")
  m = Map.set(&2, String, m, "steps.0.completed_at", "2026-01-01T00:00:08Z")
  m = Map.set(&2, String, m, "steps.1.name", "Run scripts/check.sh")
  m = Map.set(&2, String, m, "steps.1.started_at", "2026-01-01T00:00:08Z")
  m = Map.set(&2, String, m, "steps.1.completed_at", "2026-01-01T00:00:09Z")
  m

# a job log the size of a real one: Base's String.split overflowed on these
def filler(n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      "2026-01-01T00:00:08.6000000Z line\n" ++ filler(p)

def section(+src: Map<&2, String>, +text: String, position: U32) -> String:
  Maybe.default(&2, String, Runlogs.cut.section(text, Runlogs.steps.of(src, "steps", ""), position), "no section")

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
    expect("Gitea timing uses parsed offsets and includes final second", Maybe.default(&2, String, Runlogs.window(body(), "2026-01-01T00:00:00-03:00", "2026-01-01T00:00:01-03:00"), "missing"), "2026-01-01T03:00:00.0000000Z ##[group]a command unrelated to the step name\n2026-01-01T03:00:01.9999999Z last selected line\n")
    expect("missing timing does not return entire log", Maybe.default(&2, String, Runlogs.window(body(), "", ""), "missing"), "missing")
    expect("invalid interval", Maybe.default(&2, String, Runlogs.window(body(), "2026-01-01T00:00:02Z", "2026-01-01T00:00:01Z"), "missing"), "missing")
    +one : List<&2, Map<&2, String>> = [Map.new(&2, String)]
    expect("no failed job is not a missing step", Bool.show(Runs.logs.no.step(Nil{}, "Test", 0)), "False")
    expect("a selected job without the step is", Bool.show(Runs.logs.no.step(one, "Test", 0)), "True")
    expect("a matched step is not missing", Bool.show(Runs.logs.no.step(one, "Test", 1)), "False")
    expect("no --step is never missing", Bool.show(Runs.logs.no.step(one, "", 0)), "False")
    expect("a group line opens a step", Bool.show(Runlogs.group.line("2026-01-01T00:00:02.0000000Z ##[group]Run ls")), "True")
    expect("content is not a group line", Bool.show(Runlogs.group.line("2026-01-01T00:00:02.0000000Z see ##[group]Run ls")), "False")
    expect("group text", Runlogs.group.text("2026-01-01T00:00:02.0000000Z ##[group]Run npm ci"), "npm ci")
    expect("the runner closes the run steps", Bool.show(Runlogs.post.line("2026-01-01T00:00:06.0000000Z Post job cleanup.")), "True")
    expect("content is not the post line", Bool.show(Runlogs.post.line("2026-01-01T00:00:06.0000000Z [command]echo Post job cleanup.")), "False")
    expect("Set up job is the runner's", Bool.show(Runlogs.runner.step("Set up job")), "True")
    expect("Complete job is the runner's", Bool.show(Runlogs.runner.step("Complete job")), "True")
    expect("a post step is the runner's", Bool.show(Runlogs.runner.step("Post Run actions/checkout@v4")), "True")
    expect("a run step is the job's", Bool.show(Runlogs.runner.step("Run npm ci")), "False")
    expect("only the steps that ran can own a section", Nat.show(List.length(&2, Runlogs.Step, Runlogs.waiting.of(Runlogs.steps.of(frames(), "steps", "")))), "4")
    expect("a section runs from its group line to the next step's", section(frames(), frames.log(), 1), "2026-01-01T00:00:02.0000000Z ##[group]Run actions/checkout@v4\n2026-01-01T00:00:02.1000000Z with:\n2026-01-01T00:00:02.2000000Z ##[endgroup]\n2026-01-01T00:00:02.3000000Z checked out")
    expect("a composite action's inner group stays in the step before it", section(frames(), frames.log(), 2), "2026-01-01T00:00:03.0000000Z ##[group]Run npm install\n2026-01-01T00:00:03.1000000Z ##[endgroup]\n2026-01-01T00:00:03.2000000Z ##[group]Run setup-uv@v1\n2026-01-01T00:00:03.3000000Z ##[endgroup]\n2026-01-01T00:00:03.4000000Z installed")
    expect("the last run step ends where the post steps begin", section(frames(), frames.log(), 4), "2026-01-01T00:00:05.0000000Z ##[group]Run scripts/check.sh\n2026-01-01T00:00:05.1000000Z ##[endgroup]\n2026-01-01T00:00:05.2000000Z ok")
    expect("a step the runner gave no group has no section", section(frames(), frames.log(), 3), "no section")
    expect("a skipped step has no section", section(frames(), frames.log(), 5), "no section")
    expect("a runner step has no section", section(frames(), frames.log(), 0), "no section")
    expect("a step outside the job has no section", section(frames(), frames.log(), 9), "no section")
    expect("the group text tells two steps with one second between them apart", section(pair(), pair.log(), 0), "2026-01-01T00:00:08.0000000Z ##[group]Run actions/cache@v4\n2026-01-01T00:00:08.1000000Z ##[endgroup]\n2026-01-01T00:00:08.2000000Z cache restored")
    expect("and the later step keeps its own group", section(pair(), pair.log(), 1), "2026-01-01T00:00:08.3000000Z ##[group]Run scripts/check.sh\n2026-01-01T00:00:08.4000000Z ##[endgroup]\n2026-01-01T00:00:08.5000000Z ok")
    expect("a log of thousands of lines splits", Nat.show(List.length(&2, String, Runlogs.split.lines(filler(3000n)))), "3001")
    expect("and a step is cut out of it", section(pair(), pair.log() ++ filler(3000n), 1), "2026-01-01T00:00:08.3000000Z ##[group]Run scripts/check.sh\n2026-01-01T00:00:08.4000000Z ##[endgroup]\n2026-01-01T00:00:08.5000000Z ok")
