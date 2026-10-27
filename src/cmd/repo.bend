# cha repo: view, labels, label-create, branches, branch-delete, protection, file, tree.
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
import ../url.bend as Url

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
  +e = Map.set(&2, String, d, "open_issues", pick(f, d, "open_issues_count", "open_issues_count"))
  +g = Map.set(&2, String, e, "mirror", Api.raw.f(e, "mirror"))
  Map.set(&2, String, g, "original_url", Ctx.no_credentials(Api.raw.f(g, "original_url")))

# a pull mirror says what it mirrors; any other repo says nothing

def view.mirror.text(+on: Bool, +x: Map<&2, String>) -> String:
  Ctx.or.if("mirror of " ++ Ui.fg(on, Ui.aqua(), Api.f(x, "original_url")) ++ "\n", "", Bool.not(bool.f(x, "mirror")))

def view.text(+on: Bool, +x: Map<&2, String>) -> String:
  +desc = Api.f(x, "description")
  Ui.bold(on, Api.f(x, "full_name")) ++ "  " ++ vis.text(on, Api.f(x, "visibility")) ++ "\n" ++
  Ctx.or.if(Ui.dim(on, desc) ++ "\n", "", String.is_empty(desc)) ++
  "default branch  " ++ Api.f(x, "default_branch") ++ "\n" ++
  "stars  " ++ Api.f(x, "stars") ++ "  forks  " ++ Api.f(x, "forks") ++ "  open issues  " ++ Api.f(x, "open_issues") ++ "\n" ++
  Ui.fg(on, Ui.aqua(), Api.f(x, "html_url")) ++ "\n" ++
  view.mirror.text(on, x)

def view.out(+on: Bool, json: Cli.Json, +x: Map<&2, String>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(view.text(on, x))
    case j:
      Cli.json.emit(on, j, [x], ["full_name", "forge", "description", "default_branch", "visibility", "stars", "forks", "open_issues", "html_url", "mirror", "original_url"])

def view.url(+repo: Ctx.Repo) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      "repos/" ++ o ++ "/" ++ n

def view(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "repo view", args, ["--json"])
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
        Cli.check(env, "repo labels", args, ["--json"])
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
        Cli.check(env, "repo label-create", args, ["--color", "--description"])
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
        Cli.check(env, "repo branches", args, ["--json"])
        r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(10n, repo, tok, Api.path(repo, branch.query(forge.of(repo))))
        branch.show(env, r)

# branch-delete
# -------------

# a branch's path on its forge: gitea addresses the branch itself, github a ref under
# git/refs/heads. Both read a name's slashes raw, so the path keeps them.
def branch.url(f: Ctx.Forge, +name: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "branches/" ++ Url.encode.path(name)
    case Ctx.GitHub{}:
      "git/refs/heads/" ++ Url.encode.path(name)

# cha never prompts, so a delete without --yes only names what it would delete
def delete.ask(+name: String, ok: Bool) -> String:
  match ok:
    case True{}:
      ""
    case False{}:
      "repo branch-delete: would delete branch " ++ name ++ "; pass --yes to do it"

# the message a delete of the default branch leaves, "" when it is another branch
def delete.default(+name: String, same: Bool) -> String:
  match same:
    case True{}:
      "repo branch-delete: " ++ name ++ " is the default branch"
    case False{}:
      ""

# the repo's default branch, read before a delete so it can be refused
def default.branch(+env: Cli.Env, +repo: Ctx.Repo, +tok: String) -> IO(String):
  do IO<String>:
    r : Api.Reply <- Api.get(repo, tok, view.url(repo))
    b : Bytes.Bytes <- body.reply(env, r)
    IO.pure(String, Api.f(Api.obj(b), "default_branch"))

# a branch name keeps its slashes in the path, so a . or .. segment in it would walk to
# another endpoint: the delete refuses it before it sends anything
def delete.segments(ok: Bool) -> String:
  match ok:
    case True{}:
      ""
    case False{}:
      "repo branch-delete: a branch name can't have . or .. segments"

def deleted(+env: Cli.Env, +msg: String) -> IO(Unit):
  match env:
    case Cli.Env{r, t, +on, j, a}:
      Ui.done(on, "deleted " ++ msg)

def delete.send(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.send(repo, tok, "DELETE", Api.path(repo, branch.url(forge.of(repo), name)), None{})
    b : Bytes.Bytes <- body.reply(env, r)
    deleted(env, "branch " ++ name)

# refuse the repo's default branch, which a delete must not remove
def delete.compare(+env: Cli.Env, +name: String, +dflt: String) -> IO(Unit):
  Cli.check.if(env, delete.default(name, String.eq(name, dflt)), Bool.not(String.eq(name, dflt)))

# the --yes guard and the path guard come first, so a delete without --yes, or of a name
# that would walk out of the path, makes no request at all
def delete.go(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +name: String, +ok: Bool) -> IO(Unit):
  do IO<Unit>:
    Cli.check.if(env, delete.ask(name, ok), ok)
    +bad : String = delete.segments(Url.encode.path.ok(name))
    Cli.check.if(env, bad, String.is_empty(bad))
    dflt : String <- default.branch(env, repo, tok)
    delete.compare(env, name, dflt)
    delete.send(env, repo, tok, name)

def branch.delete(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "repo branch-delete", args, ["--yes"])
        +raw : String = Cli.arg(args, 1n)
        name : String <- arg.of(env, "branch-delete: a branch name is required", raw, String.is_empty(raw))
        delete.go(env, repo, tok, name, Cli.has(args, "--yes"))

# file
# ----

# ?ref=<ref>, when a ref was asked for: a query value is encoded whole, so a # or a &
# in the name cannot cut the query or add a parameter
def ref.query(+ref: String, empty: Bool) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      "?ref=" ++ Url.encode(ref)

# a path keeps its slashes in the path, so its segments are encoded one by one
def file.path(f: Ctx.Forge, +path: String, +ref: String, empty: Bool) -> String:
  match f:
    case Ctx.Gitea{}:
      "raw/" ++ Url.encode.path(path) ++ ref.query(ref, empty)
    case Ctx.GitHub{}:
      "contents/" ++ Url.encode.path(path) ++ ref.query(ref, empty)

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
        Cli.check(env, "repo file", args, ["--ref"])
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

# a ref keeps its slashes in the path (refs/heads/main), so its segments are encoded one
# by one
def tree.query(f: Ctx.Forge, +ref: String) -> String:
  match f:
    case Ctx.Gitea{}:
      "git/trees/" ++ Url.encode.path(ref) ++ "?recursive=true&per_page=1000"
    case Ctx.GitHub{}:
      "git/trees/" ++ Url.encode.path(ref) ++ "?recursive=1"

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
        Cli.check(env, "repo tree", args, ["--ref", "--json"])
        +ref : String = tree.ref(Cli.flag(args, "--ref", ""))
        r : Api.Reply <- Api.get(repo, tok, Api.path(repo, tree.query(forge.of(repo), ref)))
        b : Bytes.Bytes <- body.reply(env, r)
        tree.out(env, b)

# create and delete
# -----------------

# an owner, repo or org name as a forge allows it, so it can't reach a URL path as
# anything else: a name with a space, a ? or a % is refused before any request is built
def name.char(+c: Char) -> Bool:
  Bool.or(Bool.or(Char.is_alpha(c), Char.is_digit(c)), Bool.or(Char.is_eq(c, '-'), Bool.or(Char.is_eq(c, '_'), Char.is_eq(c, '.'))))

def name.ok(cs: List<&2, Char>) -> Bool:
  match cs:
    case Nil{}:
      True{}
    case Con{+c, t}:
      Bool.and(name.char(c), name.ok(t))

# where a repo is made: the token's own account, or an org
# both forges spell it the same way
# create.url("", True{}) is POST /user/repos, otherwise POST /orgs/{org}/repos
def create.url(+org: String, empty: Bool) -> String:
  match empty:
    case True{}:
      "user/repos"
    case False{}:
      "orgs/" ++ org ++ "/repos"

def create.body(+name: String, +desc: String, private: Bool) -> Json.Val:
  Json.Obj{[(Json.utf8("name"), Api.utf8(name)), (Json.utf8("description"), Api.utf8(desc)), (Json.utf8("private"), Json.Flag{private})]}

# an org is a URL path segment too, so it gets the same letters, digits, . _ - check
# as a delete's owner and name
def org.bad(+org: String, empty: Bool) -> Bool:
  match empty:
    case True{}:
      False{}
    case False{}:
      Bool.not(name.ok(String.to_list(org)))

def create.org.check(+env: Cli.Env, +org: String, bad: Bool) -> IO(Unit):
  match bad:
    case True{}:
      Cli.fail(Unit, env, "repo create: --org takes a name of letters, digits, . _ -")
    case False{}:
      IO.pure(Unit, Unit{})

def create.send(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +name: String, +args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +org : String = Cli.flag(args, "--org", "")
    r : Api.Reply <- Api.send(repo, tok, "POST", create.url(org, String.is_empty(org)), Some{create.body(name, Cli.flag(args, "--description", ""), Cli.has(args, "--private"))})
    b : Bytes.Bytes <- body.reply(env, r)
    +x : Map<&2, String> = Api.obj(b)
    created(env, "repo " ++ Api.f(x, "full_name"), Api.f(x, "html_url"))

def repo.create(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "repo create", args, ["--org", "--private", "--description"])
        +raw : String = Cli.arg(args, 1n)
        name : String <- arg.of(env, "repo create: a name is required", raw, String.is_empty(raw))
        +org : String = Cli.flag(args, "--org", "")
        create.org.check(env, org, org.bad(org, String.is_empty(org)))
        create.send(env, repo, tok, name, args)

# delete
# ------

def target.make(f: Ctx.Forge, +host: String, +o: String, +n: String, blank: Bool) -> Maybe<&2, Ctx.Repo>:
  match blank:
    case True{}:
      None{}
    case False{}:
      Some{Ctx.Repo{f, host, o, n}}

# an owner or a name is one path segment: the forge's letters, digits, . _ - , and not a
# . or .. that would walk out of the path. An empty half names no repo.
def target.seg(f: Ctx.Forge, +host: String, segs: List<&2, String>) -> Maybe<&2, Ctx.Repo>:
  match segs:
    case Con{+o, Con{+n, Nil{}}}:
      blank = Bool.not(Bool.and(Bool.and(name.ok(String.to_list(o)), name.ok(String.to_list(n))), Bool.and(Url.seg.ok(o), Url.seg.ok(n))))
      target.make(f, host, o, n, blank)
    case x:
      None{}

# the repo a delete names, as OWNER/NAME on the checkout's (or -R's) host
# never the checkout's own repo: the name has to be written out
def target(f: Ctx.Forge, +host: String, +s: String) -> Maybe<&2, Ctx.Repo>:
  target.seg(f, host, String.split(s, '/'))

def target.of(+repo: Ctx.Repo, +s: String) -> Maybe<&2, Ctx.Repo>:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      target(f, h, s)

def name.of(r: Ctx.Repo) -> String:
  match r:
    case Ctx.Repo{f, h, +o, +n}:
      o ++ "/" ++ n

# cha never prompts, so every destructive command needs --yes and says what it would do
# without it, before it builds a request
def delete.confirmed(+name: String, yes: Bool) -> String:
  match yes:
    case True{}:
      ""
    case False{}:
      "repo delete: this deletes " ++ name ++ "; rerun with --yes to confirm"

def delete.scope(f: Ctx.Forge) -> String:
  match f:
    case Ctx.GitHub{}:
      "github: delete_repo"
    case Ctx.Gitea{}:
      "gitea: write:repository"

def delete.why(f: Ctx.Forge, +status: U32) -> String:
  "repo delete: the token lacks the delete scope (" ++ delete.scope(f) ++ ", HTTP " ++ U32.show(status) ++ ")"

def delete.bad(+env: Cli.Env, f: Ctx.Forge, +status: U32, body: Bytes.Bytes, denied: Bool) -> IO(Unit):
  match denied:
    case True{}:
      Cli.fail(Unit, env, delete.why(f, status))
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def delete.if(+env: Cli.Env, f: Ctx.Forge, +name: String, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Unit):
  match env good:
    case Cli.Env{r, t, +on, j, a} True{}:
      Ui.done(on, "deleted " ++ name)
    case e False{}:
      delete.bad(env, f, status, body, U32.is_eq(status, 403))

def delete.check(+env: Cli.Env, f: Ctx.Forge, +name: String, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      delete.if(env, f, name, status, body, Api.ok(status))

def delete.named.if(+env: Cli.Env, +m: Maybe<&2, Ctx.Repo>) -> IO(Ctx.Repo):
  match m:
    case Some{+r}:
      IO.pure(Ctx.Repo, r)
    case None{}:
      Cli.fail(Ctx.Repo, env, "repo delete: name the repo to delete, as OWNER/NAME")

def delete.named(+env: Cli.Env, +repo: Ctx.Repo, +raw: String) -> IO(Ctx.Repo):
  delete.named.if(env, target.of(repo, raw))

def delete.ready(+env: Cli.Env, +r: Ctx.Repo, yes: Bool) -> IO(Unit):
  match yes:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Cli.fail(Unit, env, delete.confirmed(name.of(r), False{}))

def repo.delete(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "repo delete", args, ["--yes"])
        +r : Ctx.Repo <- delete.named(env, repo, Cli.arg(args, 1n))
        delete.ready(env, r, Cli.has(args, "--yes"))
        rep : Api.Reply <- Api.send(r, tok, "DELETE", Api.path(r, ""), None{})
        delete.check(env, forge.of(r), name.of(r), rep)

# protection
# ----------

# the fields a protection view prints, in this order
def prot.fields() -> List<&2, String>:
  ["branch", "approvals", "checks", "push_restricted", "force_push_blocked"]

# a required-approval count, "0" when the forge sent none
def approvals.of(+x: Map<&2, String>, +k: String) -> String:
  Ctx.or(Api.f(x, k), "0")

# "  approvals 2" when any are required, nothing at zero
def approvals.text(+n: String, none: Bool) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      "  approvals " ++ n

# github keeps a status check's contexts as strings, or as objects with a context field
# when they were configured through the checks API
def gh.checks(+x: Map<&2, String>) -> String:
  Ctx.or(Api.join(x, "required_status_checks.contexts", "", ", "), Api.join(x, "required_status_checks.checks", "context", ", "))

# one github protection is one rule for one branch. Restrictions present mean only the
# listed users, teams and apps may push; force pushes are blocked unless they are allowed.
def gh.row(+x: Map<&2, String>, +branch: String) -> Map<&2, String>:
  m = Map.set(&2, String, Map.new(&2, String), "branch", branch)
  m = Map.set(&2, String, m, "approvals", approvals.of(x, "required_pull_request_reviews.required_approving_review_count"))
  m = Map.set(&2, String, m, "checks", gh.checks(x))
  m = Map.set(&2, String, m, "push_restricted", Api.json.bool(Bool.not(String.is_empty(Api.raw.f(x, "restrictions.url")))))
  Map.set(&2, String, m, "force_push_blocked", Api.json.bool(Bool.not(String.eq(Api.raw.f(x, "allow_force_pushes.enabled"), "true"))))

# gitea 1.22 and later name a rule with rule_name and keep branch_name as an alias; forgejo
# and older gitea have only branch_name
def gitea.name(+x: Map<&2, String>) -> String:
  Ctx.or(Api.f(x, "rule_name"), Api.f(x, "branch_name"))

# pushes are restricted unless the rule lets everyone with write access push
def gitea.push(+x: Map<&2, String>) -> Bool:
  Bool.not(String.eq(Api.raw.f(x, "enable_push"), "true"))

# force pushes are blocked unless the rule turns them on; a gitea older than 1.21 has no
# such field and always blocked them
def gitea.force(+x: Map<&2, String>) -> Bool:
  Bool.not(String.eq(Api.raw.f(x, "enable_force_push"), "true"))

def gitea.contexts(+x: Map<&2, String>, on: Bool) -> String:
  match on:
    case True{}:
      Api.join(x, "status_check_contexts", "", ", ")
    case False{}:
      ""

# contexts a rule keeps while its status check requirement is off aren't required
def gitea.checks(+x: Map<&2, String>) -> String:
  gitea.contexts(x, String.eq(Api.raw.f(x, "enable_status_check"), "true"))

def gitea.row(+x: Map<&2, String>) -> Map<&2, String>:
  m = Map.set(&2, String, Map.new(&2, String), "branch", gitea.name(x))
  m = Map.set(&2, String, m, "approvals", approvals.of(x, "required_approvals"))
  m = Map.set(&2, String, m, "checks", gitea.checks(x))
  m = Map.set(&2, String, m, "push_restricted", Api.json.bool(gitea.push(x)))
  Map.set(&2, String, m, "force_push_blocked", Api.json.bool(gitea.force(x)))

def gitea.all(xs: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      gitea.row(x) <> gitea.all(rest)

def gitea.kept(+x: Map<&2, String>, later: List<&2, Map<&2, String>>, same: Bool) -> List<&2, Map<&2, String>>:
  match same:
    case True{}:
      gitea.row(x) <> later
    case False{}:
      later

def gitea.keep(+x: Map<&2, String>, +w: String, later: List<&2, Map<&2, String>>) -> List<&2, Map<&2, String>>:
  gitea.kept(x, later, String.eq(gitea.name(x), w))

# gitea's rules are one list, so a name picks the rule of that name rather than asking the
# forge to match a branch against the rule's pattern
def gitea.some(xs: List<&2, Map<&2, String>>, +w: String) -> List<&2, Map<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      gitea.keep(x, w, gitea.some(rest, w))

def gitea.rows(xs: List<&2, Map<&2, String>>, +w: String, empty: Bool) -> List<&2, Map<&2, String>>:
  match empty:
    case True{}:
      gitea.all(xs)
    case False{}:
      gitea.some(xs, w)

# what each forge says when nothing is protected
def prot.none(+b: String) -> String:
  "no branch protection on " ++ b

def prot.rule.none(+w: String, empty: Bool) -> String:
  match empty:
    case True{}:
      "no branch protection rules"
    case False{}:
      "no branch protection rule named " ++ w

def prot.line(+on: Bool, +x: Map<&2, String>) -> String:
  +n = Api.f(x, "approvals")
  Ui.bold(on, Ui.fg(on, Ui.aqua(), Api.f(x, "branch"))) ++
  approvals.text(n, String.eq(n, "0")) ++
  prefixed(Api.f(x, "checks"), "  checks ") ++
  prefixed(flag.text(on, "pushes restricted", bool.f(x, "push_restricted")), "  ") ++
  prefixed(flag.text(on, "force-push blocked", bool.f(x, "force_push_blocked")), "  ")

def prot.lines(+on: Bool, xs: List<&2, Map<&2, String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      prot.line(on, x) ++ "\n" ++ prot.lines(on, rest)

def prot.write(+on: Bool, +s: String, +msg: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      Ui.info(on, msg)
    case False{}:
      IO.write(s)

def prot.text(+on: Bool, +xs: List<&2, Map<&2, String>>, +msg: String) -> IO(Unit):
  +s = prot.lines(on, xs)
  prot.write(on, s, msg, String.is_empty(s))

def prot.print(+on: Bool, json: Cli.Json, +xs: List<&2, Map<&2, String>>, +msg: String) -> IO(Unit):
  match json:
    case Cli.Off{}:
      prot.text(on, xs, msg)
    case j:
      Cli.json.emit(on, j, xs, prot.fields())

def prot.emit(+env: Cli.Env, +xs: List<&2, Map<&2, String>>, +msg: String) -> IO(Unit):
  match env:
    case Cli.Env{r, t, +on, json, a}:
      prot.print(on, json, xs, msg)

# github answers a 404 "Branch not protected" for a branch with no protection, and any
# other refusal (403, a bare 404, or 401 without a token) means the token can't read it:
# branch protection takes admin rights on the repo
def gh.bare(+status: U32, +why: String) -> Bool:
  Bool.and(U32.is_eq(status, 404), String.contains(String.to_lower(why), "not protected"))

def gh.reply(+env: Cli.Env, +branch: String, +why: String, +x: Map<&2, String>, +good: Bool, +bare: Bool) -> IO(Unit):
  match good bare:
    case True{} b:
      prot.emit(env, [gh.row(x, branch)], "")
    case False{} True{}:
      prot.emit(env, Nil{}, prot.none(branch))
    case False{} False{}:
      Cli.fail(Unit, env, "protection: the token can't read the protection of " ++ branch ++ ": " ++ why)

# the body becomes a row either way: a protection object, or the message a refusal put in
# it, which reads the same as Api.message spells it
def gh.answer(+env: Cli.Env, +branch: String, +status: U32, +x: Map<&2, String>) -> IO(Unit):
  +why = "HTTP " ++ U32.show(status) ++ Api.message.text(Api.raw.f(x, "message"))
  gh.reply(env, branch, why, x, Api.ok(status), gh.bare(status, why))

def gh.show(+env: Cli.Env, +branch: String, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{why}:
      Cli.fail(Unit, env, why)
    case Api.Reply{+status, +next, body}:
      gh.answer(env, branch, status, Api.obj(body))

# github reads one branch's protection; the name is escaped whole, slash included
def gh.url(+branch: String) -> String:
  "branches/" ++ Url.encode(branch) ++ "/protection"

# the branch a view is about: the one asked for, else the repo's default branch
def prot.name(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +w: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      default.branch(env, repo, tok)
    case False{}:
      IO.pure(String, w)

def gh.get(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +branch: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.get(repo, tok, Api.path(repo, gh.url(branch)))
    gh.show(env, branch, r)

def gh.prot(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +w: String) -> IO(Unit):
  do IO<Unit>:
    branch : String <- prot.name(env, repo, tok, w, String.is_empty(w))
    gh.get(env, repo, tok, branch)

def gitea.show(+env: Cli.Env, +w: String, r: Result<&1, &1, String, List<&2, Map<&2, String>>>) -> IO(Unit):
  match r:
    case Done{xs}:
      prot.emit(env, gitea.rows(xs, w, String.is_empty(w)), prot.rule.none(w, String.is_empty(w)))
    case Fail{why}:
      Cli.fail(Unit, env, why)

def gitea.prot(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +w: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, String, List<&2, Map<&2, String>>> <- Api.all(10n, repo, tok, Api.path(repo, "branch_protections"))
    gitea.show(env, w, r)

def prot.run(+env: Cli.Env, +f: Ctx.Forge, +repo: Ctx.Repo, +tok: String, +w: String) -> IO(Unit):
  match f:
    case Ctx.Gitea{}:
      gitea.prot(env, repo, tok, w)
    case Ctx.GitHub{}:
      gh.prot(env, repo, tok, w)

def protection(+env: Cli.Env) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, "repo protection", args, ["--json"])
        +w : String = Cli.arg(args, 1n)
        prot.run(env, forge.of(repo), repo, tok, w)

# dispatch
# --------

def names() -> List<&2, String>:
  ["view", "labels", "label-create", "branches", "branch-delete", "protection", "file", "tree", "create", "delete"]

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
      branch.delete(env)
    case 5n:
      protection(env)
    case 6n:
      file(env)
    case 7n:
      tree(env)
    case 8n:
      repo.create(env)
    case 9n:
      repo.delete(env)
    case 10n+k:
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
