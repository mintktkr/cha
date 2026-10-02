# cha auth status: which host, which login, and where the token came from. Never the token.
import Base
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli

def forge.name(f: Ctx.Forge) -> String:
  match f:
    case Ctx.GitHub{}:
      "github"
    case Ctx.Gitea{}:
      "gitea"

def row.of(+repo: Ctx.Repo, +login: String, +source: String) -> Map<&2, String>:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      m = Map.new(&2, String)
      m = Map.set(&2, String, m, "host", h)
      m = Map.set(&2, String, m, "forge", forge.name(f))
      m = Map.set(&2, String, m, "login", login)
      Map.set(&2, String, m, "token_source", source)

def fields() -> List<&2, String>:
  ["host", "forge", "login", "token_source"]

def text(+on: Bool, +x: Map<&2, String>) -> String:
  +login = Api.f(x, "login")
  Ui.bold(on, Api.f(x, "host")) ++ "  " ++ Ui.dim(on, Api.f(x, "forge")) ++ "\n" ++
  "login  " ++ Ctx.or.if(Ui.fg(on, Ui.mint(), login), Ui.dim(on, "-"), String.is_empty(login)) ++ "\n" ++
  "token  " ++ Api.f(x, "token_source") ++ "\n"

def out(+on: Bool, json: Cli.Json, +x: Map<&2, String>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(text(on, x))
    case j:
      Cli.json.emit(on, j, [x], fields())

# exit 1 when there is no usable token, so scripts can test it
def verdict(+env: Cli.Env, +why: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Cli.fail(Unit, env, why)

def login.of(+status: U32, body: Bytes.Bytes, good: Bool) -> String:
  match good:
    case True{}:
      Api.f(Api.obj(body), "login")
    case False{}:
      ""

def rejected(+status: U32) -> String:
  "auth status: the forge refused the token (HTTP " ++ U32.show(status) ++ ")"

def ask(+env: Cli.Env, +source: String, r: Api.Reply) -> IO(Unit):
  match env r:
    case Cli.Env{+repo, t, +on, json, a} Api.Reply{+status, n, body}:
      +login = login.of(status, body, Api.ok(status))
      do IO<Unit>:
        out(on, json, row.of(repo, login, source))
        verdict(env, rejected(status), Bool.not(String.is_empty(login)))
    case e Api.Broke{w}:
      Cli.fail(Unit, e, w)

def check(+env: Cli.Env, +source: String, none: Bool) -> IO(Unit):
  match env none:
    case Cli.Env{+repo, t, +on, json, a} True{}:
      do IO<Unit>:
        out(on, json, row.of(repo, "", source))
        verdict(env, "auth status: no token; set CHA_TOKEN or add the host to ~/.git-credentials", False{})
    case Cli.Env{+repo, +tok, on, json, a} False{}:
      do IO<Unit>:
        r : Api.Reply <- Api.get(repo, tok, "user")
        ask(env, source, r)

def status(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, a}:
      do IO<Unit>:
        +source : String <- Ctx.token.source(repo)
        check(env, source, String.is_empty(tok))

def run.sub(+env: Cli.Env, known: Bool) -> IO(Unit):
  match known:
    case True{}:
      status(env)
    case False{}:
      Cli.fail(Unit, env, "auth: try cha auth status")

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      +sub = Cli.arg(args, 0n)
      run.sub(env, String.is_empty(sub) || String.eq(sub, "status"))
