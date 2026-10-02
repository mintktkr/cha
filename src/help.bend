# help: cha help, cha help <command>, the banner and fish completions.
# Full sparkle on a terminal, plain text when piped: colour, animation and kaomoji
# only when `on`, never an escape byte or a \r otherwise.
import Base
import ./ui.bend as Ui
import ./cli.bend as Cli
import 0xd60fd658d4bdabf892f8041a7a731848/tty.bend as Tty

# one line of a command list: the name and its args, a description, an example
type Row is Data:
  Row{name: String, desc: String, ex: String}

# a command group's page: title, usage, its commands, its flags, examples
type Page is Data:
  Page{title: String, usage: String, rows: List<&2, Row>, flags: List<&2, Row>, examples: List<&2, String>}

# Layout
# ------

# s padded to w columns, two spaces when it already fills them
def pad.at(+s: String, +w: Nat, short: Bool) -> String:
  match short:
    case True{}:
      s ++ String.repeat(" ", Nat.sub(w, String.length(s)))
    case False{}:
      s ++ "  "

def pad(+s: String, +w: Nat) -> String:
  pad.at(s, w, Nat.is_lt(String.length(s), w))

# esc when on, nothing otherwise: cursor moves only reach a terminal with colour
def esc.if(+on: Bool, +esc: String) -> String:
  match on:
    case True{}:
      esc
    case False{}:
      ""

# the trailing ' · example' of a row, nothing when there is no example
def tail.if(+on: Bool, +ex: String, none: Bool) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      " · " ++ Ui.dim(on, ex)

# a padded bold aqua name
def name.of(+on: Bool, +n: String, +w: Nat) -> String:
  Ui.bold(on, Ui.fg(on, Ui.aqua(), pad(n, w)))

# one row: name, description, example
def row.line(+on: Bool, +r: Row, w: Nat) -> String:
  match r:
    case Row{n, d, e}:
      "  " ++ name.of(on, n, w) ++ d ++ tail.if(on, e, String.is_empty(e))

def row.lines(+on: Bool, +rs: List<&2, Row>, +w: Nat) -> String:
  match rs:
    case Nil{}:
      ""
    case Con{r, t}:
      row.line(on, r, w) ++ "\n" ++ row.lines(on, t, w)

def ex.line(+on: Bool, +s: String) -> String:
  "    " ++ Ui.fg(on, Ui.aqua(), s)

def ex.lines(+on: Bool, +es: List<&2, String>) -> String:
  match es:
    case Nil{}:
      ""
    case Con{s, t}:
      ex.line(on, s) ++ "\n" ++ ex.lines(on, t)

# no rows at all, typed for an empty Page section
def no.rows() -> List<&2, Row>:
  Nil{}

def face.of(n: Nat) -> String:
  match n:
    case 0n:
      "(´∀｀)♡"
    case 1n+_:
      "ヽ(>∀<☆)ノ"

# The banner
# ----------
# A mug of tea beside the name. The page prints at once; then, when it all fits on the
# screen, the banner alone redraws in place for a second and comes to rest (ito's way:
# nothing waits on the show). Only on a terminal with colour.

def tagline() -> String:
  "a forge CLI for Gitea, Forgejo and GitHub"

def wisp.of(n: Nat) -> String:
  match n:
    case 0n:
      "("
    case 1n+_:
      ")"

# a wisp's curl: ( and ) swap a few times a second, so the steam seems to climb
def wisp(+k: Nat) -> String:
  wisp.of(Nat.mod(k, 2n))

def name.go(cs: List<&2, Char>, +on: Bool, +i: Nat, +t: F32) -> String:
  match cs:
    case Nil{}:
      ""
    case Con{c, rest}:
      Ui.fg(on, Ui.wave(F32.from_nat(i), t), String.from_list([c])) ++ name.go(rest, on, 1n+i, t)

# the name flowing at frame f, or the glow every log line starts with when still
def name.if(+on: Bool, +f: Nat, still: Bool) -> String:
  match still:
    case True{}:
      Ui.glow(on, "cha 茶")
    case False{}:
      name.go(String.to_list("cha 茶"), on, 0n, (F32.from_nat(f) / 30.0 : F32))

def mug(+on: Bool, s: String) -> String:
  Ui.fg(on, Ui.stop(4), s)

def steam(+on: Bool, s: String) -> String:
  Ui.fg(on, Ui.stop(4), Ui.dim(on, s))

# six lines, each clearing the rest of its row: two wisps, staggered, over the mug
def banner.of(+on: Bool, +f: Nat, still: Bool) -> String:
  +k = Nat.div(Nat.mul(f, 8n), 30n)
  "  " ++ steam(on, "   " ++ wisp(k)) ++ esc.if(on, "\u{1b}[K") ++ "\n" ++
  "  " ++ steam(on, "   " ++ wisp(1n+k) ++ "  " ++ wisp(k)) ++ esc.if(on, "\u{1b}[K") ++ "\n" ++
  "  " ++ mug(on, "╷   ") ++ steam(on, " " ++ wisp(1n+k) ++ " ") ++ mug(on, " ╷") ++ esc.if(on, "\u{1b}[K") ++ "\n" ++
  "  " ++ mug(on, "│ ") ++ Ui.fg(on, Ui.mint(), Ui.dim(on, "~~~~~")) ++ mug(on, " ├╮") ++ "    " ++ name.if(on, f, still) ++ "  " ++ face.of(0n) ++ "  " ++ tagline() ++ esc.if(on, "\u{1b}[K") ++ "\n" ++
  "  " ++ mug(on, "│       ├╯") ++ esc.if(on, "\u{1b}[K") ++ "\n" ++
  "  " ++ mug(on, "╰───────╯") ++ esc.if(on, "\u{1b}[K")

def esc.n(+n: Nat, +c: String) -> String:
  "\u{1b}[" ++ Nat.show(n) ++ c

# 30 frames at 33ms, then the still banner. up is how far the banner's first line is
# above the cursor; after the banner's six lines it is five lines lower.
def anim.go(+fuel: Nat, +on: Bool, +up: Nat, +f: Nat) -> IO(Unit):
  match fuel:
    case 0n:
      IO.write(esc.n(up, "F") ++ banner.of(on, f, True{}) ++ esc.n(Nat.sub(up, 5n), "E"))
    case 1n+k:
      do IO<Unit>:
        IO.sleep(33)
        IO.write(esc.n(up, "F") ++ banner.of(on, f, False{}) ++ esc.n(Nat.sub(up, 5n), "E"))
        anim.go(k, on, up, 1n+f)

def lines.fit(xs: List<&2, String>, +cols: U32) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{+x, rest}:
      (Tty.width(x) < cols : U32) && lines.fit(rest, cols)

def fits.wh(+lines: List<&2, String>, wh: U32 & U32) -> Bool:
  (cols, rows) = wh
  lines.fit(lines, cols) && Nat.is_lt(List.length(&2, String, lines), U32.to_nat(rows))

# the whole page is on screen without wrapping, so jumping back up lands on the banner
def fits.of(+lines: List<&2, String>, size: Maybe<&1, U32 & U32>) -> Bool:
  match size:
    case None{}:
      False{}
    case Some{wh}:
      fits.wh(lines, wh)

# cha help
# --------

def groups() -> List<&2, Row>:
  [Row{"issue", "issues: list, view, create, comment, edit, close, reopen, labels", "cha issue list --state open"},
   Row{"pr", "pull requests: list, view, diff, create, merge, edit, comment, checks", "cha pr list"},
   Row{"runs", "actions: list, view, logs, watch, dispatch, rerun, cancel", "cha runs watch 4142"},
   Row{"repo", "repo: view, labels, label-create, branches, file, tree", "cha repo labels"},
   Row{"release", "releases: list, view, latest, create", "cha release latest"},
   Row{"moved", "what changed in the repo since a time", "cha moved --since 1d"},
   Row{"auth", "which login and token source a host uses", "cha auth status"},
   Row{"runners", "a repo's or an org's self-hosted runners", "cha runners"},
   Row{"help", "this page, or one command's usage", "cha help issue"},
   Row{"version", "print the version", "cha version"},
   Row{"completions", "a fish completion script", "cha completions fish"}]

def global.rows() -> List<&2, Row>:
  [Row{"-R owner/repo", "the repo, on the checkout's host", ""},
   Row{"-R host/owner/repo", "the repo, on any host", ""},
   Row{"--json [FIELDS]", "machine-readable rows, optionally only FIELDS", ""},
   Row{"--body-file -", "read a body from stdin", ""},
   Row{"NO_COLOR / TERM=dumb", "plain text, no colour", ""},
   Row{"CHA_TOKEN", "a token for any host", ""},
   Row{"CHA_USER", "which credential to pick for a host", ""},
   Row{"GITHUB_TOKEN", "a token for github.com", ""}]

# everything below the name line
def top.rest(+on: Bool) -> String:
  "  one binary. no gh, no tea, not even git.  " ++ face.of(1n) ++ "\n\n" ++
  row.lines(on, groups(), 13n) ++
  "\n  " ++ Ui.bold(on, "global flags") ++ "\n" ++
  row.lines(on, global.rows(), 24n) ++
  "\n  " ++ Ui.dim(on, "cha help <command>   that command's usage, flags and examples") ++ "\n"

def top.body(+on: Bool) -> String:
  "  " ++ Ui.glow(on, "cha 茶") ++ "  " ++ face.of(0n) ++ "  " ++ tagline() ++ "\n\n" ++ top.rest(on)

def anim.if(+on: Bool, +up: Nat, fits: Bool) -> IO(Unit):
  match fits:
    case True{}:
      anim.go(30n, on, up, 1n)
    case False{}:
      IO.pure(Unit, Unit{})

# the show only when the terminal asked for colour; a page taller or wider than the
# screen prints still, since the jump back up would land on the wrong lines
def top.at(+on: Bool, anim: Bool) -> IO(Unit):
  match anim:
    case True{}:
      do IO<Unit>:
        size : Maybe<&1, U32 & U32> <- Tty.size()
        +lines : List<&2, String> = String.split(banner.of(False{}, 0n, True{}) ++ "\n\n" ++ top.rest(False{}), '\n')
        +fits : Bool = fits.of(lines, size)
        IO.write(banner.of(on, 0n, Bool.not(fits)) ++ "\n\n" ++ top.rest(on))
        anim.if(on, Nat.sub(List.length(&2, String, lines), 1n), fits)
    case False{}:
      IO.write(top.body(on))

# cha help issue
# --------------

def issue.rows() -> List<&2, Row>:
  [Row{"list [--state open|closed|all] [--label L] [--all] [--json]", "list issues", "cha issue list --state open"},
   Row{"view N [--comments]", "one issue", "cha issue view 42 --comments"},
   Row{"create --title T [--body B|--body-file F] [--label a,b] [--assignee u]", "open an issue", "cha issue create --title \"kettle is empty\" --label bug"},
   Row{"comment N --body B|--body-file F", "comment on an issue", "cha issue comment 42 --body \"still empty\""},
   Row{"edit N [--title T] [--body B]", "edit an issue", "cha issue edit 42 --title \"kettle is full\""},
   Row{"close N [--comment C]", "close an issue", "cha issue close 42 --comment \"fixed\""},
   Row{"reopen N", "reopen an issue", "cha issue reopen 42"},
   Row{"labels N add|remove|set a,b", "change an issue's labels", "cha issue labels 42 add bug"}]

def issue.flags() -> List<&2, Row>:
  [Row{"--state open|closed|all", "which issues (default open)", ""},
   Row{"--label L", "only issues with this label", ""},
   Row{"--all", "every page, not just the first", ""},
   Row{"--json [FIELDS]", "machine-readable rows, optionally only FIELDS", ""},
   Row{"--comments", "include comments (view)", ""},
   Row{"--title T", "the title", ""},
   Row{"--body B", "the body text", ""},
   Row{"--body-file F", "the body from a file; - is stdin", ""},
   Row{"--label a,b", "comma-separated labels (create)", ""},
   Row{"--assignee u", "assign to this user", ""},
   Row{"--comment C", "a comment with the close", ""}]

def issue.examples() -> List<&2, String>:
  ["cha issue list --state all --json",
   "cha issue list --json number,title",
   "cha issue view 42 --comments",
   "cha issue create --title \"kettle is empty\" --body-file - --label bug"]

def issue.page() -> Page:
  Page{"cha issue", "cha issue <command> [flags]", issue.rows(), issue.flags(), issue.examples()}

# cha help pr
# -----------

def pr.rows() -> List<&2, Row>:
  [Row{"list [--state] [--json]", "list pull requests", "cha pr list"},
   Row{"view N [--comments]", "one pull request", "cha pr view 7 --comments"},
   Row{"diff N", "the diff", "cha pr diff 7"},
   Row{"create --head H [--base main] --title T [--body B|--body-file F]", "open a pull request", "cha pr create --head kettle --title \"steam\""},
   Row{"merge N [--squash|--merge|--rebase] [--delete-branch]", "merge a pull request", "cha pr merge 7 --squash"},
   Row{"edit N", "edit a pull request", "cha pr edit 7"},
   Row{"comment N --body B", "comment on a pull request", "cha pr comment 7 --body \"nice\""},
   Row{"checks N", "the checks", "cha pr checks 7"}]

def pr.flags() -> List<&2, Row>:
  [Row{"--state open|closed|all", "which pull requests (default open)", ""},
   Row{"--json [FIELDS]", "machine-readable rows, optionally only FIELDS", ""},
   Row{"--comments", "include comments (view)", ""},
   Row{"--head H", "the branch with the changes", ""},
   Row{"--base main", "the branch to merge into", ""},
   Row{"--title T", "the title", ""},
   Row{"--body B", "the body text", ""},
   Row{"--body-file F", "the body from a file; - is stdin", ""},
   Row{"--squash / --merge / --rebase", "how to merge", ""},
   Row{"--delete-branch", "delete the head branch after a merge", ""}]

def pr.examples() -> List<&2, String>:
  ["cha pr list --json",
   "cha pr view 7 --comments",
   "cha pr merge 7 --squash --delete-branch"]

def pr.page() -> Page:
  Page{"cha pr", "cha pr <command> [flags]", pr.rows(), pr.flags(), pr.examples()}

# cha help runs
# -------------

def runs.rows() -> List<&2, Row>:
  [Row{"list [--branch B] [--status S] [--workflow W] [--limit N]", "recent action runs", "cha runs list --branch main"},
   Row{"view ID", "run, jobs, runners and step timings", "cha runs view 4142"},
   Row{"logs ID [--job J] [--failed] [--step NAME]", "a run's logs", "cha runs logs 4142 --failed"},
   Row{"watch ID", "follow a run", "cha runs watch 4142"},
   Row{"dispatch FILE [--ref R] [--input k=v]", "start a workflow", "cha runs dispatch ci.yml --ref main"},
   Row{"rerun ID [--failed | --job ID]", "rerun a run or selected jobs", "cha runs rerun 4142"},
   Row{"cancel ID", "cancel a run", "cha runs cancel 4142"}]

def runs.flags() -> List<&2, Row>:
  [Row{"--branch B", "only runs of this branch", ""},
   Row{"--status S", "only runs in this state", ""},
   Row{"--workflow W", "workflow file or exact display name", ""},
   Row{"--limit N", "matching runs to return (1-1000)", ""},
   Row{"--job J", "log job id or name; rerun requires an id", ""},
   Row{"--step NAME", "only this step (case-insensitive name)", ""},
   Row{"--failed", "log or rerun only failed jobs", ""},
   Row{"--ref R", "the ref to dispatch on", ""},
   Row{"--input k=v", "a workflow input", ""}]

def runs.examples() -> List<&2, String>:
  ["cha runs list --branch main",
   "cha runs logs 4142 --failed",
   "cha runs dispatch ci.yml --ref main --input cup=full"]

def runs.page() -> Page:
  Page{"cha runs", "cha runs <command> [flags]", runs.rows(), runs.flags(), runs.examples()}

# cha help repo
# -------------

def repo.rows() -> List<&2, Row>:
  [Row{"view", "the repo", "cha repo view"},
   Row{"labels", "the repo's labels", "cha repo labels"},
   Row{"label-create NAME [--color HEX]", "make a label", "cha repo label-create tea --color ff6eb4"},
   Row{"branches", "the repo's branches", "cha repo branches"},
   Row{"file PATH [--ref R]", "a file's contents", "cha repo file README.md --ref main"},
   Row{"tree [--ref R]", "the repo's file tree", "cha repo tree"}]

def repo.flags() -> List<&2, Row>:
  [Row{"--color HEX", "the label's colour, like ff6eb4", ""},
   Row{"--ref R", "read from this branch or tag", ""}]

def repo.examples() -> List<&2, String>:
  ["cha repo view",
   "cha repo label-create tea --color ff6eb4",
   "cha repo file README.md --ref main"]

def repo.page() -> Page:
  Page{"cha repo", "cha repo <command> [flags]", repo.rows(), repo.flags(), repo.examples()}

# cha help release
# ----------------

def release.rows() -> List<&2, Row>:
  [Row{"list", "the repo's releases", "cha release list"},
   Row{"view TAG|latest", "one release", "cha release view latest"},
   Row{"latest", "the latest release", "cha release latest"},
   Row{"create TAG [--title T] [--notes N|--notes-file F] [--draft] [--prerelease]", "make a release", "cha release create v0.1.0 --title \"one cup\""}]

def release.flags() -> List<&2, Row>:
  [Row{"--title T", "the release's title", ""},
   Row{"--notes N", "the release notes", ""},
   Row{"--notes-file F", "the notes from a file; - is stdin", ""},
   Row{"--draft", "keep it a draft", ""},
   Row{"--prerelease", "mark it a prerelease", ""}]

def release.examples() -> List<&2, String>:
  ["cha release list",
   "cha release view latest",
   "cha release create v0.1.0 --title \"one cup\" --notes-file - --draft"]

def release.page() -> Page:
  Page{"cha release", "cha release <command> [flags]", release.rows(), release.flags(), release.examples()}

# cha help moved
# --------------

def moved.rows() -> List<&2, Row>:
  [Row{"moved [--since 1d|6h|30m|ISO]", "what changed in the repo since a time", "cha moved --since 1d"}]

def moved.flags() -> List<&2, Row>:
  [Row{"--since 1d|6h|30m|ISO", "how far back to look (default 1d)", ""}]

def moved.examples() -> List<&2, String>:
  ["cha moved",
   "cha moved --since 6h",
   "cha moved --since 2026-09-01T00:00:00Z"]

def moved.page() -> Page:
  Page{"cha moved", "cha moved [--since ...]", moved.rows(), moved.flags(), moved.examples()}

# cha help auth
# -------------

def auth.page() -> Page:
  Page{"cha auth", "cha auth [status]", [Row{"status", "host, forge, login and where the token came from; exit 1 without a working token", "cha auth status"}], [Row{"--json [FIELDS]", "host, forge, login, token_source", ""}], ["cha auth status", "cha -R github.com/owner/repo auth status --json"]}

# cha help runners
# ----------------

def runners.page() -> Page:
  Page{"cha runners", "cha runners [--org O] [--json]", [Row{"runners [--org O] [--json]", "a repo's or an org's self-hosted runners", "cha runners"}], [Row{"--org O", "the org whose runners to list, instead of the repo's", ""}, Row{"--json [FIELDS]", "id, name, status, busy, labels, os", ""}], ["cha runners", "cha runners --org sample-org --json"]}

# cha help help, version and completions
# --------------------------------------

def help.rows() -> List<&2, Row>:
  [Row{"help", "this page", "cha help"},
   Row{"help <command>", "one command's usage, flags and examples", "cha help issue"}]

def help.examples() -> List<&2, String>:
  ["cha help", "cha help issue"]

def help.page() -> Page:
  Page{"cha help", "cha help [command]", help.rows(), no.rows(), help.examples()}

def version.page() -> Page:
  Page{"cha version", "cha version", [Row{"version", "print the version", "cha version"}], no.rows(), ["cha version"]}

def completions.page() -> Page:
  Page{"cha completions", "cha completions fish", [Row{"completions fish", "a fish completion script on stdout", "cha completions fish"}], no.rows(), ["cha completions fish", "cha completions fish > ~/.config/fish/completions/cha.fish"]}

# Rendering a page
# ----------------

def page.section(+on: Bool, +title: String, +rs: List<&2, Row>, +w: Nat) -> String:
  "\n  " ++ Ui.bold(on, title) ++ "\n" ++ row.lines(on, rs, w)

def page.body(+on: Bool, +p: Page) -> String:
  match p:
    case Page{t, u, rs, fs, es}:
      "  " ++ Ui.bold(on, Ui.fg(on, Ui.aqua(), t)) ++ "  " ++ face.of(1n) ++ "\n\n" ++
      "  usage: " ++ Ui.fg(on, Ui.aqua(), u) ++ "\n\n" ++
      row.lines(on, rs, 28n) ++
      page.section(on, "flags", fs, 26n) ++
      page.section(on, "examples", no.rows(), 0n) ++ ex.lines(on, es) ++ "\n"

def page.show(+on: Bool, +p: Page) -> IO(Unit):
  IO.write(page.body(on, p))

# Dispatch
# --------

def pick(eq: Bool, k: Nat, later: Nat) -> Nat:
  match eq:
    case True{}:
      k
    case False{}:
      later

def group(+sub: String) -> Nat:
  pick(String.eq(sub, "issue"), 1n,
  pick(String.eq(sub, "pr"), 2n,
  pick(String.eq(sub, "runs"), 3n,
  pick(String.eq(sub, "repo"), 4n,
  pick(String.eq(sub, "release"), 5n,
  pick(String.eq(sub, "moved"), 6n,
  pick(String.eq(sub, "help"), 7n,
  pick(String.eq(sub, "version"), 8n,
  pick(String.eq(sub, "completions"), 9n,
  pick(String.eq(sub, "auth"), 10n,
  pick(String.eq(sub, "runners"), 11n, 0n)))))))))))

# the word's index in args, or the length when it isn't there
def idx.at(eq: Bool, i: Nat, later: Nat) -> Nat:
  match eq:
    case True{}:
      i
    case False{}:
      later

def idx(xs: List<&2, String>, +w: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case Con{x, rest}:
      idx.at(String.eq(x, w), i, idx(rest, w, 1n+i))

# main drops one word; global flags may sit before it, so skip to "help" when present
def sub.at(+args: List<&2, String>, has: Bool) -> String:
  match has:
    case True{}:
      Cli.arg(List.drop(&2, String, args, 1n+idx(args, "help", 0n)), 0n)
    case False{}:
      Cli.arg(args, 0n)

def unknown(+on: Bool, +sub: String) -> IO(Unit):
  do IO<Unit>:
    Ui.error(on, "cha help: no such command: " ++ sub)
    IO.die(Unit, 1, "")

# no command word: the full page, banner and all
# an empty sub is "cha" and "cha help" alike
def empty.at(+on: Bool, +sub: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      top.at(on, on)
    case False{}:
      unknown(on, sub)

def show(+on: Bool, +sub: String, k: Nat) -> IO(Unit):
  match k:
    case 0n:
      empty.at(on, sub, String.is_empty(sub))
    case 1n:
      page.show(on, issue.page())
    case 2n:
      page.show(on, pr.page())
    case 3n:
      page.show(on, runs.page())
    case 4n:
      page.show(on, repo.page())
    case 5n:
      page.show(on, release.page())
    case 6n:
      page.show(on, moved.page())
    case 7n:
      page.show(on, help.page())
    case 8n:
      page.show(on, version.page())
    case 9n:
      page.show(on, completions.page())
    case 10n:
      page.show(on, auth.page())
    case 11n+_:
      page.show(on, runners.page())

# cha, cha help, cha help <command>
def run(+on: Bool, +args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +sub : String = sub.at(args, Cli.has(args, "help"))
    show(on, sub, group(sub))

# cha completions fish
# --------------------

def comp.head() -> List<&2, String>:
  ["# cha completions for fish",
   "#   cha completions fish > ~/.config/fish/completions/cha.fish",
   "# or, in config.fish:",
   "#   cha completions fish | source",
   "",
   "function __cha_needs_command",
   "    set -l cmd (commandline -opc)",
   "    test (count $cmd) -eq 1",
   "end",
   "",
   "function __cha_sub_command",
   "    set -l cmd (commandline -opc)",
   "    test (count $cmd) -eq 2; and test $cmd[2] = $argv[1]",
   "end",
   "",
   "function __cha_in_group",
   "    set -l cmd (commandline -opc)",
   "    test (count $cmd) -ge 2; and test $cmd[2] = $argv[1]",
   "end",
   "",
   "function __cha_using_sub",
   "    set -l cmd (commandline -opc)",
   "    test (count $cmd) -ge 3; and test $cmd[2] = $argv[1]; and test $cmd[3] = $argv[2]",
   "end",
   "",
   "complete -c cha -f"]

def comp.global() -> List<&2, String>:
  ["complete -c cha -s R -x -d 'repo: owner/repo, or host/owner/repo'",
   "complete -c cha -l json -d 'machine-readable rows, optionally only FIELDS'",
   "complete -c cha -s h -l help -d 'this help'",
   ""]

def comp.groups() -> List<&2, String>:
  ["complete -c cha -n '__cha_needs_command' -a issue -d 'issues: list, view, create, comment, edit, close, reopen, labels'",
   "complete -c cha -n '__cha_needs_command' -a pr -d 'pull requests: list, view, diff, create, merge, edit, comment, checks'",
   "complete -c cha -n '__cha_needs_command' -a runs -d 'actions: list, view, logs, watch, dispatch, rerun, cancel'",
   "complete -c cha -n '__cha_needs_command' -a repo -d 'repo: view, labels, label-create, branches, file, tree'",
   "complete -c cha -n '__cha_needs_command' -a release -d 'releases: list, view, latest, create'",
   "complete -c cha -n '__cha_needs_command' -a moved -d 'what changed since a time'",
   "complete -c cha -n '__cha_needs_command' -a auth -d 'login and token source'",
   "complete -c cha -n '__cha_in_group auth' -a status -d 'login and token source'",
   "complete -c cha -n '__cha_needs_command' -a runners -d \"a repo's or an org's self-hosted runners\"",
   "complete -c cha -n '__cha_needs_command' -a help -d 'help'",
   "complete -c cha -n '__cha_needs_command' -a version -d 'print the version'",
   "complete -c cha -n '__cha_needs_command' -a completions -d 'shell completions'",
   ""]

def comp.issue() -> List<&2, String>:
  ["complete -c cha -n '__cha_sub_command issue' -a list -d 'list issues'",
   "complete -c cha -n '__cha_sub_command issue' -a view -d 'one issue'",
   "complete -c cha -n '__cha_sub_command issue' -a create -d 'open an issue'",
   "complete -c cha -n '__cha_sub_command issue' -a comment -d 'comment on an issue'",
   "complete -c cha -n '__cha_sub_command issue' -a edit -d 'edit an issue'",
   "complete -c cha -n '__cha_sub_command issue' -a close -d 'close an issue'",
   "complete -c cha -n '__cha_sub_command issue' -a reopen -d 'reopen an issue'",
   "complete -c cha -n '__cha_sub_command issue' -a labels -d 'change labels'",
   "complete -c cha -n '__cha_using_sub issue list' -l state -x -a 'open closed all' -d 'which issues'",
   "complete -c cha -n '__cha_using_sub issue list' -l label -x -d 'only issues with this label'",
   "complete -c cha -n '__cha_using_sub issue list' -l all -d 'every page'",
   "complete -c cha -n '__cha_using_sub issue list' -l json -d 'machine-readable rows, optionally only FIELDS'",
   "complete -c cha -n '__cha_using_sub issue view' -l comments -d 'include comments'",
   "complete -c cha -n '__cha_using_sub issue create' -l title -x -d 'the title'",
   "complete -c cha -n '__cha_using_sub issue create' -l body -x -d 'the body text'",
   "complete -c cha -n '__cha_using_sub issue create' -l body-file -r -F -d 'the body from a file; - is stdin'",
   "complete -c cha -n '__cha_using_sub issue create' -l label -x -d 'comma-separated labels'",
   "complete -c cha -n '__cha_using_sub issue create' -l assignee -x -d 'assign to this user'",
   "complete -c cha -n '__cha_using_sub issue comment' -l body -x -d 'the body text'",
   "complete -c cha -n '__cha_using_sub issue comment' -l body-file -r -F -d 'the body from a file; - is stdin'",
   "complete -c cha -n '__cha_using_sub issue edit' -l title -x -d 'the title'",
   "complete -c cha -n '__cha_using_sub issue edit' -l body -x -d 'the body text'",
   "complete -c cha -n '__cha_using_sub issue close' -l comment -x -d 'a comment with the close'",
   ""]

def comp.pr() -> List<&2, String>:
  ["complete -c cha -n '__cha_sub_command pr' -a list -d 'list pull requests'",
   "complete -c cha -n '__cha_sub_command pr' -a view -d 'one pull request'",
   "complete -c cha -n '__cha_sub_command pr' -a diff -d 'the diff'",
   "complete -c cha -n '__cha_sub_command pr' -a create -d 'open a pull request'",
   "complete -c cha -n '__cha_sub_command pr' -a merge -d 'merge a pull request'",
   "complete -c cha -n '__cha_sub_command pr' -a edit -d 'edit a pull request'",
   "complete -c cha -n '__cha_sub_command pr' -a comment -d 'comment on a pull request'",
   "complete -c cha -n '__cha_sub_command pr' -a checks -d 'the checks'",
   "complete -c cha -n '__cha_using_sub pr list' -l state -x -a 'open closed all' -d 'which pull requests'",
   "complete -c cha -n '__cha_using_sub pr list' -l json -d 'machine-readable rows, optionally only FIELDS'",
   "complete -c cha -n '__cha_using_sub pr view' -l comments -d 'include comments'",
   "complete -c cha -n '__cha_using_sub pr create' -l head -x -d 'the branch with the changes'",
   "complete -c cha -n '__cha_using_sub pr create' -l base -x -d 'the branch to merge into'",
   "complete -c cha -n '__cha_using_sub pr create' -l title -x -d 'the title'",
   "complete -c cha -n '__cha_using_sub pr create' -l body -x -d 'the body text'",
   "complete -c cha -n '__cha_using_sub pr create' -l body-file -r -F -d 'the body from a file; - is stdin'",
   "complete -c cha -n '__cha_using_sub pr merge' -l squash -d 'squash the commits'",
   "complete -c cha -n '__cha_using_sub pr merge' -l merge -d 'a merge commit'",
   "complete -c cha -n '__cha_using_sub pr merge' -l rebase -d 'rebase the commits'",
   "complete -c cha -n '__cha_using_sub pr merge' -l delete-branch -d 'delete the head branch'",
   "complete -c cha -n '__cha_using_sub pr comment' -l body -x -d 'the body text'",
   ""]

def comp.runs() -> List<&2, String>:
  ["complete -c cha -n '__cha_sub_command runs' -a list -d 'recent action runs'",
   "complete -c cha -n '__cha_sub_command runs' -a view -d 'one run'",
   "complete -c cha -n '__cha_sub_command runs' -a logs -d \"a run's logs\"",
   "complete -c cha -n '__cha_sub_command runs' -a watch -d 'follow a run'",
   "complete -c cha -n '__cha_sub_command runs' -a dispatch -d 'start a workflow'",
   "complete -c cha -n '__cha_sub_command runs' -a rerun -d 'rerun a run'",
   "complete -c cha -n '__cha_sub_command runs' -a cancel -d 'cancel a run'",
   "complete -c cha -n '__cha_using_sub runs list' -l branch -x -d 'only runs of this branch'",
   "complete -c cha -n '__cha_using_sub runs list' -l status -x -a 'success failure running queued cancelled' -d 'only runs in this state'",
   "complete -c cha -n '__cha_using_sub runs list' -l workflow -x -d 'workflow file or display name'",
   "complete -c cha -n '__cha_using_sub runs list' -l limit -x -d 'how many runs'",
   "complete -c cha -n '__cha_using_sub runs logs' -l job -x -d \"only this job's logs\"",
   "complete -c cha -n '__cha_using_sub runs logs' -l step -x -d 'step name'",
   "complete -c cha -n '__cha_using_sub runs rerun' -l failed -d 'rerun failed jobs'",
   "complete -c cha -n '__cha_using_sub runs rerun' -l job -x -d 'rerun job id'",
   "complete -c cha -n '__cha_using_sub runs logs' -l failed -d 'only the failed jobs'",
   "complete -c cha -n '__cha_using_sub runs dispatch' -l ref -x -d 'the ref to dispatch on'",
   "complete -c cha -n '__cha_using_sub runs dispatch' -l input -x -d 'a workflow input, k=v'",
   ""]

def comp.repo() -> List<&2, String>:
  ["complete -c cha -n '__cha_sub_command repo' -a view -d 'the repo'",
   "complete -c cha -n '__cha_sub_command repo' -a labels -d \"the repo's labels\"",
   "complete -c cha -n '__cha_sub_command repo' -a label-create -d 'make a label'",
   "complete -c cha -n '__cha_sub_command repo' -a branches -d \"the repo's branches\"",
   "complete -c cha -n '__cha_sub_command repo' -a file -d \"a file's contents\"",
   "complete -c cha -n '__cha_sub_command repo' -a tree -d \"the repo's file tree\"",
   "complete -c cha -n '__cha_using_sub repo label-create' -l color -x -d 'the colour, like ff6eb4'",
   "complete -c cha -n '__cha_using_sub repo file' -l ref -x -d 'a branch or tag'",
   "complete -c cha -n '__cha_using_sub repo tree' -l ref -x -d 'a branch or tag'",
   ""]

def comp.release() -> List<&2, String>:
  ["complete -c cha -n '__cha_sub_command release' -a list -d \"the repo's releases\"",
   "complete -c cha -n '__cha_sub_command release' -a view -d 'one release'",
   "complete -c cha -n '__cha_sub_command release' -a latest -d 'the latest release'",
   "complete -c cha -n '__cha_sub_command release' -a create -d 'make a release'",
   "complete -c cha -n '__cha_using_sub release create' -l title -x -d \"the release's title\"",
   "complete -c cha -n '__cha_using_sub release create' -l notes -x -d 'the release notes'",
   "complete -c cha -n '__cha_using_sub release create' -l notes-file -r -F -d 'the notes from a file; - is stdin'",
   "complete -c cha -n '__cha_using_sub release create' -l draft -d 'keep it a draft'",
   "complete -c cha -n '__cha_using_sub release create' -l prerelease -d 'mark it a prerelease'",
   ""]

def comp.moved() -> List<&2, String>:
  ["complete -c cha -n '__cha_in_group moved' -l since -x -a '1d 6h 30m' -d 'how far back to look'",
   ""]

def comp.runners() -> List<&2, String>:
  ["complete -c cha -n '__cha_in_group runners' -l org -x -d \"the org whose runners to list\"",
   ""]

def comp.all() -> List<&2, String>:
  List.concat(&2, String, [comp.head(), comp.global(), comp.groups(), comp.issue(), comp.pr(), comp.runs(), comp.repo(), comp.release(), comp.moved(), comp.runners()])

def comp.body() -> String:
  String.join(comp.all(), "\n") ++ "\n"

def bad.shell.if(+on: Bool, +sh: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      do IO<Unit>:
        Ui.error(on, "usage: cha completions fish")
        IO.die(Unit, 1, "")
    case False{}:
      do IO<Unit>:
        Ui.error(on, "cha completions: only fish for now, not " ++ sh)
        IO.die(Unit, 1, "")

def shell.at(+on: Bool, +sh: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.write(comp.body())
    case False{}:
      bad.shell.if(on, sh, String.is_empty(sh))

def completions(+on: Bool, args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +sh : String = Cli.arg(args, 0n)
    shell.at(on, sh, String.eq(sh, "fish"))
