# offline checks for cha mirror: the two forges' mirror field names, the credentials a
# mirror URL can carry, and the sentences the command prints instead of the forge's bare
# 400. Run: bend test/mirror_check.bend
import Base
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../src/ctx.bend as Ctx
import ../src/api.bend as Api
import ../src/cli.bend as Cli
import ../src/cmd/repo.bend as Repo
import ../src/cmd/mirror.bend as Mirror

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

def row.put(m: Map<&2, String>, p: String & String) -> Map<&2, String>:
  (k, v) = p
  Map.set(&2, String, m, k, v)

def row.go(ps: List<&1, String & String>, m: Map<&2, String>) -> Map<&2, String>:
  match ps:
    case Nil{}:
      m
    case Con{p, t}:
      row.go(t, row.put(m, p))

def row.of(ps: List<&1, String & String>) -> Map<&2, String>:
  row.go(ps, Map.new(&2, String))

def sample() -> Ctx.Repo:
  Ctx.Repo{Ctx.Gitea{}, "example.org", "sample", "repo"}

# a Gitea repo that is a pull mirror, its original_url carrying a token
def pull.json() -> String:
  "{\"full_name\":\"sample/repo\",\"mirror\":true,\"original_url\":\"https://x:SECRET@upstream.example/sample/repo.git\",\"mirror_interval\":\"8h0m0s\",\"mirror_updated\":\"2026-01-02T03:04:05Z\"}"

# ... and one that isn't
def plain.json() -> String:
  "{\"full_name\":\"sample/repo\",\"mirror\":false}"

# two push mirrors, the first clean and the second with a token and a failed last sync
def push.json() -> String:
  "[{\"remote_address\":\"https://x:SECRET@other.example/sample/repo.git\",\"interval\":\"8h0m0s\",\"last_update\":\"2026-01-02T03:04:05Z\",\"last_error\":\"\"},{\"remote_address\":\"https://third.example/sample/repo.git\",\"interval\":\"24h0m0s\",\"last_update\":\"\",\"last_error\":\"dial tcp: connection refused\"}]"

def pulls(+s: String) -> List<&2, Map<&2, String>>:
  Mirror.pull.rows(Api.obj(Bytes.from_string(s)))

def pushes(+s: String) -> List<&2, Map<&2, String>>:
  Mirror.push.rows(Api.rows(Bytes.from_string(s)))

def all.pulls() -> List<&2, Map<&2, String>>:
  pulls(pull.json())

def all.pushes() -> List<&2, Map<&2, String>>:
  pushes(push.json())

def pull.check(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Con{+x, Nil{}}:
      do IO<Unit>:
        expect(Api.f(x, "kind"), "pull")
        expect(Api.f(x, "address"), "https://upstream.example/sample/repo.git")
        expect(Api.f(x, "interval"), "8h0m0s")
        expect(Api.f(x, "updated"), "2026-01-02T03:04:05Z")
        expect(Api.f(x, "error"), "")
    case x:
      IO.die(Unit, 1, "a pull mirror repo must map to one row")

def push.check(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Con{+a, Con{+b, Nil{}}}:
      do IO<Unit>:
        expect(Api.f(a, "kind"), "push")
        expect(Api.f(a, "address"), "https://other.example/sample/repo.git")
        expect(Api.f(a, "updated"), "2026-01-02T03:04:05Z")
        expect(Api.f(a, "error"), "")
        expect(Api.f(b, "address"), "https://third.example/sample/repo.git")
        expect(Api.f(b, "interval"), "24h0m0s")
        expect(Api.f(b, "updated"), "")
        expect(Api.f(b, "error"), "dial tcp: connection refused")
    case x:
      IO.die(Unit, 1, "two push mirrors must map to two rows")

def text.check() -> IO(Unit):
  do IO<Unit>:
    expect(Mirror.status.text(False{}, False{}, Nil{}), "not a pull mirror\n")
    expect(Mirror.status.text(False{}, True{}, all.pulls()), "pull mirror  https://upstream.example/sample/repo.git  every 8h0m0s  updated 2026-01-02T03:04:05Z\n")
    +ps : List<&2, Map<&2, String>> = all.pushes()
    expect(Mirror.lines(False{}, ps), "push mirror  https://other.example/sample/repo.git  every 8h0m0s  updated 2026-01-02T03:04:05Z\npush mirror  https://third.example/sample/repo.git  every 24h0m0s  error: dial tcp: connection refused\n")

def colour.check.at(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Con{a, Con{+b, Nil{}}}:
      do IO<Unit>:
        expect(Mirror.line(True{}, a), "\u{1b}[38;2;110;242;184mpush mirror\u{1b}[39m  https://other.example/sample/repo.git  every 8h0m0s  updated 2026-01-02T03:04:05Z")
        expect(Mirror.line(True{}, b), "\u{1b}[38;2;255;110;180mpush mirror\u{1b}[39m  https://third.example/sample/repo.git  every 24h0m0s  \u{1b}[38;2;255;110;180merror: dial tcp: connection refused\u{1b}[39m")
    case x:
      IO.die(Unit, 1, "expected two push mirrors")

def colour.check() -> IO(Unit):
  colour.check.at(all.pushes())

def json.check() -> IO(Unit):
  expect(Cli.json.rows(all.pulls(), Mirror.fields()), "[{\"kind\":\"pull\",\"address\":\"https://upstream.example/sample/repo.git\",\"interval\":\"8h0m0s\",\"updated\":\"2026-01-02T03:04:05Z\",\"error\":\"\"}]")

def env() -> Cli.Env:
  Cli.Env{sample(), "", False{}, Cli.Off{}, Nil{}}

# an anonymous token can't list push mirrors: the 401/403 leaves the pull mirror as the
# whole answer, in text and in --json, while any other status keeps failing
# (push.read.if(.., 500, ..) exits 1, so only its decision is checked here)
def denied.check() -> IO(Unit):
  do IO<Unit>:
    expect(Bool.pick(String, Mirror.denied(401), "denied", "other"), "denied")
    expect(Bool.pick(String, Mirror.denied(403), "denied", "other"), "denied")
    expect(Bool.pick(String, Mirror.denied(500), "denied", "other"), "other")
    +no : List<&2, Map<&2, String>> <- Mirror.push.read.if(env(), False{}, 403, Bytes.from_string(""), False{})
    expect(Nat.show(List.length(&2, Map<&2, String>, no)), "0")
    expect(Mirror.status.text(False{}, True{}, all.pulls()), "pull mirror  https://upstream.example/sample/repo.git  every 8h0m0s  updated 2026-01-02T03:04:05Z\n")
    expect(Mirror.status.text(False{}, False{}, Nil{}), "not a pull mirror\n")
    expect(Cli.json.rows(no, Mirror.fields()), "[]")
    expect(Cli.json.rows(all.pulls(), Mirror.fields()), "[{\"kind\":\"pull\",\"address\":\"https://upstream.example/sample/repo.git\",\"interval\":\"8h0m0s\",\"updated\":\"2026-01-02T03:04:05Z\",\"error\":\"\"}]")

# repo view: a pull mirror says what it mirrors, with the token stripped; --json carries
# the same two fields
def view.check() -> IO(Unit):
  do IO<Unit>:
    +x : Map<&2, String> = row.of([("full_name", "sample/repo"), ("private", "false"), ("internal", "false"), ("mirror", "true"), ("original_url", "https://x:SECRET@upstream.example/sample/repo.git")])
    +row : Map<&2, String> = Repo.view.row(Ctx.Gitea{}, x)
    expect(Repo.view.mirror.text(False{}, row), "mirror of https://upstream.example/sample/repo.git\n")
    expect(Cli.json.rows([row], ["mirror", "original_url"]), "[{\"mirror\":\"true\",\"original_url\":\"https://upstream.example/sample/repo.git\"}]")
    +plain : Map<&2, String> = row.of([("full_name", "sample/repo"), ("private", "false"), ("internal", "false")])
    expect(Repo.view.mirror.text(False{}, Repo.view.row(Ctx.Gitea{}, plain)), "")

def main() -> IO(Unit):
  do IO<Unit>:
    expect(Mirror.pull.url(sample()), "repos/sample/repo")
    expect(Mirror.push.url(sample()), "repos/sample/repo/push_mirrors")
    expect(Mirror.github.msg(), "mirror: GitHub has no mirror API")
    expect(Mirror.not.mirror.msg(sample()), "mirror sync: sample/repo isn't a pull mirror")
    expect(Nat.show(List.length(&2, Map<&2, String>, pulls(plain.json()))), "0")
    expect(Ctx.no_credentials("https://x:SECRET@example.org/o/r.git"), "https://example.org/o/r.git")
    expect(Ctx.no_credentials("https://SECRET@example.org/o/r"), "https://example.org/o/r")
    expect(Ctx.no_credentials("https://example.org/o/r.git"), "https://example.org/o/r.git")
    expect(Ctx.no_credentials("https://example.org/a@b/c.git"), "https://example.org/a@b/c.git")
    expect(Ctx.no_credentials(""), "")
    pull.check(all.pulls())
    push.check(all.pushes())
    text.check()
    colour.check()
    json.check()
    denied.check()
    view.check()
