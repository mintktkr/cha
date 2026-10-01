# offline checks for the pr command's pure pieces: no network, no forge.
import Base
import ../src/ctx.bend as Ctx
import ../src/api.bend as Api
import ../src/cmd/pr.bend as Pr

def gitea() -> Ctx.Repo:
  Ctx.Repo{Ctx.Gitea{}, "tea.example.org", "memu", "sandbox"}

def github() -> Ctx.Repo:
  Ctx.Repo{Ctx.GitHub{}, "github.com", "memu", "sandbox"}

def y(x: Bool) -> String:
  String.to_lower(Bool.show(x))

def row.kv(+k: String, +v: String) -> Map<&2, String>:
  Map.set(&2, String, Map.new(&2, String), k, v)

def review(+st: String) -> Map<&2, String>:
  Map.set(&2, String, Map.new(&2, String), "state", st)

def lines.of(xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      Api.f(x, "name") ++ "|" ++ Api.f(x, "state") ++ "|" ++ Api.f(x, "url") ++ "\n" ++ lines.of(rest)

def tally.text(+t: Pr.Tally) -> String:
  match t:
    case Pr.Tally{a, c, n}:
      Nat.show(a) ++ "/" ++ Nat.show(c) ++ "/" ++ Nat.show(n)

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

# the flattened object a Gitea commit-status reply becomes
def statuses() -> Map<&2, String>:
  +a = Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), "statuses.#", "2"), "statuses.0.context", "ci / hello"), "statuses.0.status", "success")
  +b = Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, a, "statuses.0.target_url", "/runs/1"), "statuses.1.context", "ci / sad"), "statuses.1.status", "failure")
  Map.set(&2, String, b, "statuses.1.target_url", "/runs/2")

def main() -> IO(Unit):
  do IO<Unit>:
    expect("web.url gitea", Pr.web.url(gitea(), "3"), "https://tea.example.org/memu/sandbox/pulls/3")
    expect("web.url github", Pr.web.url(github(), "3"), "https://github.com/memu/sandbox/pull/3")
    expect("state.merged closed", Pr.state.merged("closed", True{}), "merged")
    expect("state.merged open", Pr.state.merged("open", False{}), "open")
    expect("flag.of True", y(Pr.flag.of("True")), "true")
    expect("flag.of False", y(Pr.flag.of("False")), "false")
    expect("flag.of empty", y(Pr.flag.of("")), "false")
    expect("merged.of flag", y(Pr.merged.of(row.kv("merged", "True"))), "true")
    expect("merged.of at", y(Pr.merged.of(row.kv("merged_at", "2026-01-01"))), "true")
    expect("merged.of none", y(Pr.merged.of(row.kv("title", "x"))), "false")
    expect("review approved", Nat.show(Pr.review.kind("APPROVED")), "1")
    expect("review changes", Nat.show(Pr.review.kind("CHANGES_REQUESTED")), "2")
    expect("review request changes", Nat.show(Pr.review.kind("REQUEST_CHANGES")), "2")
    expect("review commented", Nat.show(Pr.review.kind("COMMENTED")), "0")
    expect("tally", tally.text(Pr.tally.of([review("APPROVED"), review("REQUEST_CHANGES"), review("COMMENTED")])), "1/1/1")
    expect("merge.pick squash", Pr.merge.pick(True{}, False{}, False{}), "squash")
    expect("merge.pick merge", Pr.merge.pick(False{}, True{}, False{}), "merge")
    expect("merge.pick rebase", Pr.merge.pick(False{}, False{}, True{}), "rebase")
    expect("merge.pick default", Pr.merge.pick(False{}, False{}, False{}), "merge")
    expect("check.bad failure", y(Pr.check.bad("failure")), "true")
    expect("check.bad timed_out", y(Pr.check.bad("timed_out")), "true")
    expect("check.bad success", y(Pr.check.bad("success")), "false")
    expect("check.bad pending", y(Pr.check.bad("pending")), "false")
    expect("state.ok open", y(Pr.state.ok("open")), "true")
    expect("state.ok bogus", y(Pr.state.ok("bogus")), "false")
    expect("nled plain", Pr.nled("a"), "a\n")
    expect("nled kept", Pr.nled("a\n"), "a\n")
    expect("body.block", Pr.body.block("x", False{}), "\nx\n")
    expect("body.block empty", Pr.body.block("x", True{}), "")
    expect("abs.url path", Pr.abs.url("tea.example.org", "/runs/1"), "https://tea.example.org/runs/1")
    expect("abs.url full", Pr.abs.url("tea.example.org", "https://ci.example.org/1"), "https://ci.example.org/1")
    expect("check.walk", lines.of(Pr.check.walk(2n, statuses(), "statuses", "tea.example.org", Pr.Gitea{}, 0, Nil{})), "ci / hello|success|https://tea.example.org/runs/1\nci / sad|failure|https://tea.example.org/runs/2\n")
    expect("checks.bads", Nat.show(Pr.checks.bads(Pr.check.walk(2n, statuses(), "statuses", "tea.example.org", Pr.Gitea{}, 0, Nil{}))), "1")
