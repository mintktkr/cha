# cha issue: list, view, create, comment, edit, close, reopen, labels.
import Base
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli
import ../url.bend as Url
import ../since.bend as Since
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time

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
def query(f: Ctx.Forge, +state: String, +label: String, +assignee: String, +since: String, prs: Bool) -> String:
  match f:
    case Ctx.Gitea{}:
      "issues?" ++ Ctx.or.if("type=issues&", "", prs) ++ "limit=50&state=" ++ Url.encode(state) ++ param.q("&labels=", label) ++ param.q("&assigned_by=", assignee) ++ param.q("&since=", since)
    case Ctx.GitHub{}:
      "issues?per_page=100&state=" ++ Url.encode(state) ++ param.q("&labels=", label) ++ param.q("&assignee=", assignee) ++ param.q("&since=", since)

# --since as the RFC 3339 text a forge query takes, "" when the flag wasn't given
def since.text(+env: Cli.Env, m: Maybe<&2, Time.Instant>) -> IO(String):
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
        now : Time.Instant <- Time.now()
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

def list.show(+env: Cli.Env, r: Result<&1, &1, String, List<&2, Map<&2, String>>>) -> IO(Unit):
  match env r:
    case Cli.Env{repo, tok, +on, json, args} Done{xs}:
      list.print(on, json, with_labels(prs.keep(xs, Cli.has(args, "--with-prs"))))
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
        +f : Ctx.Forge = forge.of(repo)
        +assignee : String = Cli.flag(args, "--assignee", "")
        assignee.check(env, assignee.bad(f, assignee))
        bound : String <- since.bound(env, Cli.flag(args, "--since", ""))
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(list.pages(Cli.has(args, "--all")), repo, tok, Api.path(repo, query(f, Cli.flag(args, "--state", "open"), Cli.flag(args, "--label", ""), assignee, bound, Cli.has(args, "--with-prs"))))
        list.show(env, r)

# replies
# -------

def obj.if(+status: U32, body: Bytes.Bytes, good: Bool) -> Result<&1, &1, String, Map<&2, String>>:
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

# json
# ----

def field(+k: String, v: Json.Val) -> Bytes.Bytes & Json.Val:
  (Json.utf8(k), v)

def kv.if(+k: String, +v: String, give: Bool, rest: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  match give:
    case True{}:
      Con{field(k, Api.utf8(v)), rest}
    case False{}:
      rest

def strs.go(ss: List<&2, String>) -> List<&1, Json.Val>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      Api.utf8(s) <> strs.go(rest)

def strs.items(ss: List<&2, String>) -> Json.Val:
  Json.Arr{strs.go(ss)}

def nums.go(ss: List<&2, String>) -> List<&1, Json.Val>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      Json.Num{Bytes.from_string(s)} <> nums.go(rest)

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
  ["user.login", "created_at", "body", "html_url"]

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
  "#" ++ Api.f(x, "number") ++ "  " ++ Ui.state(on, Api.f(x, "state")) ++ "  " ++ Ui.bold(on, Api.f(x, "title")) ++ "\n" ++ "@" ++ Api.f(x, "user.login") ++ "  " ++ Api.f(x, "created_at") ++ view.labels(on, x) ++ "\n" ++ Ui.dim(on, Api.f(x, "html_url")) ++ "\n\n" ++ Api.f(x, "body")

def comment.text(+on: Bool, +c: Map<&2, String>) -> String:
  "\n\n@" ++ Api.f(c, "user.login") ++ "  " ++ Ui.dim(on, Api.f(c, "created_at")) ++ "\n" ++ Api.f(c, "body")

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

def create.labels.by(github: Bool, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +names: List<&2, String>) -> IO(Json.Val):
  match github:
    case True{}:
      IO.pure(Json.Val, strs.items(names))
    case False{}:
      create.labels.gitea(env, repo, tok, names)

# github takes label names, gitea takes label ids
def create.labels(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +names: List<&2, String>) -> IO(Json.Val):
  create.labels.by(is.github(forge.of(repo)), env, repo, tok, names)

def create(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
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
        +n : String = Cli.arg(args, 1n)
        num.need(env, n, "comment")
        got : Maybe<&2, String> <- text.args(args)
        +body : String <- need.maybe(env, got, "issue comment: can't read the body file")
        need(env, String.is_empty(body), "issue comment: --body or --body-file is required")
        comment.send(env, repo, tok, n, body)

# edit
# ----

def edit(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
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
        +n : String = Cli.arg(args, 1n)
        num.need(env, n, "close")
        set.state(env, "closed", n, Cli.flag(args, "--comment", ""), "issue close")

def reopen(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
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
# name before a write: both forges ignore one, and gitea's PUT clears the issue's labels for it
def labels.refs.by(github: Bool, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +names: List<&2, String>) -> IO(List<&2, String>):
  match github:
    case True{}:
      IO.pure(List<&2, String>, names)
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
  ["list", "view", "create", "comment", "edit", "close", "reopen", "labels"]

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
      edit(env)
    case 5n:
      close(env)
    case 6n:
      reopen(env)
    case 7n:
      labels(env)
    case 8n+k:
      Cli.fail(Unit, env, "issue: unknown subcommand " ++ sub)

def run.sub(+env: Cli.Env, +sub: String) -> IO(Unit):
  run.at(env, sub, sub.kind(sub))

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      run.sub(env, Cli.arg(args, 0n))
