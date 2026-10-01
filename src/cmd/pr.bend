# cha pr: list, view, diff, create, merge, edit, comment, checks.
import Base
import bend-kit-hairpin@0.1.0.0/hairpin.bend as Hairpin
import bend-kit-http@0.23.0.1/http.bend as Http
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli

# Small shared pieces
# -------------------

def forge.of(r: Ctx.Repo) -> Ctx.Forge:
  match r:
    case Ctx.Repo{f, h, o, n}:
      f

def host.of(r: Ctx.Repo) -> String:
  match r:
    case Ctx.Repo{f, h, o, n}:
      h

# where a pull request lives in a browser: Gitea spells it /pulls/N, GitHub /pull/N
def web.url(+repo: Ctx.Repo, +n: String) -> String:
  match repo:
    case Ctx.Repo{Ctx.Gitea{}, +h, +o, +nm}:
      "https://" ++ h ++ "/" ++ o ++ "/" ++ nm ++ "/pulls/" ++ n
    case Ctx.Repo{Ctx.GitHub{}, +h, +o, +nm}:
      "https://" ++ h ++ "/" ++ o ++ "/" ++ nm ++ "/pull/" ++ n

# a forge path as a full URL
def pick.if(+yes: String, +no: String, cond: Bool) -> String:
  match cond:
    case True{}:
      yes
    case False{}:
      no

def abs.url(+host: String, +u: String) -> String:
  pick.if("https://" ++ host ++ u, u, String.starts_with(u, "/"))

# end text with a newline, unless it already does
def nled(+s: String) -> String:
  pick.if(s, s ++ "\n", String.ends_with(s, "\n"))

# a line on stderr, through the palette
def note(+env: Cli.Env, msg: String) -> IO(Unit):
  match env:
    case Cli.Env{r, t, +c, j, a}:
      Ui.info(c, msg)

# a flattened JSON bool reads as True or False
# (Api.flat turns every Json.Flag into Bool.show)
def flag.of(+s: String) -> Bool:
  String.eq(String.to_lower(s), "true")

# merged is a bool on a Gitea pull request and on a viewed GitHub one; a listed
# GitHub pull request only carries merged_at
def merged.of(+row: Map<&2, String>) -> Bool:
  flag.of(Api.f(row, "merged")) || Bool.not(String.is_empty(Api.f(row, "merged_at")))

def state.merged(+s: String, merged: Bool) -> String:
  match merged:
    case True{}:
      "merged"
    case False{}:
      s

# Writing
# -------

# the changed item's html_url, or the browser URL we know when the reply has none
def url.of(body: Bytes.Bytes, +fallback: String) -> String:
  Ctx.or(Api.f(Api.obj(body), "html_url"), fallback)

def written.if(+env: Cli.Env, body: Bytes.Bytes, +status: U32, +fallback: String, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      IO.print(url.of(body, fallback))
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

# the reply to a write: the changed item's url on stdout, the forge's error otherwise
def written(+env: Cli.Env, +fallback: String, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      written.if(env, body, status, fallback, Api.ok(status))

# Arguments
# ---------

def number.ok(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{n}:
      True{}
    case None{}:
      False{}

def need.number(+env: Cli.Env, +n: String, ok: Bool) -> IO(String):
  match ok:
    case True{}:
      IO.pure(String, n)
    case False{}:
      Cli.fail(String, env, "pr: expected a pull request number, got '" ++ n ++ "'")

def need.flag(+env: Cli.Env, +name: String, +v: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      Cli.fail(String, env, "pr: --" ++ name ++ " is required")
    case False{}:
      IO.pure(String, v)

# Bodies
# ------

def stdin.path(+p: String, dash: Bool) -> String:
  match dash:
    case True{}:
      "/dev/stdin"
    case False{}:
      p

def file.text(r: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match r:
    case Done{s}:
      Some{s}
    case Fail{e}:
      None{}

def file.done(r: File & Result<&1, &1, U32 & String, String>) -> IO(Maybe<&2, String>):
  (f, g) = r
  do IO<Maybe<&2, String>>:
    File.close(f)
    return file.text(g)

def file.open(r: Result<&1, &1, U32 & String, File>) -> IO(Maybe<&2, String>):
  match r:
    case Done{f}:
      do IO<Maybe<&2, String>>:
        got : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1048576)
        file.done(got)
    case Fail{e}:
      IO.pure(Maybe<&2, String>, None{})

# a file's text, None when it can't be read; "-" means stdin
def file.maybe(+path: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    r : Result<&1, &1, U32 & String, File> <- File.open(stdin.path(path, String.eq(path, "-")), "r")
    file.open(r)

def body.got(+env: Cli.Env, m: Maybe<&2, String>) -> IO(String):
  match m:
    case Some{s}:
      IO.pure(String, s)
    case None{}:
      Cli.fail(String, env, "pr: can't read the body file")

def body.read(+path: String, needed: Bool) -> IO(Maybe<&2, String>):
  match needed:
    case True{}:
      file.maybe(path)
    case False{}:
      IO.pure(Maybe<&2, String>, None{})

def body.pick(+env: Cli.Env, +inline: String, m: Maybe<&2, String>, needed: Bool) -> IO(String):
  match needed:
    case True{}:
      body.got(env, m)
    case False{}:
      IO.pure(String, inline)

# the body from --body, or --body-file PATH (- is stdin); "" when neither is given
def body.text(+env: Cli.Env, +args: List<&2, String>) -> IO(String):
  do IO<String>:
    +inline : String = Cli.flag(args, "--body", "")
    +path : String = Cli.flag(args, "--body-file", "")
    +from_file : Bool = Bool.not(String.is_empty(path))
    m : Maybe<&2, String> <- body.read(path, from_file)
    body.pick(env, inline, m, from_file)

# A GET with its own accept header: GitHub answers a diff only for its diff media type.
def accept.get(repo: Ctx.Repo, +tok: String, url: String, +accept: String) -> IO(Api.Reply):
  do IO<Api.Reply>:
    c : Hairpin.Client = Hairpin.header(Api.client(repo, tok), "accept", accept)
    r : Hairpin.Client & Result<&1, &1, Http.Err, Http.Res> <- Hairpin.request(c, "GET", url, Map.new(&2, List<&2, String>), Http.from_string(""))
    Api.reply(r)

# Reviews
# -------

type Tally is Data:
  Tally{approved: Nat, changes: Nat, notes: Nat}

def review.kind.of(approved: Bool, changes: Bool) -> Nat:
  match approved changes:
    case True{} c:
      1n
    case False{} True{}:
      2n
    case False{} False{}:
      0n

# 1 approved, 2 changes requested, 0 anything else (Gitea and GitHub spell them differently)
def review.kind(+s: String) -> Nat:
  review.kind.of(String.eq(s, "APPROVED"), String.eq(s, "CHANGES_REQUESTED") || String.eq(s, "REQUEST_CHANGES"))

def tally.at(+t: Tally, k: Nat) -> Tally:
  match t k:
    case Tally{a, c, n} 1n:
      Tally{Nat.add(a, 1n), c, n}
    case Tally{a, c, n} 2n:
      Tally{a, Nat.add(c, 1n), n}
    case Tally{a, c, n} k2:
      Tally{a, c, Nat.add(n, 1n)}

def tally.of(xs: List<&2, Map<&2, String>>) -> Tally:
  match xs:
    case Nil{}:
      Tally{0n, 0n, 0n}
    case Con{+x, rest}:
      tally.at(tally.of(rest), review.kind(Api.f(x, "state")))

def reviews.line(+on: Bool, +t: Tally) -> String:
  match t:
    case Tally{a, c, n}:
      "reviews: " ++ Ui.fg(on, Ui.mint(), Nat.show(a) ++ " approved") ++ ", " ++ Ui.fg(on, Ui.pink(), Nat.show(c) ++ " changes requested") ++ ", " ++ Ui.dim(on, Nat.show(n) ++ " commented")

def reviews.ok(+env: Cli.Env, body: Bytes.Bytes, +status: U32, good: Bool) -> IO(Tally):
  match good:
    case True{}:
      IO.pure(Tally, tally.of(Api.rows(body)))
    case False{}:
      Cli.fail(Tally, env, Api.message(status, body))

def reviews.got(+env: Cli.Env, r: Api.Reply) -> IO(Tally):
  match r:
    case Api.Broke{w}:
      Cli.fail(Tally, env, w)
    case Api.Reply{+status, next, body}:
      reviews.ok(env, body, status, Api.ok(status))

# mergeable is a bool, or missing while the forge works it out
def mergeable.if(+on: Bool, +state: String, yes: Bool, no: Bool) -> String:
  match yes no:
    case True{} x:
      Ui.fg(on, Ui.mint(), "mergeable")
    case False{} True{}:
      Ui.fg(on, Ui.pink(), "conflicts")
    case False{} False{}:
      Ui.dim(on, "mergeable: " ++ Ctx.or(state, "?"))

def mergeable.line(+on: Bool, +state: String) -> String:
  mergeable.if(on, state, flag.of(state), Bool.not(flag.of(state)) && Bool.not(String.is_empty(state)))

def body.block(+b: String, empty: Bool) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      "\n" ++ b ++ "\n"

# Comments
# --------

def comment.url(f: Ctx.Forge, +n: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "issues/" ++ n ++ "/comments?limit=50"
    case Ctx.GitHub{}:
      "issues/" ++ n ++ "/comments?per_page=100"

def comment.lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      Ui.dim(on, "@" ++ Api.f(x, "user.login") ++ "  " ++ Api.f(x, "created_at")) ++ "\n" ++ Api.f(x, "body") ++ "\n\n" ++ comment.lines(on, rest)

def comment.ok(+env: Cli.Env, +on: Bool, body: Bytes.Bytes, +status: U32, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      IO.write(comment.lines(on, Api.rows(body)))
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def comment.got(+env: Cli.Env, +on: Bool, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      comment.ok(env, on, body, status, Api.ok(status))

# view
# ----

def view.text(+on: Bool, +row: Map<&2, String>, +reviews: Tally) -> String:
  st = state.merged(Api.f(row, "state"), merged.of(row))
  +txt = Api.f(row, "body")
  Ui.bold(on, "#" ++ Api.f(row, "number") ++ "  " ++ Api.f(row, "title")) ++ "\n" ++
  Ui.state(on, st) ++ "  " ++ Api.f(row, "head.ref") ++ " -> " ++ Api.f(row, "base.ref") ++ "  " ++ Ui.dim(on, "@" ++ Api.f(row, "user.login")) ++ "\n" ++
  mergeable.line(on, Api.f(row, "mergeable")) ++ "  " ++ reviews.line(on, reviews) ++ "\n" ++
  Api.f(row, "html_url") ++ "\n" ++
  body.block(txt, String.is_empty(txt))

def view.comments(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +on: Bool, want: Bool) -> IO(Unit):
  match want:
    case True{}:
      do IO<Unit>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, comment.url(forge.of(repo), n)))
        comment.got(env, on, r)
    case False{}:
      IO.pure(Unit, Unit{})

def view.row(+env: Cli.Env, +n: String, +row: Map<&2, String>) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "pulls/" ++ n ++ "/reviews"))
        t : Tally <- reviews.got(env, r)
        IO.write(view.text(on, row, t))
        view.comments(env, repo, tok, n, on, Cli.has(args, "--comments"))

def view.pick(+env: Cli.Env, +n: String, json: Bool, +row: Map<&2, String>) -> IO(Unit):
  match json:
    case True{}:
      IO.print(Cli.json.rows(Con{row, Nil{}}, ["number", "title", "state", "head.ref", "base.ref", "user.login", "mergeable", "html_url", "body"]))
    case False{}:
      view.row(env, n, row)

def view.good(+env: Cli.Env, +n: String, json: Bool, body: Bytes.Bytes, +status: U32, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      view.pick(env, n, json, Api.obj(body))
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def view.reply(+env: Cli.Env, +n: String, json: Bool, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      view.good(env, n, json, body, status, Api.ok(status))

def view(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +num : String = Cli.arg(args, 1n)
        +n : String <- need.number(env, num, number.ok(U32.read(num)))
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "pulls/" ++ n))
        view.reply(env, n, json, r)

# list
# ----

def list.query(f: Ctx.Forge, +state: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "pulls?limit=50&state=" ++ state
    case Ctx.GitHub{}:
      "pulls?per_page=100&state=" ++ state

def state.ok(+s: String) -> Bool:
  String.eq(s, "open") || String.eq(s, "closed") || String.eq(s, "all")

def need.state(+env: Cli.Env, +s: String, bad: Bool) -> IO(String):
  match bad:
    case True{}:
      Cli.fail(String, env, "pr list: --state wants open, closed or all")
    case False{}:
      IO.pure(String, s)

def list.line(+on: Bool, +x: Map<&2, String>) -> String:
  st = state.merged(Api.f(x, "state"), merged.of(x))
  Ui.bold(on, Ui.fg(on, Ui.aqua(), "#" ++ Api.f(x, "number"))) ++ "  " ++ Ui.state(on, st) ++ "  " ++ Api.f(x, "title") ++ "  " ++ Ui.dim(on, "@" ++ Api.f(x, "user.login"))

def list.lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      list.line(on, x) ++ "\n" ++ list.lines(on, rest)

def list.print(+on: Bool, json: Bool, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case True{}:
      IO.print(Cli.json.rows(xs, ["number", "title", "state", "user.login", "html_url"]))
    case False{}:
      IO.write(list.lines(on, xs))

def list.show(+env: Cli.Env, r: Result<&1, &1, String, List<&2, Map<&2, String>>>) -> IO(Unit):
  match env r:
    case Cli.Env{repo, tok, +on, json, args} Done{xs}:
      list.print(on, json, xs)
    case e Fail{w}:
      Cli.fail(Unit, e, w)

def list.pages(all: Bool) -> Nat:
  match all:
    case True{}:
      100n
    case False{}:
      1n

def list(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +st : String = Cli.flag(args, "--state", "open")
        state : String <- need.state(env, st, Bool.not(state.ok(st)))
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(list.pages(Cli.has(args, "--all")), repo, tok, Api.path(repo, list.query(forge.of(repo), state)))
        list.show(env, r)

# checks
# ------

def check.bad(+s: String) -> Bool:
  +l = String.to_lower(s)
  String.eq(l, "failure") || String.eq(l, "failed") || String.eq(l, "error") || String.eq(l, "cancelled") || String.eq(l, "canceled") || String.eq(l, "timed_out") || String.eq(l, "action_required") || String.eq(l, "startup_failure") || String.eq(l, "stale")

def check.failed(+x: Map<&2, String>, bad: Bool) -> Nat:
  match bad:
    case True{}:
      1n
    case False{}:
      0n

def checks.bads(xs: List<&2, Map<&2, String>>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{+x, rest}:
      Nat.add(checks.bads(rest), check.failed(x, check.bad(Api.f(x, "state"))))

def checks.line(+on: Bool, +x: Map<&2, String>) -> String:
  +url = Api.f(x, "url")
  Ui.state(on, Api.f(x, "state")) ++ "  " ++ Api.f(x, "name") ++ Ctx.or.if("  " ++ Ui.dim(on, url), "", String.is_empty(url))

def checks.lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      checks.line(on, x) ++ "\n" ++ checks.lines(on, rest)

def checks.emit.if(+on: Bool, json: Bool, +rows: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case True{}:
      IO.print(Cli.json.rows(rows, ["name", "state", "url"]))
    case False{}:
      IO.write(checks.lines(on, rows))

def checks.emit(+env: Cli.Env, +rows: List<&2, Map<&2, String>>) -> IO(Unit):
  match env:
    case Cli.Env{r, t, +on, json, a}:
      checks.emit.if(on, json, rows)

def checks.exit.if(+env: Cli.Env, bad: Bool, n: Nat) -> IO(Unit):
  match bad:
    case True{}:
      do IO<Unit>:
        note(env, Nat.show(n) ++ " checks failed")
        IO.die(Unit, 1, "")
    case False{}:
      IO.pure(Unit, Unit{})

def checks.exit(+env: Cli.Env, +rows: List<&2, Map<&2, String>>) -> IO(Unit):
  checks.exit.if(env, Nat.is_gt(checks.bads(rows), 0n), checks.bads(rows))

# the rows on stdout, then exit 1 when any of them failed
def checks.print(+env: Cli.Env, +rows: List<&2, Map<&2, String>>) -> IO(Unit):
  do IO<Unit>:
    checks.emit(env, rows)
    checks.exit(env, rows)

def got.body(+env: Cli.Env, body: Bytes.Bytes, +status: U32, good: Bool) -> IO(Bytes.Bytes):
  match good:
    case True{}:
      IO.pure(Bytes.Bytes, body)
    case False{}:
      Cli.fail(Bytes.Bytes, env, Api.message(status, body))

# the body of a good reply, or a failure carrying the forge's message
def checks.bytes(+env: Cli.Env, r: Api.Reply) -> IO(Bytes.Bytes):
  match r:
    case Api.Broke{w}:
      Cli.fail(Bytes.Bytes, env, w)
    case Api.Reply{+status, next, body}:
      got.body(env, body, status, Api.ok(status))

# Checks arrive as a list inside an object, so read them from the flattened object:
# <list>.# counts them and <list>.<i>.<field> reads one.
type Source is Data:
  Gitea{}
  GhStatus{}
  GhRun{}

def check.row(+name: String, +state: String, +url: String) -> Map<&2, String>:
  Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), "name", name), "state", state), "url", url)

def check.name(+row: Map<&2, String>, +p: String, s: Source) -> String:
  match s:
    case Gitea{}:
      Api.f(row, p ++ ".context")
    case GhStatus{}:
      Api.f(row, p ++ ".context")
    case GhRun{}:
      Api.f(row, p ++ ".name")

def check.state(+row: Map<&2, String>, +p: String, s: Source) -> String:
  match s:
    case Gitea{}:
      Api.f(row, p ++ ".status")
    case GhStatus{}:
      Api.f(row, p ++ ".state")
    case GhRun{}:
      Ctx.or(Api.f(row, p ++ ".conclusion"), Api.f(row, p ++ ".status"))

def check.url(+row: Map<&2, String>, +p: String, +host: String, s: Source) -> String:
  match s:
    case Gitea{}:
      abs.url(host, Api.f(row, p ++ ".target_url"))
    case GhStatus{}:
      abs.url(host, Api.f(row, p ++ ".target_url"))
    case GhRun{}:
      Ctx.or(Api.f(row, p ++ ".html_url"), Api.f(row, p ++ ".details_url"))

def check.p(+list: String, +i: U32) -> String:
  list ++ "." ++ U32.show(i)

# the i-th entry of a flattened list field, as one row
def check.row.at(+row: Map<&2, String>, +list: String, +host: String, +s: Source, +i: U32) -> Map<&2, String>:
  +p = check.p(list, i)
  check.row(check.name(row, p, s), check.state(row, p, s), check.url(row, p, host, s))

def check.one(+x: Map<&2, String>) -> List<&2, Map<&2, String>>:
  Con{x, Nil{}}

def check.walk(n: Nat, +row: Map<&2, String>, +list: String, +host: String, +s: Source, +i: U32, acc: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match n:
    case 0n:
      acc
    case 1n+k:
      check.walk(k, row, list, host, s, (i + 1 : U32), List.append(&2, Map<&2, String>, acc, check.one(check.row.at(row, list, host, s, i))))

# Gitea answers a combined state plus its statuses
# (target_url is usually a path there, so it needs the host)
def checks.gitea.rows(+env: Cli.Env, +host: String, +row: Map<&2, String>) -> IO(Unit):
  checks.print(env, check.walk(Api.count(row, "statuses"), row, "statuses", host, Gitea{}, 0, Nil{}))

def checks.gitea.if(+env: Cli.Env, +host: String, body: Bytes.Bytes, +status: U32, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      checks.gitea.rows(env, host, Api.obj(body))
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def checks.gitea.got(+env: Cli.Env, +host: String, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      checks.gitea.if(env, host, body, status, Api.ok(status))

def checks.gitea(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +sha: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "commits/" ++ sha ++ "/status"))
    checks.gitea.got(env, host.of(repo), r)

def checks.github.rows(+env: Cli.Env, +host: String, +runs: Map<&2, String>, +sts: Map<&2, String>) -> IO(Unit):
  checks.print(env, List.append(&2, Map<&2, String>, check.walk(Api.count(runs, "check_runs"), runs, "check_runs", host, GhRun{}, 0, Nil{}), check.walk(Api.count(sts, "statuses"), sts, "statuses", host, GhStatus{}, 0, Nil{})))

# GitHub answers check runs and, separately, commit statuses
def checks.github(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +sha: String) -> IO(Unit):
  do IO<Unit>:
    a : Api.Reply <- Api.get(repo, tok, Api.path(repo, "commits/" ++ sha ++ "/check-runs?per_page=100"))
    ra : Bytes.Bytes <- checks.bytes(env, a)
    b : Api.Reply <- Api.get(repo, tok, Api.path(repo, "commits/" ++ sha ++ "/status"))
    rb : Bytes.Bytes <- checks.bytes(env, b)
    checks.github.rows(env, host.of(repo), Api.obj(ra), Api.obj(rb))

def checks.sha(f: Ctx.Forge, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +sha: String) -> IO(Unit):
  match f:
    case Ctx.Gitea{}:
      checks.gitea(env, repo, tok, sha)
    case Ctx.GitHub{}:
      checks.github(env, repo, tok, sha)

def checks.pr(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "pulls/" ++ n))
    body : Bytes.Bytes <- checks.bytes(env, r)
    checks.sha(forge.of(repo), env, repo, tok, Api.f(Api.obj(body), "head.sha"))

def checks(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +num : String = Cli.arg(args, 1n)
        +n : String <- need.number(env, num, number.ok(U32.read(num)))
        checks.pr(env, repo, tok, n)

# diff
# ----

def diff.accept(f: Ctx.Forge) -> String:
  match f:
    case Ctx.Gitea{}:
      "text/plain"
    case Ctx.GitHub{}:
      "application/vnd.github.diff"

def diff.url(f: Ctx.Forge, +n: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "pulls/" ++ n ++ ".diff"
    case Ctx.GitHub{}:
      "pulls/" ++ n

def diff.ok(+env: Cli.Env, body: Bytes.Bytes, +status: U32, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      IO.write(nled(Api.text(body)))
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def diff.print(+env: Cli.Env, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      diff.ok(env, body, status, Api.ok(status))

def diff(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +num : String = Cli.arg(args, 1n)
        +n : String <- need.number(env, num, number.ok(U32.read(num)))
        r : Api.Reply <- accept.get(repo, tok, Api.path(repo, diff.url(forge.of(repo), n)), diff.accept(forge.of(repo)))
        diff.print(env, r)

# create
# ------

def create.body(+head: String, +base: String, +title: String, +body: String) -> Json.Val:
  Json.Obj{[(Json.utf8("head"), Api.utf8(head)), (Json.utf8("base"), Api.utf8(base)), (Json.utf8("title"), Api.utf8(title)), (Json.utf8("body"), Api.utf8(body))]}

def create(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +head : String = Cli.flag(args, "--head", "")
        +title : String = Cli.flag(args, "--title", "")
        h : String <- need.flag(env, "head", head, String.is_empty(head))
        t : String <- need.flag(env, "title", title, String.is_empty(title))
        body : String <- body.text(env, args)
        base : String = Cli.flag(args, "--base", "main")
        r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, "pulls"), Some{create.body(h, base, t, body)})
        written(env, "", r)

# merge
# -----

def merge.pick(squash: Bool, plain: Bool, rebase: Bool) -> String:
  match squash plain rebase:
    case True{} p r:
      "squash"
    case False{} True{} r:
      "merge"
    case False{} False{} True{}:
      "rebase"
    case False{} False{} False{}:
      "merge"

# Gitea deletes the head branch in the merge call; GitHub's merge takes no such field
def merge.body(f: Ctx.Forge, +method: String, delete: Bool) -> Json.Val:
  match f:
    case Ctx.Gitea{}:
      Json.Obj{[(Json.utf8("Do"), Api.utf8(method)), (Json.utf8("delete_branch_after_merge"), Json.Flag{delete})]}
    case Ctx.GitHub{}:
      Json.Obj{[(Json.utf8("merge_method"), Api.utf8(method))]}

# Gitea answers 405 "Please try again later" when the pull request conflicts or its
# base moved; that is not a rate limit
def merge.fail(+env: Cli.Env, body: Bytes.Bytes, +status: U32, gone: Bool) -> IO(Unit):
  match gone:
    case True{}:
      Cli.fail(Unit, env, "pr merge: the pull request conflicts or its base branch moved; update the branch and try again")
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def merged.if(+env: Cli.Env, body: Bytes.Bytes, +status: U32, +fallback: String, gone: Bool, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      IO.print(url.of(body, fallback))
    case False{}:
      merge.fail(env, body, status, gone)

def merged(+env: Cli.Env, +fallback: String, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      merged.if(env, body, status, fallback, U32.is_eq(status, 405), Api.ok(status))

def same.repo(+repo: Ctx.Repo, +full: String) -> Bool:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      String.eq(full, o ++ "/" ++ n)

# the head ref of a merged GitHub pull request
def gh.ref.ok(+env: Cli.Env, body: Bytes.Bytes, +status: U32, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def gh.ref.got(+env: Cli.Env, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      gh.ref.ok(env, body, status, Api.ok(status))

def gh.ref.if(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +ref: String, mine: Bool) -> IO(Unit):
  match mine:
    case True{}:
      do IO<Unit>:
        r : Api.Reply <- Api.send(repo, tok, "DELETE", Api.path(repo, "git/refs/heads/" ++ ref), None{})
        gh.ref.got(env, r)
    case False{}:
      note(env, "the head branch is in a fork; --delete-branch left it alone")

def gh.ref.row(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +row: Map<&2, String>) -> IO(Unit):
  gh.ref.if(env, repo, tok, Api.f(row, "head.ref"), same.repo(repo, Api.f(row, "head.repo.full_name")))

def gh.ref.maybe(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, body: Bytes.Bytes, +status: U32, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      gh.ref.row(env, repo, tok, Api.obj(body))
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def gh.ref.reply(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      gh.ref.maybe(env, repo, tok, body, status, Api.ok(status))

def gh.ref.want(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, want: Bool) -> IO(Unit):
  match want:
    case True{}:
      do IO<Unit>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "pulls/" ++ n))
        gh.ref.reply(env, repo, tok, r)
    case False{}:
      IO.pure(Unit, Unit{})

def merge.gitea(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +method: String, delete: Bool) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, "pulls/" ++ n ++ "/merge"), Some{merge.body(Ctx.Gitea{}, method, delete)})
    merged(env, web.url(repo, n), r)

def merge.github(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +method: String, delete: Bool) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.send(repo, tok, "PUT", Api.path(repo, "pulls/" ++ n ++ "/merge"), Some{merge.body(Ctx.GitHub{}, method, False{})})
    merged(env, web.url(repo, n), r)
    gh.ref.want(env, repo, tok, n, delete)

def merge.at(f: Ctx.Forge, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +method: String, delete: Bool) -> IO(Unit):
  match f:
    case Ctx.Gitea{}:
      merge.gitea(env, repo, tok, n, method, delete)
    case Ctx.GitHub{}:
      merge.github(env, repo, tok, n, method, delete)

def merge(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +num : String = Cli.arg(args, 1n)
        +n : String <- need.number(env, num, number.ok(U32.read(num)))
        +method : String = merge.pick(Cli.has(args, "--squash"), Cli.has(args, "--merge"), Cli.has(args, "--rebase"))
        +del : Bool = Cli.has(args, "--delete-branch")
        merge.at(forge.of(repo), env, repo, tok, n, method, del)

# edit
# ----

def edit.pair.if(+k: String, +v: String, rest: List<&1, Bytes.Bytes & Json.Val>, keep: Bool) -> List<&1, Bytes.Bytes & Json.Val>:
  match keep:
    case True{}:
      Con{(Json.utf8(k), Api.utf8(v)), rest}
    case False{}:
      rest

def edit.pairs(+title: String, +body: String, has_title: Bool, has_body: Bool) -> List<&1, Bytes.Bytes & Json.Val>:
  edit.pair.if("title", title, edit.pair.if("body", body, Nil{}, has_body), has_title)

def edit.check(+env: Cli.Env, neither: Bool) -> IO(Unit):
  match neither:
    case True{}:
      Cli.fail(Unit, env, "pr edit: give --title or --body")
    case False{}:
      IO.pure(Unit, Unit{})

def edit(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +num : String = Cli.arg(args, 1n)
        +n : String <- need.number(env, num, number.ok(U32.read(num)))
        +title : String = Cli.flag(args, "--title", "")
        +body : String <- body.text(env, args)
        +has_title : Bool = Cli.has(args, "--title") || Bool.not(String.is_empty(title))
        +has_body : Bool = Cli.has(args, "--body") || Cli.has(args, "--body-file") || Bool.not(String.is_empty(body))
        u : Unit <- edit.check(env, Bool.not(has_title || has_body))
        r : Api.Reply <- Api.send(repo, tok, "PATCH", Api.path(repo, "pulls/" ++ n), Some{Json.Obj{edit.pairs(title, body, has_title, has_body)}})
        written(env, web.url(repo, n), r)

# comment
# -------

def comment.body(+body: String) -> Json.Val:
  Json.Obj{[(Json.utf8("body"), Api.utf8(body))]}

def comment(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +num : String = Cli.arg(args, 1n)
        +n : String <- need.number(env, num, number.ok(U32.read(num)))
        +b : String <- body.text(env, args)
        txt : String <- need.flag(env, "body", b, String.is_empty(b))
        r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, comment.url(forge.of(repo), n)), Some{comment.body(txt)})
        written(env, web.url(repo, n), r)

# dispatch
# --------

def subs() -> List<&2, String>:
  ["list", "view", "diff", "create", "merge", "edit", "comment", "checks"]

def index.at(eq: Bool, +i: Nat, +later: Nat) -> Nat:
  match eq:
    case True{}:
      i
    case False{}:
      later

def index(xs: List<&2, String>, +w: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case Con{x, rest}:
      index.at(String.eq(x, w), i, index(rest, w, Nat.add(i, 1n)))

def kind.of(empty: Bool, +sub: String) -> Nat:
  match empty:
    case True{}:
      0n
    case False{}:
      index(subs(), sub, 0n)

def run.at(+env: Cli.Env, +sub: String, kind: Nat) -> IO(Unit):
  match kind:
    case 0n:
      list(env)
    case 1n:
      view(env)
    case 2n:
      diff(env)
    case 3n:
      create(env)
    case 4n:
      merge(env)
    case 5n:
      edit(env)
    case 6n:
      comment(env)
    case 7n:
      checks(env)
    case 8n+k:
      Cli.fail(Unit, env, "pr " ++ sub ++ ": unknown subcommand, try cha help")

def run.sub(+env: Cli.Env, +sub: String) -> IO(Unit):
  run.at(env, sub, kind.of(String.is_empty(sub), sub))

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      run.sub(env, Cli.arg(args, 0n))
