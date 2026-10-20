# cha secrets and cha variables: a repo's or an org's Actions secrets and variables.
#
# A secret's value leaves cha once, in the request body, and never comes back: neither
# forge returns one. A failed reply's body can echo it, so the message for a failed
# `secrets set` is built from the status alone (LAWS.bend, Failed secrets set).
import Base
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

# github seals a secret's value with the repo's public key before it takes one
def forge.gh(f: Ctx.Forge) -> Bool:
  match f:
    case Ctx.GitHub{}:
      True{}
    case Ctx.Gitea{}:
      False{}

# Endpoints
# ---------

# the path a list lives at: an org's when --org named one, else the repo's. --org is
# encoded, so "a/../b" can't climb to another endpoint.
def root(+org: String, +owner: String, +name: String, +kind: String) -> String:
  Ctx.or.if("orgs/" ++ Url.encode(org) ++ "/actions/" ++ kind, "repos/" ++ owner ++ "/" ++ name ++ "/actions/" ++ kind, String.is_empty(org))

def url.of(+repo: Ctx.Repo, +org: String, +kind: String) -> String:
  match repo:
    case Ctx.Repo{f, h, o, n}:
      root(org, o, n, kind)

# one secret or variable under its list: a name is checked before it gets here
def item.url(+list: String, +name: String) -> String:
  list ++ "/" ++ name

# one page's query, as runners asks for one: Gitea counts the rest in total_count and
# ignores limit unless page is sent, GitHub pages with per_page and links the next page
def query(+forge: Ctx.Forge, +page: U32) -> String:
  match forge:
    case Ctx.Gitea{}:
      "?page=" ++ U32.show(page) ++ "&limit=50"
    case Ctx.GitHub{}:
      "?per_page=100&page=" ++ U32.show(page)

def list.url(+repo: Ctx.Repo, +org: String, +kind: String, +page: U32) -> String:
  match repo:
    case Ctx.Repo{+f, h, o, n}:
      url.of(repo, org, kind) ++ query(f, page)

# Names
# -----
# A name goes into a path and, on the forge, into a workflow: letters, digits and
# underscore, no leading digit, and never the GITHUB_ prefix the forges reserve.

def name.head(+c: Char) -> Bool:
  Bool.or(Char.is_alpha(c), Char.is_eq(c, '_'))

def name.rest(+c: Char) -> Bool:
  Bool.or(name.head(c), Char.is_digit(c))

def name.rest.ok(cs: List<&2, Char>) -> Bool:
  match cs:
    case Nil{}:
      True{}
    case Con{+c, t}:
      Bool.and(name.rest(c), name.rest.ok(t))

def name.after.head(+s: String, ok: Bool) -> Bool:
  match ok:
    case True{}:
      name.rest.ok(String.to_list(String.drop(s, 1n)))
    case False{}:
      False{}

# the shape: one letter or underscore, then letters, digits and underscores
def name.shape(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{h, t}:
      name.after.head(s, name.head(h))

def name.reserved(+s: String) -> Bool:
  String.starts_with(String.to_upper(s), "GITHUB_")

def name.after.shape(+s: String, ok: Bool) -> Bool:
  match ok:
    case True{}:
      Bool.not(name.reserved(s))
    case False{}:
      False{}

def name.ok(+s: String) -> Bool:
  name.after.shape(s, name.shape(s))

def name.msg(+cmd: String) -> String:
  cmd ++ ": a name is letters, digits and underscore, and can't start with a digit or GITHUB_"

def name.if.ok(+env: Cli.Env, +cmd: String, name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Cli.fail(Unit, env, name.msg(cmd))

def name.check(+env: Cli.Env, +cmd: String, +name: String) -> IO(Unit):
  name.if.ok(env, cmd, name, name.ok(name))

# the name argument, the command failing when it is missing or unusable
def name.require(+env: Cli.Env, +cmd: String, +name: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      Cli.fail(String, env, cmd ++ ": a name is required")
    case False{}:
      do IO<String>:
        name.check(env, cmd, name)
        return name

# Rows
# ----

# field k of an object flattened under prefix; "" when missing. Raw: this reads only to
# build a row, which holds what the forge sent, so the text printer reads the row back
# through Api.f (clean) and --json through Api.raw.f (exact).
def g(+src: Map<&2, String>, +prefix: String, +k: String) -> String:
  Api.raw.f(src, Api.key(prefix, k))

def prefix.of(+root: String, i: U32) -> String:
  root ++ "." ++ U32.show(i)

# gitea spells a variable's value data, github spells it value
def pick.of(f: Ctx.Forge, +src: Map<&2, String>, +prefix: String, +gitea: String, +github: String) -> String:
  match f:
    case Ctx.Gitea{}:
      g(src, prefix, gitea)
    case Ctx.GitHub{}:
      g(src, prefix, github)

# when it last changed: GitHub sends updated_at, Gitea and Forgejo only created_at
def updated.of(+src: Map<&2, String>, +prefix: String) -> String:
  Ctx.or(g(src, prefix, "updated_at"), g(src, prefix, "created_at"))

# one secret as the flat row every output reads. A secret has no value: neither forge
# sends one back, and cha never asks.
def secrets.row(+src: Map<&2, String>, +prefix: String) -> Map<&2, String>:
  m = Map.set(&2, String, Map.new(&2, String), "name", g(src, prefix, "name"))
  Map.set(&2, String, m, "updated", updated.of(src, prefix))

# one variable: its value is not a secret, and both forges send it back
def var.row(f: Ctx.Forge, +src: Map<&2, String>, +prefix: String) -> Map<&2, String>:
  m = Map.set(&2, String, Map.new(&2, String), "name", g(src, prefix, "name"))
  Map.set(&2, String, m, "value", pick.of(f, src, prefix, "data", "value"))

# An item of a page: the flattened map it sits in, and the prefix its fields start at.
# Gitea answers an array, one map per item, so the prefix is ""; GitHub answers a wrapper
# with the list inside it, so the prefix is where the item sits in the flat map.
type Slot is Data:
  Slot{src: Map<&2, String>, prefix: String}

# one page's items, and the total the forge claims ("" when it names none)
type Sheet is Data:
  Sheet{slots: List<&2, Slot>, total: String}

def items.gh(n: Nat, +i: U32, +kind: String, +src: Map<&2, String>) -> List<&2, Slot>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{Slot{src, prefix.of(kind, i)}, items.gh(p, (i + 1 : U32), kind, src)}

def items.array(xs: List<&2, Map<&2, String>>) -> List<&2, Slot>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      Con{Slot{x, ""}, items.array(rest)}

# github's wrapper names the total in total_count; gitea's array names no total at all
def items.gh.page(+kind: String, body: Bytes.Bytes) -> Sheet:
  +src = Api.obj(body)
  Sheet{items.gh(Api.count(src, kind), 0, kind, src), Api.f(src, "total_count")}

def items.of(f: Ctx.Forge, +kind: String, body: Bytes.Bytes) -> Sheet:
  match f:
    case Ctx.Gitea{}:
      Sheet{items.array(Api.rows(body)), ""}
    case Ctx.GitHub{}:
      items.gh.page(kind, body)

def secrets.rows(ps: List<&2, Slot>) -> List<&2, Map<&2, String>>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{Slot{+src, +prefix}, rest}:
      secrets.row(src, prefix) <> secrets.rows(rest)

def var.rows(ps: List<&2, Slot>, +f: Ctx.Forge) -> List<&2, Map<&2, String>>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{Slot{+src, +prefix}, rest}:
      var.row(f, src, prefix) <> var.rows(rest, f)

def rows.if(+f: Ctx.Forge, ps: List<&2, Slot>, secret: Bool) -> List<&2, Map<&2, String>>:
  match secret:
    case True{}:
      secrets.rows(ps)
    case False{}:
      var.rows(ps, f)

def rows.of(+f: Ctx.Forge, +kind: String, ps: List<&2, Slot>) -> List<&2, Map<&2, String>>:
  rows.if(f, ps, String.eq(kind, "secrets"))

# Text
# ----

# s with pre in front of it, unless s is empty
def prefixed(+s: String, +pre: String) -> String:
  Ctx.or.if(pre ++ s, "", String.is_empty(s))

def secrets.line(+on: Bool, +x: Map<&2, String>) -> String:
  Ui.bold(on, Api.f(x, "name")) ++ prefixed(Ui.dim(on, Api.f(x, "updated")), "  ")

def var.line(+on: Bool, +x: Map<&2, String>) -> String:
  Ui.bold(on, Api.f(x, "name")) ++ prefixed(Api.f(x, "value"), "  ")

def line.if(+on: Bool, +x: Map<&2, String>, secret: Bool) -> String:
  match secret:
    case True{}:
      secrets.line(on, x)
    case False{}:
      var.line(on, x)

def lines.go(xs: List<&2, Map<&2, String>>, +on: Bool, +secret: Bool) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      line.if(on, x, secret) ++ "\n" ++ lines.go(rest, on, secret)

def lines.of(xs: List<&2, Map<&2, String>>, +on: Bool, +kind: String) -> String:
  lines.go(xs, on, String.eq(kind, "secrets"))

def fields.if(secret: Bool) -> List<&2, String>:
  match secret:
    case True{}:
      ["name", "updated"]
    case False{}:
      ["name", "value"]

def fields(+kind: String) -> List<&2, String>:
  fields.if(String.eq(kind, "secrets"))

def emit(+on: Bool, json: Cli.Json, +kind: String, xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match json:
    case Cli.Off{}:
      IO.write(lines.of(xs, on, kind))
    case j:
      Cli.json.emit(on, j, xs, fields(kind))

# Replies
# -------

# a reply's body, or the command fails with the forge's error
def body.ok(+env: Cli.Env, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Bytes.Bytes):
  match good:
    case True{}:
      IO.pure(Bytes.Bytes, body)
    case False{}:
      Cli.fail(Bytes.Bytes, env, Api.message(status, body))

# Pagination
# ----------

# Gitea 1.25 answers with no Link header, so until the rows seen reach total_count, ask
# for the next page ourselves. GitHub links the next page itself.
def page.next(+next: String, +fallback: String, +seen: Nat, +total: String, empty: Bool) -> String:
  Ctx.or(next, Ctx.or.if(fallback, "", empty || Bool.not(Nat.is_gt(Api.count.of(U32.read(total)), seen))))

type Pages is Type:
  FetchPage{url: String, acc: List<&2, Slot>}
  ReadPage{reply: Api.Reply, acc: List<&2, Slot>}
  NextPage{done: Bool, url: String, seen: Nat, acc: List<&2, Slot>}

def page.items(+repo: Ctx.Repo, +org: String, +kind: String, +page: U32, +next: String, +seen: Nat, sh: Sheet, acc: List<&2, Slot>) -> Pages:
  match sh:
    case Sheet{+ps, +total}:
      +got : Nat = List.length(&2, Slot, ps)
      +count : Nat = Nat.add(seen, got)
      +url : String = page.next(next, list.url(repo, org, kind, (page + 1 : U32)), count, total, Nat.is_eq(got, 0n))
      NextPage{String.is_empty(url), url, count, List.append(&2, Slot, acc, ps)}

def page.of(+f: Ctx.Forge, +repo: Ctx.Repo, +org: String, +kind: String, +page: U32, +next: String, +seen: Nat, body: Bytes.Bytes, acc: List<&2, Slot>) -> Pages:
  page.items(repo, org, kind, page, next, seen, items.of(f, kind, body), acc)

def walk(fuel: Nat, +env: Cli.Env, +repo: Ctx.Repo, +tok: String, +org: String, +kind: String, +page: U32, +seen: Nat, st: Pages) -> IO(List<&2, Slot>):
  match fuel st:
    case 0n s:
      Cli.fail(List<&2, Slot>, env, kind ++ ": too many pages")
    case 1n+p FetchPage{url, acc}:
      do IO<List<&2, Slot>>:
        r : Api.Reply <- Api.get(repo, tok, url)
        walk(p, env, repo, tok, org, kind, page, seen, ReadPage{r, acc})
    case 1n+p ReadPage{Api.Broke{w}, acc}:
      Cli.fail(List<&2, Slot>, env, w)
    case 1n+p ReadPage{Api.Reply{+status, +next, body}, acc}:
      do IO<List<&2, Slot>>:
        b : Bytes.Bytes <- body.ok(env, status, body, Api.ok(status))
        walk(p, env, repo, tok, org, kind, page, seen, page.of(forge.of(repo), repo, org, kind, page, next, seen, b, acc))
    case 1n+p NextPage{True{}, url, n, acc}:
      IO.pure(List<&2, Slot>, acc)
    case 1n+p NextPage{False{}, url, n, acc}:
      walk(p, env, repo, tok, org, kind, (page + 1 : U32), n, FetchPage{url, acc})

# Values
# ------
# A value comes from --value, or from --value-file: a path, "-" for stdin, so a secret
# never has to pass through a shell's history. cha never prompts. --value stays in argv,
# where ps and the shell's history see it, so --value-file is the one to reach for.

# a value was given: a --value-file path, or a string after --value. Read by value, not by
# Cli.has, so --value=x and --value-file=F count. An explicit --value "" is not a value: an
# empty secret is useless, and an unset shell variable must not set one.
def value.given(+inline: String, +path: String) -> Bool:
  Bool.or(Bool.not(String.is_empty(path)), Bool.not(String.is_empty(inline)))

def value.msg(+cmd: String) -> String:
  cmd ++ ": a value is required, from --value or --value-file"

def value.need(+env: Cli.Env, +msg: String, given: Bool) -> IO(Unit):
  match given:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Cli.fail(Unit, env, msg)

# a value file over the cap is refused rather than sent cut short, so one byte past the
# cap is read: a file of exactly the cap still reads whole
def value.cap() -> U32:
  1048576

def read.max() -> U32:
  (value.cap() + 1 : U32)

def stdin.path(+path: String, dash: Bool) -> String:
  match dash:
    case True{}:
      "/dev/stdin"
    case False{}:
      path

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
        got : File & Result<&1, &1, U32 & String, String> <- File.read(f, read.max())
        read.got(env, path, got)
    case Fail{e}:
      Cli.fail(String, env, "can't read " ++ path)

def read.file(+env: Cli.Env, +path: String, dash: Bool) -> IO(String):
  do IO<String>:
    +p : String = stdin.path(path, dash)
    r : Result<&1, &1, U32 & String, File> <- File.open(p, "r")
    read.open(env, p, r)

def newline(+c: Char) -> Bool:
  Bool.or(Char.is_eq(c, '\n'), Char.is_eq(c, '\r'))

# the text from a head that is not a newline, or the tail's own answer when it is
def chomp.keep(rest: String, +t: String, h: Char, cut: Bool) -> String:
  match cut:
    case True{}:
      rest
    case False{}:
      SCon{h, t}

# s from its first character that is not a newline
def chomp.lead(s: String) -> String:
  match s:
    case SNil{}:
      s
    case SCon{+h, +t}:
      chomp.keep(chomp.lead(t), t, h, newline(h))

# a value as a file holds it: a trailing newline is the file's, not the value's, so a
# heredoc or an echo writes the value an agent meant
def chomp(s: String) -> String:
  String.reverse(chomp.lead(String.reverse(s)))

# whether the text a source read is over the cap: a read String carries one octet per Char,
# so this counts the bytes the source sent
def read.over(+s: String) -> Bool:
  U32.is_gt(Bytes.count(s, 0), value.cap())

# the text a value file held, a trailing newline dropped, or the command failing when the
# file is over the cap
def read.checked(+env: Cli.Env, +cmd: String, +s: String, over: Bool) -> IO(String):
  match over:
    case True{}:
      Cli.fail(String, env, cmd ++ ": the value file is over 1 MiB")
    case False{}:
      IO.pure(String, chomp(s))

def value.of(+env: Cli.Env, +cmd: String, +inline: String, +path: String, from_file: Bool) -> IO(String):
  match from_file:
    case True{}:
      do IO<String>:
        +s : String <- read.file(env, path, String.eq(path, "-"))
        read.checked(env, cmd, s, read.over(s))
    case False{}:
      IO.pure(String, inline)

# the value of --value, or of --value-file when it was given
def value(+env: Cli.Env, +cmd: String, +args: List<&2, String>) -> IO(String):
  do IO<String>:
    +path : String = Cli.flag(args, "--value-file", "")
    +inline : String = Cli.flag(args, "--value", "")
    +from_file : Bool = Bool.not(String.is_empty(path))
    value.need(env, value.msg(cmd), value.given(inline, path))
    value.of(env, cmd, inline, path, from_file)

# Secrets: set
# ------------
# GitHub only takes a secret sealed with the repo's public key (libsodium's sealed box),
# which cha can't build yet, so it says so before making any request.

def set.github.msg() -> String:
  "secrets set: GitHub needs the value sealed with the repo's public key; cha can't do that yet"

def set.github(+env: Cli.Env) -> IO(Unit):
  Cli.fail(Unit, env, set.github.msg())

def set.body(+value: String) -> Json.Val:
  Json.Obj{[(Json.utf8("data"), Api.utf8(value))]}

# A failed set says why from the status alone. The forge's error body can repeat the
# value whole, in part, re-cased or escaped, and a control byte in it would only be dropped
# after a check, so no word of that body reaches output (LAWS.bend, Failed secrets set).
def set.why(+status: U32) -> String:
  match status:
    case 401:
      "the token can't write secrets here (HTTP 401)"
    case 403:
      "the token can't write secrets here (HTTP 403)"
    case 404:
      "no such repo or org (HTTP 404)"
    case 422:
      "the forge refused the name or the value (HTTP 422)"
    case _:
      "HTTP " ++ U32.show(status)

def set.done(+on: Bool, +name: String) -> IO(Unit):
  Ui.done(on, "set secret " ++ name)

def set.result(+env: Cli.Env, +on: Bool, +status: U32, +name: String, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      set.done(on, name)
    case False{}:
      Cli.fail(Unit, env, set.why(status))

def set.check(+env: Cli.Env, r: Api.Reply, +on: Bool, +name: String) -> IO(Unit):
  match r:
    case Api.Broke{why}:
      Cli.fail(Unit, env, why)
    case Api.Reply{+status, next, body}:
      set.result(env, on, status, name, Api.ok(status))

def set.send(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +on: Bool, +org: String, +name: String, +value: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.send(repo, tok, "PUT", item.url(url.of(repo, org, "secrets"), name), Some{set.body(value)})
    set.check(env, r, on, name)

def set.secret.if(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +on: Bool, +name: String, +args: List<&2, String>, gh: Bool) -> IO(Unit):
  match gh:
    case True{}:
      set.github(env)
    case False{}:
      do IO<Unit>:
        +value : String <- value(env, "secrets set", args)
        set.send(env, repo, tok, on, Cli.flag(args, "--org", ""), name, value)

# Variables: set
# --------------
# Setting a variable creates it or updates it: Gitea takes POST on the item, GitHub POST
# on the list, and a 409 from either means "it is there already", so the update follows.

def var.body(+name: String, +value: String) -> Json.Val:
  Json.Obj{[(Json.utf8("name"), Api.utf8(name)), (Json.utf8("value"), Api.utf8(value))]}

def var.value.body(+value: String) -> Json.Val:
  Json.Obj{[(Json.utf8("value"), Api.utf8(value))]}

def var.create(f: Ctx.Forge, +repo: Ctx.Repo, +tok: String, +org: String, +name: String, +value: String) -> IO(Api.Reply):
  match f:
    case Ctx.Gitea{}:
      Api.send(repo, tok, "POST", item.url(url.of(repo, org, "variables"), name), Some{var.value.body(value)})
    case Ctx.GitHub{}:
      Api.send(repo, tok, "POST", url.of(repo, org, "variables"), Some{var.body(name, value)})

def var.update(f: Ctx.Forge, +repo: Ctx.Repo, +tok: String, +org: String, +name: String, +value: String) -> IO(Api.Reply):
  match f:
    case Ctx.Gitea{}:
      Api.send(repo, tok, "PUT", item.url(url.of(repo, org, "variables"), name), Some{var.value.body(value)})
    case Ctx.GitHub{}:
      Api.send(repo, tok, "PATCH", item.url(url.of(repo, org, "variables"), name), Some{var.body(name, value)})

def var.done(+on: Bool, +name: String) -> IO(Unit):
  Ui.done(on, "set variable " ++ name)

def var.fail(+env: Cli.Env, +status: U32, body: Bytes.Bytes) -> IO(Unit):
  Cli.fail(Unit, env, Api.message(status, body))

def var.again(+env: Cli.Env, +on: Bool, +name: String, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      var.done(on, name)
    case False{}:
      var.fail(env, status, body)

def var.retried(+env: Cli.Env, r: Api.Reply, +on: Bool, +name: String) -> IO(Unit):
  match r:
    case Api.Broke{why}:
      Cli.fail(Unit, env, why)
    case Api.Reply{+status, next, body}:
      var.again(env, on, name, status, body, Api.ok(status))

def var.retry(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +org: String, +on: Bool, +name: String, +value: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- var.update(forge.of(repo), repo, tok, org, name, value)
    var.retried(env, r, on, name)

# what the forging attempt came back with: set, taken already, or an error
def var.taken.if(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +org: String, +on: Bool, +name: String, +value: String, +status: U32, body: Bytes.Bytes, taken: Bool) -> IO(Unit):
  match taken:
    case True{}:
      var.retry(env, repo, tok, org, on, name, value)
    case False{}:
      var.fail(env, status, body)

# what a first attempt came back with: set, taken already, or an error
def var.out.match(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +org: String, +on: Bool, +name: String, +value: String, +status: U32, body: Bytes.Bytes, taken: Bool, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      var.done(on, name)
    case False{}:
      var.taken.if(env, repo, tok, org, on, name, value, status, body, taken)

def var.result(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +org: String, +on: Bool, +name: String, +value: String, +status: U32, body: Bytes.Bytes) -> IO(Unit):
  var.out.match(env, repo, tok, org, on, name, value, status, body, U32.is_eq(status, 409), Api.ok(status))

def var.check(+env: Cli.Env, r: Api.Reply, +repo: Ctx.Repo, +tok: String, +org: String, +on: Bool, +name: String, +value: String) -> IO(Unit):
  match r:
    case Api.Broke{why}:
      Cli.fail(Unit, env, why)
    case Api.Reply{+status, next, body}:
      var.result(env, repo, tok, org, on, name, value, status, body)

def var.set(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +on: Bool, +name: String, +args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +value : String <- value(env, "variables set", args)
    +org : String = Cli.flag(args, "--org", "")
    r : Api.Reply <- var.create(forge.of(repo), repo, tok, org, name, value)
    var.check(env, r, repo, tok, org, on, name, value)

# set
# ---

def set.at(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +on: Bool, +name: String, +args: List<&2, String>, secret: Bool) -> IO(Unit):
  match secret:
    case True{}:
      set.secret.if(env, repo, tok, on, name, args, forge.gh(forge.of(repo)))
    case False{}:
      var.set(env, repo, tok, on, name, args)

def set(+env: Cli.Env, +kind: String) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        +cmd : String = kind ++ " set"
        Cli.check(env, cmd, args, ["--value", "--value-file", "--org"])
        +raw : String = Cli.arg(args, 1n)
        +name : String <- name.require(env, cmd, raw, String.is_empty(raw))
        set.at(env, repo, tok, on, name, args, String.eq(kind, "secrets"))

# delete
# ------
# cha never prompts, so a delete always needs --yes: without it the command names what it
# would delete and exits 1, having made no request at all.

def guard.msg(+cmd: String, +what: String, +name: String) -> String:
  cmd ++ ": would delete " ++ what ++ " " ++ name ++ "; pass --yes to go ahead"

def guard(+env: Cli.Env, +cmd: String, +what: String, +name: String, yes: Bool) -> IO(Unit):
  match yes:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Cli.fail(Unit, env, guard.msg(cmd, what, name))

def deleted(+on: Bool, +what: String, +name: String) -> IO(Unit):
  Ui.done(on, "deleted " ++ what ++ " " ++ name)

def delete.result(+env: Cli.Env, +on: Bool, +what: String, +name: String, +status: U32, body: Bytes.Bytes, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      deleted(on, what, name)
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def delete.check(+env: Cli.Env, r: Api.Reply, +on: Bool, +what: String, +name: String) -> IO(Unit):
  match r:
    case Api.Broke{why}:
      Cli.fail(Unit, env, why)
    case Api.Reply{+status, next, body}:
      delete.result(env, on, what, name, status, body, Api.ok(status))

def delete(+env: Cli.Env, +kind: String) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, +on, json, +args}:
      do IO<Unit>:
        +cmd : String = kind ++ " delete"
        Cli.check(env, cmd, args, ["--yes", "--org"])
        +raw : String = Cli.arg(args, 1n)
        +name : String <- name.require(env, cmd, raw, String.is_empty(raw))
        +what : String = Ctx.or.if("variable", "secret", String.eq(kind, "secrets"))
        guard(env, cmd, what, name, Cli.has(args, "--yes"))
        r : Api.Reply <- Api.send(repo, tok, "DELETE", item.url(url.of(repo, Cli.flag(args, "--org", ""), kind), name), None{})
        delete.check(env, r, on, what, name)

# list
# ----

def list(+env: Cli.Env, +kind: String) -> IO(Unit):
  match env:
    case Cli.Env{+repo, +tok, on, json, +args}:
      do IO<Unit>:
        Cli.check(env, kind, args, ["--org", "--json"])
        +org : String = Cli.flag(args, "--org", "")
        ps : List<&2, Slot> <- walk(301n, env, repo, tok, org, kind, 1, 0n, FetchPage{list.url(repo, org, kind, 1), Nil{}})
        emit(on, json, kind, rows.of(forge.of(repo), kind, ps))

# dispatch
# --------

def names() -> List<&2, String>:
  ["list", "set", "delete"]

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

def run.at(+env: Cli.Env, +kind: String, n: Nat) -> IO(Unit):
  match n:
    case 0n:
      list(env, kind)
    case 1n:
      set(env, kind)
    case 2n:
      delete(env, kind)
    case 3n+k:
      Cli.fail(Unit, env, kind ++ ": unknown subcommand, try cha help")

def run.sub(+env: Cli.Env, +kind: String, +sub: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      list(env, kind)
    case False{}:
      run.at(env, kind, index(names(), sub, 0n))

def at(+env: Cli.Env, +kind: String) -> IO(Unit):
  match env:
    case Cli.Env{r, t, c, j, +args}:
      +sub : String = Cli.arg(args, 0n)
      run.sub(env, kind, sub, String.is_empty(sub))

def run(+env: Cli.Env) -> IO(Unit):
  at(env, "secrets")

def vars(+env: Cli.Env) -> IO(Unit):
  at(env, "variables")
