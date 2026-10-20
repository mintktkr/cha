import Base
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../src/ctx.bend as Ctx
import ../src/cli.bend as Cli
import ../src/api.bend as Api
import ../src/cmd/secrets.bend as Secrets

def expect.if(+got: String, +want: String, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      IO.print("ok  " ++ got)
    case False{}:
      do IO<Unit>:
        IO.print("bad " ++ got ++ " != " ++ want)
        IO.die(Unit, 1, "")

def expect(+got: String, +want: String) -> IO(Unit):
  expect.if(got, want, String.eq(got, want))

def yes_no(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

# Synthetic pages. Gitea answers an array of secrets, GitHub the list inside an object
# with both timestamps; Gitea spells a variable's value data, GitHub spells it value.
def gitea_secrets() -> String:
  "[{\"name\":\"TOKEN\",\"created_at\":\"2026-10-01T09:00:00-03:00\"},{\"name\":\"DEPLOY_KEY\",\"created_at\":\"2026-10-02T09:00:00-03:00\"}]"

def gh_secrets() -> String:
  "{\"total_count\":2,\"secrets\":[{\"name\":\"TOKEN\",\"created_at\":\"2026-10-01T12:00:00Z\",\"updated_at\":\"2026-10-02T12:00:00Z\"},{\"name\":\"DEPLOY_KEY\",\"created_at\":\"2026-10-01T12:00:00Z\",\"updated_at\":\"2026-10-01T12:00:00Z\"}]}"

def gitea_variables() -> String:
  "[{\"name\":\"REGION\",\"data\":\"eu-west\"},{\"name\":\"STAGE\",\"data\":\"prod\"}]"

def gh_variables() -> String:
  "{\"total_count\":2,\"variables\":[{\"name\":\"REGION\",\"value\":\"eu-west\"},{\"name\":\"STAGE\",\"value\":\"prod\"}]}"

def gh_repo() -> Ctx.Repo:
  Ctx.Repo{Ctx.GitHub{}, "github.com", "sample", "repo"}

def gitea_repo() -> Ctx.Repo:
  Ctx.Repo{Ctx.Gitea{}, "example.org", "sample", "repo"}

# A Gitea page is an array of items, one map each; a GitHub page is a wrapper with the
# list inside it. Both go through the same row builder.
def page_gitea(+repo: Ctx.Repo, +kind: String, body: Bytes.Bytes) -> List<&2, Map<&2, String>>:
  Secrets.rows.of(Secrets.forge.of(repo), kind, Secrets.items.array(Api.rows(body)))

def page_gh(+repo: Ctx.Repo, +kind: String, body: Bytes.Bytes) -> List<&2, Map<&2, String>>:
  +src : Map<&2, String> = Api.obj(body)
  Secrets.rows.of(Secrets.forge.of(repo), kind, Secrets.items.gh(Api.count(src, kind), 0, kind, src))

def check_secrets_gh(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Con{+a, Con{+b, Nil{}}}:
      do IO<Unit>:
        expect(Api.f(a, "name"), "TOKEN")
        expect(Api.f(a, "updated"), "2026-10-02T12:00:00Z")
        expect(Api.f(b, "name"), "DEPLOY_KEY")
        expect(Api.f(b, "updated"), "2026-10-01T12:00:00Z")
        expect(Secrets.secrets.line(False{}, a), "TOKEN  2026-10-02T12:00:00Z")
        expect(Cli.json.rows(Con{a, Nil{}}, Secrets.fields("secrets")), "[{\"name\":\"TOKEN\",\"updated\":\"2026-10-02T12:00:00Z\"}]")
    case x:
      IO.die(Unit, 1, "a GitHub page of two secrets must map to two rows")

def check_secrets_gitea(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Con{+a, Con{+b, Nil{}}}:
      do IO<Unit>:
        expect(Api.f(a, "name"), "TOKEN")
        expect(Api.f(a, "updated"), "2026-10-01T09:00:00-03:00")
        expect(Api.f(b, "name"), "DEPLOY_KEY")
        expect(Api.f(a, "value"), "")
        expect(Api.f(a, "data"), "")
    case x:
      IO.die(Unit, 1, "a Gitea page of two secrets must map to two rows")

def check_variables_gh(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Con{+a, Con{+b, Nil{}}}:
      do IO<Unit>:
        expect(Api.f(a, "name"), "REGION")
        expect(Api.f(a, "value"), "eu-west")
        expect(Api.f(b, "value"), "prod")
        expect(Secrets.var.line(False{}, a), "REGION  eu-west")
        expect(Cli.json.rows(Con{a, Nil{}}, Secrets.fields("variables")), "[{\"name\":\"REGION\",\"value\":\"eu-west\"}]")
    case x:
      IO.die(Unit, 1, "a GitHub page of two variables must map to two rows")

def check_variables_gitea(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Con{+a, Con{+b, Nil{}}}:
      do IO<Unit>:
        expect(Api.f(a, "name"), "REGION")
        expect(Api.f(a, "value"), "eu-west")
        expect(Secrets.var.line(False{}, b), "STAGE  prod")
    case x:
      IO.die(Unit, 1, "a Gitea page of two variables must map to two rows")

def check_names() -> IO(Unit):
  do IO<Unit>:
    expect(yes_no(Secrets.name.ok("TOKEN")), "yes")
    expect(yes_no(Secrets.name.ok("A_b1")), "yes")
    expect(yes_no(Secrets.name.ok("_under")), "yes")
    expect(yes_no(Secrets.name.ok("")), "no")
    expect(yes_no(Secrets.name.ok("1TOKEN")), "no")
    expect(yes_no(Secrets.name.ok("TO-KEN")), "no")
    expect(yes_no(Secrets.name.ok("TO KEN")), "no")
    expect(yes_no(Secrets.name.ok("TOKEN\n")), "no")
    expect(yes_no(Secrets.name.ok("GITHUB_TOKEN")), "no")
    expect(yes_no(Secrets.name.ok("github_token")), "no")
    expect(Secrets.name.msg("secrets set"), "secrets set: a name is letters, digits and underscore, and can't start with a digit or GITHUB_")

# the body as the request sends it, byte for byte
def body.text(v: Json.Val) -> String:
  Bytes.to_string(Json.encode.bytes(v))

def check_bodies() -> IO(Unit):
  do IO<Unit>:
    expect(body.text(Secrets.set.body("s3cret")), "{\"data\":\"s3cret\"}")
    expect(body.text(Secrets.var.body("REGION", "eu-west")), "{\"name\":\"REGION\",\"value\":\"eu-west\"}")
    expect(body.text(Secrets.var.value.body("eu-west")), "{\"value\":\"eu-west\"}")

# a failed secrets set answers from the status alone: a body that echoed the value whole,
# in part or re-cased has no way into the message

def check_set_why() -> IO(Unit):
  do IO<Unit>:
    expect(Secrets.set.why(401), "the token can't write secrets here (HTTP 401)")
    expect(Secrets.set.why(403), "the token can't write secrets here (HTTP 403)")
    expect(Secrets.set.why(404), "no such repo or org (HTTP 404)")
    expect(Secrets.set.why(422), "the forge refused the name or the value (HTTP 422)")
    expect(Secrets.set.why(500), "HTTP 500")
    expect(Secrets.set.why(409), "HTTP 409")
    expect(yes_no(String.contains(Secrets.set.why(422), "hunter2")), "no")
    expect(yes_no(String.contains(Secrets.set.why(500), "hunter2")), "no")

# --value=x and --value-file=F are read by value, not by Cli.has; an explicit --value "" is
# not a value, because an unset shell variable must not silently set an empty secret

def check_value() -> IO(Unit):
  do IO<Unit>:
    +inline : String = Cli.flag(["--value=hunter2"], "--value", "")
    expect(yes_no(Secrets.value.given(inline, "")), "yes")
    +spaced : String = Cli.flag(["--value", "hunter2"], "--value", "")
    expect(yes_no(Secrets.value.given(spaced, "")), "yes")
    +path : String = Cli.flag(["--value-file=secret.txt"], "--value-file", "")
    expect(yes_no(Secrets.value.given("", path)), "yes")
    +blank : String = Cli.flag(["--value", ""], "--value", "")
    expect(yes_no(Secrets.value.given(blank, "")), "no")
    expect(Secrets.value.msg("secrets set"), "secrets set: a value is required, from --value or --value-file")
    expect(yes_no(Secrets.read.over("s3cret")), "no")
    # a value file of exactly the cap fits; one byte more is refused, not sent cut short
    expect(yes_no(Secrets.read.over(Bytes.to_string(Bytes.new(1048576)))), "no")
    expect(yes_no(Secrets.read.over(Bytes.to_string(Bytes.new(1048577)))), "yes")


def check_guard() -> IO(Unit):
  do IO<Unit>:
    expect(Secrets.guard.msg("secrets delete", "secret", "TOKEN"), "secrets delete: would delete secret TOKEN; pass --yes to go ahead")
    expect(Secrets.guard.msg("variables delete", "variable", "REGION"), "variables delete: would delete variable REGION; pass --yes to go ahead")
    expect(Secrets.set.github.msg(), "secrets set: GitHub needs the value sealed with the repo's public key; cha can't do that yet")

def check_chomp() -> IO(Unit):
  do IO<Unit>:
    expect(Secrets.chomp("s3cret\n"), "s3cret")
    expect(Secrets.chomp("s3cret\r\n"), "s3cret")
    expect(Secrets.chomp("s3cret\n\n"), "s3cret")
    expect(Secrets.chomp("s3cret"), "s3cret")
    expect(Secrets.chomp(""), "")
    expect(Secrets.chomp("s3\ncret"), "s3\ncret")

def main() -> IO(Unit):
  do IO<Unit>:
    expect(Secrets.list.url(gh_repo(), "", "secrets", 1), "repos/sample/repo/actions/secrets?per_page=100&page=1")
    expect(Secrets.list.url(gh_repo(), "sample-org", "variables", 2), "orgs/sample-org/actions/variables?per_page=100&page=2")
    expect(Secrets.list.url(gitea_repo(), "", "secrets", 1), "repos/sample/repo/actions/secrets?page=1&limit=50")
    expect(Secrets.list.url(gitea_repo(), "sample-org", "variables", 3), "orgs/sample-org/actions/variables?page=3&limit=50")
    expect(Secrets.url.of(gh_repo(), "a/../b", "secrets"), "orgs/a%2F..%2Fb/actions/secrets")
    expect(Secrets.item.url("orgs/sample-org/actions/secrets", "TOKEN"), "orgs/sample-org/actions/secrets/TOKEN")
    expect(Secrets.item.url("repos/sample/repo/actions/variables", "REGION"), "repos/sample/repo/actions/variables/REGION")
    expect(Secrets.page.next("", "next-page", 2n, "5", False{}), "next-page")
    expect(Secrets.page.next("", "next-page", 5n, "5", False{}), "")
    expect(Secrets.page.next("", "next-page", 0n, "5", True{}), "")
    expect(Secrets.page.next("link-page", "next-page", 2n, "5", False{}), "link-page")
    expect(String.join(Secrets.fields("secrets"), ","), "name,updated")
    expect(String.join(Secrets.fields("variables"), ","), "name,value")
    expect(Nat.show(Secrets.index(Secrets.names(), "set", 0n)), "1")
    expect(Nat.show(Secrets.index(Secrets.names(), "delete", 0n)), "2")
    expect(Nat.show(Secrets.index(Secrets.names(), "nope", 0n)), "3")
    check_secrets_gh(page_gh(gh_repo(), "secrets", Bytes.from_string(gh_secrets())))
    check_secrets_gitea(page_gitea(gitea_repo(), "secrets", Bytes.from_string(gitea_secrets())))
    check_variables_gh(page_gh(gh_repo(), "variables", Bytes.from_string(gh_variables())))
    check_variables_gitea(page_gitea(gitea_repo(), "variables", Bytes.from_string(gitea_variables())))
    check_names()
    check_bodies()
    check_set_why()
    check_value()
    check_guard()
    check_chomp()
