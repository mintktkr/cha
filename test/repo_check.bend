# offline checks for cha repo and cha release: the forge-specific field names, label
# colours and release flags, on synthetic rows. Run: bend test/repo_check.bend
import Base
import ../lib/chaki/json.bend as Json
import ../src/ctx.bend as Ctx
import ../src/api.bend as Api
import ../src/cli.bend as Cli
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

# create and delete
# -----------------

def expect.if(+label: String, +got: String, +want: String, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      IO.print("ok   " ++ label)
    case False{}:
      do IO<Unit>:
        IO.print("FAIL " ++ label ++ ": got [" ++ got ++ "] want [" ++ want ++ "]")
        IO.die(Unit, 1, "")

def expect(+label: String, +got: String, +want: String) -> IO(Unit):
  expect.if(label, got, want, String.eq(got, want))

def checkout() -> Ctx.Repo:
  Ctx.Repo{Ctx.GitHub{}, "github.com", "checkout", "repo"}

def repo.text(r: Ctx.Repo) -> String:
  match r:
    case Ctx.Repo{f, +h, +o, +n}:
      h ++ " " ++ o ++ "/" ++ n

def repo.show(m: Maybe<&2, Ctx.Repo>) -> String:
  match m:
    case Some{+r}:
      repo.text(r)
    case None{}:
      "none"

def named.if(m: Maybe<&2, Ctx.Repo>) -> Ctx.Repo:
  match m:
    case Some{+r}:
      r
    case None{}:
      checkout()

def named() -> Ctx.Repo:
  named.if(Repo.target.of(checkout(), "OWNER/cha-sandbox"))

def json.text(v: Json.Val) -> String:
  Json.encode(v)

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
    expect("create.url, own account", Repo.create.url("", True{}), "user/repos")
    expect("create.url, an org", Repo.create.url("sample-org", False{}), "orgs/sample-org/repos")
    expect("--org takes a plain name", String.to_lower(Bool.show(Repo.org.bad("sample-org", False{}))), "false")
    expect("--org refuses a path", String.to_lower(Bool.show(Repo.org.bad("a/b", False{}))), "true")
    expect("--org absent is fine", String.to_lower(Bool.show(Repo.org.bad("", True{}))), "false")
    expect("create.body, private with a description", json.text(Repo.create.body("sandbox", "test repo", True{})), "{\"name\":\"sandbox\",\"description\":\"test repo\",\"private\":true}")
    expect("create.body, public without one", json.text(Repo.create.body("sandbox", "", False{})), "{\"name\":\"sandbox\",\"description\":\"\",\"private\":false}")
    expect("target, named on the checkout's host", repo.show(Repo.target.of(checkout(), "OWNER/cha-sandbox")), "github.com OWNER/cha-sandbox")
    expect("target, a bare name is not enough", repo.show(Repo.target.of(checkout(), "cha-sandbox")), "none")
    expect("target, owner and name only", repo.show(Repo.target.of(checkout(), "OWNER/NAME/EXTRA")), "none")
    expect("target, an empty owner", repo.show(Repo.target.of(checkout(), "/NAME")), "none")
    expect("target, an empty name", repo.show(Repo.target.of(checkout(), "OWNER/")), "none")
    expect("target, a space can't reach the url", repo.show(Repo.target.of(checkout(), "OWNER/na me")), "none")
    expect("target, a query can't reach the url", repo.show(Repo.target.of(checkout(), "OWNER/n?x=1")), "none")
    expect("api.path of the named repo", Api.path(named(), ""), "repos/OWNER/cha-sandbox")
    expect("delete without --yes names the repo", Repo.delete.confirmed("OWNER/cha-sandbox", False{}), "repo delete: this deletes OWNER/cha-sandbox; rerun with --yes to confirm")
    expect("delete with --yes is ready", Repo.delete.confirmed("OWNER/cha-sandbox", True{}), "")
    expect("a 403 names the github scope", Repo.delete.why(Ctx.GitHub{}, 403), "repo delete: the token lacks the delete scope (github: delete_repo, HTTP 403)")
    expect("a 403 names the gitea scope", Repo.delete.why(Ctx.Gitea{}, 403), "repo delete: the token lacks the delete scope (gitea: write:repository, HTTP 403)")
    expect("repo create takes its three flags", String.join(Cli.unknown(["--org", "--private", "--description"], ["--org", "x", "--private", "--description", "d"]), ","), "")
    expect("repo delete takes only --yes", String.join(Cli.unknown(["--yes"], ["--yes"]), ","), "")
    expect("--private does not swallow the name", Cli.arg(["create", "--private", "sandbox"], 1n), "sandbox")
    expect("--yes does not swallow the target", Cli.arg(["delete", "--yes", "OWNER/cha-sandbox"], 1n), "OWNER/cha-sandbox")
