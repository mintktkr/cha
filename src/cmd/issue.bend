# cha issue: list, view, create, comment, edit, close, reopen, labels.
import Base
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli

# list
# ----

# github lists pull requests among issues; they carry a pull_request object
def real.at(+x: Map<&2, String>, rest: List<&2, Map<&2, String>>, keep: Bool) -> List<&2, Map<&2, String>>:
  match keep:
    case True{}:
      x <> rest
    case False{}:
      rest

def real(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      real.at(x, real(rest), String.is_empty(Api.f(x, "pull_request.url")))

# labels joined into one field, for display and --json
def with_labels(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      Map.set(&2, String, x, "labels", Api.join(x, "labels", "name", ",")) <> with_labels(rest)

def line(+on: Bool, +x: Map<&2, String>) -> String:
  +labels = Api.f(x, "labels")
  Ui.bold(on, Ui.fg(on, Ui.aqua(), "#" ++ Api.f(x, "number"))) ++ "  " ++ Ui.state(on, Api.f(x, "state")) ++ "  " ++ Api.f(x, "title") ++ Ctx.or.if("  " ++ Ui.dim(on, "[" ++ labels ++ "]"), "", String.is_empty(labels)) ++ "  " ++ Ui.dim(on, "@" ++ Api.f(x, "user.login"))

def lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      line(on, x) ++ "\n" ++ lines(on, rest)

def forge.of(r: Ctx.Repo) -> Ctx.Forge:
  match r:
    case Ctx.Repo{f, h, o, n}:
      f

def query(f: Ctx.Forge, +state: String, +label: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "issues?type=issues&limit=50&state=" ++ state ++ Ctx.or.if("&labels=" ++ label, "", String.is_empty(label))
    case Ctx.GitHub{}:
      "issues?per_page=100&state=" ++ state ++ Ctx.or.if("&labels=" ++ label, "", String.is_empty(label))

def list.print(+on: Bool, json: Bool, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case True{}:
      IO.print(Cli.json.rows(xs, ["number", "title", "state", "user.login", "labels", "html_url"]))
    case False{}:
      IO.write(lines(on, xs))

def list.show(+env: Cli.Env, r: Result<&1, &1, String, List<&2, Map<&2, String>>>) -> IO(Unit):
  match env r:
    case Cli.Env{repo, tok, +on, json, args} Done{xs}:
      list.print(on, json, with_labels(real(xs)))
    case e Fail{w}:
      Cli.fail(Unit, e, w)

def list.pages(all: Bool) -> Nat:
  match all:
    case True{}:
      100n
    case False{}:
      1n

def list(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(list.pages(Cli.has(args, "--all")), repo, tok, Api.path(repo, query(forge.of(repo), Cli.flag(args, "--state", "open"), Cli.flag(args, "--label", ""))))
        list.show(env, r)

# dispatch
# --------

def run.at(+env: Cli.Env, +sub: String, is_list: Bool) -> IO(Unit):
  match is_list:
    case True{}:
      list(env)
    case False{}:
      Cli.fail(Unit, env, "issue " ++ sub ++ ": not yet")

def run.sub(+env: Cli.Env, +sub: String) -> IO(Unit):
  run.at(env, sub, String.eq(sub, "list") || String.is_empty(sub))

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      run.sub(env, Cli.arg(args, 0n))
