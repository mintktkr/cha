# cha 茶: a forge CLI for Gitea, Forgejo and GitHub.
import Base
import ./src/ctx.bend as Ctx
import ./src/ui.bend as Ui
import ./src/cli.bend as Cli
import ./src/help.bend as Help
import ./src/cmd/issue.bend as Issue
import ./src/cmd/pr.bend as Pr
import ./src/cmd/runs.bend as Runs
import ./src/cmd/repo.bend as RepoCmd
import ./src/cmd/release.bend as Release
import ./src/cmd/moved.bend as Moved

def version() -> String:
  "0.0.1"

# the command word's index in this list, or its length when unknown
def names() -> List<&2, String>:
  ["issue", "pr", "runs", "repo", "release", "moved", "help", "version"]

def index.at(eq: Bool, +i: Nat, +later: Nat) -> Nat:
  match eq:
    case True{}:
      i
    case False{}:
      later

def index(xs: List<&2, String>, +w: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case Con{x, rest}:
      index.at(String.eq(x, w), i, index(rest, w, 1n+i))

def dispatch(+env: Cli.Env, n: Nat) -> IO(Unit):
  match n:
    case 0n:
      Issue.run(env)
    case 1n:
      Pr.run(env)
    case 2n:
      Runs.run(env)
    case 3n:
      RepoCmd.run(env)
    case 4n:
      Release.run(env)
    case 5n:
      Moved.run(env)
    case 6n+k:
      Cli.fail(Unit, env, "unknown command, try cha help")

# the command's arguments: everything after the command word
def after(+args: List<&2, String>, +w: String) -> List<&2, String>:
  List.drop(&2, String, args, 1n+index(args, w, 0n))

def go(+on: Bool, +args: List<&2, String>, m: Maybe<&2, Ctx.Repo>, +tok: String, +w: String) -> IO(Unit):
  match m:
    case Some{+repo}:
      dispatch(Cli.Env{repo, tok, on, Cli.has(args, "--json"), after(args, w)}, index(names(), w, 0n))
    case None{}:
      do IO<Unit>:
        Ui.error(on, "no repo here: run inside a checkout, or pass -R owner/repo or -R host/owner/repo")
        IO.die(Unit, 1, "")

def token.of(m: Maybe<&2, Ctx.Repo>) -> IO(String):
  match m:
    case Some{r}:
      Ctx.token(r)
    case None{}:
      IO.pure(String, "")

def repo.pick(+flag: String, +cur: Maybe<&2, Ctx.Repo>, none: Bool) -> Maybe<&2, Ctx.Repo>:
  match none:
    case True{}:
      cur
    case False{}:
      Ctx.flag.repo(flag, cur)

def start(+on: Bool, +args: List<&2, String>, +w: String, simple: Nat) -> IO(Unit):
  match simple:
    case 0n:
      do IO<Unit>:
        +cfg : String <- Ctx.git_config()
        +flag : String = Cli.flag(args, "-R", "")
        +m : Maybe<&2, Ctx.Repo> = repo.pick(flag, Ctx.parse_remote(Ctx.origin_url(cfg)), String.is_empty(flag))
        +tok : String <- token.of(m)
        go(on, args, m, tok, w)
    case 1n:
      Help.run(on, List.drop(&2, String, args, 1n))
    case 2n+k:
      IO.print(version())

# 0: a command that needs a repo; 1: help; 2: version
def simple(+w: String) -> Nat:
  index.at(String.is_empty(w) || String.eq(w, "help") || String.eq(w, "--help") || String.eq(w, "-h"), 1n, index.at(String.eq(w, "version") || String.eq(w, "--version"), 2n, 0n))

# IO.args gives a use-once list; strings are Data, so it can be rebuilt reusable
def share(xs: List<&1, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      x <> share(t)

def main() -> IO(Unit):
  do IO<Unit>:
    argv : List<String> <- IO.args()
    +args : List<&2, String> = List.tail(&2, String, share(argv))
    +on : Bool <- Ui.color()
    +w : String = Ctx.first(Cli.positional(args))
    start(on, args, w, simple(w))
