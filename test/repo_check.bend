# offline checks for cha repo and cha release: the forge-specific field names, label
# colours and release flags, on synthetic rows. Run: bend test/repo_check.bend
import Base
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import ../src/ctx.bend as Ctx
import ../src/api.bend as Api
import ../src/cli.bend as Cli
import ../src/ui.bend as Ui
import ../src/url.bend as Url
import ../src/cmd/repo.bend as Repo
import ../src/cmd/release.bend as Rel
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes

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
  Api.raw.text(Json.encode.bytes(v))

# Branches and protection
# -----------------------

def same.if(+got: String, +want: String, eq: Bool) -> IO(Unit):
  match eq:
    case True{}:
      IO.print("ok  " ++ got)
    case False{}:
      do IO<Unit>:
        IO.print("bad " ++ got ++ " != " ++ want)
        IO.die(Unit, 1, "")

def same(+got: String, +want: String) -> IO(Unit):
  same.if(got, want, String.eq(got, want))

# a row's five protection fields, so one expect covers a whole rule
def card(+x: Map<&2, String>) -> String:
  Api.f(x, "branch") ++ "|" ++ Api.f(x, "approvals") ++ "|" ++ Api.f(x, "checks") ++ "|" ++ Api.f(x, "push_restricted") ++ "|" ++ Api.f(x, "force_push_blocked")

# a protected main: two required checks, two approvals, pushes restricted, force pushes
# blocked
def gh.body() -> String:
  "{\"required_status_checks\":{\"strict\":true,\"contexts\":[\"ci\",\"lint\"]},\"required_pull_request_reviews\":{\"required_approving_review_count\":2},\"restrictions\":{\"url\":\"https://api.github.com/repos/example/repo/branches/main/protection/restrictions\",\"users\":[],\"teams\":[],\"apps\":[]},\"allow_force_pushes\":{\"enabled\":false}}"

# a branch with nothing required: every field is null in the reply
def gh.bare.body() -> String:
  "{\"required_status_checks\":null,\"required_pull_request_reviews\":null,\"restrictions\":null,\"allow_force_pushes\":null}"

# github sends checks set up through the checks API as objects, with no contexts
def gh.checks.body() -> String:
  "{\"required_status_checks\":{\"contexts\":[],\"checks\":[{\"context\":\"build\"},{\"context\":\"test\"}]},\"allow_force_pushes\":{\"enabled\":true}}"

# gitea 1.25: the rule has both names, and force push is turned on
def gitea.rule.body() -> String:
  "{\"id\":1,\"rule_name\":\"\",\"branch_name\":\"main\",\"enable_push\":false,\"enable_force_push\":true,\"enable_status_check\":true,\"status_check_contexts\":[\"ci/woodpecker\"],\"required_approvals\":2}"

# a gitea older than 1.21 has no enable_force_push, and keeps contexts it doesn't require
def gitea.off.body() -> String:
  "{\"id\":2,\"branch_name\":\"release/*\",\"enable_push\":true,\"enable_status_check\":false,\"status_check_contexts\":[\"stale\"],\"required_approvals\":0}"

def gh.row.of(+b: String) -> Map<&2, String>:
  Repo.gh.row(Api.obj(Bytes.from_string(b)), "main")

def gitea.rows() -> List<&2, Map<&2, String>>:
  Api.rows(Bytes.from_string("[" ++ gitea.rule.body() ++ "," ++ gitea.off.body() ++ "]"))

def rule.row.of(+b: String) -> Map<&2, String>:
  Repo.gitea.row(Api.obj(Bytes.from_string(b)))

def picked(+w: String, empty: Bool) -> String:
  Nat.show(List.length(&2, Map<&2, String>, Repo.gitea.rows(gitea.rows(), w, empty)))

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
    expect("--org refuses ..", String.to_lower(Bool.show(Repo.org.bad("..", False{}))), "true")
    expect("--org refuses .", String.to_lower(Bool.show(Repo.org.bad(".", False{}))), "true")
    expect("--org absent is fine", String.to_lower(Bool.show(Repo.org.bad("", True{}))), "false")
    expect("create.body, private with a description", json.text(Repo.create.body("sandbox", "test repo", True{})), "{\"name\":\"sandbox\",\"description\":\"test repo\",\"private\":true}")
    expect("create.body, public without one", json.text(Repo.create.body("sandbox", "", False{})), "{\"name\":\"sandbox\",\"description\":\"\",\"private\":false}")
    expect("target, named on the checkout's host", repo.show(Repo.target.of(checkout(), "OWNER/cha-sandbox")), "github.com OWNER/cha-sandbox")
    expect("target, a bare name is not enough", repo.show(Repo.target.of(checkout(), "cha-sandbox")), "none")
    expect("target, owner and name only", repo.show(Repo.target.of(checkout(), "OWNER/NAME/EXTRA")), "none")
    expect("target, an empty owner", repo.show(Repo.target.of(checkout(), "/NAME")), "none")
    expect("target, an empty name", repo.show(Repo.target.of(checkout(), "OWNER/")), "none")
    expect("target, . is not an owner", repo.show(Repo.target.of(checkout(), "./repo")), "none")
    expect("target, .. is not a name", repo.show(Repo.target.of(checkout(), "checkout/..")), "none")
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
    # branch-delete: the paths each forge wants, and the two guards
    same(Repo.branch.url(Ctx.GitHub{}, "memu/foo"), "git/refs/heads/memu/foo")
    same(Repo.branch.url(Ctx.Gitea{}, "memu/foo"), "branches/memu/foo")
    same(Repo.branch.url(Ctx.GitHub{}, "fix#1"), "git/refs/heads/fix%231")
    same(Repo.branch.url(Ctx.Gitea{}, "fix#1"), "branches/fix%231")
    same(Repo.gh.url("memu/foo"), "branches/memu%2Ffoo/protection")
    same(Url.encode.path("a b/c"), "a%20b/c")
    same(Url.encode.path("memu/foo"), "memu/foo")
    same(Url.encode("memu/foo"), "memu%2Ffoo")
    same(Repo.delete.ask("memu/foo", False{}), "repo branch-delete: would delete branch memu/foo; pass --yes to do it")
    same(Repo.delete.ask("memu/foo", True{}), "")
    same(Repo.delete.default("main", True{}), "repo branch-delete: main is the default branch")
    same(Repo.delete.default("feature", False{}), "")
    # the path-walking names branch-delete refuses before it sends a request
    same(Repo.delete.segments(Url.encode.path.ok("../../x")), "repo branch-delete: a branch name can't have . or .. segments")
    same(Repo.delete.segments(Url.encode.path.ok("a/./b")), "repo branch-delete: a branch name can't have . or .. segments")
    same(Repo.delete.segments(Url.encode.path.ok("a//b")), "repo branch-delete: a branch name can't have . or .. segments")
    same(Repo.delete.segments(Url.encode.path.ok("release/1.0")), "")
    # protection: the same fields, from each forge's shape
    same(card(gh.row.of(gh.body())), "main|2|ci, lint|true|true")
    same(card(gh.row.of(gh.bare.body())), "main|0||false|true")
    same(card(gh.row.of(gh.checks.body())), "main|0|build, test|false|false")
    same(card(rule.row.of(gitea.rule.body())), "main|2|ci/woodpecker|true|false")
    same(card(rule.row.of(gitea.off.body())), "release/*|0||false|true")
    same(Repo.prot.line(False{}, rule.row.of(gitea.rule.body())), "main  approvals 2  checks ci/woodpecker  pushes restricted")
    same(Repo.prot.line(False{}, rule.row.of(gitea.off.body())), "release/*  force-push blocked")
    same(picked("", True{}), "2")
    same(picked("main", False{}), "1")
    same(picked("release/*", False{}), "1")
    same(picked("release/1.0", False{}), "0")
    same(Cli.json.rows([rule.row.of(gitea.rule.body())], Repo.prot.fields()), "[{\"branch\":\"main\",\"approvals\":\"2\",\"checks\":\"ci/woodpecker\",\"push_restricted\":\"true\",\"force_push_blocked\":\"false\"}]")
