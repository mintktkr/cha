# cha runs: list, view, logs, watch, dispatch, rerun, cancel.
import Base
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time
import 0x4eed9d7ac6ece61523d747a9d804e4f0/int.bend as Int

# Reading a flat object
# ----------------------

# field k of an object flattened under prefix; "" when missing. prefix "" is the root.
def g(+src: Map<&2, String>, +prefix: String, +k: String) -> String:
  Api.f(src, Api.key(prefix, k))

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
  state.of(g(src, prefix, "status"), g(src, prefix, "conclusion"), String.eq(g(src, prefix, "status"), "completed"))

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
  Ctx.or.if(pre ++ v, "", String.is_empty(v))

# the list endpoint of a forge's action runs, newest first. Gitea reads limit only
# when a page is asked for, so page=1 is always part of the query.
def runs.url(+forge: Ctx.Forge, +branch: String, +status: String, +limit: String) -> String:
  match forge:
    case Ctx.Gitea{}:
      "actions/runs?page=1&limit=" ++ limit ++ param.q("&branch=", branch) ++ param.q("&status=", status)
    case Ctx.GitHub{}:
      "actions/runs?page=1&per_page=" ++ limit ++ param.q("&branch=", branch) ++ param.q("&status=", status)

def short.if(+s: String, cut: Bool) -> String:
  match cut:
    case True{}:
      String.take(s, 7n)
    case False{}:
      s

# the first seven characters of a sha
def short.sha(+s: String) -> String:
  short.if(s, Nat.is_gt(String.length(s), 7n))

# when a run started: Gitea says started_at, GitHub run_started_at then created_at
def started.at(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge) -> String:
  match forge:
    case Ctx.Gitea{}:
      g(src, prefix, "started_at")
    case Ctx.GitHub{}:
      Ctx.or(g(src, prefix, "run_started_at"), g(src, prefix, "created_at"))

# the workflow's name: Gitea only names the file, GitHub names the workflow
def wf.of(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge) -> String:
  match forge:
    case Ctx.Gitea{}:
      Ctx.first(String.split(g(src, prefix, "path"), '@'))
    case Ctx.GitHub{}:
      g(src, prefix, "name")

def age.at(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge, +now: Time.Instant) -> String:
  age.of.parse(Time.rfc3339.parse(started.at(src, prefix, forge)), now)

# one run, as the flat row every run command reads
def run.row(+src: Map<&2, String>, +prefix: String, +forge: Ctx.Forge, +now: Time.Instant) -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "id", g(src, prefix, "id"))
  m = Map.set(&2, String, m, "run_number", g(src, prefix, "run_number"))
  m = Map.set(&2, String, m, "status", g(src, prefix, "status"))
  m = Map.set(&2, String, m, "conclusion", g(src, prefix, "conclusion"))
  m = Map.set(&2, String, m, "state", state(src, prefix))
  m = Map.set(&2, String, m, "workflow", wf.of(src, prefix, forge))
  m = Map.set(&2, String, m, "branch", g(src, prefix, "head_branch"))
  m = Map.set(&2, String, m, "sha", g(src, prefix, "head_sha"))
  m = Map.set(&2, String, m, "title", Ctx.or(g(src, prefix, "display_title"), wf.of(src, prefix, forge)))
  m = Map.set(&2, String, m, "event", g(src, prefix, "event"))
  m = Map.set(&2, String, m, "started_at", started.at(src, prefix, forge))
  m = Map.set(&2, String, m, "age", age.at(src, prefix, forge, now))
  m = Map.set(&2, String, m, "html_url", g(src, prefix, "html_url"))
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
  ["id", "run_number", "state", "status", "conclusion", "workflow", "branch", "sha", "title", "event", "age", "started_at", "html_url"]

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

def job.row(+src: Map<&2, String>, +prefix: String) -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "id", g(src, prefix, "id"))
  m = Map.set(&2, String, m, "name", g(src, prefix, "name"))
  m = Map.set(&2, String, m, "status", g(src, prefix, "status"))
  m = Map.set(&2, String, m, "conclusion", g(src, prefix, "conclusion"))
  m = Map.set(&2, String, m, "state", state(src, prefix))
  m = Map.set(&2, String, m, "html_url", g(src, prefix, "html_url"))
  m

def jrows.go(n: Nat, +i: U32, +src: Map<&2, String>) -> List<&2, Map<&2, String>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      job.row(src, prefix.of("jobs", i)) <> jrows.go(p, (i + 1 : U32), src)

def jrows.of(+src: Map<&2, String>) -> List<&2, Map<&2, String>>:
  jrows.go(Api.count(src, "jobs"), 0, src)

def job.line(+on: Bool, +row: Map<&2, String>) -> String:
  "  " ++ Api.f(row, "name") ++ "  " ++ Ui.state(on, Api.f(row, "state")) ++ "  " ++ Ui.dim(on, "#" ++ Api.f(row, "id")) ++ "\n"

def job.lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, rest}:
      job.line(on, x) ++ job.lines(on, rest)

def job.fields() -> List<&2, String>:
  ["id", "name", "state", "status", "conclusion", "html_url"]

# which jobs a filter keeps: --job is an id, --failed drops the ones that passed
def want.job(+id: String, +conclusion: String, +job: String, only_failed: Bool) -> Bool:
  Bool.and(Bool.or(String.is_empty(job), String.eq(id, job)), Bool.or(Bool.not(only_failed), failed.labels(conclusion)))

def keep.if(+row: Map<&2, String>, rest: List<&2, Map<&2, String>>, keep: Bool) -> List<&2, Map<&2, String>>:
  match keep:
    case True{}:
      row <> rest
    case False{}:
      rest

def keep.job(+row: Map<&2, String>, rest: List<&2, Map<&2, String>>, +job: String, only_failed: Bool) -> List<&2, Map<&2, String>>:
  keep.if(row, rest, want.job(Api.f(row, "id"), Api.f(row, "conclusion"), job, only_failed))

def keep.go(n: Nat, +i: U32, +src: Map<&2, String>, +job: String, +only_failed: Bool) -> List<&2, Map<&2, String>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      keep.job(job.row(src, prefix.of("jobs", i)), keep.go(p, (i + 1 : U32), src, job, only_failed), job, only_failed)

# view
# ----

def view.json.jobs(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{x, rest}:
      do IO<Unit>:
        IO.print(Cli.json.row(x, job.fields()))
        view.json.jobs(rest)

def view.json(+row: Map<&2, String>, +jobs: List<&2, Map<&2, String>>) -> IO(Unit):
  do IO<Unit>:
    IO.print(Cli.json.row(row, run.fields()))
    view.json.jobs(jobs)

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
        case True{}:
          view.json(row, jobs)
        case False{}:
          IO.write(view.text(on, row, jobs))

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
        jr : Api.Reply <- Api.get(repo, tok, Api.path(repo, "actions/runs/" ++ id ++ "/jobs"))
        jb : Bytes.Bytes <- fetch.body(env, jr)
        view.print(env, row, jrows.of(Api.obj(jb)))

# logs
# ----

def log.nl(+text: String) -> String:
  Ctx.or.if(text ++ "\n", text, String.ends_with(text, "\n"))

def logs.head(+on: Bool, +row: Map<&2, String>) -> String:
  Ui.bold(on, Api.f(row, "name")) ++ "  " ++ Ui.state(on, Api.f(row, "state")) ++ "  " ++ Ui.dim(on, "#" ++ Api.f(row, "id")) ++ "\n"

def logs.one(+env: Cli.Env, +row: Map<&2, String>) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, a}:
      do IO<Unit>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "actions/jobs/" ++ Api.f(row, "id") ++ "/logs"))
        b : Bytes.Bytes <- fetch.body(env, r)
        IO.write(logs.head(on, row) ++ log.nl(Api.text(b)) ++ "\n")

def logs.jobs(+env: Cli.Env, xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{x, rest}:
      do IO<Unit>:
        logs.one(env, x)
        logs.jobs(env, rest)

def logs.miss(+xs: List<&2, Map<&2, String>>, +job: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(job)), Nat.is_eq(List.length(&2, Map<&2, String>, xs), 0n))

def logs.pick.if(+env: Cli.Env, +xs: List<&2, Map<&2, String>>, +job: String, miss: Bool) -> IO(Unit):
  match miss:
    case True{}:
      Cli.fail(Unit, env, "runs logs: no job " ++ job)
    case False{}:
      logs.jobs(env, xs)

def logs(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +id : String <- require.at(env, 1n, "run id")
        +job : String = Cli.flag(args, "--job", "")
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "actions/runs/" ++ id ++ "/jobs"))
        body : Bytes.Bytes <- fetch.body(env, r)
        +js : Map<&2, String> = Api.obj(body)
        +ks : List<&2, Map<&2, String>> = keep.go(Api.count(js, "jobs"), 0, js, job, Cli.has(args, "--failed"))
        logs.pick.if(env, ks, job, logs.miss(ks, job))

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

def tick.of(+src: Map<&2, String>) -> Tick:
  tick.at(state(src, ""), g(src, "", "conclusion"), String.eq(g(src, "", "status"), "completed"))

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

def rerun.post(+env: Cli.Env, +id: String) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, a}:
      do IO<Unit>:
        r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, "actions/runs/" ++ id ++ "/rerun"), None{})
        check.ok(env, r)
        done.url(env, "actions/runs/" ++ id)

def rerun.go(+env: Cli.Env, +forge: Ctx.Forge, +id: String) -> IO(Unit):
  match forge:
    case Ctx.Gitea{}:
      Cli.fail(Unit, env, "runs rerun: this forge has no rerun API; push a commit or rerun from the web UI")
    case Ctx.GitHub{}:
      rerun.post(env, id)

def rerun(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +id : String <- require.at(env, 1n, "run id")
        rerun.go(env, forge.of(repo), id)

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

def list.print(+on: Bool, json: Bool, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case True{}:
      IO.print(Cli.json.rows(xs, run.fields()))
    case False{}:
      IO.write(run.lines(on, xs))

def list(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, runs.url(forge.of(repo), Cli.flag(args, "--branch", ""), Cli.flag(args, "--status", ""), Cli.flag(args, "--limit", "20"))))
        body : Bytes.Bytes <- fetch.body(env, r)
        now : Time.Instant <- Time.now()
        +src : Map<&2, String> = Api.obj(body)
        list.print(on, json, rows.of(src, "workflow_runs", forge.of(repo), now))

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
