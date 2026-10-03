# cha moved: what happened in a repo since a window, in one sweep.
import Base
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli
import ../since.bend as Since

# one section of the sweep: its heading, its rows, and the error when it couldn't be fetched
type Section is Data:
  Section{head: String, rows: List<&2, Map<&2, String>>, error: String}

# the four sections together
type Sections is Data:
  Sections{issues: Section, comments: Section, commits: Section, runs: Section}

# which section a row belongs to, so one renderer serves them all
type Part is Data:
  Issue{}
  Comment{}
  Commit{}
  Run{}

# Windows
# -------

def cmp.at.least(c: Cmp) -> Bool:
  match c:
    case LT{}:
      False{}
    case x:
      True{}

# whether a parsed timestamp is at or after the window's start; False when it doesn't parse
def at.least(m: Maybe<&2, Time.Instant>, bound: Time.Instant) -> Bool:
  match m:
    case Some{i}:
      cmp.at.least(Time.Instant.cmp(i, bound))
    case None{}:
      False{}

def at.least.text(+text: String, bound: Time.Instant) -> Bool:
  at.least(Time.rfc3339.parse(text), bound)

# Sections
# --------

def section.of(+head: String, r: Result<&1, &1, String, List<&2, Map<&2, String>>>) -> Section:
  match r:
    case Done{rows}:
      Section{head, rows, ""}
    case Fail{w}:
      Section{head, Nil{}, w}

def section.error(+s: Section) -> String:
  match s:
    case Section{h, rows, e}:
      e

def section.rows(+s: Section) -> List<&2, Map<&2, String>>:
  match s:
    case Section{h, rows, e}:
      rows

# issues and pull requests go in one section, so their two pages merge
def section.merge(a: Section, b: Section) -> Section:
  match a b:
    case Section{h, xs, ea} Section{h2, ys, eb}:
      Section{h, List.append(&2, Map<&2, String>, xs, ys), Ctx.or(ea, eb)}

def head.issues() -> String:
  "issues and pull requests"

def head.comments() -> String:
  "new comments"

def head.commits(+branch: String) -> String:
  Ctx.or.if("commits on " ++ branch, "commits", String.is_empty(branch))

def head.runs() -> String:
  "actions runs"

# Queries
# -------

def issue.query(+f: Ctx.Forge, +kind: String, +since: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "issues?state=all&type=" ++ kind ++ "&limit=50&page=1&since=" ++ since
    case Ctx.GitHub{}:
      "issues?state=all&per_page=100&since=" ++ since

def comment.query(+f: Ctx.Forge, +since: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "issues/comments?limit=50&page=1&since=" ++ since
    case Ctx.GitHub{}:
      "issues/comments?per_page=100&since=" ++ since

def commit.query(+f: Ctx.Forge, +branch: String, +since: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "commits?limit=50&page=1&since=" ++ since ++ Ctx.or.if("&sha=" ++ branch, "", String.is_empty(branch))
    case Ctx.GitHub{}:
      "commits?per_page=100&since=" ++ since ++ Ctx.or.if("&sha=" ++ branch, "", String.is_empty(branch))

def run.query(+f: Ctx.Forge) -> String:
  match f:
    case Ctx.Gitea{}:
      "actions/runs?limit=50&page=1"
    case Ctx.GitHub{}:
      "actions/runs?per_page=100"

# Rows
# ----

# A row holds what the forge sent: these builders read raw, and the text printers read the
# row back through Api.f. --json reads it through Api.raw.f.

# a comment sits on an issue or a pull request; a forge may fill only one of the two urls
def with.number(+x: Map<&2, String>) -> Map<&2, String>:
  Map.set(&2, String, x, "number", Ctx.last(String.split(Ctx.or(Api.raw.f(x, "issue_url"), Api.raw.f(x, "pull_request_url")), '/')))

def with.first(+x: Map<&2, String>) -> Map<&2, String>:
  Map.set(&2, String, x, "first", Ctx.first(String.lines(Api.raw.f(x, "body"))))

def comment.row(+x: Map<&2, String>) -> Map<&2, String>:
  with.first(with.number(x))

def comment.rows(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      comment.row(x) <> comment.rows(t)

def comment.section(s: Section) -> Section:
  match s:
    case Section{h, xs, e}:
      Section{h, comment.rows(xs), e}

def with.short(+x: Map<&2, String>) -> Map<&2, String>:
  Map.set(&2, String, x, "short", String.take(Api.raw.f(x, "sha"), 7n))

def with.subject(+x: Map<&2, String>) -> Map<&2, String>:
  Map.set(&2, String, x, "subject", Ctx.first(String.lines(Api.raw.f(x, "commit.message"))))

def with.who(+x: Map<&2, String>) -> Map<&2, String>:
  Map.set(&2, String, x, "author", Ctx.or(Api.raw.f(x, "commit.author.name"), Api.raw.f(x, "author.login")))

def commit.row(+x: Map<&2, String>) -> Map<&2, String>:
  with.who(with.subject(with.short(x)))

def commit.rows(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      commit.row(x) <> commit.rows(t)

def commit.section(s: Section) -> Section:
  match s:
    case Section{h, xs, e}:
      Section{h, commit.rows(xs), e}

# the run's conclusion once it finished, its status while it runs
def run.state(+flat: Map<&2, String>, +pre: String) -> String:
  Ctx.or(Api.raw.f(flat, pre ++ "conclusion"), Api.raw.f(flat, pre ++ "status"))

# the workflow's name, or its file for a forge that answers with a run path
def run.workflow(+flat: Map<&2, String>, +pre: String) -> String:
  Ctx.or(Api.raw.f(flat, pre ++ "name"), Ctx.first(String.split(Api.raw.f(flat, pre ++ "path"), '@')))

def run.created(+flat: Map<&2, String>, +pre: String) -> String:
  Ctx.or(Api.raw.f(flat, pre ++ "created_at"), Api.raw.f(flat, pre ++ "started_at"))

def run.updated(+flat: Map<&2, String>, +pre: String) -> String:
  Ctx.or(Api.raw.f(flat, pre ++ "updated_at"), Api.raw.f(flat, pre ++ "completed_at"))

def run.row(+flat: Map<&2, String>, +pre: String) -> Map<&2, String>:
  +r0 = Map.new(&2, String)
  +r1 = Map.set(&2, String, r0, "state", run.state(flat, pre))
  +r2 = Map.set(&2, String, r1, "workflow", run.workflow(flat, pre))
  +r3 = Map.set(&2, String, r2, "branch", Api.raw.f(flat, pre ++ "head_branch"))
  +r4 = Map.set(&2, String, r3, "created", run.created(flat, pre))
  +r5 = Map.set(&2, String, r4, "updated", run.updated(flat, pre))
  Map.set(&2, String, r5, "html_url", Api.raw.f(flat, pre ++ "html_url"))

def run.recent(+row: Map<&2, String>, +bound: Time.Instant) -> Bool:
  Bool.or(at.least.text(Api.raw.f(row, "created"), bound), at.least.text(Api.raw.f(row, "updated"), bound))

def run.rows(+n: Nat, +flat: Map<&2, String>, +i: U32, acc: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match n:
    case 0n:
      acc
    case 1n+k:
      run.rows(k, flat, (i + 1 : U32), List.append(&2, Map<&2, String>, acc, run.row(flat, "workflow_runs." ++ U32.show(i) ++ ".") <> Nil{}))

def run.mark(keep: Bool, +row: Map<&2, String>) -> Maybe<&2, Map<&2, String>>:
  match keep:
    case True{}:
      Some{row}
    case False{}:
      None{}

# each run paired with whether it belongs in the window
# classify, then match: the Bool must be read before the list can be walked
def run.marked(xs: List<&2, Map<&2, String>>, +bound: Time.Instant) -> List<&2, Maybe<&2, Map<&2, String>>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      run.mark(run.recent(x, bound), x) <> run.marked(t, bound)

# the runs created or updated in the window, newest first
def run.kept(ms: List<&2, Maybe<&2, Map<&2, String>>>) -> List<&2, Map<&2, String>>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{Some{x}, t}:
      x <> run.kept(t)
    case Con{None{}, t}:
      run.kept(t)

# the runs endpoint answers with an object holding workflow_runs, which Api.rows can't read
def run.section(+flat: Map<&2, String>, +bound: Time.Instant) -> Section:
  Section{head.runs(), run.kept(run.marked(run.rows(Api.count(flat, "workflow_runs"), flat, 0, Nil{}), bound)), ""}

# Fetching
# --------

def fetch.section(+repo: Ctx.Repo, +tok: String, +head: String, url: String) -> IO(Section):
  do IO<Section>:
    r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(1n, repo, tok, url)
    return section.of(head, r)

def issues.of(+repo: Ctx.Repo, +tok: String, +since: String) -> IO(Section):
  match repo:
    case Ctx.Repo{+f, h, o, n}:
      match f:
        case Ctx.Gitea{}:
          do IO<Section>:
            a : Section <- fetch.section(repo, tok, head.issues(), Api.path(repo, issue.query(f, "issues", since)))
            b : Section <- fetch.section(repo, tok, head.issues(), Api.path(repo, issue.query(f, "pulls", since)))
            return section.merge(a, b)
        case Ctx.GitHub{}:
          fetch.section(repo, tok, head.issues(), Api.path(repo, issue.query(f, "issues", since)))

def comments.of(+repo: Ctx.Repo, +tok: String, +since: String) -> IO(Section):
  match repo:
    case Ctx.Repo{+f, h, o, n}:
      do IO<Section>:
        s : Section <- fetch.section(repo, tok, head.comments(), Api.path(repo, comment.query(f, since)))
        return comment.section(s)

# the repo's default branch, "" when the request fails
def branch.of(rep: Api.Reply) -> String:
  match rep:
    case Api.Broke{w}:
      ""
    case Api.Reply{+status, next, body}:
      Bool.pick(String, Api.ok(status), Api.f(Api.obj(body), "default_branch"), "")

# the repo itself. Api.path always ends in a slash, which github answers with a 404
def repo.url(+repo: Ctx.Repo) -> String:
  Ctx.strip_suffix(Api.path(repo, ""), "/")

def default_branch(+repo: Ctx.Repo, +tok: String) -> IO(String):
  do IO<String>:
    rep : Api.Reply <- Api.get(repo, tok, repo.url(repo))
    return branch.of(rep)

def commits.of(+repo: Ctx.Repo, +tok: String, +since: String) -> IO(Section):
  match repo:
    case Ctx.Repo{+f, h, o, n}:
      do IO<Section>:
        +branch : String <- default_branch(repo, tok)
        s : Section <- fetch.section(repo, tok, head.commits(branch), Api.path(repo, commit.query(f, branch, since)))
        return commit.section(s)

def runs.status(ok: Bool, +status: U32, body: Bytes.Bytes, +bound: Time.Instant) -> Section:
  match ok:
    case True{}:
      run.section(Api.obj(body), bound)
    case False{}:
      Section{head.runs(), Nil{}, Api.message(status, body)}

def runs.reply(rep: Api.Reply, +bound: Time.Instant) -> Section:
  match rep:
    case Api.Broke{w}:
      Section{head.runs(), Nil{}, w}
    case Api.Reply{+status, next, body}:
      runs.status(Api.ok(status), status, body, bound)

def runs.of(+repo: Ctx.Repo, +tok: String, +bound: Time.Instant) -> IO(Section):
  match repo:
    case Ctx.Repo{+f, h, o, n}:
      do IO<Section>:
        rep : Api.Reply <- Api.get(repo, tok, Api.path(repo, run.query(f)))
        return runs.reply(rep, bound)

# Rendering
# ---------

def issue.line(+on: Bool, +x: Map<&2, String>) -> String:
  Ui.bold(on, Ui.fg(on, Ui.aqua(), "#" ++ Api.f(x, "number"))) ++ "  " ++ Ui.state(on, Api.f(x, "state")) ++ "  " ++ Api.f(x, "title") ++ "  " ++ Ui.dim(on, "@" ++ Api.f(x, "user.login"))

def comment.line(+on: Bool, +x: Map<&2, String>) -> String:
  Ui.bold(on, Ui.fg(on, Ui.aqua(), "#" ++ Api.f(x, "number"))) ++ "  " ++ Ui.dim(on, "@" ++ Api.f(x, "user.login")) ++ "  " ++ Api.f(x, "first")

def commit.line(+on: Bool, +x: Map<&2, String>) -> String:
  Ui.fg(on, Ui.aqua(), Api.f(x, "short")) ++ "  " ++ Ui.dim(on, Api.f(x, "author")) ++ "  " ++ Api.f(x, "subject")

def run.line(+on: Bool, +x: Map<&2, String>) -> String:
  Ui.state(on, Api.f(x, "state")) ++ "  " ++ Api.f(x, "workflow") ++ "  " ++ Ui.dim(on, Api.f(x, "branch"))

def row.line(+part: Part, +on: Bool, +x: Map<&2, String>) -> String:
  match part:
    case Issue{}:
      issue.line(on, x)
    case Comment{}:
      comment.line(on, x)
    case Commit{}:
      commit.line(on, x)
    case Run{}:
      run.line(on, x)

def rows.lines(+part: Part, +on: Bool, xs: List<&2, Map<&2, String>>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      row.line(part, on, x) <> rows.lines(part, on, t)

def indent(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, t}:
      "  " ++ x ++ "\n" ++ indent(t)

def block.at(+on: Bool, +head: String, +body: String) -> String:
  "\n" ++ Ui.bold(on, head) ++ "\n" ++ Ctx.or.if(body, "  " ++ Ui.dim(on, "nothing") ++ "\n", String.is_empty(body))

def block(+on: Bool, +part: Part, s: Section) -> String:
  match s:
    case Section{head, rows, error}:
      block.at(on, head, indent(rows.lines(part, on, rows)))

def text(+on: Bool, +label: String, +s: Sections) -> String:
  match s:
    case Sections{i, c, m, r}:
      "moved since " ++ label ++ "\n" ++ block(on, Issue{}, i) ++ block(on, Comment{}, c) ++ block(on, Commit{}, m) ++ block(on, Run{}, r)

def json.fields(part: Part) -> List<&2, String>:
  match part:
    case Issue{}:
      ["number", "state", "title", "user.login", "html_url"]
    case Comment{}:
      ["number", "user.login", "first", "html_url"]
    case Commit{}:
      ["sha", "short", "author", "subject", "html_url"]
    case Run{}:
      ["state", "workflow", "branch", "html_url"]

def json.part(part: Part, +s: Section) -> String:
  Cli.json.rows(section.rows(s), json.fields(part))

def json.text(+label: String, +s: Sections) -> String:
  match s:
    case Sections{i, c, m, r}:
      "{\"since\":\"" ++ label ++ "\",\"issues\":" ++ json.part(Issue{}, i) ++ ",\"comments\":" ++ json.part(Comment{}, c) ++ ",\"commits\":" ++ json.part(Commit{}, m) ++ ",\"runs\":" ++ json.part(Run{}, r) ++ "}"

# Command
# -------

def sections.error(+s: Sections) -> String:
  match s:
    case Sections{i, c, m, r}:
      Ctx.or(section.error(i), Ctx.or(section.error(c), Ctx.or(section.error(m), section.error(r))))

def show(+on: Bool, json: Cli.Json, +label: String, +s: Sections) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(text(on, label, s))
    case j:
      do IO<Unit>:
        Cli.json.whole(on, j, "moved")
        IO.print(json.text(label, s))

def decide(empty: Bool, +env: Cli.Env, +label: String, +s: Sections) -> IO(Unit):
  match empty:
    case True{}:
      match env:
        case Cli.Env{r, t, on, json, a}:
          show(on, json, label, s)
    case False{}:
      Cli.fail(Unit, env, sections.error(s))

def out(+env: Cli.Env, +label: String, +s: Sections) -> IO(Unit):
  decide(String.is_empty(sections.error(s)), env, label, s)

# the four sections are independent requests, so they run at the same time
def sweep(+env: Cli.Env, +bound: Time.Instant, +label: String) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, args}:
      do IO<Unit>:
        ci : Chan(Section) <- IO.fork(Section, issues.of(repo, tok, label))
        cc : Chan(Section) <- IO.fork(Section, comments.of(repo, tok, label))
        cm : Chan(Section) <- IO.fork(Section, commits.of(repo, tok, label))
        cr : Chan(Section) <- IO.fork(Section, runs.of(repo, tok, bound))
        si : Section <- IO.join(Section, ci)
        sc : Section <- IO.join(Section, cc)
        sm : Section <- IO.join(Section, cm)
        sr : Section <- IO.join(Section, cr)
        +s : Sections = Sections{si, sc, sm, sr}
        out(env, label, s)

def start(+env: Cli.Env, +since: Maybe<&2, Time.Instant>) -> IO(Unit):
  match since:
    case Some{bound}:
      sweep(env, bound, Since.rfc(bound))
    case None{}:
      Cli.fail(Unit, env, "moved --since: expected 1d, 6h, 30m or an RFC 3339 date-time")

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{repo, tok, on, json, +args}:
      do IO<Unit>:
        now : Time.Instant <- Time.now()
        +m : Maybe<&2, Time.Instant> = Since.of(now, Cli.flag(args, "--since", "1d"))
        start(env, m)
