# cha mirror: whether a repo is a pull mirror, what it pushes to, and a sync on demand.
#
# Gitea and Forgejo mirror; GitHub has no mirror API at all, so every subcommand stops
# there before a request. A pull mirror's original_url and a push mirror's remote_address
# can both carry a token (https://user:pass@host/...), so they reach a row, the terminal
# or --json only through Ctx.no_credentials.
import Base
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli

# Repo
# ----

def forge.of(r: Ctx.Repo) -> Ctx.Forge:
  match r:
    case Ctx.Repo{f, h, o, n}:
      f

# owner/name, as errors name the repo
def full.name(r: Ctx.Repo) -> String:
  match r:
    case Ctx.Repo{f, h, o, n}:
      o ++ "/" ++ n

def github.msg() -> String:
  "mirror: GitHub has no mirror API"

def not.mirror.msg(+repo: Ctx.Repo) -> String:
  "mirror sync: " ++ full.name(repo) ++ " isn't a pull mirror"

# the endpoints, relative to the repo's API root
def pull.url(r: Ctx.Repo) -> String:
  Api.path(r, "")

def push.url(r: Ctx.Repo) -> String:
  Api.path(r, "push_mirrors")

# GitHub has no mirror endpoints: refuse here, before any request
def github.check(+env: Cli.Env, f: Ctx.Forge) -> IO(Unit):
  match f:
    case Ctx.GitHub{}:
      Cli.fail(Unit, env, github.msg())
    case Ctx.Gitea{}:
      IO.pure(Unit, Unit{})

# Replies
# -------

# the reply's body when the status was ok, failing the command otherwise
def body.of(+env: Cli.Env, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Bytes.Bytes):
  match good:
    case True{}:
      IO.pure(Bytes.Bytes, body)
    case False{}:
      Cli.fail(Bytes.Bytes, env, Api.message(status, body))

def body.reply(+env: Cli.Env, r: Api.Reply) -> IO(Bytes.Bytes):
  match r:
    case Api.Broke{why}:
      Cli.fail(Bytes.Bytes, env, why)
    case Api.Reply{+status, +next, body}:
      body.of(env, status, body, Api.ok(status))

# a reply that carries nothing worth printing: fail on anything but 2xx
def check.ok.if(+env: Cli.Env, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def check.ok(+env: Cli.Env, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{why}:
      Cli.fail(Unit, env, why)
    case Api.Reply{+status, +next, body}:
      check.ok.if(env, status, body, Api.ok(status))

# Rows
# ----
# One flat row per mirror, pull or push, so the text printer and --json read one shape.

# a flattened JSON bool, which Api renders as "true" or "false"
def mirrored(+x: Map<&2, String>) -> Bool:
  String.eq(Api.raw.f(x, "mirror"), "true")

def row.of(+kind: String, +address: String, +interval: String, +updated: String, +error: String) -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "kind", kind)
  m = Map.set(&2, String, m, "address", Ctx.no_credentials(address))
  m = Map.set(&2, String, m, "interval", interval)
  m = Map.set(&2, String, m, "updated", updated)
  Map.set(&2, String, m, "error", error)

def pull.rows.if(+x: Map<&2, String>, mirrored: Bool) -> List<&2, Map<&2, String>>:
  match mirrored:
    case True{}:
      [row.of("pull", Api.raw.f(x, "original_url"), Api.raw.f(x, "mirror_interval"), Api.raw.f(x, "mirror_updated"), "")]
    case False{}:
      Nil{}

# the pull mirror of a repo object: one row, or none when the repo isn't one
def pull.rows(+x: Map<&2, String>) -> List<&2, Map<&2, String>>:
  pull.rows.if(x, mirrored(x))

def push.row(+x: Map<&2, String>) -> Map<&2, String>:
  row.of("push", Api.raw.f(x, "remote_address"), Api.raw.f(x, "interval"), Api.raw.f(x, "last_update"), Api.raw.f(x, "last_error"))

def push.rows(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      push.row(x) <> push.rows(rest)

def fields() -> List<&2, String>:
  ["kind", "address", "interval", "updated", "error"]

# Text
# ----

def every.if(+v: String, empty: Bool) -> String:
  Ctx.or.if("  every " ++ v, "", empty)

def updated.if(+v: String, empty: Bool) -> String:
  Ctx.or.if("  updated " ++ v, "", empty)

def error.if(+on: Bool, +v: String) -> String:
  Ctx.or.if("  " ++ Ui.fg(on, Ui.pink(), "error: " ++ v), "", String.is_empty(v))

# kind mint when it synced clean, pink when its last sync failed
def kind.of(+on: Bool, +k: String, failed: Bool) -> String:
  match failed:
    case True{}:
      Ui.fg(on, Ui.pink(), k ++ " mirror")
    case False{}:
      Ui.fg(on, Ui.mint(), k ++ " mirror")

def kind(+on: Bool, +row: Map<&2, String>) -> String:
  kind.of(on, Api.f(row, "kind"), Bool.not(String.is_empty(Api.f(row, "error"))))

def line(+on: Bool, +row: Map<&2, String>) -> String:
  kind(on, row) ++ "  " ++ Api.f(row, "address") ++
  every.if(Api.f(row, "interval"), String.is_empty(Api.f(row, "interval"))) ++
  updated.if(Api.f(row, "updated"), String.is_empty(Api.f(row, "updated"))) ++
  error.if(on, Api.f(row, "error"))

def lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      line(on, x) ++ "\n" ++ lines(on, rest)

# a repo that isn't a pull mirror says so, since no pull row would say nothing at all
def absent.text(+on: Bool, pull: Bool) -> String:
  match pull:
    case True{}:
      ""
    case False{}:
      Ui.dim(on, "not a pull mirror") ++ "\n"

def status.text(+on: Bool, +pull: Bool, xs: List<&2, Map<&2, String>>) -> String:
  absent.text(on, pull) ++ lines(on, xs)

def status.out(+on: Bool, json: Cli.Json, +pull: Bool, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(status.text(on, pull, xs))
    case j:
      Cli.json.emit(on, j, xs, fields())

# Commands
# --------

# listing push mirrors needs admin rights, so a 401 or 403 on them says the pull mirror is
# all this repo will show, instead of failing the whole command
def denied.msg() -> String:
  "push mirrors need admin rights on this repo"

def denied(+status: U32) -> Bool:
  Bool.or(U32.is_eq(status, 401), U32.is_eq(status, 403))

def denied.list(+on: Bool) -> IO(List<&2, Map<&2, String>>):
  do IO<List<&2, Map<&2, String>>>:
    Ui.info(on, denied.msg())
    IO.pure(List<&2, Map<&2, String>>, Nil{})

def push.read.bad(+env: Cli.Env, +on: Bool, +status: U32, body: Bytes.Bytes, refused: Bool) -> IO(List<&2, Map<&2, String>>):
  match refused:
    case True{}:
      denied.list(on)
    case False{}:
      Cli.fail(List<&2, Map<&2, String>>, env, Api.message(status, body))

def push.read.if(+env: Cli.Env, +on: Bool, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(List<&2, Map<&2, String>>):
  match good:
    case True{}:
      IO.pure(List<&2, Map<&2, String>>, push.rows(Api.rows(body)))
    case False{}:
      push.read.bad(env, on, status, body, denied(status))

def push.read(+env: Cli.Env, +on: Bool, r: Api.Reply) -> IO(List<&2, Map<&2, String>>):
  match r:
    case Api.Broke{why}:
      Cli.fail(List<&2, Map<&2, String>>, env, why)
    case Api.Reply{+status, +next, body}:
      push.read.if(env, on, status, body, Api.ok(status))

# status: the repo's own object says whether it is a pull mirror; push_mirrors lists the
# mirrors it pushes to
def status(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "mirror status", args, ["--json"])
        github.check(env, forge.of(repo))
        r1 : Api.Reply <- Api.get(repo, tok, pull.url(repo))
        b1 : Bytes.Bytes <- body.reply(env, r1)
        r2 : Api.Reply <- Api.get(repo, tok, push.url(repo))
        +pushs : List<&2, Map<&2, String>> <- push.read(env, on, r2)
        +x : Map<&2, String> = Api.obj(b1)
        +pulls : List<&2, Map<&2, String>> = pull.rows(x)
        +xs : List<&2, Map<&2, String>> = List.concat(&2, Map<&2, String>, [pulls, pushs])
        status.out(on, json, Bool.not(List.is_empty(&2, Map<&2, String>, pulls)), xs)

# sync: POST mirror-sync, but only once the repo has said it is a pull mirror, so a repo
# that isn't one gets a sentence instead of the forge's bare 400
def sync.post(+env: Cli.Env, +repo: Ctx.Repo) -> IO(Unit):
  match env:
    case Cli.Env{r, +tok, on, json, a}:
      do IO<Unit>:
        got : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, "mirror-sync"), None{})
        check.ok(env, got)
        Ui.done(on, "asked " ++ full.name(repo) ++ " to sync")

def sync.if(+env: Cli.Env, +repo: Ctx.Repo, mirrored: Bool) -> IO(Unit):
  match mirrored:
    case True{}:
      sync.post(env, repo)
    case False{}:
      Cli.fail(Unit, env, not.mirror.msg(repo))

def sync.read(+env: Cli.Env, r: Api.Reply, +repo: Ctx.Repo) -> IO(Unit):
  match r:
    case Api.Broke{why}:
      Cli.fail(Unit, env, why)
    case Api.Reply{+status, +next, body}:
      do IO<Unit>:
        b : Bytes.Bytes <- body.of(env, status, body, Api.ok(status))
        sync.if(env, repo, mirrored(Api.obj(b)))

def sync(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, +json, +args}:
      do IO<Unit>:
        Cli.check(env, "mirror sync", args, [])
        github.check(env, forge.of(repo))
        r : Api.Reply <- Api.get(repo, tok, pull.url(repo))
        sync.read(env, r, repo)

# push-sync: POST push_mirrors-sync. A repo with no push mirror has nothing to do, and the
# forge answers that with a 2xx.
def push.sync(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, +json, +args}:
      do IO<Unit>:
        Cli.check(env, "mirror push-sync", args, [])
        github.check(env, forge.of(repo))
        got : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, "push_mirrors-sync"), None{})
        check.ok(env, got)
        Ui.done(on, "asked " ++ full.name(repo) ++ " to push")

# dispatch
# --------

def names() -> List<&2, String>:
  ["status", "sync", "push-sync"]

def index.at(eq: Bool, +i: Nat, +later: Nat) -> Nat:
  match eq:
    case True{}:
      i
    case False{}:
      later

# the subcommand's index in names(), or the list's length when unknown
def index(xs: List<&2, String>, +w: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case Con{x, rest}:
      index.at(String.eq(x, w), i, index(rest, w, 1n+i))

def run.at(+env: Cli.Env, n: Nat) -> IO(Unit):
  match n:
    case 0n:
      status(env)
    case 1n:
      sync(env)
    case 2n:
      push.sync(env)
    case 3n+k:
      Cli.fail(Unit, env, "mirror: unknown subcommand, try cha help")

def run.sub(+env: Cli.Env, +sub: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      status(env)
    case False{}:
      run.at(env, index(names(), sub, 0n))

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      +sub : String = Cli.arg(args, 0n)
      run.sub(env, sub, String.is_empty(sub))
