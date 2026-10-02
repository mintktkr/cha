# cli: what every command gets (Env), argument helpers and --json output.
import Base
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0xcfc8be7b076f41f95c8e118383892d55/encoding.bend as Enc
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ./ctx.bend as Ctx
import ./api.bend as Api
import ./ui.bend as Ui

# which fields --json asked for: none, every field, or a named list
type Json is Data:
  Off{}
  All{}
  Only{fields: List<&2, String>}

# repo: the resolved repo. tok: its token ("" for anonymous). color: the colour decision.
# json: what --json asked for. args: the command's own arguments, global flags removed.
type Env is Data:
  Env{repo: Ctx.Repo, tok: String, color: Bool, json: Json, args: List<&2, String>}

# Arguments
# ---------

# an argument as a flag lookup sees it
type Arg is Data:
  Exact{}
  Inline{v: String}
  Plain{s: String}

def mark.one(+a: String, +name: String, same: Bool, eq: Bool) -> Arg:
  match same eq:
    case True{} e:
      Exact{}
    case False{} True{}:
      Inline{String.drop(a, (String.length(name) + 1n : Nat))}
    case False{} False{}:
      Plain{a}

def mark(args: List<&2, String>, +name: String) -> List<&2, Arg>:
  match args:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      mark.one(a, name, String.eq(a, name), String.starts_with(a, name ++ "=")) <> mark(rest, name)

def flag.find(ms: List<&2, Arg>, +dflt: String) -> String:
  match ms:
    case Nil{}:
      dflt
    case Con{Exact{}, Con{Plain{v}, t}}:
      v
    case Con{Inline{v}, t}:
      v
    case Con{x, t}:
      flag.find(t, dflt)

# the value after flag (--state open, or --state=open); dflt when absent
def flag(args: List<&2, String>, +name: String, +dflt: String) -> String:
  flag.find(mark(args, name), dflt)

# flag was given at all
def has(args: List<&2, String>, +name: String) -> Bool:
  match args:
    case Nil{}:
      False{}
    case Con{a, rest}:
      String.eq(a, name) || has(rest, name)

# flags that stand alone; every other --flag takes the next word as its value
def switch(+a: String) -> Bool:
  String.eq(a, "--json") || String.eq(a, "--comments") || String.eq(a, "--all") || String.eq(a, "--failed") || String.eq(a, "--yes") || String.eq(a, "--web") || String.eq(a, "--help") || String.eq(a, "-h") || String.eq(a, "--draft") || String.eq(a, "--prerelease") || String.eq(a, "--squash") || String.eq(a, "--merge") || String.eq(a, "--rebase") || String.eq(a, "--delete-branch")

type Tok is Data:
  Pos{s: String}
  Opt{takes: Bool}

def word.one(+a: String, flag: Bool) -> Tok:
  match flag:
    case True{}:
      Opt{Bool.not(switch(a)) && Bool.not(String.contains(a, "="))}
    case False{}:
      Pos{a}

def words(args: List<&2, String>) -> List<&2, Tok>:
  match args:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      word.one(a, String.starts_with(a, "-") && Nat.is_gt(String.length(a), 1n)) <> words(rest)

def positional.go(ws: List<&2, Tok>) -> List<&2, String>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{Opt{True{}}, Con{w, t}}:
      positional.go(t)
    case Con{Pos{s}, t}:
      s <> positional.go(t)
    case Con{x, t}:
      positional.go(t)

# the arguments that aren't flags or flag values
def positional(args: List<&2, String>) -> List<&2, String>:
  positional.go(words(args))

# the nth positional argument, "" when missing
def arg(args: List<&2, String>, n: Nat) -> String:
  Ctx.last.of(List.get(&2, String, positional(args), n))

# Output
# ------

def json.obj(+row: Map<&2, String>, fields: List<&2, String>) -> List<&1, Bytes.Bytes & Json.Val>:
  match fields:
    case Nil{}:
      Nil{}
    case Con{+k, rest}:
      Con{(Json.utf8(k), Api.utf8(Api.f(row, k))), json.obj(row, rest)}

# one row as a JSON object of the given flat fields, all values strings
def json.row(+row: Map<&2, String>, +fields: List<&2, String>) -> String:
  Enc.utf8.decode(Json.encode.bytes(Json.Obj{json.obj(row, fields)}))

def json.rows.go(xs: List<&2, Map<&2, String>>, +fields: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, rest}:
      json.row(x, fields) <> json.rows.go(rest, fields)

# rows as a JSON array of objects, one per line
def json.rows(xs: List<&2, Map<&2, String>>, +fields: List<&2, String>) -> String:
  "[" ++ String.join(json.rows.go(xs, fields), ",\n") ++ "]"

# --json field selection
# ----------------------

# x is one of xs
def list.has(+x: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{a, rest}:
      String.eq(a, x) || list.has(x, rest)

def split.fields.trim(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      String.trim(x) <> split.fields.trim(rest)

def split.fields.keep.if(+x: String, later: List<&2, String>, blank: Bool) -> List<&2, String>:
  match blank:
    case True{}:
      later
    case False{}:
      Con{x, later}

def split.fields.keep(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      split.fields.keep.if(x, split.fields.keep(rest), String.is_empty(x))

# "a, b," as ["a", "b"]
def split.fields(+s: String) -> List<&2, String>:
  split.fields.keep(split.fields.trim(String.split(s, ',')))

# an empty field list means every field
def json.only.if(+fs: List<&2, String>, none: Bool) -> Json:
  match none:
    case True{}:
      All{}
    case False{}:
      Only{fs}

def json.only(+fs: List<&2, String>) -> Json:
  json.only.if(fs, List.is_empty(&2, String, fs))

# the word after a bare --json is its field list, unless it is a flag or a command name
def json.takes.field.if(+w: String, +cmds: List<&2, String>, dash: Bool) -> Bool:
  match dash:
    case True{}:
      False{}
    case False{}:
      Bool.not(list.has(w, cmds))

def digit.first(+w: String) -> Bool:
  String.starts_with(w, "0") || String.starts_with(w, "1") || String.starts_with(w, "2") || String.starts_with(w, "3") || String.starts_with(w, "4") || String.starts_with(w, "5") || String.starts_with(w, "6") || String.starts_with(w, "7") || String.starts_with(w, "8") || String.starts_with(w, "9")

# field names never start with a digit, so `pr view --json 7` keeps 7 as the number
def json.takes.field(+w: String, +cmds: List<&2, String>) -> Bool:
  json.takes.field.if(w, cmds, String.starts_with(w, "-") || digit.first(w))

def json.of.word.if(+fs: List<&2, String>, take: Bool) -> Json:
  match take:
    case True{}:
      json.only(fs)
    case False{}:
      All{}

def json.of.word(+w: String, +cmds: List<&2, String>) -> Json:
  json.of.word.if(split.fields(w), json.takes.field(w, cmds))

def json.of.mark(ms: List<&2, Arg>, +cmds: List<&2, String>) -> Json:
  match ms:
    case Nil{}:
      Off{}
    case Con{Inline{v}, t}:
      json.only(split.fields(v))
    case Con{Exact{}, Con{Plain{+v}, t}}:
      json.of.word(v, cmds)
    case Con{Exact{}, t}:
      All{}
    case Con{x, t}:
      json.of.mark(t, cmds)

# which fields --json asked for in args; cmds are the command names that aren't a field list
def json.of(args: List<&2, String>, cmds: List<&2, String>) -> Json:
  json.of.mark(mark(args, "--json"), cmds)

def json.strip.keep(+v: String, later: List<&2, String>, take: Bool) -> List<&2, String>:
  match take:
    case True{}:
      later
    case False{}:
      Con{v, later}

def json.strip.mark(ms: List<&2, Arg>, +cmds: List<&2, String>) -> List<&2, String>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{Inline{v}, t}:
      json.strip.mark(t, cmds)
    case Con{Exact{}, Con{Plain{+v}, t}}:
      json.strip.keep(v, json.strip.mark(t, cmds), json.takes.field(v, cmds))
    case Con{Exact{}, t}:
      json.strip.mark(t, cmds)
    case Con{Plain{+s}, t}:
      Con{s, json.strip.mark(t, cmds)}

# args with --json and the value word it consumed removed
def json.strip(args: List<&2, String>, cmds: List<&2, String>) -> List<&2, String>:
  json.strip.mark(mark(args, "--json"), cmds)

def json.unknown.one(+f: String, later: String, known: Bool) -> String:
  match known:
    case True{}:
      later
    case False{}:
      f

def json.unknown.go(sel: List<&2, String>, +valid: List<&2, String>) -> String:
  match sel:
    case Nil{}:
      ""
    case Con{+f, rest}:
      json.unknown.one(f, json.unknown.go(rest, valid), list.has(f, valid))

# the first selected field that isn't valid, "" when they all are
def json.unknown(sel: List<&2, String>, +valid: List<&2, String>) -> String:
  json.unknown.go(sel, valid)

# the defaults when nothing was selected
def json.pick(sel: List<&2, String>, +defaults: List<&2, String>) -> List<&2, String>:
  match sel:
    case Nil{}:
      defaults
    case Con{+x, +rest}:
      Con{x, rest}

# the error for a field the command doesn't print
def json.bad(+field: String, +valid: List<&2, String>) -> String:
  "unknown JSON field " ++ field ++ "; valid fields: " ++ String.join(valid, ", ")

# --json is on at all
def json.on(j: Json) -> Bool:
  match j:
    case Off{}:
      False{}
    case x:
      True{}

def json.emit.if(+on: Bool, xs: List<&2, Map<&2, String>>, +sel: List<&2, String>, +valid: List<&2, String>, +bad: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print(json.rows(xs, json.pick(sel, valid)))
    case False{}:
      do IO<Unit>:
        Ui.error(on, json.bad(bad, valid))
        IO.die(Unit, 1, "")

# rows as JSON: every field in valid, or only the fields --json named
def json.emit(+on: Bool, j: Json, xs: List<&2, Map<&2, String>>, +valid: List<&2, String>) -> IO(Unit):
  match j:
    case Only{+fs}:
      +bad = json.unknown(fs, valid)
      json.emit.if(on, xs, fs, valid, bad, String.is_empty(bad))
    case x:
      IO.print(json.rows(xs, valid))

def json.whole.if(+on: Bool, +what: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        Ui.error(on, what ++ " --json prints nested records and takes no field list; use bare --json")
        IO.die(Unit, 1, "")

# for outputs that aren't flat rows: refuse a field list instead of ignoring it
def json.whole(+on: Bool, j: Json, +what: String) -> IO(Unit):
  match j:
    case Only{fs}:
      json.whole.if(on, what, False{})
    case x:
      json.whole.if(on, what, True{})

# print the error and exit 1
def fail(-A: Type, +env: Env, msg: String) -> IO(A):
  match env:
    case Env{r, t, +c, j, a}:
      do IO<A>:
        Ui.error(c, msg)
        IO.die(A, 1, "")
