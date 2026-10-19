# offline checks for issue's pure helpers: names, percent-encoding, label ids, op codes,
# the list query every filter goes into, --limit, and the unknown-flag check
import Base
import ../src/ctx.bend as Ctx
import ../src/cli.bend as Cli
import ../src/cmd/issue.bend as Issue

def row.of(+id: String, +name: String) -> Map<&2, String>:
  Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), "id", id), "name", name)

# a row as github answers it: a pull request carries pull_request.url, an issue doesn't
def url.row(+url: String) -> Map<&2, String>:
  Map.set(&2, String, Map.new(&2, String), "pull_request.url", url)

def report.if(good: Bool, +name: String, +got: String, +want: String) -> String:
  match good:
    case True{}:
      "ok   " ++ name
    case False{}:
      "FAIL " ++ name ++ ": got [" ++ got ++ "], want [" ++ want ++ "]"

def report(good: Bool, +name: String, +got: String, +want: String) -> String:
  report.if(good, name, got, want)

def check(+name: String, +got: String, +want: String) -> String:
  report(String.eq(got, want), name, got, want)

def main() -> IO(Unit):
  do IO<Unit>:
    +rows : List<&2, Map<&2, String>> = Con{row.of("34", "bug"), Con{row.of("35", "ready"), Nil{}}}
    IO.print(check("split.names trims, drops blanks", String.join(Issue.split.names(" bug ,, ready "), ","), "bug,ready"))
    IO.print(check("split.names of nothing", String.join(Issue.split.names(""), ","), ""))
    IO.print(check("enc.seg keeps unreserved", Issue.enc.seg("bug_1.2~3"), "bug_1.2~3"))
    IO.print(check("enc.seg encodes space and slash", Issue.enc.seg("good first issue/a"), "good%20first%20issue%2Fa"))
    IO.print(check("labels.op add", Nat.show(Issue.labels.op("add")), "0"))
    IO.print(check("labels.op remove", Nat.show(Issue.labels.op("remove")), "1"))
    IO.print(check("labels.op set", Nat.show(Issue.labels.op("set")), "2"))
    IO.print(check("labels.op unknown", Nat.show(Issue.labels.op("nope")), "3"))
    IO.print(check("ids.of finds each name", String.join(Issue.ids.of(Con{"ready", Con{"bug", Nil{}}}, rows), ","), "35,34"))
    IO.print(check("ids.of leaves an unknown name blank", String.join(Issue.ids.of(Con{"nope", Con{"bug", Nil{}}}, rows), ","), ",34"))
    IO.print(check("miss names the unknown ones", Issue.miss(Con{"bug", Con{"nope", Con{"x", Nil{}}}}, Con{"34", Con{"", Con{"", Nil{}}}}), "nope, x"))
    +prs : List<&2, Map<&2, String>> = Con{url.row("https://example.test/pull/1"), Con{url.row(""), Nil{}}}
    IO.print(check("prs.keep drops pull requests", Nat.show(List.length(&2, Map<&2, String>, Issue.prs.keep(prs, False{}))), "1"))
    IO.print(check("prs.keep keeps them with --with-prs", Nat.show(List.length(&2, Map<&2, String>, Issue.prs.keep(prs, True{}))), "2"))
    IO.print(check("query gitea, state only", Issue.query(Ctx.Gitea{}, 50n, "open", "", "", "", False{}), "issues?type=issues&limit=50&state=open"))
    IO.print(check("query github, state only", Issue.query(Ctx.GitHub{}, 100n, "open", "", "", "", False{}), "issues?per_page=100&state=open"))
    IO.print(check("query gitea, label only", Issue.query(Ctx.Gitea{}, 50n, "open", "bug", "", "", False{}), "issues?type=issues&limit=50&state=open&labels=bug"))
    IO.print(check("query github, label only", Issue.query(Ctx.GitHub{}, 100n, "open", "bug", "", "", False{}), "issues?per_page=100&state=open&labels=bug"))
    IO.print(check("query gitea, assignee only", Issue.query(Ctx.Gitea{}, 50n, "open", "", "memu", "", False{}), "issues?type=issues&limit=50&state=open&assigned_by=memu"))
    IO.print(check("query github, assignee only", Issue.query(Ctx.GitHub{}, 100n, "open", "", "memu", "", False{}), "issues?per_page=100&state=open&assignee=memu"))
    IO.print(check("query github, assignee none", Issue.query(Ctx.GitHub{}, 100n, "open", "", "none", "", False{}), "issues?per_page=100&state=open&assignee=none"))
    IO.print(check("query github, assignee anyone", Issue.query(Ctx.GitHub{}, 100n, "open", "", "*", "", False{}), "issues?per_page=100&state=open&assignee=%2A"))
    IO.print(check("query gitea, since only", Issue.query(Ctx.Gitea{}, 50n, "open", "", "", "2026-09-30T12:00:00Z", False{}), "issues?type=issues&limit=50&state=open&since=2026-09-30T12%3A00%3A00Z"))
    IO.print(check("query github, since only", Issue.query(Ctx.GitHub{}, 100n, "open", "", "", "2026-09-30T12:00:00Z", False{}), "issues?per_page=100&state=open&since=2026-09-30T12%3A00%3A00Z"))
    IO.print(check("query gitea, every filter", Issue.query(Ctx.Gitea{}, 50n, "closed", "bug", "memu", "2026-09-30T12:00:00Z", False{}), "issues?type=issues&limit=50&state=closed&labels=bug&assigned_by=memu&since=2026-09-30T12%3A00%3A00Z"))
    IO.print(check("query github, every filter", Issue.query(Ctx.GitHub{}, 100n, "closed", "bug", "memu", "2026-09-30T12:00:00Z", False{}), "issues?per_page=100&state=closed&labels=bug&assignee=memu&since=2026-09-30T12%3A00%3A00Z"))
    IO.print(check("query gitea, with-prs drops type", Issue.query(Ctx.Gitea{}, 50n, "open", "", "", "", True{}), "issues?limit=50&state=open"))
    IO.print(check("query github, with-prs keeps its query", Issue.query(Ctx.GitHub{}, 100n, "open", "", "", "", True{}), "issues?per_page=100&state=open"))
    IO.print(check("query gitea, a label can't inject a parameter", Issue.query(Ctx.Gitea{}, 50n, "open", "a&state=closed", "", "", False{}), "issues?type=issues&limit=50&state=open&labels=a%26state%3Dclosed"))
    IO.print(check("query github, a label can't inject a parameter", Issue.query(Ctx.GitHub{}, 100n, "open", "a&state=closed", "", "", False{}), "issues?per_page=100&state=open&labels=a%26state%3Dclosed"))
    IO.print(check("query github, an assignee can't inject a parameter", Issue.query(Ctx.GitHub{}, 100n, "open", "", "a&labels=bug", "", False{}), "issues?per_page=100&state=open&assignee=a%26labels%3Dbug"))
    +three : List<&2, Map<&2, String>> = [url.row(""), url.row(""), url.row("")]
    IO.print(check("list.cut: --limit 2 keeps two rows", Nat.show(List.length(&2, Map<&2, String>, Issue.list.cut(three, 2n, True{}))), "2"))
    IO.print(check("list.cut: a limit past the rows keeps them all", Nat.show(List.length(&2, Map<&2, String>, Issue.list.cut(three, 5n, True{}))), "3"))
    IO.print(check("list.cut: no --limit keeps every row", Nat.show(List.length(&2, Map<&2, String>, Issue.list.cut(three, 2n, False{}))), "3"))
    IO.print(check("list.pages.of: --limit 2 reads one page", Nat.show(Issue.list.pages.of(False{}, 2n, 100n, True{})), "1"))
    IO.print(check("list.pages.of: --limit 120 reads three gitea pages", Nat.show(Issue.list.pages.of(False{}, 120n, 50n, True{})), "3"))
    IO.print(check("list.pages.of: no --limit reads one page", Nat.show(Issue.list.pages.of(False{}, 50n, 50n, False{})), "1"))
    IO.print(check("list.pages.of: --all reads a hundred", Nat.show(Issue.list.pages.of(True{}, 100n, 100n, False{})), "100"))
    IO.print(check("unknown: issue list --bogus 3", String.join(Cli.unknown(Issue.list.flags(), ["--bogus", "3"]), ","), "--bogus"))
    IO.print(check("unknown: issue list --bogus message", Cli.unknown.msg("issue list", Ctx.first(Cli.unknown(Issue.list.flags(), ["--bogus", "3"])), Issue.list.flags()), "unknown flag --bogus for issue list; flags: --state --label --assignee --since --with-prs --all --limit --json"))
    IO.print(check("unknown: every issue list flag is known", String.join(Cli.unknown(Issue.list.flags(), ["--state", "all", "--label", "bug", "--assignee", "u", "--since", "1d", "--with-prs", "--all", "--limit", "2", "--json"]), ","), ""))
    IO.print(check("unknown: --limit=3 is judged as --limit", String.join(Cli.unknown(["--state"], ["--limit=3", "--state=open"]), ","), "--limit"))
    IO.print(check("unknown: -h, --help and -R always pass", String.join(Cli.unknown(Nil{}, ["-h", "--help", "-R", "o/r"]), ","), ""))
    IO.print(check("unknown: a value that starts with - is a value", String.join(Cli.unknown(["--body"], ["7", "--body", "-1 from me"]), ","), ""))
    IO.print(check("unknown: first seen, each once", String.join(Cli.unknown(["--a"], ["--y", "1", "--a", "2", "--x", "3", "--y", "4"]), ","), "--y,--x"))
    IO.print(check("unknown.msg: a command without flags", Cli.unknown.msg("issue reopen", "--x", Nil{}), "unknown flag --x for issue reopen; flags: none"))
