# offline checks for hooks: endpoints, create bodies, the redaction that keeps a hook's
# secret and its URL out of every row, the id check and the --yes wording. No network.
# Run: bend test/hooks_check.bend
import Base
import ../lib/chaki/utf8.bend as Utf8
import ../lib/chaki/json.bend as Json
import ../src/ctx.bend as Ctx
import ../src/cli.bend as Cli
import ../src/api.bend as Api
import ../src/hooks.bend as Hooks
import ../src/cmd/hooks.bend as Hook

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

def expect.flag(+name: String, want: Bool, got: Bool) -> IO(Unit):
  match want got:
    case True{} True{}:
      IO.print("ok  " ++ name)
    case False{} False{}:
      IO.print("ok  " ++ name)
    case x y:
      do IO<Unit>:
        IO.print("bad " ++ name)
        IO.die(Unit, 1, "")

# a synthetic GitHub hook: GitHub masks the secret in the config it returns
def gh.hook() -> String:
  "{\"id\":12,\"name\":\"web\",\"active\":true,\"events\":[\"push\",\"pull_request\"],\"config\":{\"content_type\":\"json\",\"insecure_ssl\":\"0\",\"url\":\"https://hooks.example/hook\",\"secret\":\"********\"}}"

# a synthetic Gitea hook: no secret in the reply, and disabled
def gitea.hook() -> String:
  "{\"id\":5,\"type\":\"gitea\",\"active\":false,\"events\":[\"push\"],\"config\":{\"content_type\":\"form\",\"url\":\"https://ci.example/gitea\"}}"

# a reply that hands the real secret back, as Gitea can
def leaky.hook() -> String:
  "{\"id\":3,\"active\":true,\"events\":[\"push\"],\"config\":{\"content_type\":\"json\",\"url\":\"https://x.example/hook\",\"secret\":\"s3cr3t\"},\"metadata\":{\"token\":\"t0ken\"}}"

def body.text(v: Json.Val) -> String:
  (Json.encode(v))

def gh.row() -> Map<&2, String>:
  Hook.hook.row(Api.obj(Utf8.encode(gh.hook())))

def gitea.row() -> Map<&2, String>:
  Hook.hook.row(Api.obj(Utf8.encode(gitea.hook())))

def row.check(+row: Map<&2, String>) -> IO(Unit):
  do IO<Unit>:
    expect(Api.f(row, "id"), "12")
    expect(Api.f(row, "url"), "https://hooks.example/…")
    expect(Api.f(row, "events"), "push,pull_request")
    expect(Api.f(row, "active"), "true")
    expect(Api.f(row, "content_type"), "json")
    expect(Cli.json.rows(Con{row, Nil{}}, Hook.fields()), "[{\"id\":\"12\",\"url\":\"https://hooks.example/…\",\"events\":\"push,pull_request\",\"active\":\"true\",\"content_type\":\"json\"}]")
    expect(Hook.line(False{}, row), "#12  https://hooks.example/…  push,pull_request  active  json")

# a webhook URL can be the secret itself, so only its scheme, host and port survive
# (the laws in LAWS.bend pin the same cases)
def url.check() -> IO(Unit):
  do IO<Unit>:
    expect(Hooks.url.redact("https://hooks.slack.com/services/T000/B000/XXXX"), "https://hooks.slack.com/…")
    expect(Hooks.url.redact("https://user:pass@hooks.example/hook"), "https://hooks.example/…")
    expect(Hooks.url.redact("https://hooks.example/hook?token=s3cr3t"), "https://hooks.example/…")
    expect(Hooks.url.redact("https://hooks.example/hook#frag"), "https://hooks.example/…")
    expect(Hooks.url.redact("https://hooks.example:8443/hook"), "https://hooks.example:8443/…")
    expect(Hooks.url.redact("https://hooks.example"), "https://hooks.example")
    expect(Hooks.url.redact("https://hooks.example/"), "https://hooks.example")
    expect(Hooks.url.redact("https://hooks.example?token=s3cr3t"), "https://hooks.example")
    expect(Hooks.url.redact(""), "")

# the recursive row mapping shows every hook redacted, not just the first
def rows.check() -> IO(Unit):
  do IO<Unit>:
    +xs : List<&2, Map<&2, String>> = [Api.obj(Utf8.encode(gh.hook())), Api.obj(Utf8.encode(leaky.hook()))]
    expect(Hook.lines(False{}, Hook.rows.of(xs)), "#12  https://hooks.example/…  push,pull_request  active  json\n#3  https://x.example/…  push  active  json\n")

# the secret is gone from the flattened reply, and the fields next to it stay
def redact.check() -> IO(Unit):
  do IO<Unit>:
    +leak : Map<&2, String> = Api.obj(Utf8.encode(leaky.hook()))
    +red : Map<&2, String> = Hooks.row.redact(leak)
    expect(Api.raw.f(red, "config.secret"), "")
    expect(Api.raw.f(red, "metadata.token"), "")
    expect(Api.raw.f(red, "config.url"), "https://x.example/hook")
    expect(Api.raw.f(red, "config.content_type"), "json")
    +gh : Map<&2, String> = Api.obj(Utf8.encode(gh.hook()))
    +masked : Map<&2, String> = Hooks.row.redact(gh)
    expect(Api.raw.f(masked, "config.secret"), "")

def main() -> IO(Unit):
  do IO<Unit>:
    expect(Hook.url.of(Ctx.Repo{Ctx.GitHub{}, "github.com", "sample", "repo"}, ""), "repos/sample/repo/hooks?per_page=100")
    expect(Hook.url.of(Ctx.Repo{Ctx.GitHub{}, "github.com", "sample", "repo"}, "sample-org"), "orgs/sample-org/hooks?per_page=100")
    expect(Hook.url.of(Ctx.Repo{Ctx.Gitea{}, "example.org", "sample", "repo"}, ""), "repos/sample/repo/hooks?limit=1000")
    expect(Hook.url.of(Ctx.Repo{Ctx.Gitea{}, "example.org", "sample", "repo"}, "a/../b"), "orgs/a%2F..%2Fb/hooks?limit=1000")
    expect(Hook.hook.url(Ctx.Repo{Ctx.GitHub{}, "github.com", "sample", "repo"}, "", "12"), "repos/sample/repo/hooks/12")
    expect(Hook.hook.url(Ctx.Repo{Ctx.Gitea{}, "example.org", "sample", "repo"}, "sample-org", "7"), "orgs/sample-org/hooks/7")
    expect(body.text(Hook.create.body(Ctx.GitHub{}, "https://hooks.example/hook", ["push", "pull_request"], "json", "s3cr3t")), "{\"name\":\"web\",\"active\":true,\"events\":[\"push\",\"pull_request\"],\"config\":{\"url\":\"https://hooks.example/hook\",\"content_type\":\"json\",\"secret\":\"s3cr3t\"}}")
    expect(body.text(Hook.create.body(Ctx.Gitea{}, "https://ci.example/hook", ["push"], "form", "")), "{\"type\":\"gitea\",\"active\":true,\"events\":[\"push\"],\"config\":{\"url\":\"https://ci.example/hook\",\"content_type\":\"form\"}}")
    +row : Map<&2, String> = gh.row()
    row.check(row)
    url.check()
    rows.check()
    expect(Hook.line(False{}, gitea.row()), "#5  https://ci.example/…  push  disabled  form")
    expect(Hook.active.text(False{}, True{}), "  active")
    expect(Hook.active.text(True{}, True{}), "  \u{1b}[38;2;110;242;184mactive\u{1b}[39m")
    expect(Hook.active.text(False{}, False{}), "  disabled")
    redact.check()
    expect(String.join(Hooks.row.fields(["id", "config.secret", "config.password", "metadata.token", "config.url"]), ","), "id,config.url")
    expect(String.join(Hooks.row.fields(["config.Secret", "TOKEN"]), ","), "")
    expect.flag("id 12", True{}, Hooks.id.ok("12"))
    expect.flag("id ..", False{}, Hooks.id.ok(".."))
    expect.flag("id 12a", False{}, Hooks.id.ok("12a"))
    expect.flag("id -3", False{}, Hooks.id.ok("-3"))
    expect.flag("id empty", False{}, Hooks.id.ok(""))
    expect.flag("content-type json", True{}, Hook.ct.ok("json"))
    expect.flag("content-type form", True{}, Hook.ct.ok("form"))
    expect.flag("content-type yaml", False{}, Hook.ct.ok("yaml"))
    expect(Hook.yes.msg("12"), "hooks delete: would delete hook #12; rerun with --yes")
    expect(Hook.id.bad.msg("hooks delete", ".."), "hooks delete: expected a hook id, got '..'")
    expect(Hook.id.empty.msg("hooks test"), "hooks test: give a hook id")
