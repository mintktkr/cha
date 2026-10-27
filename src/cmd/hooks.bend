# cha hooks: a repo's or an org's webhooks: list, create, delete, test.
import Base
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli
import ../url.bend as Url
import ../hooks.bend as Hooks

# Endpoints
# ---------

# where a repo's or an org's hooks live: an org's when --org named one, else the repo's.
# --org is encoded, so "a/../b" can't climb to another endpoint.
def endpoint(+org: String, +owner: String, +name: String) -> String:
  Ctx.or.if("orgs/" ++ Url.encode(org) ++ "/hooks", "repos/" ++ owner ++ "/" ++ name ++ "/hooks", String.is_empty(org))

def forge.of(+repo: Ctx.Repo) -> Ctx.Forge:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      f

# one page's query. GitHub pages with per_page and links the next page itself. Gitea 1.25
# ignores limit unless page is sent, so the walk follows Link where there is one and the
# first page is all there is otherwise.
def query(f: Ctx.Forge) -> String:
  match f:
    case Ctx.Gitea{}:
      "?limit=1000"
    case Ctx.GitHub{}:
      "?per_page=100"

def url.of(+repo: Ctx.Repo, +org: String) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      endpoint(org, o, n) ++ query(f)

# one hook's endpoint; a test delivery is this plus "/tests"
def hook.url(+repo: Ctx.Repo, +org: String, +id: String) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      endpoint(org, o, n) ++ "/" ++ id

# Requests
# --------

def body.of(+env: Cli.Env, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Bytes.Bytes):
  match good:
    case True{}:
      IO.pure(Bytes.Bytes, body)
    case False{}:
      Cli.fail(Bytes.Bytes, env, Api.message(status, body))

# a reply's body, or the command fails with the forge's error
def body.reply(+env: Cli.Env, r: Api.Reply) -> IO(Bytes.Bytes):
  match r:
    case Api.Broke{why}:
      Cli.fail(Bytes.Bytes, env, why)
    case Api.Reply{+status, +next, body}:
      body.of(env, status, body, Api.ok(status))

# Create body
# -----------
# GitHub calls a hook's kind "name" and a webhook "web"; Gitea and Forgejo call it "type"
# and "gitea". Forgejo's swagger lists both "forgejo" and "gitea" in that enum, and cha
# speaks to Gitea and Forgejo as one forge, so "gitea" is the type that works on both.

def kind.key(f: Ctx.Forge) -> String:
  match f:
    case Ctx.GitHub{}:
      "name"
    case Ctx.Gitea{}:
      "type"

def kind.value(f: Ctx.Forge) -> String:
  match f:
    case Ctx.GitHub{}:
      "web"
    case Ctx.Gitea{}:
      "gitea"

def kv.if(kvs: List<&1, Bytes.Bytes & Json.Val>, +k: String, +v: String, keep: Bool) -> List<&1, Bytes.Bytes & Json.Val>:
  match keep:
    case True{}:
      Con{(Json.utf8(k), Api.utf8(v)), kvs}
    case False{}:
      kvs

# the hook's config: its target, its payload format, and the secret when --secret-file
# gave one. Both forges take these three under config.
def config.kvs(+url: String, +ct: String, +secret: String) -> List<&1, Bytes.Bytes & Json.Val>:
  k0 : List<&1, Bytes.Bytes & Json.Val> = kv.if(Nil{}, "secret", secret, Bool.not(String.is_empty(secret)))
  Con{(Json.utf8("url"), Api.utf8(url)), Con{(Json.utf8("content_type"), Api.utf8(ct)), k0}}

def event.vals(xs: List<&2, String>) -> List<&1, Json.Val>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      Con{Api.utf8(x), event.vals(rest)}

# the events are passed through as given: GitHub and Gitea name most of them alike
# (push, pull_request) and cha doesn't try to translate the rest
def create.body(+f: Ctx.Forge, +url: String, +events: List<&2, String>, +ct: String, +secret: String) -> Json.Val:
  k0 : List<&1, Bytes.Bytes & Json.Val> = Con{(Json.utf8("config"), Json.Obj{config.kvs(url, ct, secret)}), Nil{}}
  k1 : List<&1, Bytes.Bytes & Json.Val> = Con{(Json.utf8("events"), Json.Arr{event.vals(events)}), k0}
  k2 : List<&1, Bytes.Bytes & Json.Val> = Con{(Json.utf8("active"), Json.Flag{True{}}), k1}
  Json.Obj{Con{(Json.utf8(kind.key(f)), Api.utf8(kind.value(f))), k2}}

# Secret
# ------
# A hook's secret signs its deliveries. It is read from a file, never from a flag value,
# and it only ever goes into the request body: it never reaches a row, a message or --json.

# the secret a source held, its surrounding whitespace dropped, or the command failing
# when it can't be read or is over 1 MiB
def secret.at(+env: Cli.Env, +path: String, t: Cli.Text) -> IO(String):
  match t:
    case Cli.TextOf{+s}:
      IO.pure(String, String.trim(s))
    case Cli.TextNone{}:
      Cli.fail(String, env, "hooks create: can't read " ++ path)
    case Cli.TextOver{}:
      Cli.fail(String, env, "hooks create: the secret file is over 1 MiB")

def secret.if(+env: Cli.Env, +path: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      IO.pure(String, "")
    case False{}:
      do IO<String>:
        +p : String = Ctx.or.if(path, "/dev/stdin", String.eq(path, "-"))
        t : Cli.Text <- Cli.file.text(p)
        secret.at(env, p, t)

# the secret from --secret-file PATH ("-" is stdin), or "" when the flag is absent.
# A file's trailing whitespace comes from the editor or the echo, not from the secret.
def secret.read(+env: Cli.Env, +path: String) -> IO(String):
  secret.if(env, path, String.is_empty(path))

# Rows
# ----

# one hook as the flat row every output reads. The hook is redacted first, so its secret
# is gone before anything prints the row or hands it to --json. Its target is config.url:
# the hook's own url field is the API path of the hook, not where deliveries go.
def hook.row(x: Map<&2, String>) -> Map<&2, String>:
  +src = Hooks.row.redact(x)
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "id", Api.raw.f(src, "id"))
  m = Map.set(&2, String, m, "url", Api.raw.f(src, "config.url"))
  m = Map.set(&2, String, m, "events", Api.raw.join(src, "events", "", ","))
  m = Map.set(&2, String, m, "active", Api.raw.f(src, "active"))
  Map.set(&2, String, m, "content_type", Api.raw.f(src, "config.content_type"))

def rows.of(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, rest}:
      Con{hook.row(x), rows.of(rest)}

# Text
# ----

# a flattened JSON bool, which Api renders as "true" or "false"
def bool.f(+x: Map<&2, String>, +k: String) -> Bool:
  String.eq(Api.f(x, k), "true")

# "  active" in mint, "  disabled" dim
def active.text(+on: Bool, yes: Bool) -> String:
  match yes:
    case True{}:
      "  " ++ Ui.fg(on, Ui.mint(), "active")
    case False{}:
      "  " ++ Ui.dim(on, "disabled")

# s with pre in front of it, unless s is empty
def prefixed(+s: String, +pre: String) -> String:
  Ctx.or.if(pre ++ s, "", String.is_empty(s))

def line(+on: Bool, +row: Map<&2, String>) -> String:
  Ui.bold(on, Ui.fg(on, Ui.aqua(), "#" ++ Api.f(row, "id"))) ++ "  " ++
  Api.f(row, "url") ++ "  " ++
  Api.f(row, "events") ++
  active.text(on, bool.f(row, "active")) ++
  prefixed(Api.f(row, "content_type"), "  ")

def lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, rest}:
      line(on, x) ++ "\n" ++ lines(on, rest)

def fields() -> List<&2, String>:
  ["id", "url", "events", "active", "content_type"]

def emit(+on: Bool, json: Cli.Json, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(lines(on, xs))
    case j:
      Cli.json.emit(on, j, xs, fields())

# Ids
# ---

def id.bad.msg(+what: String, +raw: String) -> String:
  what ++ ": expected a hook id, got '" ++ raw ++ "'"

def id.empty.msg(+what: String) -> String:
  what ++ ": give a hook id"

def id.check.if(+env: Cli.Env, +what: String, +raw: String, bad: Bool) -> IO(String):
  match bad:
    case True{}:
      Cli.fail(String, env, id.bad.msg(what, raw))
    case False{}:
      IO.pure(String, raw)

def id.need.if(+env: Cli.Env, +what: String, +raw: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      Cli.fail(String, env, id.empty.msg(what))
    case False{}:
      id.check.if(env, what, raw, Bool.not(Hooks.id.ok(raw)))

# a hook id that may go into a path: digits only, never empty
def id.need(+env: Cli.Env, +raw: String, +what: String) -> IO(String):
  id.need.if(env, what, raw, String.is_empty(raw))

# Command
# -------

def need(+env: Cli.Env, bad: Bool, +msg: String) -> IO(Unit):
  match bad:
    case True{}:
      Cli.fail(Unit, env, msg)
    case False{}:
      IO.pure(Unit, Unit{})

def show(+env: Cli.Env, r: Result<&1, &1, String, List<&2, Map<&2, String>>>) -> IO(Unit):
  match env r:
    case Cli.Env{r, t, +on, json, a} Done{xs}:
      emit(on, json, rows.of(xs))
    case e Fail{w}:
      Cli.fail(Unit, e, w)

def list(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "hooks", args, ["--org", "--json"])
        +org : String = Cli.flag(args, "--org", "")
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(10n, repo, tok, url.of(repo, org))
        show(env, r)

# --content-type is one of the two payload formats both forges take
def ct.ok(+ct: String) -> Bool:
  String.eq(ct, "json") || String.eq(ct, "form")

def ct.need.if(+env: Cli.Env, +ct: String, ok: Bool) -> IO(String):
  match ok:
    case True{}:
      IO.pure(String, ct)
    case False{}:
      Cli.fail(String, env, "hooks create: --content-type takes json or form, not '" ++ ct ++ "'")

def ct.need(+env: Cli.Env, +ct: String) -> IO(String):
  ct.need.if(env, ct, ct.ok(ct))

# a created hook: "#id  url" on stdout, a mint ✓ line on stderr
def created(+env: Cli.Env, +id: String, +url: String) -> IO(Unit):
  match env:
    case Cli.Env{r, t, +on, j, a}:
      do IO<Unit>:
        IO.print("#" ++ id ++ "  " ++ url)
        Ui.done(on, "created hook #" ++ id)

def create.send(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +org: String, +target: String, +events: List<&2, String>, +ct: String, +secret: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.send(repo, tok, "POST", url.of(repo, org), Some{create.body(forge.of(repo), target, events, ct, secret)})
    b : Bytes.Bytes <- body.reply(env, r)
    +x : Map<&2, String> = Hooks.row.redact(Api.obj(b))
    created(env, Api.f(x, "id"), Api.f(x, "config.url"))

def create(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "hooks create", args, ["--events", "--secret-file", "--content-type", "--org"])
        +target : String = Cli.arg(args, 1n)
        need(env, String.is_empty(target), "hooks create: a webhook URL is required")
        +ev : String = Cli.flag(args, "--events", "")
        need(env, String.is_empty(ev), "hooks create: --events is required, like push,pull_request")
        +org : String = Cli.flag(args, "--org", "")
        ct : String <- ct.need(env, Cli.flag(args, "--content-type", "json"))
        secret : String <- secret.read(env, Cli.flag(args, "--secret-file", ""))
        create.send(env, repo, tok, org, target, Cli.split.fields(ev), ct, secret)

# Delete
# ------

# cha never prompts: it can't tell whether stdin is a terminal, so a delete always needs
# --yes and says what it would delete without it, before it builds a request
def yes.msg(+id: String) -> String:
  "hooks delete: would delete hook #" ++ id ++ "; rerun with --yes"

def yes.need.if(+env: Cli.Env, +id: String, yes: Bool) -> IO(Unit):
  match yes:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Cli.fail(Unit, env, yes.msg(id))

def delete.if(+env: Cli.Env, +id: String, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Unit):
  match env good:
    case Cli.Env{r, t, +on, j, a} True{}:
      Ui.done(on, "deleted hook #" ++ id)
    case e False{}:
      Cli.fail(Unit, e, Api.message(status, body))

def delete.got(+env: Cli.Env, +id: String, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      delete.if(env, id, status, body, Api.ok(status))

def delete(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "hooks delete", args, ["--org", "--yes"])
        +org : String = Cli.flag(args, "--org", "")
        +id : String <- id.need(env, Cli.arg(args, 1n), "hooks delete")
        yes.need.if(env, id, Cli.has(args, "--yes"))
        r : Api.Reply <- Api.send(repo, tok, "DELETE", hook.url(repo, org, id), None{})
        delete.got(env, id, r)

# Test
# ----

# a test delivery: both forges answer 204 with no body, so exit 0 is the receipt
def test.if(+env: Cli.Env, +id: String, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Unit):
  match env good:
    case Cli.Env{r, t, +on, j, a} True{}:
      Ui.done(on, "sent a test delivery to hook #" ++ id)
    case e False{}:
      Cli.fail(Unit, e, Api.message(status, body))

def test.got(+env: Cli.Env, +id: String, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      test.if(env, id, status, body, Api.ok(status))

def hook.test(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "hooks test", args, ["--org"])
        +org : String = Cli.flag(args, "--org", "")
        +id : String <- id.need(env, Cli.arg(args, 1n), "hooks test")
        r : Api.Reply <- Api.send(repo, tok, "POST", hook.url(repo, org, id) ++ "/tests", None{})
        test.got(env, id, r)

# dispatch
# --------

def names() -> List<&2, String>:
  ["list", "create", "delete", "test"]

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
      list(env)
    case 1n:
      create(env)
    case 2n:
      delete(env)
    case 3n:
      hook.test(env)
    case 4n+k:
      Cli.fail(Unit, env, "hooks: unknown subcommand, try cha help")

def run.sub(+env: Cli.Env, +sub: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      list(env)
    case False{}:
      run.at(env, index(names(), sub, 0n))

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      +sub : String = Cli.arg(args, 0n)
      run.sub(env, sub, String.is_empty(sub))
