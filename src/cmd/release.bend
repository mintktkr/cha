# cha release: list, view, latest, create.
import Base
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli

# Replies
# -------

# the reply's body when the status was ok, failing the command otherwise
def body.of(+env: Cli.Env, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Bytes.Bytes):
  match good:
    case True{}:
      IO.pure(Bytes.Bytes, body)
    case False{}:
      Cli.fail(Bytes.Bytes, env, Api.message(status, body))

def body.reply(+env: Cli.Env, r: Api.Reply) -> IO(Bytes.Bytes):
  match r:
    case Api.Broke{why}:
      Cli.fail(Bytes.Bytes, env, why)
    case Api.Reply{+status, +next, body}:
      body.of(env, status, body, Api.ok(status))

# a created thing: its url on stdout, a ✓ line on stderr
def created(+env: Cli.Env, +msg: String, +url: String) -> IO(Unit):
  match env:
    case Cli.Env{r, t, +on, j, a}:
      do IO<Unit>:
        IO.print(url)
        Ui.done(on, "created " ++ msg)

# s with pre in front of it, unless s is empty
def prefixed(+s: String, +pre: String) -> String:
  Ctx.or.if(pre ++ s, "", String.is_empty(s))

# a flattened JSON bool field, which Api.rows renders as "True" or "False"
def bool.f(+x: Map<&2, String>, +k: String) -> Bool:
  String.eq(Api.f(x, k), "True")

# Rows
# ----

# published_at, or created_at for a release the forge has not published yet
def release.row(+x: Map<&2, String>) -> Map<&2, String>:
  Map.set(&2, String, x, "published", Ctx.or(Api.f(x, "published_at"), Api.f(x, "created_at")))

def release.rows(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      release.row(x) <> release.rows(rest)

# List
# ----

def release.flags.go(+on: Bool, draft: Bool, pre: Bool) -> String:
  match draft pre:
    case True{} True{}:
      Ui.state.of(on, "draft", 0n) ++ " " ++ Ui.state.of(on, "prerelease", 3n)
    case True{} False{}:
      Ui.state.of(on, "draft", 0n)
    case False{} True{}:
      Ui.state.of(on, "prerelease", 3n)
    case False{} False{}:
      ""

def release.flags(+on: Bool, +x: Map<&2, String>) -> String:
  release.flags.go(on, bool.f(x, "draft"), bool.f(x, "prerelease"))

def release.line(+on: Bool, +x: Map<&2, String>) -> String:
  Ui.bold(on, Ui.fg(on, Ui.aqua(), Api.f(x, "tag_name"))) ++ "  " ++ Api.f(x, "name") ++ "  " ++ Ui.dim(on, String.take(Api.f(x, "published"), 10n)) ++ prefixed(release.flags(on, x), "  ")

def release.lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      release.line(on, x) ++ "\n" ++ release.lines(on, rest)

def release.print(+on: Bool, json: Bool, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case True{}:
      IO.print(Cli.json.rows(xs, ["tag_name", "name", "published", "draft", "prerelease", "html_url"]))
    case False{}:
      IO.write(release.lines(on, xs))

def release.show(+env: Cli.Env, r: Result<&1, &1, String, List<&2, Map<&2, String>>>) -> IO(Unit):
  match env r:
    case Cli.Env{r2, t, +on, json, a} Done{xs}:
      release.print(on, json, release.rows(xs))
    case e Fail{w}:
      Cli.fail(Unit, e, w)

def release.query(f: Ctx.Forge) -> String:
  match f:
    case Ctx.Gitea{}:
      "releases?limit=50"
    case Ctx.GitHub{}:
      "releases?per_page=100"

def release.query.repo(+repo: Ctx.Repo) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      release.query(f)

def list(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(1n, repo, tok, Api.path(repo, release.query.repo(repo)))
        release.show(env, r)

# view
# ----

def view.text(+on: Bool, +x: Map<&2, String>) -> String:
  +body = Api.f(x, "body")
  Ui.bold(on, Ui.fg(on, Ui.aqua(), Api.f(x, "tag_name"))) ++ "  " ++ Api.f(x, "name") ++ prefixed(release.flags(on, x), "  ") ++ "\n" ++
  Ui.dim(on, String.take(Api.f(x, "published"), 10n)) ++ "\n" ++
  Ui.fg(on, Ui.aqua(), Api.f(x, "html_url")) ++ "\n" ++
  Ctx.or.if("\n" ++ body ++ "\n", "", String.is_empty(body))

def view.out(+on: Bool, json: Bool, +x: Map<&2, String>) -> IO(Unit):
  match json:
    case True{}:
      IO.print(Cli.json.rows([x], ["tag_name", "name", "published", "draft", "prerelease", "body", "html_url"]))
    case False{}:
      IO.write(view.text(on, x))

# which endpoint answers a tag: latest, or releases/tags/<tag>
def latest.of(+tag: String) -> Bool:
  Bool.or(String.is_empty(tag), String.eq(tag, "latest"))

def view.url(+tag: String, latest: Bool) -> String:
  match latest:
    case True{}:
      "releases/latest"
    case False{}:
      "releases/tags/" ++ tag

def view(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +tag : String = Cli.arg(args, 1n)
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, view.url(tag, latest.of(tag))))
        b : Bytes.Bytes <- body.reply(env, r)
        view.out(on, json, release.row(Api.obj(b)))

# latest
# ------

def latest.line(+on: Bool, +x: Map<&2, String>) -> String:
  Ui.bold(on, Ui.fg(on, Ui.aqua(), Api.f(x, "tag_name"))) ++ "  " ++ Api.f(x, "name") ++ "  " ++ Ui.dim(on, String.take(Api.f(x, "published"), 10n)) ++ "  " ++ Api.f(x, "html_url") ++ "\n"

def latest.out(+on: Bool, json: Bool, +x: Map<&2, String>) -> IO(Unit):
  match json:
    case True{}:
      IO.print(Cli.json.rows([x], ["tag_name", "name", "published", "draft", "prerelease", "html_url"]))
    case False{}:
      IO.write(latest.line(on, x))

def latest(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, "releases/latest"))
        b : Bytes.Bytes <- body.reply(env, r)
        latest.out(on, json, release.row(Api.obj(b)))

# create
# ------

# a word of the arguments, as the tag scan sees it
type Piece is Data:
  Keep{s: String}
  Skip{}

def piece.of(+a: String, same: Bool) -> Piece:
  match same:
    case True{}:
      Skip{}
    case False{}:
      Keep{a}

def piece.add(p: Piece, tail: List<&2, String>) -> List<&2, String>:
  match p:
    case Keep{s}:
      s <> tail
    case Skip{}:
      tail

# args without a standalone flag, so Cli.arg does not read the word after it as its value
def flag.drop(xs: List<&2, String>, +name: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      piece.add(piece.of(a, String.eq(a, name)), flag.drop(rest, name))

def create.tag(+env: Cli.Env, +tag: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      Cli.fail(String, env, "release create: a tag is required")
    case False{}:
      IO.pure(String, tag)

# a read result as its text, or the command fails
def read.text(+env: Cli.Env, +path: String, r: Result<&1, &1, U32 & String, String>) -> IO(String):
  match r:
    case Done{s}:
      IO.pure(String, s)
    case Fail{e}:
      Cli.fail(String, env, "can't read " ++ path)

def read.got(+env: Cli.Env, +path: String, r: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, got) = r
  do IO<String>:
    File.close(f)
    read.text(env, path, got)

def read.open(+env: Cli.Env, +path: String, r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Done{f}:
      do IO<String>:
        got : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1048576)
        read.got(env, path, got)
    case Fail{e}:
      Cli.fail(String, env, "can't read " ++ path)

# a file's text, failing the command when it cannot be read; "-" means stdin
def read.file(+env: Cli.Env, +path: String, dash: Bool) -> IO(String):
  do IO<String>:
    +p : String = Ctx.or.if(path, "/dev/stdin", dash)
    r : Result<&1, &1, U32 & String, File> <- File.open(p, "r")
    read.open(env, p, r)

def notes.file(+env: Cli.Env, +path: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      Cli.fail(String, env, "release create: --notes-file needs a path")
    case False{}:
      read.file(env, path, String.eq(path, "-"))

# the notes: --notes-file, when given, else the --notes text
def notes.of(+env: Cli.Env, +notes: String, +path: String, from_file: Bool) -> IO(String):
  match from_file:
    case True{}:
      notes.file(env, path, String.is_empty(path))
    case False{}:
      IO.pure(String, notes)

def kv.text(kvs: List<&1, Bytes.Bytes & Json.Val>, +k: String, +v: String, keep: Bool) -> List<&1, Bytes.Bytes & Json.Val>:
  match keep:
    case True{}:
      Con{(Json.utf8(k), Api.utf8(v)), kvs}
    case False{}:
      kvs

def kv.flag(kvs: List<&1, Bytes.Bytes & Json.Val>, +k: String, on: Bool) -> List<&1, Bytes.Bytes & Json.Val>:
  Con{(Json.utf8(k), Json.Flag{on}), kvs}

def create.kvs(+tag: String, +title: String, +notes: String, +target: String, draft: Bool, pre: Bool) -> List<&1, Bytes.Bytes & Json.Val>:
  k0 : List<&1, Bytes.Bytes & Json.Val> = Con{(Json.utf8("tag_name"), Api.utf8(tag)), Nil{}}
  k1 = kv.text(k0, "name", title, Bool.not(String.is_empty(title)))
  k2 = kv.text(k1, "body", notes, Bool.not(String.is_empty(notes)))
  k3 = kv.text(k2, "target_commitish", target, Bool.not(String.is_empty(target)))
  kv.flag(kv.flag(k3, "draft", draft), "prerelease", pre)

def create.body(+tag: String, +title: String, +notes: String, +target: String, draft: Bool, pre: Bool) -> Json.Val:
  Json.Obj{create.kvs(tag, title, notes, target, draft, pre)}

def create.send(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +tag: String, +title: String, +notes: String, draft: Bool, pre: Bool, +target: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, "releases"), Some{create.body(tag, title, notes, target, draft, pre)})
    b : Bytes.Bytes <- body.reply(env, r)
    created(env, "release " ++ tag, Api.f(Api.obj(b), "html_url"))

def create(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +tag : String = Cli.arg(flag.drop(flag.drop(args, "--draft"), "--prerelease"), 1n)
        t : String <- create.tag(env, tag, String.is_empty(tag))
        notes : String <- notes.of(env, Cli.flag(args, "--notes", ""), Cli.flag(args, "--notes-file", ""), Cli.has(args, "--notes-file"))
        create.send(env, repo, tok, t, Cli.flag(args, "--title", ""), notes, Cli.has(args, "--draft"), Cli.has(args, "--prerelease"), Cli.flag(args, "--target", ""))

# dispatch
# --------

def names() -> List<&2, String>:
  ["list", "view", "latest", "create"]

def index.at(eq: Bool, +i: Nat, +later: Nat) -> Nat:
  match eq:
    case True{}:
      i
    case False{}:
      later

# the subcommand's index in names(), or the list's length when unknown
def index(xs: List<&2, String>, +w: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case Con{x, rest}:
      index.at(String.eq(x, w), i, index(rest, w, 1n+i))

def run.at(+env: Cli.Env, n: Nat) -> IO(Unit):
  match n:
    case 0n:
      list(env)
    case 1n:
      view(env)
    case 2n:
      latest(env)
    case 3n:
      create(env)
    case 4n+k:
      Cli.fail(Unit, env, "release: unknown subcommand, try cha help")

def run.sub(+env: Cli.Env, +sub: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      list(env)
    case False{}:
      run.at(env, index(names(), sub, 0n))

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      +sub : String = Cli.arg(args, 0n)
      run.sub(env, sub, String.is_empty(sub))
