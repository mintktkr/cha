# cli: what every command gets (Env), argument helpers and --json output.
import Base
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0xcfc8be7b076f41f95c8e118383892d55/encoding.bend as Enc
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ./ctx.bend as Ctx
import ./api.bend as Api
import ./ui.bend as Ui

# repo: the resolved repo. tok: its token ("" for anonymous). color: the colour decision.
# json: --json was given. args: the command's own arguments, global flags removed.
type Env is Data:
  Env{repo: Ctx.Repo, tok: String, color: Bool, json: Bool, args: List<&2, String>}

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
  String.eq(a, "--json") || String.eq(a, "--comments") || String.eq(a, "--all") || String.eq(a, "--failed") || String.eq(a, "--yes") || String.eq(a, "--web") || String.eq(a, "--help") || String.eq(a, "-h")

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

# print the error and exit 1
def fail(-A: Type, +env: Env, msg: String) -> IO(A):
  match env:
    case Env{r, t, +c, j, a}:
      do IO<A>:
        Ui.error(c, msg)
        IO.die(A, 1, "")
