import Base
import ../src/ctx.bend as Ctx
import ../src/api.bend as Api

def lines(xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      "#" ++ Api.f(x, "number") ++ " " ++ Api.f(x, "title") ++ " by " ++ Api.f(x, "user.login") ++ " [" ++ Api.join(x, "labels", "name", ", ") ++ "]\n" ++ lines(rest)

def show(r: Result<&1, &1, String, List<&2, Map<&2, String>>>) -> String:
  match r:
    case Done{xs}:
      lines(xs)
    case Fail{w}:
      "error: " ++ w

def main() -> IO(Unit):
  do IO<Unit>:
    +repo : Ctx.Repo = Ctx.Repo{Ctx.Gitea{}, "codeberg.org", "forgejo", "forgejo"}
    r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(3n, repo, "", Api.path(repo, "issues?limit=2&type=issues&state=open"))
    IO.print(show(r))
    e : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(1n, repo, "", Api.path(repo, "nope-not-here"))
    IO.print(show(e))
    +gh : Ctx.Repo = Ctx.Repo{Ctx.GitHub{}, "github.com", "bendlang", "bend"}
    g : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(1n, gh, "", Api.path(gh, "issues?per_page=3"))
    IO.print(show(g))
