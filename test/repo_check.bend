# offline checks for cha repo and cha release: the forge-specific field names, label
# colours and release flags, on synthetic rows. Run: bend test/repo_check.bend
import Base
import ../src/ctx.bend as Ctx
import ../src/api.bend as Api
import ../src/ui.bend as Ui
import ../src/cmd/repo.bend as Repo
import ../src/cmd/release.bend as Rel

def row.put(m: Map<&2, String>, p: String & String) -> Map<&2, String>:
  (k, v) = p
  Map.set(&2, String, m, k, v)

def row.go(ps: List<&1, String & String>, m: Map<&2, String>) -> Map<&2, String>:
  match ps:
    case Nil{}:
      m
    case Con{p, t}:
      row.go(t, row.put(m, p))

# a row as Api.rows flattens one
def row.of(ps: List<&1, String & String>) -> Map<&2, String>:
  row.go(ps, Map.new(&2, String))

def gitea.public() -> Map<&2, String>:
  row.of([("full_name", "example/sandbox"), ("private", "false"), ("internal", "false"), ("stars_count", "3"), ("forks_count", "1"), ("open_issues_count", "2")])

def gitea.private() -> Map<&2, String>:
  row.of([("full_name", "example/secret"), ("private", "true"), ("internal", "false"), ("stars_count", "0")])

def github() -> Map<&2, String>:
  row.of([("full_name", "example/bend"), ("visibility", "public"), ("stargazers_count", "9")])

def view.show(+x: Map<&2, String>) -> String:
  Api.f(x, "forge") ++ " " ++ Api.f(x, "visibility") ++ " stars=" ++ Api.f(x, "stars") ++ " " ++ Api.f(x, "full_name")

def rgb.show(+c: String, m: Maybe<&2, Ui.Rgb>) -> String:
  match m:
    case Some{Ui.Rgb{r, g, b}}:
      c ++ " = " ++ U32.show(r) ++ "," ++ U32.show(g) ++ "," ++ U32.show(b)
    case None{}:
      c ++ " = none"

def release.demo() -> Map<&2, String>:
  row.of([("tag_name", "v1"), ("published_at", ""), ("created_at", "2026-01-02T03:04:05Z"), ("draft", "false"), ("prerelease", "true")])

def drops() -> String:
  String.join(Rel.flag.drop(Rel.flag.drop(["release", "create", "--draft", "v1", "--prerelease"], "--draft"), "--prerelease"), " ")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(view.show(Repo.view.row(Ctx.Gitea{}, gitea.public())))
    IO.print(view.show(Repo.view.row(Ctx.Gitea{}, gitea.private())))
    IO.print(view.show(Repo.view.row(Ctx.GitHub{}, github())))
    IO.print(rgb.show("#ff6eb4", Repo.color.rgb("#ff6eb4")))
    IO.print(rgb.show("#zzz", Repo.color.rgb("#zzz")))
    IO.print("published=" ++ Api.f(Rel.release.row(release.demo()), "published"))
    IO.print("flags=" ++ Rel.release.flags(False{}, release.demo()))
    IO.print("tag scan=" ++ drops())
