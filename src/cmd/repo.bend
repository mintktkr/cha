# cha repo: view, labels, label-create, branches, file, tree.
#
# gitea answers a raw file path with bytes; github answers a contents path with base64
# unless the accept header asks for raw, so a file read carries its own client.
import Base
import bend-kit-hairpin@0.1.0.0/hairpin.bend as Hairpin
import bend-kit-http@0.23.0.1/http.bend as Http
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../ctx.bend as Ctx
import ../api.bend as Api
import ../ui.bend as Ui
import ../cli.bend as Cli

# Forge
# -----

def forge.of(r: Ctx.Repo) -> Ctx.Forge:
  match r:
    case Ctx.Repo{f, h, o, n}:
      f

def forge.name(f: Ctx.Forge) -> String:
  match f:
    case Ctx.Gitea{}:
      "gitea"
    case Ctx.GitHub{}:
      "github"

# a flattened JSON bool field, which Api.rows renders as "true" or "false"
def bool.f(+x: Map<&2, String>, +k: String) -> Bool:
  String.eq(Api.f(x, k), "true")

# s with pre in front of it, unless s is empty
def prefixed(+s: String, +pre: String) -> String:
  Ctx.or.if(pre ++ s, "", String.is_empty(s))

# the word a flag adds to a row, or nothing
def flag.text(+on: Bool, +word: String, set: Bool) -> String:
  match set:
    case True{}:
      Ui.dim(on, word)
    case False{}:
      ""

# value, or the command fails saying what was missing
def arg.of(+env: Cli.Env, +msg: String, +value: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      Cli.fail(String, env, msg)
    case False{}:
      IO.pure(String, value)

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

# a repo's page on its forge
def repo.web(+repo: Ctx.Repo) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      "https://" ++ h ++ "/" ++ o ++ "/" ++ n

# a created thing: its url on stdout, a ✓ line on stderr
def created(+env: Cli.Env, +msg: String, +url: String) -> IO(Unit):
  match env:
    case Cli.Env{r, t, +on, j, a}:
      do IO<Unit>:
        IO.print(url)
        Ui.done(on, "created " ++ msg)

# Label colours
# -------------

def nibble.digit(x: U32) -> U32:
  U32.sub(x, 48)

def nibble.lower(x: U32) -> U32:
  U32.add(U32.sub(x, 97), 10)

def nibble.upper(x: U32) -> U32:
  U32.add(U32.sub(x, 65), 10)

def nibble.of(+x: U32, digit: Bool, low: Bool) -> U32:
  match digit low:
    case True{} l:
      nibble.digit(x)
    case False{} True{}:
      nibble.lower(x)
    case False{} False{}:
      nibble.upper(x)

# one hex digit's value; garbage on anything else, so callers check the shape first
def nibble(+c: Char) -> U32:
  nibble.of(Char.to_u32(c), Char.is_digit(c), U32.is_ge(Char.to_u32(c), 97))

def hex.alpha(+x: U32) -> Bool:
  Bool.or(Bool.and(U32.is_ge(x, 97), U32.is_le(x, 102)), Bool.and(U32.is_ge(x, 65), U32.is_le(x, 70)))

def hex.char(+c: Char) -> Bool:
  Bool.or(Char.is_digit(c), hex.alpha(Char.to_u32(c)))

def hex.ok(ps: List<&2, Char>) -> Bool:
  match ps:
    case Nil{}:
      True{}
    case Con{+c, t}:
      Bool.and(hex.char(c), hex.ok(t))

def hex.value.go(cs: List<&2, Char>, acc: U32) -> U32:
  match cs:
    case Nil{}:
      acc
    case Con{c, t}:
      hex.value.go(t, U32.add(U32.mul(acc, 16), nibble(c)))

def rgb.of(+v: U32) -> Ui.Rgb:
  Ui.Rgb{U32.and(U32.shrn(v, 16n), 255), U32.and(U32.shrn(v, 8n), 255), U32.and(v, 255)}

def color.rgb.of(+h: String, ok: Bool) -> Maybe<&2, Ui.Rgb>:
  match ok:
    case True{}:
      Some{rgb.of(hex.value.go(String.to_list(h), 0))}
    case False{}:
      None{}

# a label's colour, when its text is six hex digits
def color.rgb(+c: String) -> Maybe<&2, Ui.Rgb>:
  +h = Ctx.strip_prefix(c, "#")
  color.rgb.of(h, Bool.and(Nat.is_eq(String.length(h), 6n), hex.ok(String.to_list(h))))

def color.show(+on: Bool, +c: String, m: Maybe<&2, Ui.Rgb>) -> String:
  match m:
    case Some{rgb}:
      Ui.fg(on, rgb, "#" ++ c)
    case None{}:
      Ui.dim(on, "#" ++ c)

# a label's colour as "#rrggbb", in itself when it parses, dim otherwise
def color.text(+on: Bool, +c: String) -> String:
  color.show(on, Ctx.strip_prefix(c, "#"), color.rgb(c))

# the colour to send: github wants the hex bare, gitea's own spelling carries the #
def color.arg(f: Ctx.Forge, +c: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "#" ++ Ctx.strip_prefix(c, "#")
    case Ctx.GitHub{}:
      Ctx.strip_prefix(c, "#")

def vis.kind(public: Bool) -> Nat:
  match public:
    case True{}:
      1n
    case False{}:
      0n

# public is mint like an open item; private and internal stay dim
def vis.text(+on: Bool, +v: String) -> String:
  Ui.state.of(on, v, vis.kind(String.eq(v, "public")))

# the gitea or the github spelling of one field, for building a row: a row holds what the
# forge sent, and the text printers read it back through Api.f
def pick(f: Ctx.Forge, +x: Map<&2, String>, +gitea: String, +github: String) -> String:
  match f:
    case Ctx.Gitea{}:
      Api.raw.f(x, gitea)
    case Ctx.GitHub{}:
      Api.raw.f(x, github)

# view
# ----

def gitea.visibility(hidden: Bool, internal: Bool) -> String:
  match hidden internal:
    case True{} i:
      "private"
    case False{} True{}:
      "internal"
    case False{} False{}:
      "public"

def visibility(f: Ctx.Forge, +x: Map<&2, String>) -> String:
  match f:
    case Ctx.Gitea{}:
      gitea.visibility(bool.f(x, "private"), bool.f(x, "internal"))
    case Ctx.GitHub{}:
      Ctx.or(Api.raw.f(x, "visibility"), "public")

# the row of repo view, with the fields the two forges spell differently made one
def view.row(+f: Ctx.Forge, +x: Map<&2, String>) -> Map<&2, String>:
  +a = Map.set(&2, String, x, "forge", forge.name(f))
  +b = Map.set(&2, String, a, "visibility", visibility(f, a))
  +c = Map.set(&2, String, b, "stars", pick(f, b, "stars_count", "stargazers_count"))
  +d = Map.set(&2, String, c, "forks", pick(f, c, "forks_count", "forks_count"))
  Map.set(&2, String, d, "open_issues", pick(f, d, "open_issues_count", "open_issues_count"))

def view.text(+on: Bool, +x: Map<&2, String>) -> String:
  +desc = Api.f(x, "description")
  Ui.bold(on, Api.f(x, "full_name")) ++ "  " ++ vis.text(on, Api.f(x, "visibility")) ++ "\n" ++
  Ctx.or.if(Ui.dim(on, desc) ++ "\n", "", String.is_empty(desc)) ++
  "default branch  " ++ Api.f(x, "default_branch") ++ "\n" ++
  "stars  " ++ Api.f(x, "stars") ++ "  forks  " ++ Api.f(x, "forks") ++ "  open issues  " ++ Api.f(x, "open_issues") ++ "\n" ++
  Ui.fg(on, Ui.aqua(), Api.f(x, "html_url")) ++ "\n"

def view.out(+on: Bool, json: Cli.Json, +x: Map<&2, String>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(view.text(on, x))
    case j:
      Cli.json.emit(on, j, [x], ["full_name", "forge", "description", "default_branch", "visibility", "stars", "forks", "open_issues", "html_url"])

def view.url(+repo: Ctx.Repo) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      "repos/" ++ o ++ "/" ++ n

def view(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        r : Api.Reply <- Api.get(repo, tok, view.url(repo))
        b : Bytes.Bytes <- body.reply(env, r)
        view.out(on, json, view.row(forge.of(repo), Api.obj(b)))

# labels
# ------

def label.row(+x: Map<&2, String>) -> Map<&2, String>:
  Map.set(&2, String, x, "color", "#" ++ Ctx.strip_prefix(Api.raw.f(x, "color"), "#"))

def label.rows(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      label.row(x) <> label.rows(rest)

def label.line(+on: Bool, +x: Map<&2, String>) -> String:
  +desc = Api.f(x, "description")
  color.text(on, Api.f(x, "color")) ++ "  " ++ Ui.bold(on, Api.f(x, "name")) ++ Ctx.or.if("  " ++ Ui.dim(on, desc), "", String.is_empty(desc))

def label.lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      label.line(on, x) ++ "\n" ++ label.lines(on, rest)

def label.print(+on: Bool, json: Cli.Json, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(label.lines(on, xs))
    case j:
      Cli.json.emit(on, j, xs, ["name", "color", "description"])

# the labels of a repo, across pages where the forge pages them
def label.show(+env: Cli.Env, r: Result<&1, &1, String, List<&2, Map<&2, String>>>) -> IO(Unit):
  match env r:
    case Cli.Env{r, t, +on, json, a} Done{xs}:
      label.print(on, json, label.rows(xs))
    case e Fail{w}:
      Cli.fail(Unit, e, w)

def label.query(f: Ctx.Forge) -> String:
  match f:
    case Ctx.Gitea{}:
      "labels?limit=1000"
    case Ctx.GitHub{}:
      "labels?per_page=100"

def labels(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(10n, repo, tok, Api.path(repo, label.query(forge.of(repo))))
        label.show(env, r)

# label-create
# ------------

def label.body(+name: String, +color: String, +desc: String) -> Json.Val:
  Json.Obj{[(Json.utf8("name"), Api.utf8(name)), (Json.utf8("color"), Api.utf8(color)), (Json.utf8("description"), Api.utf8(desc))]}

def label.send(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +name: String, +args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.send(repo, tok, "POST", Api.path(repo, "labels"), Some{label.body(name, color.arg(forge.of(repo), Cli.flag(args, "--color", "#ff6eb4")), Cli.flag(args, "--description", ""))})
    b : Bytes.Bytes <- body.reply(env, r)
    created(env, "label " ++ name, repo.web(repo) ++ "/labels")

def create(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +raw : String = Cli.arg(args, 1n)
        name : String <- arg.of(env, "label-create: a name is required", raw, String.is_empty(raw))
        label.send(env, repo, tok, name, args)

# branches
# --------

def branch.sha(f: Ctx.Forge, +x: Map<&2, String>) -> String:
  match f:
    case Ctx.Gitea{}:
      Api.f(x, "commit.id")
    case Ctx.GitHub{}:
      Api.f(x, "commit.sha")

def branch.row(f: Ctx.Forge, +x: Map<&2, String>) -> Map<&2, String>:
  Map.set(&2, String, x, "sha", branch.sha(f, x))

def branch.rows(+f: Ctx.Forge, xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      branch.row(f, x) <> branch.rows(f, rest)

def branch.line(+on: Bool, +x: Map<&2, String>) -> String:
  Ui.bold(on, Ui.fg(on, Ui.aqua(), Api.f(x, "name"))) ++ "  " ++ Ui.dim(on, String.take(Api.f(x, "sha"), 12n)) ++ prefixed(flag.text(on, "protected", bool.f(x, "protected")), "  ")

def branch.lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      branch.line(on, x) ++ "\n" ++ branch.lines(on, rest)

def branch.print(+on: Bool, json: Cli.Json, +xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(branch.lines(on, xs))
    case j:
      Cli.json.emit(on, j, xs, ["name", "sha", "protected"])

def branch.show(+env: Cli.Env, r: Result<&1, &1, String, List<&2, Map<&2, String>>>) -> IO(Unit):
  match env r:
    case Cli.Env{+repo, +tok, on, json, +args} Done{xs}:
      branch.print(on, json, branch.rows(forge.of(repo), xs))
    case e Fail{w}:
      Cli.fail(Unit, e, w)

def branch.query(f: Ctx.Forge) -> String:
  match f:
    case Ctx.Gitea{}:
      "branches?limit=1000"
    case Ctx.GitHub{}:
      "branches?per_page=100"

def branches(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(10n, repo, tok, Api.path(repo, branch.query(forge.of(repo))))
        branch.show(env, r)

# file
# ----

# ?ref=<ref>, when a ref was asked for
def ref.query(+ref: String, empty: Bool) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      "?ref=" ++ ref

def file.path(f: Ctx.Forge, +path: String, +ref: String, empty: Bool) -> String:
  match f:
    case Ctx.Gitea{}:
      "raw/" ++ path ++ ref.query(ref, empty)
    case Ctx.GitHub{}:
      "contents/" ++ path ++ ref.query(ref, empty)

# a client whose accept header asks github for the file's bytes rather than base64
def raw.client(+repo: Ctx.Repo, +tok: String) -> Hairpin.Client:
  match repo:
    case Ctx.Repo{+f, +h, o, n}:
      c = Hairpin.header(Hairpin.header(Hairpin.base(Hairpin.new(), Api.base(f, h)), "accept", "application/vnd.github.raw"), "user-agent", "cha")
      Api.authed(c, f, tok, String.is_empty(tok))

def raw.get(+repo: Ctx.Repo, +tok: String, url: String) -> IO(Api.Reply):
  do IO<Api.Reply>:
    r : Hairpin.Client & Result<&1, &1, Http.Err, Http.Res> <- Hairpin.request(raw.client(repo, tok), "GET", url, Map.new(&2, List<&2, String>), Http.from_string(""))
    Api.reply(r)

def file.reply(f: Ctx.Forge, +repo: Ctx.Repo, +tok: String, url: String) -> IO(Api.Reply):
  match f:
    case Ctx.Gitea{}:
      Api.get(repo, tok, url)
    case Ctx.GitHub{}:
      raw.get(repo, tok, url)

# A file's contents are the file, so a pipe or a redirect keeps them byte-exact: the body
# is printed as it came. A terminal gets the text without escape sequences, so a file whose
# bytes are a title screen cannot draw on it.
def file.text(body: Bytes.Bytes, tty: Bool) -> String:
  match tty:
    case True{}:
      Api.text(body)
    case False{}:
      Api.raw.text(body)

def file.write(body: Bytes.Bytes) -> IO(Unit):
  do IO<Unit>:
    # the stream decides, not the colour flag: NO_COLOR in a terminal still means a human
    # is reading the bytes, and only a pipe or a redirect needs them exact
    tty : Bool <- Ui.tty()
    IO.write(file.text(body, tty))

def file.print(+env: Cli.Env, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      file.write(body)
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def file.show(+env: Cli.Env, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{why}:
      Cli.fail(Unit, env, why)
    case Api.Reply{+status, +next, body}:
      file.print(env, status, body, Api.ok(status))

def file(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +raw : String = Cli.arg(args, 1n)
        path : String <- arg.of(env, "file: a path is required", raw, String.is_empty(raw))
        +ref : String = Cli.flag(args, "--ref", "")
        +f : Ctx.Forge = forge.of(repo)
        r : Api.Reply <- file.reply(f, repo, tok, Api.path(repo, file.path(f, path, ref, String.is_empty(ref))))
        file.show(env, r)

# tree
# ----

def tree.ref(+ref: String) -> String:
  Ctx.or(ref, "HEAD")

def tree.query(f: Ctx.Forge, +ref: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "git/trees/" ++ ref ++ "?recursive=true&per_page=1000"
    case Ctx.GitHub{}:
      "git/trees/" ++ ref ++ "?recursive=1"

def tree.key(+i: U32, +k: String) -> String:
  "tree." ++ U32.show(i) ++ "." ++ k

def tree.row(+big: Map<&2, String>, +i: U32) -> Map<&2, String>:
  a = Map.set(&2, String, Map.new(&2, String), "path", Api.raw.f(big, tree.key(i, "path")))
  b = Map.set(&2, String, a, "type", Api.raw.f(big, tree.key(i, "type")))
  Map.set(&2, String, b, "sha", Api.raw.f(big, tree.key(i, "sha")))

def tree.rows(n: Nat, +big: Map<&2, String>, +i: U32) -> List<&2, Map<&2, String>>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      tree.row(big, i) <> tree.rows(k, big, (i + 1 : U32))

def tree.lines(n: Nat, +big: Map<&2, String>, +i: U32) -> String:
  match n:
    case 0n:
      ""
    case 1n+k:
      Api.f(big, tree.key(i, "path")) ++ "\n" ++ tree.lines(k, big, (i + 1 : U32))

def tree.note(+on: Bool, truncated: Bool) -> IO(Unit):
  match truncated:
    case True{}:
      Ui.info(on, "tree truncated by the forge; read the checkout for the whole tree")
    case False{}:
      IO.pure(Unit, Unit{})

def tree.print(+on: Bool, json: Cli.Json, +x: Map<&2, String>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(tree.lines(Api.count(x, "tree"), x, 0))
    case j:
      Cli.json.emit(on, j, tree.rows(Api.count(x, "tree"), x, 0), ["path", "type", "sha"])

def tree.out(+env: Cli.Env, b: Bytes.Bytes) -> IO(Unit):
  match env:
    case Cli.Env{r, t, +on, json, a}:
      do IO<Unit>:
        +x : Map<&2, String> = Api.obj(b)
        +cut : Bool = bool.f(x, "truncated")
        tree.print(on, json, x)
        tree.note(on, cut)

def tree(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        +ref : String = tree.ref(Cli.flag(args, "--ref", ""))
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, tree.query(forge.of(repo), ref)))
        b : Bytes.Bytes <- body.reply(env, r)
        tree.out(env, b)

# dispatch
# --------

def names() -> List<&2, String>:
  ["view", "labels", "label-create", "branches", "file", "tree"]

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
      view(env)
    case 1n:
      labels(env)
    case 2n:
      create(env)
    case 3n:
      branches(env)
    case 4n:
      file(env)
    case 5n:
      tree(env)
    case 6n+k:
      Cli.fail(Unit, env, "repo: unknown subcommand, try cha help")

def run.sub(+env: Cli.Env, +sub: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      view(env)
    case False{}:
      run.at(env, index(names(), sub, 0n))

def run(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      +sub : String = Cli.arg(args, 0n)
      run.sub(env, sub, String.is_empty(sub))
