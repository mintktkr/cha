# cha runs: list, view, logs, watch, dispatch, rerun, cancel.
import Base
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli
import ../url.bend as Url
import ../runlogs.bend as Runlogs
import ../../lib/chaki/json.bend as Json
import ../../lib/chaki/time.bend as Time
import ../../lib/chaki/sys.bend as Sys

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

# Gitea and Forgejo write the epoch when a run or a job never got a start
def zero.instant(+m: Maybe<&2, U32>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{i}:
      U32.is_eq(i, 0)

# States
# ------

# the labels meaning a run or job did not succeed
def failed.labels(+l: String) -> Bool:
  String.eq(l, "failure") || String.eq(l, "failed") || String.eq(l, "error") || String.eq(l, "cancelled") || String.eq(l, "timed_out")

# the statuses that end a run rather than name a state it is still in. GitHub and Gitea say
# "completed" and send the conclusion beside it; Forgejo names the conclusion in the status
# field itself, and sends no conclusion at all.
def status.terminal(+status: String) -> Bool:
  String.eq(status, "completed") || String.eq(status, "success") || String.eq(status, "failure") || String.eq(status, "cancelled") || String.eq(status, "skipped")

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

def secs.of(+now: U32, +then: U32, neg: Bool) -> U32:
  match neg:
    case True{}:
      0
    case False{}:
      (now - then : U32)

def secs.between(+now: U32, +then: U32) -> U32:
  secs.of(now, then, U32.is_gt(then, now))

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

def age.between(+now: U32, +then: U32) -> String:
  age.of(secs.between(now, then))

# the age text of a run whose start timestamp is m, "" when m has no timestamp
def age.of.parse(m: Maybe<&2, U32>, +now: U32) -> String:
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

def forge.github(+forge: Ctx.Forge) -> Bool:
  match forge:
    case Ctx.Gitea{}:
      False{}
    case Ctx.GitHub{}:
      True{}

def forge.gitea(+forge: Ctx.Forge) -> Bool:
  match forge:
    case Ctx.Gitea{}:
      True{}
    case Ctx.GitHub{}:
      False{}

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

# a forge timestamp, "" when the forge sent none. The epoch is compared as a parsed
# instant, so every offset form of it reads as no timestamp too.
def time.nonzero(+s: String) -> String:
  Ctx.or.if(s, "", zero.instant(Time.parse(s)))

# field k of an object as a timestamp: "" when the forge sent none, or the epoch
# 1970-01-01T00:00:00Z it writes for a time that never happened
def time.at(+src: Map<&2, String>, +prefix: String, +k: String) -> String:
  time.nonzero(g.raw(src, prefix, k))

# when a run started: Gitea says started_at, Forgejo started, GitHub
# run_started_at then created_at
def started.at(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge) -> String:
  match forge:
    case Ctx.Gitea{}:
      Ctx.or(time.at(src, prefix, "started_at"), time.at(src, prefix, "started"))
    case Ctx.GitHub{}:
      Ctx.or(time.at(src, prefix, "run_started_at"), time.at(src, prefix, "created_at"))

# the workflow's name: Gitea and Forgejo name the file, GitHub names the
# workflow
def wf.of(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge) -> String:
  match forge:
    case Ctx.Gitea{}:
      Ctx.first(String.split(Ctx.or(g.raw(src, prefix, "path"), g.raw(src, prefix, "workflow_id")), '@'))
    case Ctx.GitHub{}:
      g.raw(src, prefix, "name")

def age.at(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge, +now: U32) -> String:
  age.of.parse(Time.parse(started.at(src, prefix, forge)), now)

# updated_at can change after completion; only expose a real completion timestamp
def completed.at(+src: Map<&2, String>, +prefix: String, done: Bool) -> String:
  match done:
    case True{}:
      Ctx.or(time.at(src, prefix, "completed_at"), time.at(src, prefix, "stopped"))
    case False{}:
      ""

# when the run appeared: GitHub stamps created_at, Forgejo created, and Gitea 1.25
# neither, so a run that has started stands in for one that is still queued
def created.at(+src: Map<&2, String>, +prefix: String) -> String:
  Ctx.or(time.at(src, prefix, "created_at"), Ctx.or(time.at(src, prefix, "created"), Ctx.or(time.at(src, prefix, "started_at"), time.at(src, prefix, "started"))))

def elapsed.valid(+secs: U32, bad: Bool) -> String:
  match bad:
    case True{}:
      ""
    case False{}:
      U32.show(secs)

def elapsed.of(start: Maybe<&2, U32>, end: Maybe<&2, U32>) -> String:
  match start end:
    case Some{+s} Some{+e}:
      elapsed.valid((e - s : U32), U32.is_lt(e, s))
    case a b:
      ""

# elapsed seconds; a missing timestamp, or the epoch a forge writes for one, does not
# imply a zero-length run (nor a run of fifty-six years).
def elapsed(+start: String, +end: String) -> String:
  elapsed.of(Time.parse(time.nonzero(start)), Time.parse(time.nonzero(end)))

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
def run.row(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge, +now: U32) -> Map<&2, String>:
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
  m = Map.set(&2, String, m, "attempt", g.raw(src, prefix, "run_attempt"))
  m = Map.set(&2, String, m, "status", status)
  m = Map.set(&2, String, m, "conclusion", conclusion)
  m = Map.set(&2, String, m, "state", state.of(status, conclusion, done))
  m = Map.set(&2, String, m, "workflow", wf.of(src, prefix, forge))
  m = Map.set(&2, String, m, "branch", branch.of(src, prefix))
  m = Map.set(&2, String, m, "sha", Ctx.or(g.raw(src, prefix, "head_sha"), g.raw(src, prefix, "commit_sha")))
  m = Map.set(&2, String, m, "title", Ctx.or(Ctx.or(g.raw(src, prefix, "display_title"), g.raw(src, prefix, "title")), wf.of(src, prefix, forge)))
  m = Map.set(&2, String, m, "event", g.raw(src, prefix, "event"))
  m = Map.set(&2, String, m, "started_at", started)
  m = Map.set(&2, String, m, "updated_at", Ctx.or(time.at(src, prefix, "updated_at"), time.at(src, prefix, "updated")))
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
  ["kind", "id", "run_number", "attempt", "state", "status", "conclusion", "workflow", "branch", "sha", "title", "event", "age", "started_at", "updated_at", "completed_at", "duration", "html_url"]

# the runs of a list body, as rows
def prefix.of(+root: String, i: U32) -> String:
  root ++ "." ++ U32.show(i)

def rows.go(n: Nat, +i: U32, +src: Map<&2, String>, +root: String, +forge: Ctx.Forge, +now: U32) -> List<&2, Map<&2, String>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      run.row(src, prefix.of(root, i), forge, now) <> rows.go(p, (i + 1 : U32), src, root, forge, now)

def rows.of(+src: Map<&2, String>, +root: String, +forge: Ctx.Forge, +now: U32) -> List<&2, Map<&2, String>>:
  rows.go(Api.count(src, root), 0, src, root, forge, now)

# Replies
# -------

def ok.body(+env: Cli.Env, +status: U32, body: List<&2, U32>, good: Bool) -> IO(List<&2, U32>):
  match good:
    case True{}:
      IO.pure(List<&2, U32>, body)
    case False{}:
      Cli.fail(List<&2, U32>, env, Api.message(status, body))

# a reply's body, or the command fails with the forge's error
def fetch.body(+env: Cli.Env, r: Api.Reply) -> IO(List<&2, U32>):
  match r:
    case Api.Broke{w}:
      Cli.fail(List<&2, U32>, env, w)
    case Api.Reply{+status, next, body}:
      ok.body(env, status, body, Api.ok(status))

# Jobs
# ----

# Run, job and step durations share the same timestamp semantics.
def job.duration(+start: String, +end: String) -> String:
  elapsed(start, end)

def job.duration.text(+seconds: String) -> String:
  Ctx.or.if(seconds ++ "s", "", String.is_empty(seconds))

# Copy each step to the normalized job row, retaining the flat array convention.
def step.copy(+src: Map<&2, String>, +source: String, +target: String, m: Map<&2, String>) -> Map<&2, String>:
  +started : String = time.at(src, source, "started_at")
  +finished : String = time.at(src, source, "completed_at")
  m = Map.set(&2, String, m, Api.key(target, "number"), g.raw(src, source, "number"))
  m = Map.set(&2, String, m, Api.key(target, "name"), g.raw(src, source, "name"))
  m = Map.set(&2, String, m, Api.key(target, "status"), g.raw(src, source, "status"))
  m = Map.set(&2, String, m, Api.key(target, "conclusion"), g.raw(src, source, "conclusion"))
  m = Map.set(&2, String, m, Api.key(target, "state"), state(src, source))
  m = Map.set(&2, String, m, Api.key(target, "started_at"), started)
  m = Map.set(&2, String, m, Api.key(target, "completed_at"), finished)
  Map.set(&2, String, m, Api.key(target, "duration"), job.duration(started, finished))

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
  +started : String = time.at(src, prefix, "started_at")
  +finished : String = time.at(src, prefix, "completed_at")
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "kind", "job")
  m = Map.set(&2, String, m, "id", g.raw(src, prefix, "id"))
  m = Map.set(&2, String, m, "name", g.raw(src, prefix, "name"))
  m = Map.set(&2, String, m, "status", status)
  m = Map.set(&2, String, m, "conclusion", conclusion)
  m = Map.set(&2, String, m, "state", state.of(status, conclusion, String.eq(status, "completed")))
  m = Map.set(&2, String, m, "runner_name", g.raw(src, prefix, "runner_name"))
  m = Map.set(&2, String, m, "started_at", started)
  m = Map.set(&2, String, m, "completed_at", finished)
  m = Map.set(&2, String, m, "duration", job.duration(started, finished))
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

# GitHub counts a run's attempts and sends run_attempt; Gitea and Forgejo have no
# such field, so one that is missing reads as no attempt. A first attempt is the
# normal case and stays out of the header.
def attempt.label.above(+n: String, above: Bool) -> String:
  match above:
    case True{}:
      "  attempt " ++ n
    case False{}:
      ""

def attempt.label.of(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{+n}:
      attempt.label.above(U32.show(n), U32.is_gt(n, 1))
    case None{}:
      ""

def attempt.label(+row: Map<&2, String>) -> String:
  attempt.label.of(U32.read(Api.f(row, "attempt")))

def view.json.jobs(xs: List<&2, Map<&2, String>>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      Cli.json.row(x, job.json.fields(x)) <> view.json.jobs(rest)

# One object, the way issue view --comments prints one: the run under "run" and its jobs
# under "jobs", rather than an array mixing a run row with job rows.
def view.json.doc(+run: String, +jobs: String) -> String:
  "{\"run\":" ++ run ++ ",\"jobs\":" ++ jobs ++ "}"

def view.json.text(+row: Map<&2, String>, jobs: List<&2, Map<&2, String>>) -> String:
  view.json.doc(Cli.json.row(row, run.fields()), "[" ++ String.join(view.json.jobs(jobs), ",\n") ++ "]")

def view.json(+row: Map<&2, String>, +jobs: List<&2, Map<&2, String>>) -> IO(Unit):
  IO.print(view.json.text(row, jobs))

def view.text(+on: Bool, +row: Map<&2, String>, +jobs: List<&2, Map<&2, String>>) -> String:
  "#" ++ Api.f(row, "id") ++ "  " ++ Ui.state(on, Api.f(row, "state")) ++ "  " ++ Api.f(row, "workflow") ++ attempt.label(row) ++ "\n" ++
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

# the nth argument as a run id: digits only. A run id is one path segment, and U32.read
# alone takes some punctuation as a zero, so ".." would name another endpoint.
def require.id(+env: Cli.Env, n: Nat) -> IO(String):
  do IO<String>:
    +id : String <- require.at(env, n, "run id")
    Cli.check.if(env, "runs: a run id is digits only, got '" ++ id ++ "'", Cli.digits(id))
    return id

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

def jobs.page(+next: String, +fallback: String, body: List<&2, U32>, acc: List<&2, Map<&2, String>>) -> JobPages:
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
        b : List<&2, U32> <- ok.body(env, status, body, Api.ok(status))
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
        Cli.check(env, "runs view", args, ["--json"])
        +id : String <- require.id(env, 1n)
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "actions/runs/" ++ id))
        body : List<&2, U32> <- fetch.body(env, r)
        now : U32 <- Sys.now()
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

def logs.get(+env: Cli.Env, +row: Map<&2, String>, +suffix: String) -> IO(List<&2, U32>):
  match env:
    case Cli.Env{+repo, tok, on, json, a}:
      do IO<List<&2, U32>>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "actions/jobs/" ++ Api.f(row, "id") ++ suffix))
        fetch.body(env, r)

def logs.whole(+env: Cli.Env, +row: Map<&2, String>) -> IO(LogSummary):
  match env:
    case Cli.Env{repo, tok, on, json, a}:
      do IO<LogSummary>:
        b : List<&2, U32> <- logs.get(env, row, "/logs")
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
        b : List<&2, U32> <- logs.get(env, row, "/logs")
        logs.step.github.at(env, row, name, position, started, completed, Api.text(b))

def logs.step.fetch(+env: Cli.Env, +row: Map<&2, String>, s: Runlogs.Step, forge: Ctx.Forge) -> IO(LogSummary):
  match env s forge:
    case Cli.Env{repo, tok, on, json, a} Runlogs.Step{position, +name, status, conclusion, started, completed} Ctx.GitHub{}:
      logs.step.github(env, row, s)
    case Cli.Env{repo, tok, on, json, a} Runlogs.Step{position, +name, status, conclusion, +started, +completed} Ctx.Gitea{}:
      do IO<LogSummary>:
        b : List<&2, U32> <- logs.get(env, row, "/logs")
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
        Cli.check(env, "runs logs", args, ["--job", "--step", "--failed"])
        +id : String <- require.id(env, 1n)
        +job : String = Cli.flag(args, "--job", "")
        +step : String <- require.if(env, Cli.flag(args, "--step", ""), "step name", Cli.has(args, "--step") && (String.is_empty(Cli.flag(args, "--step", "")) || String.starts_with(Cli.flag(args, "--step", ""), "--")))
        +all : List<&2, Map<&2, String>> <- jobs.fetch(env, id)
        +ks : List<&2, Map<&2, String>> = keep.rows(all, job, Cli.has(args, "--failed"))
        +named : List<&2, Map<&2, String>> = keep.rows(all, job, False{})
        logs.pick.if(env, id, ks, all, job, step, logs.miss(named, job))

# watch
# -----

# How a poll's reply reads for the watch. A watch follows a run for days, so a poll that
# never reached the forge says nothing about the run: it is retried on the next tick.
# Only five failed polls in a row end the watch, and they end it as cha giving up, not as
# the run failing.
type Polled is Data:
  Good{}
  Retry{}
  Fatal{}

def poll.server(server: Bool) -> Polled:
  match server:
    case True{}:
      Retry{}
    case False{}:
      Fatal{}

def poll.status(good: Bool, server: Bool) -> Polled:
  match good:
    case True{}:
      Good{}
    case False{}:
      poll.server(server)

# a poll's reply read the way the watch must act on it. A request that never got a status
# (timeout, connect, read) and a 5xx say nothing about the run, so both are retried on the
# next tick; a 2xx is the run to read; any other status is the forge refusing the read.
def poll.of(+status: Maybe<&2, U32>) -> Polled:
  match status:
    case None{}:
      Retry{}
    case Some{+s}:
      poll.status(Api.ok(s), (s >= 500 : U32))

# polls in a row that may fail before the watch gives up
def poll.tries() -> Nat:
  5n

# consecutive failed polls, stepped by one poll's outcome: an answered poll resets the
# count, a retried one adds to it, and a refusal leaves it (the watch stops there anyway)
def poll.count(+fails: Nat, p: Polled) -> Nat:
  match p:
    case Good{}:
      0n
    case Retry{}:
      1n+fails
    case Fatal{}:
      fails

# the watch gives up on the forge once this many polls in a row have failed
def poll.gave.up(+fails: Nat) -> Bool:
  Nat.is_ge(fails, poll.tries())

# a poll's outcome: still going, finished, another try, cha giving up, or the forge's refusal.
# fails rides along, so the count of failed polls in a row survives a tick that shows the
# state again.
type Tick is Data:
  More{state: String, fails: Nat}
  End{state: String, conclusion: String}
  Again{fails: Nat}
  Give{fails: Nat}
  Stop{msg: String}

def tick.at(+state: String, +conclusion: String, done: Bool) -> Tick:
  match done:
    case True{}:
      End{state, conclusion}
    case False{}:
      More{state, 0n}

# The watch prints the state it reads, so unlike the row builders this reads the source
# through the clean door. state.of is the run's ending once it has one, and that ending is
# also the word the exit code is read from, so both come from it.
def tick.of(+src: Map<&2, String>) -> Tick:
  +status = Api.f(src, "status")
  +done : Bool = status.terminal(status)
  +shown : String = state.of(status, Api.f(src, "conclusion"), done)
  tick.at(shown, shown, done)

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

# another try, or a give-up once five polls in a row have failed
def tick.give(+fails: Nat, gaveup: Bool) -> Tick:
  match gaveup:
    case True{}:
      Give{fails}
    case False{}:
      Again{fails}

def tick.retry(+fails: Nat, p: Polled) -> Tick:
  +n = poll.count(fails, p)
  tick.give(n, poll.gave.up(n))

# what the watch does with the reply to a poll: the run's state, another try, or the
# forge's own error
def tick.reply(+fails: Nat, +status: U32, body: List<&2, U32>, p: Polled) -> Tick:
  match p:
    case Good{}:
      tick.of(Api.obj(body))
    case Retry{}:
      tick.retry(fails, p)
    case Fatal{}:
      Stop{Api.message(status, body)}

def tick.next(+fails: Nat, r: Api.Reply) -> Tick:
  match r:
    case Api.Broke{w}:
      tick.retry(fails, poll.of(None{}))
    case Api.Reply{+status, next, body}:
      tick.reply(fails, status, body, poll.of(Some{status}))

# a watch's exit code when it did not finish: 1 when the run concluded in failure, 2 when
# cha gave up on the forge, so a script can tell "the build failed" from "couldn't look"
def watch.code(gaveup: Bool) -> U32:
  match gaveup:
    case True{}:
      2
    case False{}:
      1

# the exit code of a run that ended: a failed ending is the failed command's code, and one
# that did not fail is not a failure at all
def watch.end.code.if(+end: String, bad: Bool) -> U32:
  match bad:
    case True{}:
      watch.code(False{})
    case False{}:
      0

def watch.end.code(+end: String) -> U32:
  watch.end.code.if(end, failed.labels(end))

def exit.if(+end: String, bad: Bool) -> IO(Unit):
  match bad:
    case True{}:
      IO.die(Unit, watch.end.code(end), "")
    case False{}:
      IO.pure(Unit, Unit{})

# a run that ended in failure is a failed command
def watch.exit(+end: String) -> IO(Unit):
  exit.if(end, failed.labels(end))

# the last thing a watch says when it gives up: the count, and the state it last read
def watch.gave.up.text(+fails: Nat, +shown: String) -> String:
  "gave up after " ++ Nat.show(fails) ++ " failed polls; the run is still " ++ Ctx.or(shown, "unknown")

# the last thing a watch says when it ran out of polls: the one state it last read
def watch.exhausted.text(+shown: String) -> String:
  "ran out of polls; the run is still " ++ Ctx.or(shown, "unknown")

# a watch that ran out of polls never saw the run end, so it exits as giving up does
def watch.exhausted.code() -> U32:
  watch.code(True{})

# the redraw line has no newline, so clear it before a line of cha's own goes to stderr
def watch.clear(+on: Bool) -> IO(Unit):
  match on:
    case True{}:
      IO.write("\r\u{1b}[K")
    case False{}:
      IO.pure(Unit, Unit{})

# cha gave up watching: five polls in a row never reached the forge
def watch.gave.up(+env: Cli.Env, +on: Bool, +shown: String, +fails: Nat) -> IO(Unit):
  do IO<Unit>:
    watch.clear(on)
    Ui.error(on, watch.gave.up.text(fails, shown))
    IO.die(Unit, watch.code(True{}), "")

# cha ran out of polls: the state it last read, and the same exit code as giving up, since
# the run never ended where the watch could see it
def watch.exhausted(+env: Cli.Env, +on: Bool, +shown: String) -> IO(Unit):
  do IO<Unit>:
    watch.clear(on)
    Ui.error(on, watch.exhausted.text(shown))
    IO.die(Unit, watch.exhausted.code(), "")

# the forge answered a poll with a refusal: that is the command failing, as on any other call
def watch.stop(+env: Cli.Env, +on: Bool, +msg: String) -> IO(Unit):
  do IO<Unit>:
    watch.clear(on)
    Cli.fail(Unit, env, msg)

# at least one step per poll (a retried one costs two), so fuel bounds the polls left.
# 100000 polls at 5 s is ~6 days.
def watch.go(fuel: Nat, +env: Cli.Env, +on: Bool, +id: String, +shown: String, +spin: U32, t: Tick) -> IO(Unit):
  match fuel t:
    case 0n m:
      watch.exhausted(env, on, shown)
    case 1n+p End{+state, +conclusion}:
      do IO<Unit>:
        watch.end(on, id, state, shown, spin)
        watch.exit(conclusion)
    case 1n+p More{+state, +fails}:
      do IO<Unit>:
        watch.step(on, id, state, shown, spin)
        IO.sleep(5000)
        r : Api.Reply <- watch.get(env, id)
        watch.go(p, env, on, id, state, (spin + 1 : U32), tick.next(fails, r))
    # the state is the one already shown, so piped nothing prints: just look again
    case 1n+p Again{+fails}:
      watch.go(p, env, on, id, shown, (spin + 1 : U32), More{shown, fails})
    case 1n+p Give{+fails}:
      watch.gave.up(env, on, shown, fails)
    case 1n+p Stop{+msg}:
      watch.stop(env, on, msg)

def watch(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "runs watch", args, [])
        +id : String <- require.id(env, 1n)
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "actions/runs/" ++ id))
        watch.go(100000n, env, on, id, "", 0, tick.next(0n, r))

# dispatch, rerun, cancel
# -----------------------

def input.key(kv: String) -> String:
  Ctx.first(String.split(kv, '='))

def input.val(kv: String) -> String:
  Ctx.rest(String.split(kv, '='), "=")

def input.pairs(xs: List<&2, String>) -> List<&2, Json.Val>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+kv, rest}:
      Con{Json.field(input.key(kv), Api.utf8(input.val(kv))), input.pairs(rest)}

def dispatch.pairs(+ref: String, xs: List<&2, String>) -> List<&2, Json.Val>:
  [Json.field("ref", Api.utf8(ref)), Json.field("inputs", Json.Obj{input.pairs(xs)})]

# GitHub names the run it made when asked; Gitea and Forgejo have no such field,
# and are not sent one
def dispatch.detail.pairs(details: Bool) -> List<&2, Json.Val>:
  match details:
    case True{}:
      [Json.field("return_run_details", Json.Flag{True{}})]
    case False{}:
      Nil{}

def dispatch.body(+ref: String, xs: List<&2, String>, details: Bool) -> Json.Val:
  Json.Obj{List.append(&2, Json.Val, dispatch.pairs(ref, xs), dispatch.detail.pairs(details))}

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

# the run a dispatch made belongs to the workflow it named: the same file, path
# or display name
def dispatch.workflow(+row: Map<&2, String>, +wf: String) -> Bool:
  +path = Ctx.first(String.split(Api.f(row, "path"), '@'))
  String.eq(wf, path) || String.eq(wf, Ctx.last(String.split(path, '/'))) || String.eq(wf, Api.f(row, "workflow")) || String.eq(wf, Api.f(row, "name"))

# the ref a run records, whole (refs/heads/main) or short (main), against the one
# asked for
def ref.same(+a: String, +b: String) -> Bool:
  String.is_empty(a) || String.eq(a, b) || String.eq(a, "refs/heads/" ++ b) || String.eq(a, "refs/tags/" ++ b) || String.eq("refs/heads/" ++ a, b) || String.eq("refs/tags/" ++ a, b)

# a run of the dispatch's workflow, from a dispatch, on the ref asked for
def dispatch.mine(+row: Map<&2, String>, +wf: String, +ref: String) -> Bool:
  String.eq(Api.f(row, "event"), "workflow_dispatch") && dispatch.workflow(row, wf) && ref.same(Api.f(row, "branch"), ref)

# at or after t0, compared as instants: Gitea stamps carry a local offset
def since.after(m: Maybe<&2, U32>, +t0: U32) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{then}:
      U32.is_le(t0, then)

# the run this dispatch made: same workflow, a dispatch event, the ref asked for,
# and it appeared at or after the instant noted before the POST
def dispatch.hit(+row: Map<&2, String>, +when: String, +wf: String, +ref: String, +t0: U32) -> Bool:
  dispatch.mine(row, wf, ref) && since.after(Time.parse(when), t0)

# one look's outcome: the url of the run the dispatch made, or none yet
type Search is Data:
  Found{url: String}
  Missing{}

def dispatch.take(hit: Bool, +row: Map<&2, String>, rest: Search) -> Search:
  match hit:
    case True{}:
      Found{Api.f(row, "html_url")}
    case False{}:
      rest

# the newest run the dispatch made, Missing{} while none has appeared. A forge
# lists the newest run first, so the first hit wins.
def dispatch.scan(n: Nat, +i: U32, +src: Map<&2, String>, +forge: Ctx.Forge, +now: U32, +wf: String, +ref: String, +t0: U32) -> Search:
  match n:
    case 0n:
      Missing{}
    case 1n+p:
      +prefix = prefix.of("workflow_runs", i)
      +row = run.row(src, prefix, forge, now)
      dispatch.take(dispatch.hit(row, created.at(src, prefix), wf, ref, t0), row, dispatch.scan(p, (i + 1 : U32), src, forge, now, wf, ref, t0))

# the url a look found, "" when it found none
def dispatch.url.of(s: Search) -> String:
  match s:
    case Found{+url}:
      url
    case Missing{}:
      ""

# where the forge lists a workflow's runs in its web UI
def dispatch.page(+forge: Ctx.Forge, +wf: String) -> String:
  match forge:
    case Ctx.Gitea{}:
      "actions?workflow=" ++ Url.encode(wf)
    case Ctx.GitHub{}:
      "actions/workflows/" ++ Url.encode(wf)

# the dispatch endpoint: the workflow file is one segment of the path, encoded like every
# other, so only the file name the API takes (ci.yml, not .github/workflows/ci.yml) fits
def dispatch.path(+wf: String) -> String:
  "actions/workflows/" ++ Url.encode(wf) ++ "/dispatches"

# the error an unsafe workflow file gives, "" when it may go in the path
def dispatch.wf.bad(ok: Bool) -> String:
  match ok:
    case True{}:
      ""
    case False{}:
      "runs dispatch: a workflow file can't have a slash, or be . or .."

# the dispatch was accepted but no run of it is listed yet: say so, and point at
# the workflow's runs instead of naming a run that may belong to someone else
def dispatch.none(+env: Cli.Env, +wf: String) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, a}:
      do IO<Unit>:
        Ui.info(on, "runs dispatch: accepted; its run isn't listed yet")
        done.url(env, dispatch.page(forge.of(repo), wf))

# Gitea and Forgejo have no per-workflow run list, so the repo's dispatch runs,
# newest first, are where the new one shows up
def dispatch.runs(+forge: Ctx.Forge) -> String:
  runs.url(forge, "", "", "20") ++ "&event=workflow_dispatch"

# one look for the run the dispatch made
def dispatch.look(+env: Cli.Env, +wf: String, +ref: String, +t0: U32) -> IO(Search):
  match env:
    case Cli.Env{+repo, +tok, on, json, a}:
      do IO<Search>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, dispatch.runs(forge.of(repo))))
        body : List<&2, U32> <- fetch.body(env, r)
        now : U32 <- Sys.now()
        +src : Map<&2, String> = Api.obj(body)
        IO.pure(Search, dispatch.scan(Api.count(src, "workflow_runs"), 0, src, forge.of(repo), now, wf, ref, t0))

def dispatch.polls() -> Nat:
  5n

# one step per look, so fuel = the looks left. A missing run costs a short wait and
# another look; the run the dispatch made usually shows up by the second.
def dispatch.poll.go(fuel: Nat, +env: Cli.Env, +wf: String, +ref: String, +t0: U32, s: Search) -> IO(Unit):
  match fuel s:
    case 0n _:
      dispatch.none(env, wf)
    case 1n+p Missing{}:
      do IO<Unit>:
        IO.sleep(2000)
        s : Search <- dispatch.look(env, wf, ref, t0)
        dispatch.poll.go(p, env, wf, ref, t0, s)
    case 1n+p Found{+url}:
      IO.print(url)

# the first look is taken before the loop, so a run already listed prints at once
def dispatch.poll(+env: Cli.Env, +wf: String, +ref: String, +t0: U32) -> IO(Unit):
  do IO<Unit>:
    s : Search <- dispatch.look(env, wf, ref, t0)
    dispatch.poll.go(Nat.sub(dispatch.polls(), 1n), env, wf, ref, t0, s)

def dispatch.found(+url: String, empty: Bool) -> Search:
  match empty:
    case True{}:
      Missing{}
    case False{}:
      Found{url}

def dispatch.html.of(+src: Map<&2, String>, good: Bool) -> Search:
  match good:
    case True{}:
      +url = Api.f(src, "html_url")
      dispatch.found(url, String.is_empty(url))
    case False{}:
      Missing{}

# the run GitHub names in its reply to a dispatch, Missing{} when it names none
def dispatch.html(body: List<&2, U32>, +status: U32) -> Search:
  dispatch.html.of(Api.obj(body), U32.is_eq(status, 200))

def dispatch.reply.at(+env: Cli.Env, +status: U32, body: List<&2, U32>, good: Bool) -> IO(Search):
  match good:
    case True{}:
      IO.pure(Search, dispatch.html(body, status))
    case False{}:
      Cli.fail(Search, env, Api.message(status, body))

def dispatch.reply(+env: Cli.Env, r: Api.Reply) -> IO(Search):
  match r:
    case Api.Broke{w}:
      Cli.fail(Search, env, w)
    case Api.Reply{+status, next, body}:
      dispatch.reply.at(env, status, body, Api.ok(status))

# a run the reply named prints at once; without one, the run has to be looked for
def dispatch.print(+env: Cli.Env, +wf: String, +ref: String, +t0: U32, s: Search) -> IO(Unit):
  match s:
    case Found{+url}:
      IO.print(url)
    case Missing{}:
      dispatch.poll(env, wf, ref, t0)

def dispatch(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "runs dispatch", args, ["--ref", "--input"])
        +wf : String <- require.at(env, 1n, "workflow file")
        +bad : String = dispatch.wf.bad(Url.encode.seg.ok(wf))
        Cli.check.if(env, bad, String.is_empty(bad))
        +ref : String = Cli.flag(args, "--ref", "main")
        ks : List<&2, String> = inputs.of(args)
        +forge : Ctx.Forge = forge.of(repo)
        t0 : U32 <- Sys.now()
        r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, dispatch.path(wf)), Some{dispatch.body(ref, ks, forge.github(forge))})
        named : Search <- dispatch.reply(env, r)
        dispatch.print(env, wf, ref, t0, named)

# A selected job uses the job endpoint; --failed uses the run's failed-jobs endpoint.
# Both forges put a run's rerun and rerun-failed-jobs at the same path. A single job does
# not: Gitea nests it under the run (actions/runs/<run>/jobs/<job>/rerun, 1.26 and later),
# GitHub names the job alone (actions/jobs/<job>/rerun).
def rerun.run.path(+id: String, +end: String) -> String:
  "actions/runs/" ++ Url.encode(id) ++ "/" ++ end

def rerun.job.path(+id: String, +job: String, nested: Bool) -> String:
  match nested:
    case True{}:
      "actions/runs/" ++ Url.encode(id) ++ "/jobs/" ++ Url.encode(job) ++ "/rerun"
    case False{}:
      "actions/jobs/" ++ Url.encode(job) ++ "/rerun"

def rerun.path(+forge: Ctx.Forge, +id: String, +job: String, failed: Bool, specific: Bool) -> String:
  match failed specific:
    case f True{}:
      rerun.job.path(id, job, forge.gitea(forge))
    case True{} False{}:
      rerun.run.path(id, "rerun-failed-jobs")
    case False{} False{}:
      rerun.run.path(id, "rerun")

# Gitea has a rerun endpoint from 1.26 on, and answers 404 before that
def rerun.missing.text() -> String:
  "runs rerun: this forge has no rerun API (HTTP 404, needs Gitea >= 1.26)"

# a 404 is a missing API only on Gitea: GitHub answers it for a run or a job that is not
# there, and its own message says so
def missing.api(+forge: Ctx.Forge, +status: U32) -> Bool:
  U32.is_eq(status, 404) && forge.gitea(forge)

def rerun.bad(+env: Cli.Env, +status: U32, body: List<&2, U32>, missing: Bool) -> IO(Unit):
  match missing:
    case True{}:
      Cli.fail(Unit, env, rerun.missing.text())
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def rerun.if(+env: Cli.Env, +status: U32, body: List<&2, U32>, +id: String, +forge: Ctx.Forge, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      done.url(env, "actions/runs/" ++ id)
    case False{}:
      rerun.bad(env, status, body, missing.api(forge, status))

def rerun.check(+env: Cli.Env, r: Api.Reply, +id: String, +forge: Ctx.Forge) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      rerun.if(env, status, body, id, forge, Api.ok(status))

def rerun.post(+env: Cli.Env, +forge: Ctx.Forge, +id: String, +job: String, +failed: Bool) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, a}:
      do IO<Unit>:
        r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, rerun.path(forge, id, job, failed, Bool.not(String.is_empty(job)))), None{})
        rerun.check(env, r, id, forge)

def rerun.job.check(+env: Cli.Env, +forge: Ctx.Forge, +id: String, +job: String, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      rerun.post(env, forge, id, job, False{})
    case False{}:
      Cli.fail(Unit, env, "runs rerun: job does not belong to run " ++ id)

# the job's record, read before its rerun. A Gitea below 1.26 has no rerun API, so the read
# itself is a 404 there, and it says what a 404 from the endpoint says.
def rerun.job.body.if(+env: Cli.Env, +status: U32, body: List<&2, U32>, +forge: Ctx.Forge, missing: Bool, good: Bool) -> IO(List<&2, U32>):
  match missing good:
    case True{} _:
      Cli.fail(List<&2, U32>, env, rerun.missing.text())
    case False{} True{}:
      IO.pure(List<&2, U32>, body)
    case False{} False{}:
      Cli.fail(List<&2, U32>, env, Api.message(status, body))

def rerun.job.body(+env: Cli.Env, +forge: Ctx.Forge, r: Api.Reply) -> IO(List<&2, U32>):
  match r:
    case Api.Broke{w}:
      Cli.fail(List<&2, U32>, env, w)
    case Api.Reply{+status, next, body}:
      rerun.job.body.if(env, status, body, forge, missing.api(forge, status), Api.ok(status))

def rerun.selected(+env: Cli.Env, +forge: Ctx.Forge, +id: String, +job: String, +failed: Bool, specific: Bool) -> IO(Unit):
  match env specific:
    case Cli.Env{repo, tok, on, json, a} False{}:
      rerun.post(env, forge, id, job, failed)
    case Cli.Env{+repo, +tok, on, json, a} True{}:
      do IO<Unit>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "actions/jobs/" ++ Url.encode(job)))
        b : List<&2, U32> <- rerun.job.body(env, forge, r)
        rerun.job.check(env, forge, id, job, String.eq(Api.f(Api.obj(b), "run_id"), id))

def rerun.valid(+env: Cli.Env, +forge: Ctx.Forge, +id: String, +job: String, +failed: Bool, conflict: Bool) -> IO(Unit):
  match conflict:
    case True{}:
      Cli.fail(Unit, env, "runs rerun: choose either --failed or --job ID")
    case False{}:
      rerun.selected(env, forge, id, job, failed, Bool.not(String.is_empty(job)))

# a --job id becomes a path segment too, so it is digits only when it is given
def rerun.job.ok(+job: String) -> Bool:
  Bool.or(String.is_empty(job), Cli.digits(job))

def rerun.args(+env: Cli.Env, +repo: Ctx.Repo, +id: String, +job: String, +failed: Bool, missing: Bool) -> IO(Unit):
  match missing:
    case True{}:
      Cli.fail(Unit, env, "runs rerun: --job needs a job id")
    case False{}:
      do IO<Unit>:
        Cli.check.if(env, "runs rerun: a job id is digits only, got '" ++ job ++ "'", rerun.job.ok(job))
        rerun.valid(env, forge.of(repo), id, job, failed, failed && Bool.not(String.is_empty(job)))

def rerun(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "runs rerun", args, ["--job", "--failed"])
        +id : String <- require.id(env, 1n)
        +job : String = Cli.flag(args, "--job", "")
        rerun.args(env, repo, id, job, Cli.has(args, "--failed"), Cli.has(args, "--job") && (String.is_empty(job) || String.starts_with(job, "--")))

# Gitea cancels a run from 28 on
def cancel.missing.text() -> String:
  "runs cancel: this forge has no cancel API (HTTP 404, needs Gitea >= 28); cancel it from the web UI"

def cancel.bad(+env: Cli.Env, +status: U32, body: List<&2, U32>, missing: Bool) -> IO(Unit):
  match missing:
    case True{}:
      Cli.fail(Unit, env, cancel.missing.text())
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def cancel.if(+env: Cli.Env, +status: U32, body: List<&2, U32>, +id: String, +forge: Ctx.Forge, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      done.url(env, "actions/runs/" ++ id)
    case False{}:
      cancel.bad(env, status, body, missing.api(forge, status))

def cancel.check(+env: Cli.Env, r: Api.Reply, +id: String, +forge: Ctx.Forge) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      cancel.if(env, status, body, id, forge, Api.ok(status))

def cancel(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "runs cancel", args, [])
        +id : String <- require.id(env, 1n)
        +forge : Ctx.Forge = forge.of(repo)
        r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, "actions/runs/" ++ id ++ "/cancel"), None{})
        cancel.check(env, r, id, forge)

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

def workflow.page(+next: String, body: List<&2, U32>, acc: List<&2, Wf>) -> WorkflowPages:
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
        b : List<&2, U32> <- ok.body(env, status, body, Api.ok(status))
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

def list.page(+env: Cli.Env, +forge: Ctx.Forge, +now: U32, +wanted: List<&2, String>, +limit: Nat, +next: String, +fallback: String, +seen: Nat, body: List<&2, U32>, acc: List<&2, Map<&2, String>>) -> RunPages:
  +src = Api.obj(body)
  +rows = rows.of(src, "workflow_runs", forge, now)
  +count = Nat.add(seen, List.length(&2, Map<&2, String>, rows))
  +url = page.next(next, fallback, count, Api.f(src, "total_count"), Nat.is_eq(List.length(&2, Map<&2, String>, rows), 0n))
  +got = List.append(&2, Map<&2, String>, acc, list.keep(rows, wanted))
  NextRuns{String.is_empty(url) || Nat.is_ge(List.length(&2, Map<&2, String>, got), limit), url, count, List.take(&2, Map<&2, String>, got, limit)}

def list.walk(fuel: Nat, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +now: U32, +wanted: List<&2, String>, +limit: Nat, +rest: String, +page: U32, +seen: Nat, st: RunPages) -> IO(List<&2, Map<&2, String>>):
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
        b : List<&2, U32> <- ok.body(env, status, body, Api.ok(status))
        list.walk(p, env, repo, tok, now, wanted, limit, rest, page, seen, list.page(env, forge.of(repo), now, wanted, limit, next, Api.path(repo, runs.at(rest, (page + 1 : U32))), seen, b, acc))
    case 1n+p NextRuns{True{}, url, n, acc}:
      IO.pure(List<&2, Map<&2, String>>, acc)
    case 1n+p NextRuns{False{}, url, n, acc}:
      list.walk(p, env, repo, tok, now, wanted, limit, rest, (page + 1 : U32), n, FetchRuns{url, acc})

def list(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "runs list", args, ["--limit", "--workflow", "--branch", "--status", "--json"])
        +limit : Nat <- list.limit(env, U32.read(Cli.flag(args, "--limit", "20")))
        +now : U32 <- Sys.now()
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
