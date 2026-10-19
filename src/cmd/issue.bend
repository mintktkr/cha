# cha issue: list, view, create, comment, comment-edit, comment-delete, edit, close, reopen,
# labels.
import Base
import ../../lib/chaki/json.bend as Json
import ../../lib/chaki/sys.bend as Sys
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli
import ../comment.bend as Comment
import ../url.bend as Url
import ../since.bend as Since

# list
# ----

# github lists pull requests among issues; they carry a pull_request object
def real.at(+x: Map<&2, String>, rest: List<&2, Map<&2, String>>, keep: Bool) -> List<&2, Map<&2, String>>:
  match keep:
    case True{}:
      x <> rest
    case False{}:
      rest

def real(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      real.at(x, real(rest), String.is_empty(Api.f(x, "pull_request.url")))

# pull requests stay in the list only when --with-prs asked for them
def prs.keep(xs: List<&2, Map<&2, String>>, keep: Bool) -> List<&2, Map<&2, String>>:
  match keep:
    case True{}:
      xs
    case False{}:
      real(xs)

# labels joined into one field, for display and --json: a row field, so it stays as the
# forge sent it and each output cleans or escapes it on the way out
def with_labels(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      Map.set(&2, String, x, "labels", Api.raw.join(x, "labels", "name", ",")) <> with_labels(rest)

def line(+on: Bool, +x: Map<&2, String>) -> String:
  +labels = Api.f(x, "labels")
  Ui.bold(on, Ui.fg(on, Ui.aqua(), "#" ++ Api.f(x, "number"))) ++ "  " ++ Ui.state(on, Api.f(x, "state")) ++ "  " ++ Api.f(x, "title") ++ Ctx.or.if("  " ++ Ui.dim(on, "[" ++ labels ++ "]"), "", String.is_empty(labels)) ++ "  " ++ Ui.dim(on, "@" ++ Api.f(x, "user.login"))

def lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      line(on, x) ++ "\n" ++ lines(on, rest)

def forge.of(r: Ctx.Repo) -> Ctx.Forge:
  match r:
    case Ctx.Repo{f, h, o, n}:
      f

def is.github(f: Ctx.Forge) -> Bool:
  match f:
    case Ctx.GitHub{}:
      True{}
    case Ctx.Gitea{}:
      False{}

# gitea's assigned_by names a login; only github takes none (unassigned) and * (anyone)
def assignee.bad(f: Ctx.Forge, +a: String) -> Bool:
  match f:
    case Ctx.Gitea{}:
      String.eq(a, "none")
    case Ctx.GitHub{}:
      False{}

def assignee.check(+env: Cli.Env, bad: Bool) -> IO(Unit):
  match bad:
    case True{}:
      Cli.fail(Unit, env, "issue list: --assignee none is GitHub-only")
    case False{}:
      IO.pure(Unit, Unit{})

# a query parameter, its value percent-encoded, "" when the value is empty
def param.q(+pre: String, +v: String) -> String:
  Ctx.or.if(pre ++ Url.encode(v), "", String.is_empty(v))

# the list endpoint: the four filters, the since bound, and whether pull requests join in.
# gitea drops them with type=issues; github lists them as issues and real() drops them after
def query(f: Ctx.Forge, +size: Nat, +state: String, +label: String, +assignee: String, +since: String, prs: Bool) -> String:
  match f:
    case Ctx.Gitea{}:
      "issues?" ++ Ctx.or.if("type=issues&", "", prs) ++ "limit=" ++ Nat.show(size) ++ "&state=" ++ Url.encode(state) ++ param.q("&labels=", label) ++ param.q("&assigned_by=", assignee) ++ param.q("&since=", since)
    case Ctx.GitHub{}:
      "issues?per_page=" ++ Nat.show(size) ++ "&state=" ++ Url.encode(state) ++ param.q("&labels=", label) ++ param.q("&assignee=", assignee) ++ param.q("&since=", since)

# --since as the RFC 3339 text a forge query takes, "" when the flag wasn't given
def since.text(+env: Cli.Env, m: Maybe<&2, U32>) -> IO(String):
  match m:
    case Some{i}:
      IO.pure(String, Since.rfc(i))
    case None{}:
      Cli.fail(String, env, "issue list: --since takes 1d, 6h, 30m or an ISO 8601 time")

def since.empty.if(+env: Cli.Env, +arg: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      IO.pure(String, "")
    case False{}:
      do IO<String>:
        now : U32 <- Sys.now()
        v : String <- since.text(env, Since.of(now, arg))
        return v

def since.bound(+env: Cli.Env, +arg: String) -> IO(String):
  since.empty.if(env, arg, String.is_empty(arg))

def list.print(+on: Bool, json: Cli.Json, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(lines(on, xs))
    case j:
      Cli.json.emit(on, j, xs, ["number", "title", "state", "user.login", "labels", "html_url"])

# --limit cuts the list to its first N; without it the list is what the pages held
def list.cut(xs: List<&2, Map<&2, String>>, +limit: Nat, given: Bool) -> List<&2, Map<&2, String>>:
  match given:
    case True{}:
      List.take(&2, Map<&2, String>, xs, limit)
    case False{}:
      xs

def list.show(+env: Cli.Env, r: Result<&1, &1, String, List<&2, Map<&2, String>>>, +limit: Nat, given: Bool) -> IO(Unit):
  match env r:
    case Cli.Env{repo, tok, +on, json, args} Done{xs}:
      list.print(on, json, with_labels(list.cut(prs.keep(xs, Cli.has(args, "--with-prs")), limit, given)))
    case e Fail{w}:
      Cli.fail(Unit, e, w)

def list.pages(all: Bool) -> Nat:
  match all:
    case True{}:
      100n
    case False{}:
      1n

# --limit reads the pages its N fill; without it, one page, or a hundred with --all
def list.pages.of(all: Bool, +limit: Nat, +size: Nat, given: Bool) -> Nat:
  match given:
    case True{}:
      Nat.div(Nat.add(limit, Nat.sub(size, 1n)), size)
    case False{}:
      list.pages(all)

# a page as each forge caps it, and the list's size without --limit
def list.size(f: Ctx.Forge) -> Nat:
  match f:
    case Ctx.Gitea{}:
      50n
    case Ctx.GitHub{}:
      100n

def require.limit(+env: Cli.Env, v: U32, valid: Bool) -> IO(Nat):
  match valid:
    case True{}:
      IO.pure(Nat, U32.to_nat(v))
    case False{}:
      Cli.fail(Nat, env, "issue list: --limit must be an integer from 1 to 1000")

def list.limit(+env: Cli.Env, n: Maybe<&2, U32>) -> IO(Nat):
  match n:
    case Some{+v}:
      require.limit(env, v, (v > 0 : U32) && (v <= 1000 : U32))
    case None{}:
      Cli.fail(Nat, env, "issue list: --limit must be an integer from 1 to 1000")

def list.flags() -> List<&2, String>:
  ["--state", "--label", "--assignee", "--since", "--with-prs", "--all", "--limit", "--json"]

def list(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "issue list", args, list.flags())
        +f : Ctx.Forge = forge.of(repo)
        +size : Nat = list.size(f)
        +given : Bool = Bool.not(String.is_empty(Cli.flag(args, "--limit", "")))
        +limit : Nat <- list.limit(env, U32.read(Cli.flag(args, "--limit", Nat.show(size))))
        +assignee : String = Cli.flag(args, "--assignee", "")
        assignee.check(env, assignee.bad(f, assignee))
        bound : String <- since.bound(env, Cli.flag(args, "--since", ""))
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(list.pages.of(Cli.has(args, "--all"), limit, size, given), repo, tok, Api.path(repo, query(f, size, Cli.flag(args, "--state", "open"), Cli.flag(args, "--label", ""), assignee, bound, Cli.has(args, "--with-prs"))))
        list.show(env, r, limit, given)

# replies
# -------

def obj.if(+status: U32, body: List<&2, U32>, good: Bool) -> Result<&1, &1, String, Map<&2, String>>:
  match good:
    case True{}:
      Done{Api.obj(body)}
    case False{}:
      Fail{Api.message(status, body)}

# a reply's object, or the forge's error message when it didn't succeed
def reply.obj(r: Api.Reply) -> Result<&1, &1, String, Map<&2, String>>:
  match r:
    case Api.Broke{w}:
      Fail{w}
    case Api.Reply{+status, +next, body}:
      obj.if(status, body, Api.ok(status))

def need.row(+env: Cli.Env, r: Result<&1, &1, String, Map<&2, String>>, +msg: String) -> IO(Map<&2, String>):
  match r:
    case Done{x}:
      IO.pure(Map<&2, String>, x)
    case Fail{w}:
      Cli.fail(Map<&2, String>, env, msg ++ Api.message.text(w))

def need.rows(+env: Cli.Env, r: Result<&1, &1, String, List<&2, Map<&2, String>>>, +msg: String) -> IO(List<&2, Map<&2, String>>):
  match r:
    case Done{xs}:
      IO.pure(List<&2, Map<&2, String>>, xs)
    case Fail{w}:
      Cli.fail(List<&2, Map<&2, String>>, env, msg ++ Api.message.text(w))

def need.if(+env: Cli.Env, +msg: String, bad: Bool) -> IO(Unit):
  match bad:
    case True{}:
      Cli.fail(Unit, env, msg)
    case False{}:
      IO.pure(Unit, Unit{})

# fail unless bad is False
def need(+env: Cli.Env, bad: Bool, +msg: String) -> IO(Unit):
  need.if(env, msg, bad)

def need.maybe(+env: Cli.Env, m: Maybe<&2, String>, +msg: String) -> IO(String):
  match m:
    case Some{s}:
      IO.pure(String, s)
    case None{}:
      Cli.fail(String, env, msg)

# a request that writes an item, printing the item's html_url
def write.done(+env: Cli.Env, r: Api.Reply, +msg: String) -> IO(Unit):
  do IO<Unit>:
    x : Map<&2, String> <- need.row(env, reply.obj(r), msg)
    IO.print(Api.f(x, "html_url"))

# check a write that answers no item, as a label removal does
def check.done(+env: Cli.Env, r: Api.Reply, +msg: String) -> IO(Unit):
  do IO<Unit>:
    x : Map<&2, String> <- need.row(env, reply.obj(r), msg)
    return Unit{}

# the issue itself, or the forge's error message
def issue.get(+repo: Ctx.Repo, +tok: String, +n: String) -> IO(Result<&1, &1, String, Map<&2, String>>):
  do IO<Result<&1, &1, String, Map<&2, String>>>:
    r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "issues/" ++ n))
    return reply.obj(r)

# the issue a write touched, as its html_url
def write.get(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, String, Map<&2, String>> <- issue.get(repo, tok, n)
    x : Map<&2, String> <- need.row(env, r, "issue")
    IO.print(Api.f(x, "html_url"))

# arguments
# ---------

# a path segment: everything but RFC 3986's unreserved characters percent-encoded
def enc.keep(+c: U32) -> Bool:
  Bool.or(Bool.and(U32.is_le(65, c), U32.is_le(c, 90)), Bool.or(Bool.and(U32.is_le(97, c), U32.is_le(c, 122)), Bool.or(Bool.and(U32.is_le(48, c), U32.is_le(c, 57)), Bool.or(U32.is_eq(c, 45), Bool.or(U32.is_eq(c, 46), Bool.or(U32.is_eq(c, 95), U32.is_eq(c, 126)))))))

def enc.hex(+n: U32) -> U32:
  Bool.pick(U32, U32.is_le(n, 9), (48 + n : U32), (55 + n : U32))

def enc.push(+c: U32, acc: String, keep: Bool) -> String:
  match keep:
    case True{}:
      SCon{Chr{c}, acc}
    case False{}:
      SCon{Chr{enc.hex(U32.mod(c, 16))}, SCon{Chr{enc.hex(U32.div(c, 16))}, SCon{Chr{37}, acc}}}

def enc.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{+c}, t}:
      enc.go(t, enc.push(c, acc, enc.keep(c)))

def enc.seg(+s: String) -> String:
  enc.go(s, SNil{})

# "a, b ,c" as ["a", "b", "c"]
def trim.all(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      String.trim(x) <> trim.all(rest)

def names.keep.if(x: String, later: List<&2, String>, drop: Bool) -> List<&2, String>:
  match drop:
    case True{}:
      later
    case False{}:
      x <> later

def names.keep(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      names.keep.if(x, names.keep(rest), String.is_empty(x))

def split.names(+s: String) -> List<&2, String>:
  names.keep(trim.all(String.split(s, ',')))

# the body: --body, or --body-file (a path, "-" for stdin)
def text.stdin.if(+p: String, dash: Bool) -> String:
  match dash:
    case True{}:
      "/dev/stdin"
    case False{}:
      p

def text.path(+p: String) -> String:
  text.stdin.if(p, String.eq(p, "-"))

def text.got(r: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match r:
    case Done{s}:
      Some{s}
    case Fail{e}:
      None{}

def text.done(r: File & Result<&1, &1, U32 & String, String>) -> IO(Maybe<&2, String>):
  (f, got) = r
  do IO<Maybe<&2, String>>:
    File.close(f)
    return text.got(got)

def text.open(r: Result<&1, &1, U32 & String, File>) -> IO(Maybe<&2, String>):
  match r:
    case Done{f}:
      do IO<Maybe<&2, String>>:
        got : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1048576)
        text.done(got)
    case Fail{e}:
      IO.pure(Maybe<&2, String>, None{})

# a whole file's text; none when it can't be read
def text.read(path: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    text.open(r)

def text.pick.if(+body: String, +file: String, none: Bool) -> IO(Maybe<&2, String>):
  match none:
    case True{}:
      IO.pure(Maybe<&2, String>, Some{body})
    case False{}:
      text.read(text.path(file))

def text.pick(+body: String, +file: String) -> IO(Maybe<&2, String>):
  text.pick.if(body, file, String.is_empty(file))

def text.args(+args: List<&2, String>) -> IO(Maybe<&2, String>):
  text.pick(Cli.flag(args, "--body", ""), Cli.flag(args, "--body-file", ""))

def num.need(+env: Cli.Env, +n: String, +sub: String) -> IO(Unit):
  need(env, String.is_empty(n), "issue " ++ sub ++ ": give an issue number")

# labels
# ------

# a repo's labels: gitea caps a page at 50, github at 100. all follows Link when the forge sends it
def label.page(f: Ctx.Forge) -> String:
  match f:
    case Ctx.Gitea{}:
      "labels?limit=50"
    case Ctx.GitHub{}:
      "labels?per_page=100"

# a repo's labels, flattened to rows of "id" and "name"
def label.rows(+repo: Ctx.Repo, +tok: String) -> IO(Result<&1, &1, String, List<&2, Map<&2, String>>>):
  Api.all(20n, repo, tok, Api.path(repo, label.page(forge.of(repo))))

def id.same(+id: String, later: String, same: Bool) -> String:
  match same:
    case True{}:
      id
    case False{}:
      later

def id.scan(ls: List<&2, Map<&2, String>>, +name: String) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+x, rest}:
      id.same(Api.f(x, "id"), id.scan(rest, name), String.eq(Api.f(x, "name"), name))

# the id of each name, "" for a name the repo doesn't have
def ids.of(ls: List<&2, String>, +rows: List<&2, Map<&2, String>>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      id.scan(rows, x) <> ids.of(rest, rows)

def miss.if(x: String, later: List<&2, String>, blank: Bool) -> List<&2, String>:
  match blank:
    case True{}:
      x <> later
    case False{}:
      later

def miss.go(ns: List<&2, String>, +ids: List<&2, String>) -> List<&2, String>:
  match ns ids:
    case Nil{} _:
      Nil{}
    case Con{x, rest} Con{i, it}:
      miss.if(x, miss.go(rest, it), String.is_empty(i))
    case Con{x, rest} Nil{}:
      x <> miss.go(rest, Nil{})

# the names with no id, for an error
def miss(+ns: List<&2, String>, +ids: List<&2, String>) -> String:
  String.join(miss.go(ns, ids), ", ")

def label.check(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +names: List<&2, String>, +what: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    rows : Result<&1, &1, String, List<&2, Map<&2, String>>> <- label.rows(repo, tok)
    ls : List<&2, Map<&2, String>> <- need.rows(env, rows, what ++ ": can't read the repo's labels")
    +ids : List<&2, String> = ids.of(names, ls)
    need(env, Bool.not(List.is_empty(&2, String, miss.go(names, ids))), what ++ ": unknown label: " ++ miss(names, ids))
    return ids

# github matches a label name without case: a repo can't hold two names differing only in
# case, so "BUG" is the repo's "bug". one the repo doesn't have, the write would create,
# so a write reads the repo's labels first and sends back the repo's own spelling
def name.same(+a: String, +b: String) -> Bool:
  String.eq(String.to_lower(a), String.to_lower(b))

def canon.same(+name: String, later: String, same: Bool) -> String:
  match same:
    case True{}:
      name
    case False{}:
      later

# the repo's spelling of a name, "" for one it doesn't have
def canon.scan(ls: List<&2, Map<&2, String>>, +want: String) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+x, rest}:
      canon.same(Api.f(x, "name"), canon.scan(rest, want), name.same(want, Api.f(x, "name")))

def canons.of(ls: List<&2, String>, +rows: List<&2, Map<&2, String>>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      canon.scan(rows, x) <> canons.of(rest, rows)

def names.go(ls: List<&2, Map<&2, String>>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      Api.f(x, "name") <> names.go(rest)

# the names the repo has, since a typo is the usual way to reach an unknown one
def label.msg(+what: String, +missed: String, +rows: List<&2, Map<&2, String>>) -> String:
  what ++ ": unknown label: " ++ missed ++ "; labels: " ++ Ctx.or(String.join(names.go(rows), ", "), "none")

# the same read for github, which takes names and creates the unknown ones
def label.check.names(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +names: List<&2, String>, +what: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    rows : Result<&1, &1, String, List<&2, Map<&2, String>>> <- label.rows(repo, tok)
    +ls : List<&2, Map<&2, String>> <- need.rows(env, rows, what ++ ": can't read the repo's labels")
    +known : List<&2, String> = canons.of(names, ls)
    need(env, Bool.not(List.is_empty(&2, String, miss.go(names, known))), label.msg(what, miss(names, known), ls))
    return known

# json
# ----

def field(+k: String, v: Json.Val) -> Json.Member():
  (k, v)

def kv.if(+k: String, +v: String, give: Bool, rest: List<&2, Json.Member()>) -> List<&2, Json.Member()>:
  match give:
    case True{}:
      Con{field(k, Api.utf8(v)), rest}
    case False{}:
      rest

def strs.go(ss: List<&2, String>) -> List<&2, Json.Val>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      Api.utf8(s) <> strs.go(rest)

def strs.items(ss: List<&2, String>) -> Json.Val:
  Json.Arr{strs.go(ss)}

def nums.go(ss: List<&2, String>) -> List<&2, Json.Val>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      Json.Num{s} <> nums.go(rest)

def nums.items(ss: List<&2, String>) -> Json.Val:
  Json.Arr{nums.go(ss)}

def one.of.if(+s: String, none: Bool) -> List<&2, String>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      Con{s, Nil{}}

def one.of(+s: String) -> List<&2, String>:
  one.of.if(s, String.is_empty(s))

def obj.of(+k: String, v: Json.Val) -> Json.Val:
  Json.Obj{Con{field(k, v), Nil{}}}

def state.obj(+s: String) -> Json.Val:
  obj.of("state", Api.utf8(s))

def comment.obj(+body: String) -> Json.Val:
  obj.of("body", Api.utf8(body))

def create.obj(+title: String, +body: String, labels: Json.Val, +assignee: String) -> Json.Val:
  Json.Obj{Con{field("title", Api.utf8(title)), Con{field("body", Api.utf8(body)), Con{field("labels", labels), Con{field("assignees", strs.items(one.of(assignee))), Nil{}}}}}}

def edit.obj(+title: String, +body: String, title_on: Bool, body_on: Bool) -> Json.Val:
  Json.Obj{kv.if("title", title, title_on, kv.if("body", body, body_on, Nil{}))}

# view
# ----

def issue.fields() -> List<&2, String>:
  ["number", "title", "state", "user.login", "labels", "created_at", "html_url", "body"]

def comment.fields() -> List<&2, String>:
  ["id", "user.login", "created_at", "body", "html_url"]

def comments.path(f: Ctx.Forge, +n: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "issues/" ++ n ++ "/comments?limit=50"
    case Ctx.GitHub{}:
      "issues/" ++ n ++ "/comments?per_page=100"

def comments.get(+repo: Ctx.Repo, +tok: String, +n: String) -> IO(Result<&1, &1, String, List<&2, Map<&2, String>>>):
  Api.all(1n, repo, tok, Api.path(repo, comments.path(forge.of(repo), n)))

def view.labels.if(+on: Bool, +names: String, none: Bool) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      "  [" ++ Ui.dim(on, names) ++ "]"

def view.labels(+on: Bool, +x: Map<&2, String>) -> String:
  +names = Api.join(x, "labels", "name", ", ")
  view.labels.if(on, names, String.is_empty(names))

def view.text(+on: Bool, +x: Map<&2, String>) -> String:
  "#" ++ Api.f(x, "number") ++ "  " ++ Ui.state(on, Api.f(x, "state")) ++ "  " ++ Ui.bold(on, Api.f(x, "title")) ++ "\n" ++ "@" ++ Api.f(x, "user.login") ++ "  " ++ Api.f(x, "created_at") ++ view.labels(on, x) ++ "\n" ++ Ui.dim(on, Api.f(x, "html_url")) ++ "\n\n" ++ Api.f.lines(x, "body")

def comment.text(+on: Bool, +c: Map<&2, String>) -> String:
  "\n\n@" ++ Api.f(c, "user.login") ++ "  " ++ Ui.dim(on, Api.f(c, "created_at") ++ "  id " ++ Api.f(c, "id")) ++ "\n" ++ Api.f.lines(c, "body")

def comments.text(+on: Bool, cs: List<&2, Map<&2, String>>) -> String:
  match cs:
    case Nil{}:
      ""
    case Con{+c, rest}:
      comment.text(on, c) ++ comments.text(on, rest)

def view.json.if(want: Bool, +x: Map<&2, String>, +cs: List<&2, Map<&2, String>>) -> String:
  match want:
    case True{}:
      "{\"issue\":" ++ Cli.json.row(x, issue.fields()) ++ ",\"comments\":" ++ Cli.json.rows(cs, comment.fields()) ++ "}"
    case False{}:
      Cli.json.rows(Con{x, Nil{}}, issue.fields())

def view.json(+x: Map<&2, String>, +cs: List<&2, Map<&2, String>>, want: Bool) -> String:
  view.json.if(want, Map.set(&2, String, x, "labels", Api.raw.join(x, "labels", "name", ", ")), cs)

def view.json.out(+on: Bool, j: Cli.Json, +x: Map<&2, String>, +cs: List<&2, Map<&2, String>>, want: Bool) -> IO(Unit):
  match want:
    case True{}:
      do IO<Unit>:
        Cli.json.whole(on, j, "issue view --comments")
        IO.write(view.json(x, cs, True{}) ++ "\n")
    case False{}:
      Cli.json.emit(on, j, [Map.set(&2, String, x, "labels", Api.raw.join(x, "labels", "name", ", "))], issue.fields())

def view.print.if(json: Cli.Json, +on: Bool, +x: Map<&2, String>, +cs: List<&2, Map<&2, String>>, want: Bool) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(view.text(on, x) ++ comments.text(on, cs) ++ "\n")
    case j:
      view.json.out(on, j, x, cs, want)

def view.print(+env: Cli.Env, +x: Map<&2, String>, +cs: List<&2, Map<&2, String>>, want: Bool) -> IO(Unit):
  match env:
    case Cli.Env{r, t, +on, json, a}:
      view.print.if(json, on, x, cs, want)

def view.comments.by(want: Bool, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +x: Map<&2, String>) -> IO(Unit):
  match want:
    case True{}:
      do IO<Unit>:
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- comments.get(repo, tok, Api.f(x, "number"))
        cs : List<&2, Map<&2, String>> <- need.rows(env, r, "issue view: can't read comments")
        view.print(env, x, cs, True{})
    case False{}:
      view.print(env, x, Nil{}, False{})

# title, state, author, labels, created, url, then the body; comments with --comments
def view(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "issue view", args, ["--comments", "--json"])
        +n : String = Cli.arg(args, 1n)
        num.need(env, n, "view")
        r : Result<&1, &1, String, Map<&2, String>> <- issue.get(repo, tok, n)
        x : Map<&2, String> <- need.row(env, r, "issue view")
        view.comments.by(Cli.has(args, "--comments"), env, repo, tok, x)

# create
# ------

def create.labels.gitea(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +names: List<&2, String>) -> IO(Json.Val):
  do IO<Json.Val>:
    ids : List<&2, String> <- label.check(env, repo, tok, names, "issue create")
    return nums.items(ids)

# github creates a label it doesn't know, so the names are resolved first, when there are any
def create.labels.github(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +names: List<&2, String>, some: Bool) -> IO(Json.Val):
  match some:
    case True{}:
      do IO<Json.Val>:
        known : List<&2, String> <- label.check.names(env, repo, tok, names, "issue create")
        return strs.items(known)
    case False{}:
      IO.pure(Json.Val, strs.items(names))

def create.labels.by(github: Bool, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +names: List<&2, String>) -> IO(Json.Val):
  match github:
    case True{}:
      create.labels.github(env, repo, tok, names, Bool.not(List.is_empty(&2, String, names)))
    case False{}:
      create.labels.gitea(env, repo, tok, names)

# github takes label names, gitea takes label ids
def create.labels(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +names: List<&2, String>) -> IO(Json.Val):
  create.labels.by(is.github(forge.of(repo)), env, repo, tok, names)

def create(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "issue create", args, ["--title", "--body", "--body-file", "--label", "--assignee"])
        +title : String = Cli.flag(args, "--title", "")
        need(env, String.is_empty(title), "issue create: --title is required")
        got : Maybe<&2, String> <- text.args(args)
        +body : String <- need.maybe(env, got, "issue create: can't read the body file")
        +names : List<&2, String> = split.names(Cli.flag(args, "--label", ""))
        +assignee : String = Cli.flag(args, "--assignee", "")
        labels : Json.Val <- create.labels(env, repo, tok, names)
        r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, "issues"), Some{create.obj(title, body, labels, assignee)})
        write.done(env, r, "issue create")

# comment
# -------

def comment.post(+repo: Ctx.Repo, +tok: String, +n: String, +body: String) -> IO(Api.Reply):
  Api.send(repo, tok, "POST", Api.path(repo, "issues/" ++ n ++ "/comments"), Some{comment.obj(body)})

def comment.send(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +body: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- comment.post(repo, tok, n, body)
    write.done(env, r, "issue comment")

def comment(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "issue comment", args, ["--body", "--body-file"])
        +n : String = Cli.arg(args, 1n)
        num.need(env, n, "comment")
        got : Maybe<&2, String> <- text.args(args)
        +body : String <- need.maybe(env, got, "issue comment: can't read the body file")
        need(env, String.is_empty(body), "issue comment: --body or --body-file is required")
        comment.send(env, repo, tok, n, body)

# comment-edit, comment-delete
# ----------------------------
# A comment is addressed by its id, the one `issue view N --comments` prints beside each
# comment; a pull request's conversation comments are the same comments, so pr shares
# src/comment.bend.

def comment.edit.flags() -> List<&2, String>:
  ["--body", "--body-file"]

def comment.edit(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "issue comment-edit", args, comment.edit.flags())
        +id : String <- Comment.id.need(env, Cli.arg(args, 1n), "issue comment-edit")
        got : Maybe<&2, String> <- text.args(args)
        +body : String <- need.maybe(env, got, "issue comment-edit: can't read the body file")
        need(env, String.is_empty(body), "issue comment-edit: --body or --body-file is required")
        Comment.edit(env, repo, tok, id, body)

def comment.delete.flags() -> List<&2, String>:
  ["--yes"]

def comment.delete(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "issue comment-delete", args, comment.delete.flags())
        +id : String <- Comment.id.need(env, Cli.arg(args, 1n), "issue comment-delete")
        Comment.yes.need(env, Cli.has(args, "--yes"), "issue comment-delete", id)
        Comment.delete(env, repo, tok, id)

# edit
# ----

def edit(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "issue edit", args, ["--title", "--body", "--body-file"])
        +n : String = Cli.arg(args, 1n)
        num.need(env, n, "edit")
        +title_on : Bool = Cli.has(args, "--title")
        +body_on : Bool = Cli.has(args, "--body") || Cli.has(args, "--body-file")
        need(env, Bool.not(title_on || body_on), "issue edit: give --title, --body or --body-file")
        +title : String = Cli.flag(args, "--title", "")
        got : Maybe<&2, String> <- text.args(args)
        +body : String <- need.maybe(env, got, "issue edit: can't read the body file")
        r : Api.Reply <- Api.send(repo, tok, "PATCH", Api.path(repo, "issues/" ++ n), Some{edit.obj(title, body, title_on, body_on)})
        write.done(env, r, "issue edit")

# close, reopen
# -------------

# close's --comment is a side note: the issue's url is the one line it prints
def note.send.if(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +note: String, none: Bool) -> IO(Unit):
  match none:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        r : Api.Reply <- comment.post(repo, tok, n, note)
        check.done(env, r, "issue close: can't comment")

def note.send(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +note: String) -> IO(Unit):
  note.send.if(env, repo, tok, n, note, String.is_empty(note))

def set.state(+env: Cli.Env, +state: String, +n: String, +note: String, +what: String) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        r : Api.Reply <- Api.send(repo, tok, "PATCH", Api.path(repo, "issues/" ++ n), Some{state.obj(state)})
        write.done(env, r, what)
        note.send(env, repo, tok, n, note)

def close(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "issue close", args, ["--comment"])
        +n : String = Cli.arg(args, 1n)
        num.need(env, n, "close")
        set.state(env, "closed", n, Cli.flag(args, "--comment", ""), "issue close")

def reopen(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "issue reopen", args, [])
        +n : String = Cli.arg(args, 1n)
        num.need(env, n, "reopen")
        set.state(env, "open", n, "", "issue reopen")

# labels
# ------

def del.each(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +refs: List<&2, String>) -> IO(Unit):
  match refs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{r, rest}:
      do IO<Unit>:
        reply : Api.Reply <- Api.send(repo, tok, "DELETE", Api.path(repo, "issues/" ++ n ++ "/labels/" ++ enc.seg(r)), None{})
        check.done(env, reply, "issue labels: remove")
        del.each(env, repo, tok, n, rest)

# github addresses a label by its name, gitea by its id. resolving first catches an unknown
# name before a write: both forges ignore one, github creates it on the repo, and gitea's PUT
# clears the issue's labels for it. a known name is sent as the repo spells it
def labels.refs.by(github: Bool, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +names: List<&2, String>) -> IO(List<&2, String>):
  match github:
    case True{}:
      label.check.names(env, repo, tok, names, "issue labels")
    case False{}:
      label.check(env, repo, tok, names, "issue labels")

def labels.remove.by(github: Bool, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +names: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    refs : List<&2, String> <- labels.refs.by(github, env, repo, tok, names)
    del.each(env, repo, tok, n, refs)
    write.get(env, repo, tok, n)

def labels.remove(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +names: List<&2, String>) -> IO(Unit):
  labels.remove.by(is.github(forge.of(repo)), env, repo, tok, n, names)

def labels.items.by(github: Bool, +refs: List<&2, String>) -> Json.Val:
  match github:
    case True{}:
      strs.items(refs)
    case False{}:
      nums.items(refs)

# PUT replaces the whole set, POST adds to it
def labels.put.by(+github: Bool, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +method: String, +names: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    refs : List<&2, String> <- labels.refs.by(github, env, repo, tok, names)
    r : Api.Reply <- Api.send(repo, tok, method, Api.path(repo, "issues/" ++ n ++ "/labels"), Some{obj.of("labels", labels.items.by(github, refs))})
    check.done(env, r, "issue labels")
    write.get(env, repo, tok, n)

def labels.put(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +method: String, +names: List<&2, String>) -> IO(Unit):
  labels.put.by(is.github(forge.of(repo)), env, repo, tok, n, method, names)

def labels.op.of(add: Bool, remove: Bool, set: Bool) -> Nat:
  match add remove set:
    case True{} _ _:
      0n
    case False{} True{} _:
      1n
    case False{} False{} True{}:
      2n
    case False{} False{} False{}:
      3n

def labels.op(+op: String) -> Nat:
  labels.op.of(String.eq(op, "add"), String.eq(op, "remove"), String.eq(op, "set"))

def labels.do(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +n: String, +names: List<&2, String>, kind: Nat) -> IO(Unit):
  match kind:
    case 0n:
      labels.put(env, repo, tok, n, "POST", names)
    case 1n:
      labels.remove(env, repo, tok, n, names)
    case 2n:
      labels.put(env, repo, tok, n, "PUT", names)
    case 3n+k:
      Cli.fail(Unit, env, "issue labels: use add, remove or set")

def labels(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "issue labels", args, [])
        +n : String = Cli.arg(args, 1n)
        +op : String = Cli.arg(args, 2n)
        +names : List<&2, String> = split.names(Cli.arg(args, 3n))
        num.need(env, n, "labels")
        need(env, String.is_empty(op), "issue labels: use add, remove or set")
        need(env, List.is_empty(&2, String, names), "issue labels: give label names")
        labels.do(env, repo, tok, n, names, labels.op(op))

# dispatch
# --------

def subs() -> List<&2, String>:
  ["list", "view", "create", "comment", "comment-edit", "comment-delete", "edit", "close", "reopen", "labels"]

def index.at(eq: Bool, +i: Nat, +later: Nat) -> Nat:
  match eq:
    case True{}:
      i
    case False{}:
      later

def sub.scan(ls: List<&2, String>, +sub: String, +i: Nat) -> Nat:
  match ls:
    case Nil{}:
      i
    case Con{+x, rest}:
      index.at(String.eq(x, sub), i, sub.scan(rest, sub, 1n+i))

def sub.kind.if(kind: Nat, empty: Bool) -> Nat:
  match empty:
    case True{}:
      0n
    case False{}:
      kind

def sub.kind(+sub: String) -> Nat:
  sub.kind.if(sub.scan(subs(), sub, 0n), String.is_empty(sub))

def run.at(+env: Cli.Env, +sub: String, kind: Nat) -> IO(Unit):
  match kind:
    case 0n:
      list(env)
    case 1n:
      view(env)
    case 2n:
      create(env)
    case 3n:
      comment(env)
    case 4n:
      comment.edit(env)
    case 5n:
      comment.delete(env)
    case 6n:
      edit(env)
    case 7n:
      close(env)
    case 8n:
      reopen(env)
    case 9n:
      labels(env)
    case 10n+k:
      Cli.fail(Unit, env, "issue: unknown subcommand " ++ sub)

def run.sub(+env: Cli.Env, +sub: String) -> IO(Unit):
  run.at(env, sub, sub.kind(sub))

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      run.sub(env, Cli.arg(args, 0n))
