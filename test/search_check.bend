# offline checks for search: the kind words and their flags, the query and url each forge
# asks (scope, state, encoding), the page size cap, and the rows an item list becomes.
# Run: bend test/search_check.bend
import Base
import ../src/ctx.bend as Ctx
import ../src/api.bend as Api
import ../src/cmd/search.bend as Search

def row.put(m: Map<&2, String>, p: String & String) -> Map<&2, String>:
  (k, v) = p
  Map.set(&2, String, m, k, v)

def row.go(ps: List<&1, String & String>, m: Map<&2, String>) -> Map<&2, String>:
  match ps:
    case Nil{}:
      m
    case Con{p, t}:
      row.go(t, row.put(m, p))

# a row as Api.obj flattens one
def row.of(ps: List<&1, String & String>) -> Map<&2, String>:
  row.go(ps, Map.new(&2, String))

def report.if(good: Bool, +name: String, +got: String, +want: String) -> String:
  match good:
    case True{}:
      "ok   " ++ name
    case False{}:
      "FAIL " ++ name ++ ": got [" ++ got ++ "], want [" ++ want ++ "]"

def check(+name: String, +got: String, +want: String) -> String:
  report.if(String.eq(got, want), name, got, want)

def gh.repo() -> Ctx.Repo:
  Ctx.Repo{Ctx.GitHub{}, "github.com", "bendlang", "bend"}

def gitea.repo() -> Ctx.Repo:
  Ctx.Repo{Ctx.Gitea{}, "codeberg.org", "forgejo", "forgejo"}

# no repo at all: what search gets outside a checkout
def whole.repo() -> Ctx.Repo:
  Ctx.Repo{Ctx.GitHub{}, "github.com", "", ""}

def head(xs: List<&2, Map<&2, String>>) -> Map<&2, String>:
  match xs:
    case Nil{}:
      Map.new(&2, String)
    case Con{+x, rest}:
      x

def count(xs: List<&2, Map<&2, String>>) -> String:
  Nat.show(List.length(&2, Map<&2, String>, xs))

# a github issue search body, flattened as Api.obj flattens one
def issues.map() -> Map<&2, String>:
  row.of([("items.#", "1"),
          ("items.0.number", "7"),
          ("items.0.state", "open"),
          ("items.0.title", "kettle leak"),
          ("items.0.user.login", "memu"),
          ("items.0.html_url", "https://example.test/issues/7"),
          ("items.0.repository_url", "https://api.github.com/repos/bendlang/bend"),
          ("items.0.labels.#", "2"),
          ("items.0.labels.0.name", "bug"),
          ("items.0.labels.1.name", "tea")])

# a gitea issue search row: Api.all gives it already flat, with the repo in repository
def gitea.issue() -> Map<&2, String>:
  row.of([("number", "12"),
          ("state", "open"),
          ("title", "a leak"),
          ("user.login", "forgejo"),
          ("repository.full_name", "forgejo/forgejo"),
          ("labels.#", "1"),
          ("labels.0.name", "tea")])

# a github code hit: it names its repo in repository.full_name, not repository_url
def github.code() -> Map<&2, String>:
  row.of([("items.#", "1"),
          ("items.0.name", "main.bend"),
          ("items.0.path", "src/main.bend"),
          ("items.0.html_url", "https://example.test/blob/main.bend"),
          ("items.0.repository.full_name", "bendlang/bend")])

# gitea's repo search answers the whole repo, under data
def gitea.repos() -> Map<&2, String>:
  row.of([("data.#", "1"),
          ("data.0.full_name", "example/sandbox"),
          ("data.0.description", "a sandbox"),
          ("data.0.private", "false"),
          ("data.0.internal", "false"),
          ("data.0.stars_count", "3"),
          ("data.0.forks_count", "1"),
          ("data.0.open_issues_count", "2")])

def issue.show(+x: Map<&2, String>) -> String:
  Api.f(x, "repo") ++ " #" ++ Api.f(x, "number") ++ " " ++ Api.f(x, "state") ++ " " ++ Api.f(x, "title") ++ " " ++ Api.f(x, "user.login") ++ " [" ++ Api.f(x, "labels") ++ "]"

def code.show(+x: Map<&2, String>) -> String:
  Api.f(x, "repo") ++ " " ++ Api.f(x, "path") ++ " " ++ Api.f(x, "name")

def repo.show(+x: Map<&2, String>) -> String:
  Api.f(x, "full_name") ++ " " ++ Api.f(x, "forge") ++ " " ++ Api.f(x, "visibility") ++ " stars " ++ Api.f(x, "stars") ++ " forks " ++ Api.f(x, "forks") ++ " issues " ++ Api.f(x, "open_issues")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(check("kind: issues", Nat.show(Search.kind.of("issues")), "0"))
    IO.print(check("kind: prs", Nat.show(Search.kind.of("prs")), "1"))
    IO.print(check("kind: repos", Nat.show(Search.kind.of("repos")), "2"))
    IO.print(check("kind: code", Nat.show(Search.kind.of("code")), "3"))
    IO.print(check("kind: a word that is no kind", Nat.show(Search.kind.of("issuesx")), "4"))
    IO.print(check("kind: nothing", Nat.show(Search.kind.of("")), "4"))
    IO.print(check("kind.name: 0", Search.kind.name(0n), "issues"))
    IO.print(check("kind.name: 3", Search.kind.name(3n), "code"))
    IO.print(check("flags: issues take --state and --owner", String.join(Search.flags.of(0n), " "), "--state --owner --limit --json"))
    IO.print(check("flags: repos take no --state", String.join(Search.flags.of(2n), " "), "--owner --limit --json"))
    IO.print(check("state.bad: empty", Bool.show(Search.state.bad("")), "False"))
    IO.print(check("state.bad: all", Bool.show(Search.state.bad("all")), "False"))
    IO.print(check("state.bad: closed", Bool.show(Search.state.bad("closed")), "False"))
    IO.print(check("state.bad: anything else", Bool.show(Search.state.bad("merged")), "True"))
    IO.print(check("state.norm: all is every state", Search.state.norm("all"), ""))
    IO.print(check("state.norm: closed stays", Search.state.norm("closed"), "closed"))
    IO.print(check("wide.of: the current repo", Bool.show(Search.wide.of(gh.repo(), "")), "False"))
    IO.print(check("wide.of: an owner", Bool.show(Search.wide.of(gh.repo(), "bendlang")), "True"))
    IO.print(check("wide.of: no repo at all", Bool.show(Search.wide.of(whole.repo(), "")), "True"))
    IO.print(check("size.of: github takes a hundred", Nat.show(Search.size.of(Ctx.GitHub{}, 200n)), "100"))
    IO.print(check("size.of: gitea takes fifty", Nat.show(Search.size.of(Ctx.Gitea{}, 200n)), "50"))
    IO.print(check("size.of: a smaller limit stands", Nat.show(Search.size.of(Ctx.GitHub{}, 7n)), "7"))
    IO.print(check("github issues, repo scope", Search.issue.url(Ctx.GitHub{}, gh.repo(), "", "kettle", "", 20n, False{}), "search/issues?q=kettle%20is%3Aissue%20repo%3Abendlang%2Fbend&per_page=20"))
    IO.print(check("github prs, state and repo", Search.issue.url(Ctx.GitHub{}, gh.repo(), "", "steam", "open", 20n, True{}), "search/issues?q=steam%20is%3Apr%20is%3Aopen%20repo%3Abendlang%2Fbend&per_page=20"))
    IO.print(check("github prs, closed", Search.issue.url(Ctx.GitHub{}, gh.repo(), "", "steam", "closed", 5n, True{}), "search/issues?q=steam%20is%3Apr%20is%3Aclosed%20repo%3Abendlang%2Fbend&per_page=5"))
    IO.print(check("github issues, an owner", Search.issue.url(Ctx.GitHub{}, gh.repo(), "forgejo", "kettle", "", 20n, False{}), "search/issues?q=kettle%20is%3Aissue%20user%3Aforgejo&per_page=20"))
    IO.print(check("github issues, the whole forge", Search.issue.url(Ctx.GitHub{}, whole.repo(), "", "kettle", "", 20n, False{}), "search/issues?q=kettle%20is%3Aissue&per_page=20"))
    IO.print(check("gitea issues, repo scope", Search.issue.url(Ctx.Gitea{}, gitea.repo(), "", "kettle", "", 20n, False{}), "repos/forgejo/forgejo/issues?limit=20&state=all&type=issues&q=kettle"))
    IO.print(check("gitea prs, closed and an owner", Search.issue.url(Ctx.Gitea{}, gitea.repo(), "forgejo", "kettle", "closed", 20n, True{}), "repos/issues/search?limit=20&state=closed&type=pulls&q=kettle&owner=forgejo"))
    IO.print(check("gitea issues, the whole forge", Search.issue.url(Ctx.Gitea{}, whole.repo(), "", "kettle", "", 20n, False{}), "repos/issues/search?limit=20&state=all&type=issues&q=kettle"))
    IO.print(check("gitea issues, a query can't inject a parameter", Search.issue.url(Ctx.Gitea{}, gitea.repo(), "", "a&type=pulls", "", 20n, False{}), "repos/forgejo/forgejo/issues?limit=20&state=all&type=issues&q=a%26type%3Dpulls"))
    IO.print(check("github repos, an owner", Search.repo.url(Ctx.GitHub{}, "bendlang", "bend", 20n), "search/repositories?q=bend%20user%3Abendlang&per_page=20"))
    IO.print(check("github repos, the whole forge", Search.repo.url(Ctx.GitHub{}, "", "bend", 20n), "search/repositories?q=bend&per_page=20"))
    IO.print(check("gitea repos, the whole forge", Search.repo.url(Ctx.Gitea{}, "", "forgejo", 50n), "repos/search?limit=50&q=forgejo"))
    IO.print(check("github code, repo scope", Search.code.url(Ctx.GitHub{}, gh.repo(), "", "IO.now", 20n), "search/code?q=IO.now%20repo%3Abendlang%2Fbend&per_page=20"))
    IO.print(check("github code, an owner", Search.code.url(Ctx.GitHub{}, gh.repo(), "bendlang", "IO.now", 20n), "search/code?q=IO.now%20user%3Abendlang&per_page=20"))
    IO.print(check("gitea code asks nothing", Search.code.url(Ctx.Gitea{}, gitea.repo(), "", "IO.now", 20n), ""))
    IO.print(check("url.of: issues", Search.url.of(0n, Ctx.GitHub{}, whole.repo(), "", "kettle", "", 20n), "search/issues?q=kettle%20is%3Aissue&per_page=20"))
    IO.print(check("url.of: code", Search.url.of(3n, Ctx.GitHub{}, whole.repo(), "", "kettle", "", 20n), "search/code?q=kettle&per_page=20"))
    +rows : List<&2, Map<&2, String>> = Search.rows.of(0n, issues.map(), "items", Ctx.GitHub{})
    IO.print(check("rows.of: one github issue", count(rows), "1"))
    IO.print(check("rows.of: an issue, as issue list prints it", issue.show(head(rows)), "bendlang/bend #7 open kettle leak memu [bug,tea]"))
    +grows : List<&2, Map<&2, String>> = Search.shape(0n, Con{gitea.issue(), Nil{}}, False{})
    IO.print(check("shape: a gitea issue joins labels and names its repo", issue.show(head(grows)), "forgejo/forgejo #12 open a leak forgejo [tea]"))
    +shaped : List<&2, Map<&2, String>> = Search.rows.of(2n, gitea.repos(), "data", Ctx.Gitea{})
    IO.print(check("rows.of: a gitea repo becomes repo view's row", repo.show(head(shaped)), "example/sandbox gitea public stars 3 forks 1 issues 2"))
    +hits : List<&2, Map<&2, String>> = Search.rows.of(3n, github.code(), "items", Ctx.GitHub{})
    IO.print(check("rows.of: a code hit names its repo", code.show(head(hits)), "bendlang/bend src/main.bend main.bend"))
    +prs : List<&2, Map<&2, String>> = Search.rows.of(1n, issues.map(), "items", Ctx.GitHub{})
    IO.print(check("rows.of: a pr row carries labels too", Api.f(head(prs), "labels"), "bug,tea"))
