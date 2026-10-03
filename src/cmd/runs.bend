# cha runs: list, view, logs, watch, dispatch, rerun, cancel.
import Base
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli
import ../url.bend as Url
import ../runlogs.bend as Runlogs
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time
import 0x4eed9d7ac6ece61523d747a9d804e4f0/int.bend as Int

# Reading a flat object
# ----------------------

# field k of an object flattened under prefix; "" when missing. prefix "" is the root.
def g(+src: Map<&2, String>, +prefix: String, +k: String) -> String:
  Api.f(src, Api.key(prefix, k))

# the same field as the forge sent it, for the defs that build a row. A row holds what
# the forge sent, so a command prints a field through g (clean) and passes it to --json
# through Api.raw.f (exact). Reading something to print it goes through g, never g.raw.
def g.raw(+src: Map<&2, String>, +prefix: String, +k: String) -> String:
  Api.raw.f(src, Api.key(prefix, k))

# Shapes
# ------
# Forgejo serves its own Actions schema. Its runs name the commit in commit_sha
# where Gitea and GitHub name it head_sha, and its jobs carry a task_id, so key
# presence tells the schemas apart even when a value is empty.

def has.got(r: Map<&2, String> & Bool) -> Bool:
  (m, ok) = r
  ok

def key.has(+src: Map<&2, String>, +k: String) -> Bool:
  has.got(Map.has(&2, String, src, k))

def fj.run(+src: Map<&2, String>, +prefix: String) -> Bool:
  key.has(src, Api.key(prefix, "commit_sha"))

def fj.job(+src: Map<&2, String>, +prefix: String) -> Bool:
  key.has(src, Api.key(prefix, "task_id"))

# Forgejo's open statuses: a blocked run waits for approval, it has not run;
# every other value it reports is a conclusion
def live.status(+status: String) -> Bool:
  String.eq(status, "waiting") || String.eq(status, "blocked") || String.eq(status, "running") || String.eq(status, "unknown") || String.is_empty(status)

def fj.status.of(+status: String, open: Bool) -> String:
  match open:
    case True{}:
      status
    case False{}:
      "completed"

def fj.conclusion.of(+status: String, open: Bool) -> String:
  match open:
    case True{}:
      ""
    case False{}:
      status

# Forgejo carries one status field where Gitea and GitHub carry a status and a
# conclusion: map it onto the pair the rest of cha reads.
def status.of(+src: Map<&2, String>, +prefix: String, fj: Bool) -> String:
  match fj:
    case True{}:
      fj.status.of(g.raw(src, prefix, "status"), live.status(g.raw(src, prefix, "status")))
    case False{}:
      g.raw(src, prefix, "status")

def conclusion.of(+src: Map<&2, String>, +prefix: String, fj: Bool) -> String:
  match fj:
    case True{}:
      fj.conclusion.of(g.raw(src, prefix, "status"), live.status(g.raw(src, prefix, "status")))
    case False{}:
      g.raw(src, prefix, "conclusion")

# Forgejo writes the epoch when a run never got a start
def zero.instant(+m: Maybe<&2, Time.Instant>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{i}:
      Int.I64.is_zero(Time.Duration.to_ms(Time.Instant.since_epoch(i)))

# States
# ------

# the labels meaning a run or job did not succeed
def failed.labels(+l: String) -> Bool:
  String.eq(l, "failure") || String.eq(l, "failed") || String.eq(l, "error") || String.eq(l, "cancelled") || String.eq(l, "timed_out")

# what to show: the conclusion once it is done, the status before that
def state.of(+status: String, +conclusion: String, done: Bool) -> String:
  match done:
    case True{}:
      Ctx.or(conclusion, status)
    case False{}:
      status

def state(+src: Map<&2, String>, +prefix: String) -> String:
  state.of(g.raw(src, prefix, "status"), g.raw(src, prefix, "conclusion"), String.eq(g.raw(src, prefix, "status"), "completed"))

# Age
# ---

def secs.of(+now: Time.Instant, +then: Time.Instant, neg: Bool) -> U32:
  match neg:
    case True{}:
      0
    case False{}:
      (Int.I64.to_u32(Time.Duration.to_ms(Time.Instant.since(now, then))) / 1000 : U32)

def secs.between(+now: Time.Instant, +then: Time.Instant) -> U32:
  secs.of(now, then, Int.I64.is_neg(Time.Duration.to_ms(Time.Instant.since(now, then))))

def age.unit(n: U32, u: String) -> String:
  U32.show(n) ++ u ++ " ago"

def age.bucket(+s: U32, mins: Bool, hours: Bool, days: Bool) -> String:
  match mins hours days:
    case True{} _ _:
      age.unit(s, "s")
    case False{} True{} _:
      age.unit((s / 60 : U32), "m")
    case False{} False{} True{}:
      age.unit((s / 3600 : U32), "h")
    case False{} False{} False{}:
      age.unit((s / 86400 : U32), "d")

def age.of(+s: U32) -> String:
  age.bucket(s, U32.is_lt((s / 60 : U32), 1), U32.is_lt((s / 3600 : U32), 1), U32.is_lt((s / 86400 : U32), 1))

def age.between(+now: Time.Instant, +then: Time.Instant) -> String:
  age.of(secs.between(now, then))

# the age text of a run whose start timestamp is m, "" when m has no timestamp
def age.of.parse(m: Maybe<&2, Time.Instant>, +now: Time.Instant) -> String:
  match m:
    case None{}:
      ""
    case Some{then}:
      age.between(now, then)

# Runs
# ----

def forge.of(r: Ctx.Repo) -> Ctx.Forge:
  match r:
    case Ctx.Repo{f, h, o, n}:
      f

def param.q(+pre: String, +v: String) -> String:
  Ctx.or.if(pre ++ Url.encode(v), "", String.is_empty(v))

def runs.rest(+forge: Ctx.Forge, +branch: String, +status: String, +limit: String) -> String:
  match forge:
    case Ctx.Gitea{}:
      "&limit=" ++ limit ++ param.q("&branch=", branch) ++ param.q("&status=", status)
    case Ctx.GitHub{}:
      "&per_page=" ++ limit ++ param.q("&branch=", branch) ++ param.q("&status=", status)

def runs.at(+rest: String, +page: U32) -> String:
  "actions/runs?page=" ++ U32.show(page) ++ rest

# the list endpoint of a forge's action runs, newest first. Gitea reads limit only
# when a page is asked for, so page=1 is always part of the query.
def runs.url(+forge: Ctx.Forge, +branch: String, +status: String, +limit: String) -> String:
  runs.at(runs.rest(forge, branch, status, limit), 1)

def short.if(+s: String, cut: Bool) -> String:
  match cut:
    case True{}:
      String.take(s, 7n)
    case False{}:
      s

# the first seven characters of a sha
def short.sha(+s: String) -> String:
  short.if(s, Nat.is_gt(String.length(s), 7n))

# Forgejo writes the epoch where a run has no timestamp
def time.nonzero(+s: String) -> String:
  Ctx.or.if(s, "", zero.instant(Time.rfc3339.parse(s)))

# when a run started: Gitea says started_at, Forgejo started, GitHub
# run_started_at then created_at
def started.at(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge) -> String:
  match forge:
    case Ctx.Gitea{}:
      time.nonzero(Ctx.or(g.raw(src, prefix, "started_at"), g.raw(src, prefix, "started")))
    case Ctx.GitHub{}:
      Ctx.or(g.raw(src, prefix, "run_started_at"), g.raw(src, prefix, "created_at"))

# the workflow's name: Gitea and Forgejo name the file, GitHub names the
# workflow
def wf.of(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge) -> String:
  match forge:
    case Ctx.Gitea{}:
      Ctx.first(String.split(Ctx.or(g.raw(src, prefix, "path"), g.raw(src, prefix, "workflow_id")), '@'))
    case Ctx.GitHub{}:
      g.raw(src, prefix, "name")

def age.at(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge, +now: Time.Instant) -> String:
  age.of.parse(Time.rfc3339.parse(started.at(src, prefix, forge)), now)

# updated_at can change after completion; only expose a real completion timestamp
def completed.at(+src: Map<&2, String>, +prefix: String, done: Bool) -> String:
  match done:
    case True{}:
      time.nonzero(Ctx.or(g.raw(src, prefix, "completed_at"), g.raw(src, prefix, "stopped")))
    case False{}:
      ""

def elapsed.valid(+ms: Int.I64, bad: Bool) -> String:
  match bad:
    case True{}:
      ""
    case False{}:
      Int.I64.show(Int.I64.div(ms, Int.I64.from_u32(1000)))

def elapsed.of(start: Maybe<&2, Time.Instant>, end: Maybe<&2, Time.Instant>) -> String:
  match start end:
    case Some{s} Some{e}:
      +ms = Time.Duration.to_ms(Time.Instant.since(e, s))
      elapsed.valid(ms, Int.I64.is_neg(ms))
    case a b:
      ""

# elapsed seconds; absent/invalid timestamps do not imply a zero-length run.
def elapsed(+start: String, +end: String) -> String:
  elapsed.of(Time.rfc3339.parse(start), Time.rfc3339.parse(end))

# Gitea leaves head_branch empty for tags and PR refs. Keep those full refs
# recognizable instead of presenting a tag or pull request as a branch.
# Forgejo has no head_branch: its prettyref is the branch, tag or pull request
def branch.ref(+ref: String, branch: Bool) -> String:
  match branch:
    case True{}:
      String.drop(ref, 11n)
    case False{}:
      ref

def branch.of(+src: Map<&2, String>, +prefix: String) -> String:
  +ref = Ctx.or(g.raw(src, prefix, "ref"), Ctx.rest(String.split(g.raw(src, prefix, "path"), '@'), "@"))
  Ctx.or(Ctx.or(g.raw(src, prefix, "head_branch"), g.raw(src, prefix, "prettyref")), branch.ref(ref, String.starts_with(ref, "refs/heads/")))

# one run, as the flat row every run command reads. Gitea 1.25 and GitHub share
# their field names; Forgejo's are the fallback on the right of every or.
def run.row(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge, +now: Time.Instant) -> Map<&2, String>:
  +fj : Bool = fj.run(src, prefix)
  +status : String = status.of(src, prefix, fj)
  +conclusion : String = conclusion.of(src, prefix, fj)
  +done : Bool = String.eq(status, "completed")
  +started : String = started.at(src, prefix, forge)
  +finished : String = completed.at(src, prefix, done)
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "id", g.raw(src, prefix, "id"))
  m = Map.set(&2, String, m, "kind", "run")
  m = Map.set(&2, String, m, "path", Ctx.or(g.raw(src, prefix, "path"), g.raw(src, prefix, "workflow_id")))
  m = Map.set(&2, String, m, "name", Ctx.or(g.raw(src, prefix, "name"), g.raw(src, prefix, "workflow_id")))
  m = Map.set(&2, String, m, "run_number", Ctx.or(g.raw(src, prefix, "run_number"), g.raw(src, prefix, "index_in_repo")))
  m = Map.set(&2, String, m, "status", status)
  m = Map.set(&2, String, m, "conclusion", conclusion)
  m = Map.set(&2, String, m, "state", state.of(status, conclusion, done))
  m = Map.set(&2, String, m, "workflow", wf.of(src, prefix, forge))
  m = Map.set(&2, String, m, "branch", branch.of(src, prefix))
  m = Map.set(&2, String, m, "sha", Ctx.or(g.raw(src, prefix, "head_sha"), g.raw(src, prefix, "commit_sha")))
  m = Map.set(&2, String, m, "title", Ctx.or(Ctx.or(g.raw(src, prefix, "display_title"), g.raw(src, prefix, "title")), wf.of(src, prefix, forge)))
  m = Map.set(&2, String, m, "event", g.raw(src, prefix, "event"))
  m = Map.set(&2, String, m, "started_at", started)
  m = Map.set(&2, String, m, "updated_at", Ctx.or(g.raw(src, prefix, "updated_at"), g.raw(src, prefix, "updated")))
  m = Map.set(&2, String, m, "completed_at", finished)
  m = Map.set(&2, String, m, "duration", elapsed(started, finished))
  m = Map.set(&2, String, m, "age", age.at(src, prefix, forge, now))
  m = Map.set(&2, String, m, "html_url", g.raw(src, prefix, "html_url"))
  m

def run.line(+on: Bool, +row: Map<&2, String>) -> String:
  Ui.bold(on, Ui.fg(on, Ui.aqua(), "#" ++ Api.f(row, "id"))) ++ "  " ++
  Ui.state(on, Api.f(row, "state")) ++ "  " ++
  Api.f(row, "workflow") ++ "  " ++
  Api.f(row, "branch") ++ "  " ++
  Ui.dim(on, short.sha(Api.f(row, "sha"))) ++ "  " ++
  Api.f(row, "title") ++ "  " ++
  Ui.dim(on, Api.f(row, "age"))

def run.lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, rest}:
      run.line(on, x) ++ "\n" ++ run.lines(on, rest)

def run.fields() -> List<&2, String>:
  ["kind", "id", "run_number", "state", "status", "conclusion", "workflow", "branch", "sha", "title", "event", "age", "started_at", "updated_at", "completed_at", "duration", "html_url"]

# the runs of a list body, as rows
def prefix.of(+root: String, i: U32) -> String:
  root ++ "." ++ U32.show(i)

def rows.go(n: Nat, +i: U32, +src: Map<&2, String>, +root: String, +forge: Ctx.Forge, +now: Time.Instant) -> List<&2, Map<&2, String>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      run.row(src, prefix.of(root, i), forge, now) <> rows.go(p, (i + 1 : U32), src, root, forge, now)

def rows.of(+src: Map<&2, String>, +root: String, +forge: Ctx.Forge, +now: Time.Instant) -> List<&2, Map<&2, String>>:
  rows.go(Api.count(src, root), 0, src, root, forge, now)

# Replies
# -------

def ok.body(+env: Cli.Env, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Bytes.Bytes):
  match good:
    case True{}:
      IO.pure(Bytes.Bytes, body)
    case False{}:
      Cli.fail(Bytes.Bytes, env, Api.message(status, body))

# a reply's body, or the command fails with the forge's error
def fetch.body(+env: Cli.Env, r: Api.Reply) -> IO(Bytes.Bytes):
  match r:
    case Api.Broke{w}:
      Cli.fail(Bytes.Bytes, env, w)
    case Api.Reply{+status, next, body}:
      ok.body(env, status, body, Api.ok(status))

def check.ok.if(+env: Cli.Env, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

# a reply that carries nothing worth printing: fail on anything but 2xx
def check.ok(+env: Cli.Env, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      check.ok.if(env, status, body, Api.ok(status))

# Jobs
# ----

# Run, job and step durations share the same timestamp semantics.
def job.duration(+start: String, +end: String) -> String:
  elapsed(start, end)

def job.duration.text(+seconds: String) -> String:
  Ctx.or.if(seconds ++ "s", "", String.is_empty(seconds))

# Copy each step to the normalized job row, retaining the flat array convention.
def step.copy(+src: Map<&2, String>, +source: String, +target: String, m: Map<&2, String>) -> Map<&2, String>:
  m = Map.set(&2, String, m, Api.key(target, "number"), g.raw(src, source, "number"))
  m = Map.set(&2, String, m, Api.key(target, "name"), g.raw(src, source, "name"))
  m = Map.set(&2, String, m, Api.key(target, "status"), g.raw(src, source, "status"))
  m = Map.set(&2, String, m, Api.key(target, "conclusion"), g.raw(src, source, "conclusion"))
  m = Map.set(&2, String, m, Api.key(target, "state"), state(src, source))
  m = Map.set(&2, String, m, Api.key(target, "started_at"), g.raw(src, source, "started_at"))
  m = Map.set(&2, String, m, Api.key(target, "completed_at"), g.raw(src, source, "completed_at"))
  Map.set(&2, String, m, Api.key(target, "duration"), job.duration(g.raw(src, source, "started_at"), g.raw(src, source, "completed_at")))

def steps.copy(n: Nat, +i: U32, +src: Map<&2, String>, +prefix: String, m: Map<&2, String>) -> Map<&2, String>:
  match n:
    case 0n:
      m
    case 1n+p:
      +target = prefix.of("steps", i)
      steps.copy(p, (i + 1 : U32), src, prefix, step.copy(src, Api.key(prefix, target), target, m))

def job.row(+src: Map<&2, String>, +prefix: String) -> Map<&2, String>:
  +fj : Bool = fj.job(src, prefix)
  +status : String = status.of(src, prefix, fj)
  +conclusion : String = conclusion.of(src, prefix, fj)
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "kind", "job")
  m = Map.set(&2, String, m, "id", g.raw(src, prefix, "id"))
  m = Map.set(&2, String, m, "name", g.raw(src, prefix, "name"))
  m = Map.set(&2, String, m, "status", status)
  m = Map.set(&2, String, m, "conclusion", conclusion)
  m = Map.set(&2, String, m, "state", state.of(status, conclusion, String.eq(status, "completed")))
  m = Map.set(&2, String, m, "runner_name", g.raw(src, prefix, "runner_name"))
  m = Map.set(&2, String, m, "started_at", g.raw(src, prefix, "started_at"))
  m = Map.set(&2, String, m, "completed_at", g.raw(src, prefix, "completed_at"))
  m = Map.set(&2, String, m, "duration", job.duration(g.raw(src, prefix, "started_at"), g.raw(src, prefix, "completed_at")))
  m = Map.set(&2, String, m, "html_url", g.raw(src, prefix, "html_url"))
  +count = Api.count(src, Api.key(prefix, "steps"))
  m = Map.set(&2, String, m, "steps.#", Nat.show(count))
  steps.copy(count, 0, src, prefix, m)

# Gitea and GitHub wrap a job list in "jobs"; Forgejo answers a bare array,
# whose rows sit at the root of the flattened body.
def jobs.wrapped(+src: Map<&2, String>) -> Bool:
  Bool.not(String.is_empty(Api.f(src, "jobs.#")))

def jobs.root.of(+src: Map<&2, String>, wrapped: Bool) -> String:
  match wrapped:
    case True{}:
      "jobs"
    case False{}:
      ""

# jobs.# when the list is wrapped, # when it is a bare array at the root
def jobs.count(+src: Map<&2, String>, +root: String) -> Nat:
  Api.count.of(U32.read(g(src, root, "#")))

def jrows.go(n: Nat, +i: U32, +src: Map<&2, String>, +root: String) -> List<&2, Map<&2, String>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      job.row(src, Api.key(root, U32.show(i))) <> jrows.go(p, (i + 1 : U32), src, root)

def jrows.of(+src: Map<&2, String>) -> List<&2, Map<&2, String>>:
  +root = jobs.root.of(src, jobs.wrapped(src))
  jrows.go(jobs.count(src, root), 0, src, root)

def step.text(+on: Bool, +label: String, +name: String, +seconds: String, skipped: Bool) -> String:
  match skipped:
    case True{}:
      Ui.dim(on, "    " ++ label ++ "  " ++ name ++ "  " ++ job.duration.text(seconds))
    case False{}:
      "    " ++ Ui.state(on, label) ++ "  " ++ name ++ "  " ++ job.duration.text(seconds)

def steps.lines(n: Nat, +i: U32, +on: Bool, +row: Map<&2, String>) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      +prefix = prefix.of("steps", i)
      step.text(on, g(row, prefix, "state"), g(row, prefix, "name"), g(row, prefix, "duration"), String.eq(g(row, prefix, "state"), "skipped")) ++ "\n" ++ steps.lines(p, (i + 1 : U32), on, row)

def job.line(+on: Bool, +row: Map<&2, String>) -> String:
  "  " ++ Api.f(row, "name") ++ "  " ++ Ui.state(on, Api.f(row, "state")) ++ "  " ++ Ui.dim(on, "#" ++ Api.f(row, "id")) ++ "  " ++ Api.f(row, "runner_name") ++ "  " ++ job.duration.text(Api.f(row, "duration")) ++ "\n" ++
  steps.lines(Api.count(row, "steps"), 0, on, row)

def job.lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, rest}:
      job.line(on, x) ++ job.lines(on, rest)

def job.fields() -> List<&2, String>:
  ["kind", "id", "name", "state", "status", "conclusion", "runner_name", "started_at", "completed_at", "duration", "html_url", "steps.#"]

def steps.fields(n: Nat, +i: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +prefix = prefix.of("steps", i)
      List.append(&2, String, [Api.key(prefix, "number"), Api.key(prefix, "name"), Api.key(prefix, "state"), Api.key(prefix, "status"), Api.key(prefix, "conclusion"), Api.key(prefix, "started_at"), Api.key(prefix, "completed_at"), Api.key(prefix, "duration")], steps.fields(p, (i + 1 : U32)))

def job.json.fields(+row: Map<&2, String>) -> List<&2, String>:
  List.append(&2, String, job.fields(), steps.fields(Api.count(row, "steps"), 0))

# The original id-only predicate remains useful to callers without a job name.
def want.job(+id: String, +conclusion: String, +job: String, only_failed: Bool) -> Bool:
  Bool.and(Bool.or(String.is_empty(job), String.eq(id, job)), Bool.or(Bool.not(only_failed), failed.labels(conclusion)))

# Names match exactly apart from case. A partial matrix label must not silently
# select another job. --failed intersects the name/id selection.
def want.job.named(+id: String, +name: String, +conclusion: String, +job: String, only_failed: Bool) -> Bool:
  (String.is_empty(job) || String.eq(id, job) || Runlogs.same(name, job)) && (Bool.not(only_failed) || failed.labels(conclusion))

def keep.if(+row: Map<&2, String>, rest: List<&2, Map<&2, String>>, keep: Bool) -> List<&2, Map<&2, String>>:
  match keep:
    case True{}:
      row <> rest
    case False{}:
      rest

def keep.job(+row: Map<&2, String>, rest: List<&2, Map<&2, String>>, +job: String, only_failed: Bool) -> List<&2, Map<&2, String>>:
  keep.if(row, rest, want.job.named(Api.f(row, "id"), Api.f(row, "name"), Api.f(row, "conclusion"), job, only_failed))

def keep.go(n: Nat, +i: U32, +src: Map<&2, String>, +job: String, +only_failed: Bool) -> List<&2, Map<&2, String>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      keep.job(job.row(src, prefix.of("jobs", i)), keep.go(p, (i + 1 : U32), src, job, only_failed), job, only_failed)

def keep.rows(xs: List<&2, Map<&2, String>>, +job: String, +only_failed: Bool) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, rest}:
      keep.job(x, keep.rows(rest, job, only_failed), job, only_failed)

# view
# ----

def view.json.jobs(xs: List<&2, Map<&2, String>>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      Cli.json.row(x, job.json.fields(x)) <> view.json.jobs(rest)

def view.json.text(+row: Map<&2, String>, jobs: List<&2, Map<&2, String>>) -> String:
  "[" ++ String.join(Cli.json.row(row, run.fields()) <> view.json.jobs(jobs), ",\n") ++ "]"

def view.json(+row: Map<&2, String>, +jobs: List<&2, Map<&2, String>>) -> IO(Unit):
  IO.print(view.json.text(row, jobs))

def view.text(+on: Bool, +row: Map<&2, String>, +jobs: List<&2, Map<&2, String>>) -> String:
  "#" ++ Api.f(row, "id") ++ "  " ++ Ui.state(on, Api.f(row, "state")) ++ "  " ++ Api.f(row, "workflow") ++ "\n" ++
  Api.f(row, "title") ++ "\n" ++
  Ui.dim(on, Api.f(row, "branch") ++ "  " ++ short.sha(Api.f(row, "sha")) ++ "  " ++ Api.f(row, "event") ++ "  " ++ Api.f(row, "age")) ++ "\n" ++
  Api.f(row, "html_url") ++ "\n" ++
  "\n" ++ job.lines(on, jobs)

def view.print(+env: Cli.Env, +row: Map<&2, String>, +jobs: List<&2, Map<&2, String>>) -> IO(Unit):
  match env:
    case Cli.Env{r, t, on, json, a}:
      match json:
        case Cli.Off{}:
          IO.write(view.text(on, row, jobs))
        case j:
          do IO<Unit>:
            Cli.json.whole(on, j, "runs view")
            view.json(row, jobs)

# Arguments
# ---------

def require.if(+env: Cli.Env, +v: String, +what: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      Cli.fail(String, env, "runs: missing " ++ what)
    case False{}:
      IO.pure(String, v)

def require.str(+env: Cli.Env, +v: String, +what: String) -> IO(String):
  require.if(env, v, what, String.is_empty(v))

def require.at(+env: Cli.Env, n: Nat, +what: String) -> IO(String):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      require.str(env, Cli.arg(args, n), what)

# View and log selection need every job, including jobs beyond the first page.
type JobPages is Type:
  FetchJobs{url: String, acc: List<&2, Map<&2, String>>}
  ReadJobs{reply: Api.Reply, acc: List<&2, Map<&2, String>>}
  NextJobs{last: Bool, url: String, acc: List<&2, Map<&2, String>>}

# Gitea 1.25 answers Actions lists with total_count but no Link header. Until the
# rows seen reach total_count, ask for the next page ourselves.
def page.next(+next: String, +fallback: String, +seen: Nat, +total: String, empty: Bool) -> String:
  Ctx.or(next, Ctx.or.if(fallback, "", empty || Bool.not(Nat.is_gt(Api.count.of(U32.read(total)), seen))))

def jobs.at(+id: String, +page: U32) -> String:
  "actions/runs/" ++ Url.encode(id) ++ "/jobs?page=" ++ U32.show(page) ++ "&per_page=100&limit=100"

def jobs.page(+next: String, +fallback: String, body: Bytes.Bytes, acc: List<&2, Map<&2, String>>) -> JobPages:
  +src = Api.obj(body)
  +rows = jrows.of(src)
  +got = List.append(&2, Map<&2, String>, acc, rows)
  +url = page.next(next, fallback, List.length(&2, Map<&2, String>, got), Api.f(src, "total_count"), Nat.is_eq(List.length(&2, Map<&2, String>, rows), 0n))
  NextJobs{String.is_empty(url), url, got}

def jobs.walk(fuel: Nat, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +id: String, +page: U32, st: JobPages) -> IO(List<&2, Map<&2, String>>):
  match fuel st:
    case 0n s:
      Cli.fail(List<&2, Map<&2, String>>, env, "runs: too many job pages")
    case 1n+p FetchJobs{url, acc}:
      do IO<List<&2, Map<&2, String>>>:
        r : Api.Reply <- Api.get(repo, tok, url)
        jobs.walk(p, env, repo, tok, id, page, ReadJobs{r, acc})
    case 1n+p ReadJobs{Api.Broke{w}, acc}:
      Cli.fail(List<&2, Map<&2, String>>, env, w)
    case 1n+p ReadJobs{Api.Reply{+status, +next, body}, acc}:
      do IO<List<&2, Map<&2, String>>>:
        b : Bytes.Bytes <- ok.body(env, status, body, Api.ok(status))
        jobs.walk(p, env, repo, tok, id, page, jobs.page(next, Api.path(repo, jobs.at(id, (page + 1 : U32))), b, acc))
    case 1n+p NextJobs{True{}, url, acc}:
      IO.pure(List<&2, Map<&2, String>>, acc)
    case 1n+p NextJobs{False{}, url, acc}:
      jobs.walk(p, env, repo, tok, id, (page + 1 : U32), FetchJobs{url, acc})

def jobs.fetch(+env: Cli.Env, +id: String) -> IO(List<&2, Map<&2, String>>):
  match env:
    case Cli.Env{+repo, +tok, on, json, a}:
      jobs.walk(301n, env, repo, tok, id, 1, FetchJobs{Api.path(repo, jobs.at(id, 1)), Nil{}})

def view(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +id : String <- require.at(env, 1n, "run id")
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "actions/runs/" ++ id))
        body : Bytes.Bytes <- fetch.body(env, r)
        now : Time.Instant <- Time.now()
        +src : Map<&2, String> = Api.obj(body)
        +row : Map<&2, String> = run.row(src, "", forge.of(repo), now)
        jobs : List<&2, Map<&2, String>> <- jobs.fetch(env, id)
        view.print(env, row, jobs)

# logs
# ----

# A summary lets unfinished jobs report their status without stopping completed
# jobs later in the response from printing. Incomplete retrieval exits 1 at end.
type LogSummary is Data:
  LogSummary{matched: U32, printed: U32, incomplete: Bool}

def logs.sum(a: LogSummary, b: LogSummary) -> LogSummary:
  match a b:
    case LogSummary{am, ap, ai} LogSummary{bm, bp, bi}:
      LogSummary{(am + bm : U32), (ap + bp : U32), ai || bi}

def log.nl(+text: String) -> String:
  Ctx.or.if(text ++ "\n", text, String.ends_with(text, "\n"))

def logs.head(+on: Bool, +row: Map<&2, String>) -> String:
  Ui.bold(on, Api.f(row, "name")) ++ "  " ++ Ui.state(on, Api.f(row, "state")) ++ "  " ++ Ui.dim(on, "#" ++ Api.f(row, "id")) ++ "\n"

def logs.pending(forge: Ctx.Forge, +status: String) -> Bool:
  match forge:
    case Ctx.GitHub{}:
      Bool.not(String.eq(status, "completed"))
    case Ctx.Gitea{}:
      False{}

def logs.pending.message(+id: String, +name: String, +status: String) -> String:
  "runs logs: job " ++ name ++ " is " ++ status ++ "; logs appear when it finishes; try cha runs watch " ++ id

def logs.get(+env: Cli.Env, +row: Map<&2, String>, +suffix: String) -> IO(Bytes.Bytes):
  match env:
    case Cli.Env{+repo, tok, on, json, a}:
      do IO<Bytes.Bytes>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "actions/jobs/" ++ Api.f(row, "id") ++ suffix))
        fetch.body(env, r)

def logs.whole(+env: Cli.Env, +row: Map<&2, String>) -> IO(LogSummary):
  match env:
    case Cli.Env{repo, tok, on, json, a}:
      do IO<LogSummary>:
        b : Bytes.Bytes <- logs.get(env, row, "/logs")
        IO.write(logs.head(on, row) ++ log.nl(Runlogs.strip.bom(Api.text(b))) ++ "\n")
        return LogSummary{1, 1, False{}}

def logs.step.show(+env: Cli.Env, +row: Map<&2, String>, +name: String, +text: String) -> IO(LogSummary):
  match env:
    case Cli.Env{repo, tok, on, json, a}:
      do IO<LogSummary>:
        IO.write(logs.head(on, row) ++ "  step: " ++ name ++ "\n" ++ log.nl(text) ++ "\n")
        return LogSummary{1, 1, False{}}

def logs.step.missing(+env: Cli.Env, +row: Map<&2, String>, +name: String, why: String) -> IO(LogSummary):
  match env:
    case Cli.Env{repo, tok, on, json, a}:
      do IO<LogSummary>:
        Ui.error(on, "runs logs: no " ++ why ++ " for step " ++ name ++ " in job " ++ Api.f(row, "name") ++ "; omit --step to read the job log")
        return LogSummary{1, 0, True{}}

def logs.step.text(+env: Cli.Env, +row: Map<&2, String>, +name: String, text: Maybe<&2, String>) -> IO(LogSummary):
  match text:
    case Some{+t}:
      logs.step.show(env, row, name, t)
    case None{}:
      logs.step.missing(env, row, name, "log section and no step times")

# the section the log opened for the step, or its step times when the runner wrote
# no group line for it
def logs.step.section(+env: Cli.Env, +row: Map<&2, String>, +name: String, got: Maybe<&2, String>, fallback: Maybe<&2, String>) -> IO(LogSummary):
  logs.step.text(env, row, name, Maybe.or(&2, String, got, fallback))

def logs.step.gitea(+env: Cli.Env, +row: Map<&2, String>, +name: String, body: Maybe<&2, String>) -> IO(LogSummary):
  match env body:
    case Cli.Env{repo, tok, on, json, a} None{}:
      logs.step.missing(env, row, name, "usable timing metadata")
    case Cli.Env{repo, tok, on, json, a} Some{text}:
      do IO<LogSummary>:
        Ui.info(on, "runs logs: Gitea step times have one-second precision; boundary lines can overlap adjacent steps")
        logs.step.show(env, row, name, text)

# GitHub has no per-step log endpoint, so the step's section is cut out of the job log.
# A step the runner wrote no group line for still has its step times to fall back on.
def logs.step.github.at(+env: Cli.Env, +row: Map<&2, String>, +name: String, +position: U32, +started: String, +completed: String, +text: String) -> IO(LogSummary):
  logs.step.section(env, row, name, Runlogs.cut.section(text, Runlogs.steps.of(row, "steps", ""), position), Runlogs.window(text, started, completed))

def logs.step.github(+env: Cli.Env, +row: Map<&2, String>, s: Runlogs.Step) -> IO(LogSummary):
  match env s:
    case Cli.Env{repo, tok, on, json, a} Runlogs.Step{position, +name, status, conclusion, +started, +completed}:
      do IO<LogSummary>:
        b : Bytes.Bytes <- logs.get(env, row, "/logs")
        logs.step.github.at(env, row, name, position, started, completed, Api.text(b))

def logs.step.fetch(+env: Cli.Env, +row: Map<&2, String>, s: Runlogs.Step, forge: Ctx.Forge) -> IO(LogSummary):
  match env s forge:
    case Cli.Env{repo, tok, on, json, a} Runlogs.Step{position, +name, status, conclusion, started, completed} Ctx.GitHub{}:
      logs.step.github(env, row, s)
    case Cli.Env{repo, tok, on, json, a} Runlogs.Step{position, +name, status, conclusion, +started, +completed} Ctx.Gitea{}:
      do IO<LogSummary>:
        b : Bytes.Bytes <- logs.get(env, row, "/logs")
        logs.step.gitea(env, row, name, Runlogs.window(Api.text(b), started, completed))

def logs.step.skip(+env: Cli.Env, +row: Map<&2, String>, +s: Runlogs.Step, forge: Ctx.Forge, skipped: Bool) -> IO(LogSummary):
  match env s skipped:
    case Cli.Env{repo, tok, on, json, a} Runlogs.Step{position, name, status, conclusion, started, completed} True{}:
      do IO<LogSummary>:
        Ui.info(on, "runs logs: step " ++ name ++ " was skipped and has no logs")
        return LogSummary{1, 0, False{}}
    case Cli.Env{repo, tok, on, json, a} Runlogs.Step{position, name, status, conclusion, started, completed} False{}:
      logs.step.fetch(env, row, s, forge)

def logs.step(+env: Cli.Env, +row: Map<&2, String>, +s: Runlogs.Step, forge: Ctx.Forge) -> IO(LogSummary):
  match s:
    case Runlogs.Step{position, name, status, +conclusion, started, completed}:
      logs.step.skip(env, row, s, forge, String.eq(conclusion, "skipped"))

def logs.steps(+env: Cli.Env, +row: Map<&2, String>, xs: List<&2, Runlogs.Step>) -> IO(LogSummary):
  match env xs:
    case Cli.Env{repo, tok, on, json, a} Nil{}:
      IO.pure(LogSummary, LogSummary{0, 0, False{}})
    case Cli.Env{+repo, tok, on, json, a} Con{s, rest}:
      do IO<LogSummary>:
        a : LogSummary <- logs.step(env, row, s, forge.of(repo))
        b : LogSummary <- logs.steps(env, row, rest)
        return logs.sum(a, b)

def logs.pick.step(+env: Cli.Env, +row: Map<&2, String>, +step: String, whole: Bool) -> IO(LogSummary):
  match whole:
    case True{}:
      logs.whole(env, row)
    case False{}:
      logs.steps(env, row, Runlogs.steps.of(row, "steps", step))

# A skipped job has no log to fetch; asking for one would stop the jobs after it.
def logs.skipped(+env: Cli.Env, +row: Map<&2, String>, +step: String, skipped: Bool) -> IO(LogSummary):
  match env skipped:
    case Cli.Env{repo, tok, on, json, a} True{}:
      do IO<LogSummary>:
        Ui.info(on, "runs logs: job " ++ Api.f(row, "name") ++ " was skipped and has no logs")
        return LogSummary{1, 0, False{}}
    case Cli.Env{repo, tok, on, json, a} False{}:
      logs.pick.step(env, row, step, String.is_empty(step))

def logs.one(+env: Cli.Env, +id: String, +row: Map<&2, String>, +step: String, pending: Bool) -> IO(LogSummary):
  match env pending:
    case Cli.Env{repo, tok, on, json, a} True{}:
      do IO<LogSummary>:
        Ui.info(on, logs.pending.message(id, Api.f(row, "name"), Api.f(row, "status")))
        return LogSummary{0, 0, True{}}
    case Cli.Env{repo, tok, on, json, a} False{}:
      logs.skipped(env, row, step, String.eq(Api.f(row, "conclusion"), "skipped"))

def logs.jobs(+env: Cli.Env, +id: String, xs: List<&2, Map<&2, String>>, +step: String) -> IO(LogSummary):
  match env xs:
    case Cli.Env{repo, tok, on, json, a} Nil{}:
      IO.pure(LogSummary, LogSummary{0, 0, False{}})
    case Cli.Env{+repo, tok, on, json, a} Con{+row, rest}:
      do IO<LogSummary>:
        a : LogSummary <- logs.one(env, id, row, step, logs.pending(forge.of(repo), Api.f(row, "status")))
        b : LogSummary <- logs.jobs(env, id, rest, step)
        return logs.sum(a, b)

def logs.miss(+xs: List<&2, Map<&2, String>>, +job: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(job)), Nat.is_eq(List.length(&2, Map<&2, String>, xs), 0n))

def logs.available.steps(xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+row, rest}:
      Api.f(row, "name") ++ ":\n" ++ Runlogs.steps.names(Runlogs.steps.of(row, "steps", "")) ++ logs.available.steps(rest)

def logs.finish.if(+env: Cli.Env, +xs: List<&2, Map<&2, String>>, +step: String, missing: Bool, incomplete: Bool) -> IO(Unit):
  match missing incomplete:
    case _ True{}:
      IO.die(Unit, 1, "")
    case True{} False{}:
      Cli.fail(Unit, env, "runs logs: no step named " ++ step ++ "; steps:\n" ++ logs.available.steps(xs))
    case False{} False{}:
      IO.pure(Unit, Unit{})

# --step matched nothing in the selected jobs. With no job selected (--failed on a
# green run) there was nothing to search, which is not a missing step.
def logs.no.step(+xs: List<&2, Map<&2, String>>, +step: String, +matched: U32) -> Bool:
  Bool.not(String.is_empty(step)) && U32.is_eq(matched, 0) && Bool.not(Nat.is_eq(List.length(&2, Map<&2, String>, xs), 0n))

def logs.finish(+env: Cli.Env, +xs: List<&2, Map<&2, String>>, +step: String, result: LogSummary) -> IO(Unit):
  match result:
    case LogSummary{matched, printed, incomplete}:
      logs.finish.if(env, xs, step, logs.no.step(xs, step, matched), incomplete)

def logs.pick.if(+env: Cli.Env, +id: String, +xs: List<&2, Map<&2, String>>, +all: List<&2, Map<&2, String>>, +job: String, +step: String, miss: Bool) -> IO(Unit):
  match miss:
    case True{}:
      Cli.fail(Unit, env, "runs logs: no job " ++ job ++ "; available jobs:\n" ++ job.lines(False{}, all))
    case False{}:
      do IO<Unit>:
        result : LogSummary <- logs.jobs(env, id, xs, step)
        logs.finish(env, xs, step, result)

def logs(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +id : String <- require.at(env, 1n, "run id")
        +job : String = Cli.flag(args, "--job", "")
        +step : String <- require.if(env, Cli.flag(args, "--step", ""), "step name", (Cli.has(args, "--step") || Cli.has(args, "--step=")) && (String.is_empty(Cli.flag(args, "--step", "")) || String.starts_with(Cli.flag(args, "--step", ""), "--")))
        +all : List<&2, Map<&2, String>> <- jobs.fetch(env, id)
        +ks : List<&2, Map<&2, String>> = keep.rows(all, job, Cli.has(args, "--failed"))
        +named : List<&2, Map<&2, String>> = keep.rows(all, job, False{})
        logs.pick.if(env, id, ks, all, job, step, logs.miss(named, job))

# watch
# -----

# a poll's outcome: still going, or finished
type Tick is Data:
  More{state: String, conclusion: String}
  End{state: String, conclusion: String}

def tick.at(+state: String, +conclusion: String, done: Bool) -> Tick:
  match done:
    case True{}:
      End{state, conclusion}
    case False{}:
      More{state, conclusion}

# The watch prints the state it reads, so unlike the row builders this reads the source
# through the clean door.
def tick.of(+src: Map<&2, String>) -> Tick:
  +status = Api.f(src, "status")
  +conclusion = Api.f(src, "conclusion")
  tick.at(state.of(status, conclusion, String.eq(status, "completed")), conclusion, String.eq(status, "completed"))

def spinner.at(g: Nat) -> String:
  match g:
    case 0n:
      "·"
    case 1n:
      "∘"
    case 2n:
      "°"
    case 3n+k:
      "˚"

def spinner(+i: U32) -> String:
  spinner.at(U32.to_nat((i % 4 : U32)))

def watch.line(+on: Bool, +id: String, +state: String, +spin: U32) -> String:
  Ui.fg(on, Ui.stop((spin % 7 : U32)), spinner(spin)) ++ "  " ++ Ui.bold(on, "#" ++ id) ++ "  " ++ Ui.state(on, state)

def watch.change(+state: String, +shown: String, changed: Bool) -> IO(Unit):
  match changed:
    case True{}:
      IO.write(state ++ "\n")
    case False{}:
      IO.pure(Unit, Unit{})

# on a terminal, redraw one line; piped, print only a state change
def watch.step(+on: Bool, +id: String, +state: String, +shown: String, +spin: U32) -> IO(Unit):
  match on:
    case True{}:
      IO.write("\r" ++ watch.line(on, id, state, spin) ++ "\u{1b}[K")
    case False{}:
      watch.change(state, shown, Bool.not(String.eq(state, shown)))

def watch.get(+env: Cli.Env, +id: String) -> IO(Api.Reply):
  match env:
    case Cli.Env{+repo, +tok, c, j, a}:
      Api.get(repo, tok, Api.path(repo, "actions/runs/" ++ id))

# the last line: leave the redraw line whole, or report the change once
def watch.end(+on: Bool, +id: String, +state: String, +shown: String, +spin: U32) -> IO(Unit):
  match on:
    case True{}:
      IO.write("\r" ++ watch.line(on, id, state, spin) ++ "\u{1b}[K\n")
    case False{}:
      watch.change(state, shown, Bool.not(String.eq(state, shown)))

def exit.if(+conclusion: String, bad: Bool) -> IO(Unit):
  match bad:
    case True{}:
      IO.die(Unit, 1, "")
    case False{}:
      IO.pure(Unit, Unit{})

# a run that ended in failure is a failed command
def watch.exit(+conclusion: String) -> IO(Unit):
  exit.if(conclusion, failed.labels(conclusion))

# one step per poll, so fuel = the number of polls left. 100000 polls at 5 s is ~6 days.
def watch.go(fuel: Nat, +env: Cli.Env, +on: Bool, +id: String, +shown: String, +spin: U32, t: Tick) -> IO(Unit):
  match fuel t:
    case 0n m:
      IO.pure(Unit, Unit{})
    case 1n+p End{+state, +conclusion}:
      do IO<Unit>:
        watch.end(on, id, state, shown, spin)
        watch.exit(conclusion)
    case 1n+p More{+state, +conclusion}:
      do IO<Unit>:
        watch.step(on, id, state, shown, spin)
        IO.sleep(5000)
        r : Api.Reply <- watch.get(env, id)
        body : Bytes.Bytes <- fetch.body(env, r)
        watch.go(p, env, on, id, state, (spin + 1 : U32), tick.of(Api.obj(body)))

def watch(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +id : String <- require.at(env, 1n, "run id")
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "actions/runs/" ++ id))
        body : Bytes.Bytes <- fetch.body(env, r)
        watch.go(100000n, env, on, id, "", 0, tick.of(Api.obj(body)))

# dispatch, rerun, cancel
# -----------------------

def input.key(kv: String) -> String:
  Ctx.first(String.split(kv, '='))

def input.val(kv: String) -> String:
  Ctx.rest(String.split(kv, '='), "=")

def input.pairs(xs: List<&2, String>) -> List<&1, Bytes.Bytes & Json.Val>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+kv, rest}:
      Con{(Json.utf8(input.key(kv)), Api.utf8(input.val(kv))), input.pairs(rest)}

def dispatch.body(+ref: String, xs: List<&2, String>) -> Json.Val:
  Json.Obj{[(Json.utf8("ref"), Api.utf8(ref)), (Json.utf8("inputs"), Json.Obj{input.pairs(xs)})]}

def inputs.go(ms: List<&2, Cli.Arg>) -> List<&2, String>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{Cli.Exact{}, Con{Cli.Plain{v}, t}}:
      v <> inputs.go(t)
    case Con{Cli.Inline{v}, t}:
      v <> inputs.go(t)
    case Con{x, t}:
      inputs.go(t)

# every --input k=v, in order
def inputs.of(args: List<&2, String>) -> List<&2, String>:
  inputs.go(Cli.mark(args, "--input"))

def repo.url(r: Ctx.Repo, +rest: String) -> String:
  match r:
    case Ctx.Repo{f, h, o, n}:
      "https://" ++ h ++ "/" ++ o ++ "/" ++ n ++ "/" ++ rest

def done.url(+env: Cli.Env, +rest: String) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, a}:
      IO.print(repo.url(repo, rest))

def dispatch.url.pick(+env: Cli.Env, +url: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      done.url(env, "actions")
    case False{}:
      IO.print(url)

# the run the dispatch just made: the newest one on that branch
def dispatch.url(+env: Cli.Env, +ref: String) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, a}:
      do IO<Unit>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, runs.url(forge.of(repo), ref, "", "1")))
        body : Bytes.Bytes <- fetch.body(env, r)
        +src : Map<&2, String> = Api.obj(body)
        dispatch.url.pick(env, g(src, "workflow_runs.0", "html_url"), String.is_empty(g(src, "workflow_runs.0", "html_url")))

def dispatch(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        wf : String <- require.at(env, 1n, "workflow file")
        +ref : String = Cli.flag(args, "--ref", "main")
        ks : List<&2, String> = inputs.of(args)
        r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, "actions/workflows/" ++ wf ++ "/dispatches"), Some{dispatch.body(ref, ks)})
        check.ok(env, r)
        dispatch.url(env, ref)

# A selected job uses the job endpoint; --failed uses the run's failed-jobs endpoint.
def rerun.path(+id: String, +job: String, failed: Bool, specific: Bool) -> String:
  match failed specific:
    case f True{}:
      "actions/jobs/" ++ Url.encode(job) ++ "/rerun"
    case True{} False{}:
      "actions/runs/" ++ Url.encode(id) ++ "/rerun-failed-jobs"
    case False{} False{}:
      "actions/runs/" ++ Url.encode(id) ++ "/rerun"

def rerun.post(+env: Cli.Env, +id: String, +job: String, +failed: Bool) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, a}:
      do IO<Unit>:
        r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, rerun.path(id, job, failed, Bool.not(String.is_empty(job)))), None{})
        check.ok(env, r)
        done.url(env, "actions/runs/" ++ id)

def rerun.job.check(+env: Cli.Env, +id: String, +job: String, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      rerun.post(env, id, job, False{})
    case False{}:
      Cli.fail(Unit, env, "runs rerun: job does not belong to run " ++ id)

def rerun.selected(+env: Cli.Env, +id: String, +job: String, +failed: Bool, specific: Bool) -> IO(Unit):
  match env specific:
    case Cli.Env{repo, tok, on, json, a} False{}:
      rerun.post(env, id, job, failed)
    case Cli.Env{+repo, +tok, on, json, a} True{}:
      do IO<Unit>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "actions/jobs/" ++ Url.encode(job)))
        b : Bytes.Bytes <- fetch.body(env, r)
        rerun.job.check(env, id, job, String.eq(Api.f(Api.obj(b), "run_id"), id))

def rerun.valid(+env: Cli.Env, +id: String, +job: String, +failed: Bool, conflict: Bool) -> IO(Unit):
  match conflict:
    case True{}:
      Cli.fail(Unit, env, "runs rerun: choose either --failed or --job ID")
    case False{}:
      rerun.selected(env, id, job, failed, Bool.not(String.is_empty(job)))

def rerun.go(+env: Cli.Env, +forge: Ctx.Forge, +id: String, +job: String, +failed: Bool) -> IO(Unit):
  match forge:
    case Ctx.Gitea{}:
      Cli.fail(Unit, env, "runs rerun: this forge has no rerun API; push a commit or rerun from the web UI")
    case Ctx.GitHub{}:
      rerun.valid(env, id, job, failed, failed && Bool.not(String.is_empty(job)))

def rerun.args(+env: Cli.Env, +repo: Ctx.Repo, +id: String, +job: String, +failed: Bool, missing: Bool) -> IO(Unit):
  match missing:
    case True{}:
      Cli.fail(Unit, env, "runs rerun: --job needs a job id")
    case False{}:
      rerun.go(env, forge.of(repo), id, job, failed)

def rerun(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +id : String <- require.at(env, 1n, "run id")
        +job : String = Cli.flag(args, "--job", "")
        rerun.args(env, repo, id, job, Cli.has(args, "--failed"), (Cli.has(args, "--job") || Cli.has(args, "--job=")) && (String.is_empty(job) || String.starts_with(job, "--")))

def cancel.bad(+env: Cli.Env, +status: U32, body: Bytes.Bytes, missing: Bool) -> IO(Unit):
  match missing:
    case True{}:
      Cli.fail(Unit, env, "runs cancel: this forge has no cancel API (HTTP 404); cancel it from the web UI")
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def cancel.if(+env: Cli.Env, +status: U32, body: Bytes.Bytes, +id: String, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      done.url(env, "actions/runs/" ++ id)
    case False{}:
      cancel.bad(env, status, body, U32.is_eq(status, 404))

def cancel.check(+env: Cli.Env, r: Api.Reply, +id: String) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      cancel.if(env, status, body, id, Api.ok(status))

def cancel(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +id : String <- require.at(env, 1n, "run id")
        r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, "actions/runs/" ++ id ++ "/cancel"), None{})
        cancel.check(env, r, id)

# list
# ----

def list.print(+on: Bool, json: Cli.Json, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(run.lines(on, xs))
    case j:
      Cli.json.emit(on, j, xs, run.fields())

# Match the workflow's display name, full path, or file basename. A path can
# include @ref on both forges; it is not part of the filename.
def workflow.matches(+row: Map<&2, String>, +wanted: String) -> Bool:
  +path = Ctx.first(String.split(Api.f(row, "path"), '@'))
  String.is_empty(wanted) || String.eq(wanted, Api.f(row, "workflow")) || String.eq(wanted, Api.f(row, "name")) || String.eq(wanted, path) || String.eq(wanted, Ctx.last(String.split(path, '/')))

def workflow.any(wanted: List<&2, String>, +row: Map<&2, String>) -> Bool:
  match wanted:
    case Nil{}:
      False{}
    case Con{w, rest}:
      workflow.matches(row, w) || workflow.any(rest, row)

def workflow.want(wanted: List<&2, String>, +row: Map<&2, String>) -> Bool:
  match wanted:
    case Nil{}:
      True{}
    case Con{w, rest}:
      workflow.any(Con{w, rest}, row)

# Workflow metadata, as name resolution needs it: a workflow's display name and
# the basename of its file, which is what a run's path carries. Names resolve
# through the workflows the forge lists now; historical runs are filtered by
# their file paths afterwards.
type Wf is Data:
  Wf{name: String, file: String}

def wf.entry(+src: Map<&2, String>, +prefix: String) -> Wf:
  Wf{g(src, prefix, "name"), Ctx.last(String.split(Ctx.or(g(src, prefix, "path"), g(src, prefix, "id")), '/'))}

def wf.entries(n: Nat, +i: U32, +src: Map<&2, String>, acc: List<&2, Wf>) -> List<&2, Wf>:
  match n:
    case 0n:
      acc
    case 1n+p:
      wf.entries(p, (i + 1 : U32), src, List.append(&2, Wf, acc, [wf.entry(src, prefix.of("workflows", i))]))

# the files of every workflow whose display name is wanted
def wf.add.file(acc: List<&2, String>, +file: String, same: Bool) -> List<&2, String>:
  match same:
    case True{}:
      List.append(&2, String, acc, [file])
    case False{}:
      acc

def wf.files(xs: List<&2, Wf>, +wanted: String, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      acc
    case Con{Wf{+name, +file}, rest}:
      wf.files(rest, wanted, wf.add.file(acc, file, String.eq(name, wanted)))

# every display name, for the error when a name resolves to no file
def wf.names(xs: List<&2, Wf>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      acc
    case Con{Wf{+name, +file}, rest}:
      wf.names(rest, List.append(&2, String, acc, [name]))

# Gitea and GitHub both list a repository's workflows; Gitea pages with limit,
# GitHub with per_page
def workflows.at(+forge: Ctx.Forge) -> String:
  match forge:
    case Ctx.Gitea{}:
      "actions/workflows?page=1&limit=100"
    case Ctx.GitHub{}:
      "actions/workflows?page=1&per_page=100"

def list.keep(xs: List<&2, Map<&2, String>>, +workflow: List<&2, String>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      keep.if(x, list.keep(rest, workflow), workflow.want(workflow, x))

type WorkflowPages is Type:
  FetchWorkflows{url: String, wfs: List<&2, Wf>}
  ReadWorkflows{reply: Api.Reply, wfs: List<&2, Wf>}
  NextWorkflows{last: Bool, url: String, wfs: List<&2, Wf>}

def workflow.page(+next: String, body: Bytes.Bytes, acc: List<&2, Wf>) -> WorkflowPages:
  +src = Api.obj(body)
  NextWorkflows{String.is_empty(next), next, wf.entries(Api.count(src, "workflows"), 0, src, acc)}

def workflow.finish.rows(+env: Cli.Env, xs: List<&2, String>, +wanted: String, +all: List<&2, Wf>) -> IO(List<&2, String>):
  match xs:
    case Nil{}:
      Cli.fail(List<&2, String>, env, "runs list: no workflow named " ++ wanted ++ "; workflows: " ++ Ctx.or(String.join(wf.names(all, Nil{}), ", "), "none"))
    case Con{x, rest}:
      IO.pure(List<&2, String>, Con{x, rest})

def workflow.finish(+env: Cli.Env, +wfs: List<&2, Wf>, +wanted: String) -> IO(List<&2, String>):
  workflow.finish.rows(env, wf.files(wfs, wanted, Nil{}), wanted, wfs)

def workflow.walk(fuel: Nat, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +wanted: String, st: WorkflowPages) -> IO(List<&2, String>):
  match fuel st:
    case 0n s:
      Cli.fail(List<&2, String>, env, "runs list: too many workflow pages; use a file name")
    case 1n+p FetchWorkflows{url, wfs}:
      do IO<List<&2, String>>:
        r : Api.Reply <- Api.get(repo, tok, url)
        workflow.walk(p, env, repo, tok, wanted, ReadWorkflows{r, wfs})
    case 1n+p ReadWorkflows{Api.Broke{w}, wfs}:
      Cli.fail(List<&2, String>, env, w)
    case 1n+p ReadWorkflows{Api.Reply{+status, +next, body}, wfs}:
      do IO<List<&2, String>>:
        b : Bytes.Bytes <- ok.body(env, status, body, Api.ok(status))
        workflow.walk(p, env, repo, tok, wanted, workflow.page(next, b, wfs))
    case 1n+p NextWorkflows{True{}, url, wfs}:
      workflow.finish(env, wfs, wanted)
    case 1n+p NextWorkflows{False{}, url, wfs}:
      workflow.walk(p, env, repo, tok, wanted, FetchWorkflows{url, wfs})

# --workflow by file name needs no lookup; a display name resolves through the
# workflows the forge lists now, and a name that matches none exits 1
def workflow.resolve(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +wanted: String, empty: Bool, file: Bool) -> IO(List<&2, String>):
  match empty file:
    case True{} f:
      IO.pure(List<&2, String>, Nil{})
    case False{} True{}:
      IO.pure(List<&2, String>, [wanted])
    case False{} False{}:
      workflow.walk(301n, env, repo, tok, wanted, FetchWorkflows{Api.path(repo, workflows.at(forge.of(repo))), Nil{}})

def require.limit(+env: Cli.Env, v: U32, valid: Bool) -> IO(Nat):
  match valid:
    case True{}:
      IO.pure(Nat, U32.to_nat(v))
    case False{}:
      Cli.fail(Nat, env, "runs list: --limit must be an integer from 1 to 1000")

def list.limit(+env: Cli.Env, n: Maybe<&2, U32>) -> IO(Nat):
  match n:
    case Some{+v}:
      require.limit(env, v, (v > 0 : U32) && (v <= 1000 : U32))
    case None{}:
      Cli.fail(Nat, env, "runs list: --limit must be an integer from 1 to 1000")

# Both APIs wrap their rows in workflow_runs, so Api.all's array walker cannot
# be used here. Follow Link pages until enough matching runs have been collected.
# seen counts the runs fetched before the filter, to compare with total_count.
type RunPages is Type:
  FetchRuns{url: String, acc: List<&2, Map<&2, String>>}
  ReadRuns{reply: Api.Reply, acc: List<&2, Map<&2, String>>}
  NextRuns{done: Bool, url: String, seen: Nat, acc: List<&2, Map<&2, String>>}

def list.page(+env: Cli.Env, +forge: Ctx.Forge, +now: Time.Instant, +wanted: List<&2, String>, +limit: Nat, +next: String, +fallback: String, +seen: Nat, body: Bytes.Bytes, acc: List<&2, Map<&2, String>>) -> RunPages:
  +src = Api.obj(body)
  +rows = rows.of(src, "workflow_runs", forge, now)
  +count = Nat.add(seen, List.length(&2, Map<&2, String>, rows))
  +url = page.next(next, fallback, count, Api.f(src, "total_count"), Nat.is_eq(List.length(&2, Map<&2, String>, rows), 0n))
  +got = List.append(&2, Map<&2, String>, acc, list.keep(rows, wanted))
  NextRuns{String.is_empty(url) || Nat.is_ge(List.length(&2, Map<&2, String>, got), limit), url, count, List.take(&2, Map<&2, String>, got, limit)}

def list.walk(fuel: Nat, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +now: Time.Instant, +wanted: List<&2, String>, +limit: Nat, +rest: String, +page: U32, +seen: Nat, st: RunPages) -> IO(List<&2, Map<&2, String>>):
  match fuel st:
    case 0n s:
      Cli.fail(List<&2, Map<&2, String>>, env, "runs list: pagination limit reached; narrow --branch or --status")
    case 1n+p FetchRuns{url, acc}:
      do IO<List<&2, Map<&2, String>>>:
        r : Api.Reply <- Api.get(repo, tok, url)
        list.walk(p, env, repo, tok, now, wanted, limit, rest, page, seen, ReadRuns{r, acc})
    case 1n+p ReadRuns{Api.Broke{w}, acc}:
      Cli.fail(List<&2, Map<&2, String>>, env, w)
    case 1n+p ReadRuns{Api.Reply{+status, +next, body}, acc}:
      do IO<List<&2, Map<&2, String>>>:
        b : Bytes.Bytes <- ok.body(env, status, body, Api.ok(status))
        list.walk(p, env, repo, tok, now, wanted, limit, rest, page, seen, list.page(env, forge.of(repo), now, wanted, limit, next, Api.path(repo, runs.at(rest, (page + 1 : U32))), seen, b, acc))
    case 1n+p NextRuns{True{}, url, n, acc}:
      IO.pure(List<&2, Map<&2, String>>, acc)
    case 1n+p NextRuns{False{}, url, n, acc}:
      list.walk(p, env, repo, tok, now, wanted, limit, rest, (page + 1 : U32), n, FetchRuns{url, acc})

def list(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +limit : Nat <- list.limit(env, U32.read(Cli.flag(args, "--limit", "20")))
        +now : Time.Instant <- Time.now()
        +wanted : String = Cli.flag(args, "--workflow", "")
        +workflows : List<&2, String> <- workflow.resolve(env, repo, tok, wanted, String.is_empty(wanted), String.ends_with(wanted, ".yml") || String.ends_with(wanted, ".yaml"))
        +rest : String = runs.rest(forge.of(repo), Cli.flag(args, "--branch", ""), Cli.flag(args, "--status", ""), "50")
        xs : List<&2, Map<&2, String>> <- list.walk(301n, env, repo, tok, now, workflows, limit, rest, 1, 0n, FetchRuns{Api.path(repo, runs.at(rest, 1)), Nil{}})
        list.print(on, json, xs)

# routing
# -------

def pick.at(eq: Bool, i: Nat, +later: Nat) -> Nat:
  match eq:
    case True{}:
      i
    case False{}:
      later

def kind.of(+sub: String) -> Nat:
  pick.at(String.eq(sub, "view"), 1n,
    pick.at(String.eq(sub, "logs"), 2n,
      pick.at(String.eq(sub, "watch"), 3n,
        pick.at(String.eq(sub, "dispatch"), 4n,
          pick.at(String.eq(sub, "rerun"), 5n,
            pick.at(String.eq(sub, "cancel"), 6n, 0n))))))

def run.at(+env: Cli.Env, +sub: String, kind: Nat) -> IO(Unit):
  match kind:
    case 0n:
      list(env)
    case 1n:
      view(env)
    case 2n:
      logs(env)
    case 3n:
      watch(env)
    case 4n:
      dispatch(env)
    case 5n:
      rerun(env)
    case 6n+k:
      cancel(env)

def run.sub(+env: Cli.Env, +sub: String) -> IO(Unit):
  run.at(env, sub, kind.of(sub))

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      run.sub(env, Cli.arg(args, 0n))
