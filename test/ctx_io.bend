import Base
import ../src/ctx.bend as Ctx

def show(m: Maybe<&2, Ctx.Repo>) -> String:
  match m:
    case None{}:
      "no repo"
    case Some{Ctx.Repo{f, h, o, n}}:
      h ++ " " ++ o ++ "/" ++ n

def tok(m: Maybe<&2, Ctx.Repo>) -> IO(String):
  match m:
    case None{}:
      IO.pure(String, "")
    case Some{r}:
      Ctx.token(r)

def main() -> IO(Unit):
  do IO<Unit>:
    +cfg : String <- Ctx.git_config()
    +repo : Maybe<&2, Ctx.Repo> = Ctx.parse_remote(Ctx.origin_url(cfg))
    IO.print(show(repo))
    t : String <- tok(repo)
    IO.print("token chars: " ++ Nat.show(String.length(t)))
