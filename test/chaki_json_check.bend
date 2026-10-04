# offline checks for lib/chaki/json.bend. Every flattening rule the commands depend on has
# a case here, the shapes cha reads are read, and the reader's strictness is checked
# against a page of documents that must all come back None. A row is checked as the fields
# a case names plus its size, which together pin the whole map down. Documents whose bytes
# matter (raw UTF-8, raw control bytes, a JSON escape) are written as hex, so that nothing
# here depends on how bend reads an escape in a literal.
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T
import ../lib/chaki/json.bend as Json

# Helpers
# -------

# a document's bytes, written as ASCII
def b(s: String) -> List<&2, U32>:
  Bytes.of_ascii(s)

def at.of(r: Map<&2, String> & String) -> String:
  (m, v) = r
  v

# a field of a row, "" when there is no such field
def at(+m: Map<&2, String>, k: String) -> String:
  at.of(Map.get(String, "", m, k))

def fields.go(ks: List<&2, String>, +m: Map<&2, String>, acc: String) -> String:
  match ks:
    case Nil{}: acc
    case +k <> t: fields.go(t, m, acc ++ k ++ "=" ++ at(m, k) ++ "|")

# a row as the fields named, in the order named, then its size
def row.line(+m: Map<&2, String>, ks: List<&2, String>) -> String:
  fields.go(ks, m, "") ++ "@" ++ Nat.show(Map.size(&2, String, m))

# none when the document isn't valid JSON, else its row
def flat.of(ks: List<&2, String>, m: Maybe<&2, Map<&2, String>>) -> String:
  match m:
    case Some{mm}: row.line(mm, ks)
    case None{}: "none"

def flat.is(name: String, src: String, ks: List<&2, String>, want: String) -> String:
  T.eq(name, flat.of(ks, Json.flat(b(src))), want)

def flat.hex.is(name: String, hex: String, ks: List<&2, String>, want: String) -> String:
  T.eq(name, flat.of(ks, Json.flat(Bytes.of_hex(hex))), want)

def bad(name: String, src: String) -> String:
  T.eq(name, flat.of(Nil{}, Json.flat(b(src))), "none")

def bad.hex(name: String, hex: String) -> String:
  T.eq(name, flat.of(Nil{}, Json.flat(Bytes.of_hex(hex))), "none")

def row.of(ks: List<&2, String>, m: Maybe<&2, Map<&2, String>>) -> String:
  match m:
    case Some{mm}: row.line(mm, ks)
    case None{}: "none"

# row n of a page of rows, none when there is no such row
def row.show(+xs: List<&2, Map<&2, String>>, ks: List<&2, String>, n: Nat) -> String:
  row.of(ks, List.get(&2, Map<&2, String>, xs, n))

def rows.show.go(xs: List<&2, Map<&2, String>>, +ks: List<&2, String>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{x, t}: rows.show.go(t, ks, acc ++ row.line(x, ks) ++ "\n")

# a page of rows as one line per row
def rows.show(xs: List<&2, Map<&2, String>>, ks: List<&2, String>) -> String:
  rows.show.go(xs, ks, "")

def count(xs: List<&2, Map<&2, String>>) -> String:
  Nat.show(List.length(&2, Map<&2, String>, xs))

# a String's code points, space separated: a comparison that no escape in this file hides
def cps(+s: String, acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{+c}, t}: cps(t, acc ++ U32.show(c) ++ " ")

def cps.show(+s: String) -> String:
  cps(s, "")

# a field of a document, read as code points
def cps.hex(name: String, hex: String, k: String, want: String) -> String:
  T.eq(name, cps.show(at(Json.obj(Bytes.of_hex(hex)), k)), want)

def cps.at(name: String, src: String, k: String, want: String) -> String:
  T.eq(name, cps.show(at(Json.obj(b(src)), k)), want)

# Generated documents
# -------------------

def zeros(k: Nat, acc: String) -> String:
  match k:
    case 0n: acc
    case 1n+p: zeros(p, "0." ++ acc)

def nest.open(n: Nat, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p: nest.open(p, "[" ++ acc)

def nest.close(n: Nat, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p: nest.close(p, "]" ++ acc)

# [[[1]]] with n brackets
def nest.text(+n: Nat) -> String:
  nest.open(n, "1" ++ nest.close(n, ""))

# the key the scalar of nest.text(n) lands under
def nest.path(n: Nat) -> String:
  zeros(Nat.sub(n, 1n), "0")

# one issue of the generated page
# n copies of one character
def nest.of(n: Nat, +ch: String, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p: nest.of(p, ch, ch ++ acc)

# an unbroken run of n 'a' characters
def nest.row(n: Nat, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p: nest.row(p, "a" ++ acc)

# {"a":{"a":...1...}} with n objects
def nest.obj.open(n: Nat, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p: nest.obj.open(p, "{\"a\":" ++ acc)

def nest.obj(+n: Nat) -> String:
  nest.obj.open(n, "1" ++ nest.of(n, "}", ""))

def nest.dots(k: Nat, acc: String) -> String:
  match k:
    case 0n: acc
    case 1n+p: nest.dots(p, "a." ++ acc)

# the key the scalar of nest.obj(n) lands under
def nest.obj.key(n: Nat) -> String:
  nest.dots(Nat.sub(n, 1n), "a")

def gen.item(+i: Nat) -> String:
  "{\"id\":" ++ Nat.show(i) ++ ",\"name\":\"n" ++ Nat.show(i) ++ "\"}"

# A page of issues: the index list arrives newest first, so the text builds in order and
# each item but the last keeps the comma that follows it.
def gen.page.head(+i: Nat, +acc: String) -> String:
  gen.item(i) ++ acc

def gen.page.go(xs: List<&2, Nat>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +x <> t: gen.page.go(t, gen.item(x) ++ "," ++ acc)

def gen.page(xs: List<&2, Nat>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +x <> t: gen.page.go(t, gen.page.head(x, acc))

def gen.text(n: Nat) -> String:
  "[" ++ gen.page(List.reverse(&2, Nat, List.range(n)), "]")

# The writer's value and the shapes cha reads
# -------------------------------------------

# a value with every escape the writer knows, an array and a nested object
def every() -> Json.Val:
  Json.Obj{[
    Json.Field{"s", Json.Str{SCon{Chr{34}, SCon{Chr{92}, SCon{Chr{10}, SCon{Chr{9}, SCon{Chr{8}, SCon{Chr{12}, SCon{Chr{13}, SCon{Chr{1}, SCon{Chr{31}, SNil{}}}}}}}}}}}},
    Json.Field{"n", Json.Num{"-1.5e+3"}},
    Json.Field{"t", Json.Flag{True{}}},
    Json.Field{"f", Json.Flag{False{}}},
    Json.Field{"z", Json.Null{}},
    Json.Field{"a", Json.Arr{[Json.Num{"1"}, Json.Str{"two"}]}},
    Json.Field{"o", Json.Obj{[Json.Field{"k", Json.Str{"v"}}]}}
  ]}

# the text every() writes
def encoded() -> String:
  Json.encode(every())

# an issue and an actions/runs envelope: made up names, the forge's shape
def issue() -> String:
  "{\"number\":7,\"title\":\"kettle\",\"user\":{\"login\":\"memu\"},\"labels\":[{\"name\":\"bug\"},{\"name\":\"help wanted\"}],\"pull_request\":{\"url\":\"https://example.invalid/pull/7\"}}"

def runs() -> String:
  "{\"total_count\":2,\"workflow_runs\":[{\"id\":5,\"status\":\"completed\"},{\"id\":6,\"head_branch\":\"main\"}]}"

def main() -> IO(Unit):
  do IO<Unit>:
    # flattening rules
    IO.print(flat.is("RFC 8259 2.2 empty object", "{}", Nil{}, "@0"))
    IO.print(flat.is("RFC 8259 2.2 empty array", "[]", ["#"], "#=0|@1"))
    IO.print(flat.is("RFC 8259 4 member", "{\"a\":1}", ["a"], "a=1|@1"))
    IO.print(flat.is("nested member", "{\"a\":{\"b\":2}}", ["a.b"], "a.b=2|@1"))
    IO.print(flat.is("member holding an empty object", "{\"a\":{}}", Nil{}, "@0"))
    IO.print(flat.is("array element and count", "{\"labels\":[{\"name\":\"x\"}]}", ["labels.#", "labels.0.name"], "labels.#=1|labels.0.name=x|@2"))
    IO.print(flat.is("member holding an empty array", "{\"labels\":[]}", ["labels.#"], "labels.#=0|@1"))
    IO.print(flat.is("array of scalars", "[1,2]", ["#", "0", "1"], "#=2|0=1|1=2|@3"))
    IO.print(flat.is("nested arrays", "{\"a\":[[1],[2,3]]}", ["a.#", "a.0.#", "a.0.0", "a.1.#", "a.1.0", "a.1.1"], "a.#=2|a.0.#=1|a.0.0=1|a.1.#=2|a.1.0=2|a.1.1=3|@6"))
    IO.print(flat.is("root scalar", "42", [""], "=42|@1"))
    IO.print(flat.is("root string", "\"hi\"", [""], "=hi|@1"))
    IO.print(flat.is("root null is empty text", "null", [""], "=|@1"))
    IO.print(flat.is("RFC 8259 3 true", "true", [""], "=true|@1"))
    IO.print(flat.is("RFC 8259 3 false", "false", [""], "=false|@1"))
    IO.print(flat.is("number keeps its text", "{\"n\":-1.5e+3}", ["n"], "n=-1.5e+3|@1"))
    IO.print(flat.is("RFC 8259 2 whitespace", "  {  \"a\" : 1 }  ", ["a"], "a=1|@1"))
    IO.print(flat.is("whitespace between elements", "[ 1 , 2 ]", ["#", "0", "1"], "#=2|0=1|1=2|@3"))
    IO.print(flat.is("last duplicate member wins", "{\"a\":1,\"a\":2}", ["a"], "a=2|@1"))
    IO.print(flat.is("keys are not escaped", "{\"a.b\":1}", ["a.b"], "a.b=1|@1"))
    IO.print(flat.is("null member", "{\"a\":null}", ["a"], "a=|@1"))
    IO.print(flat.is("deep member", "{\"a\":{\"b\":{\"c\":[9]}}}", ["a.b.c.#", "a.b.c.0"], "a.b.c.#=1|a.b.c.0=9|@2"))

    # the shapes cha reads
    IO.print(flat.is("an issue", issue(),
      ["user.login", "labels.#", "labels.0.name", "labels.1.name", "pull_request.url", "title", "number"],
      "user.login=memu|labels.#=2|labels.0.name=bug|labels.1.name=help wanted|pull_request.url=https://example.invalid/pull/7|title=kettle|number=7|@7"))
    IO.print(T.eq("an issue, user.login", at(Json.obj(b(issue())), "user.login"), "memu"))
    IO.print(T.eq("an issue, labels.0.name", at(Json.obj(b(issue())), "labels.0.name"), "bug"))
    IO.print(T.eq("an issue, pull_request.url", at(Json.obj(b(issue())), "pull_request.url"), "https://example.invalid/pull/7"))
    IO.print(T.eq("actions/runs rows", rows.show(Json.rows.at(b(runs()), "workflow_runs"), ["id", "status", "head_branch"]),
      "id=5|status=completed|head_branch=|@2\nid=6|status=|head_branch=main|@2\n"))
    IO.print(T.eq("actions/runs total_count", at(Json.obj(b(runs())), "total_count"), "2"))
    IO.print(T.eq("rows.at a key that isn't there", rows.show(Json.rows.at(b(runs()), "jobs"), Nil{}), ""))
    IO.print(T.eq("rows of objects", rows.show(Json.rows(b("[{\"a\":1},{\"b\":2}]")), ["a", "b"]), "a=1|b=|@1\na=|b=2|@1\n"))
    IO.print(T.eq("rows of scalars", rows.show(Json.rows(b("[1,null,\"x\"]")), [""]), "=1|@1\n=|@1\n=x|@1\n"))
    IO.print(T.eq("rows of a document that isn't an array", rows.show(Json.rows(b("{\"a\":1}")), ["a"]), ""))
    IO.print(T.eq("rows of garbage", rows.show(Json.rows(b("[1,")), Nil{}), ""))
    IO.print(T.eq("obj of garbage is an empty map", Nat.show(Map.size(&2, String, Json.obj(b("[1,")))), "0"))
    IO.print(T.eq("obj of a valid document", at(Json.obj(b("{\"a\":1}")), "a"), "1"))

    # strings, escapes and UTF-8. The hex is the document; the want is its code points.
    IO.print(cps.hex("RFC 8259 7 \\u0041", "22 5c 75 30 30 34 31 22", "", "65 "))
    IO.print(cps.hex("RFC 8259 7 short escapes", "22 5c 22 5c 5c 5c 2f 5c 62 5c 66 5c 6e 5c 72 5c 74 22", "", "34 92 47 8 12 10 13 9 "))
    IO.print(cps.hex("RFC 8259 7 \\u0000", "22 5c 75 30 30 30 30 22", "", "0 "))
    IO.print(cps.hex("surrogate pair is one character", "22 5c 75 64 38 33 64 5c 75 64 65 30 30 22", "", "128512 "))
    IO.print(cps.hex("lone high surrogate is U+FFFD", "22 5c 75 64 38 33 64 22", "", "65533 "))
    IO.print(cps.hex("lone low surrogate is U+FFFD", "22 5c 75 64 63 30 30 22", "", "65533 "))
    IO.print(cps.hex("surrogate then a character", "22 5c 75 64 38 33 64 78 22", "", "65533 120 "))
    IO.print(cps.hex("surrogate then a short escape", "22 5c 75 64 38 33 64 5c 6e 22", "", "65533 10 "))
    IO.print(cps.hex("surrogate pair then text", "22 5c 75 64 38 33 64 5c 75 64 65 30 30 21 22", "", "128512 33 "))
    IO.print(cps.hex("surrogate then a backslash", "22 5c 75 64 38 33 64 5c 5c 22", "", "65533 92 "))
    IO.print(cps.hex("two high surrogates are two U+FFFD", "22 5c 75 64 38 33 64 5c 75 64 38 33 64 22", "", "65533 65533 "))
    IO.print(cps.hex("a high surrogate then a plain escape", "22 5c 75 64 38 33 64 5c 75 30 30 34 31 22", "", "65533 65 "))
    IO.print(cps.hex("space inside a string", "22 61 20 62 22", "", "97 32 98 "))
    IO.print(cps.hex("raw UTF-8 is decoded", "22 c3 a9 22", "", "233 "))
    IO.print(cps.hex("raw 4 byte UTF-8 is decoded", "22 f0 9f 98 80 22", "", "128512 "))
    IO.print(cps.hex("invalid raw UTF-8 is U+FFFD", "22 ff 22", "", "65533 "))
    IO.print(cps.hex("overlong raw UTF-8 is U+FFFD twice", "22 c0 af 22", "", "65533 65533 "))
    IO.print(cps.hex("truncated UTF-8 at the end of a string", "22 e2 82 22", "", "65533 "))

    # a page of documents that must all be invalid
    IO.print(bad("empty input", ""))
    IO.print(bad("whitespace only", " "))
    IO.print(bad("just an open brace", "{"))
    IO.print(bad("just a close brace", "}"))
    IO.print(bad("just an open bracket", "["))
    IO.print(bad("just a close bracket", "]"))
    IO.print(bad("trailing comma in an array", "[1,]"))
    IO.print(bad("trailing comma in an object", "{\"a\":1,}"))
    IO.print(bad("comma first in an object", "{,}"))
    IO.print(bad("comma first in an array", "[,1]"))
    IO.print(bad("double comma", "{\"a\":1,,\"b\":2}"))
    IO.print(bad("single quotes", "{'a':1}"))
    IO.print(bad("leading zero", "01"))
    IO.print(bad("leading zero in an array", "[01]"))
    IO.print(bad("minus with no digits", "-"))
    IO.print(bad("plus sign", "+1"))
    IO.print(bad("bare fraction", ".5"))
    IO.print(bad("dot with no fraction", "1."))
    IO.print(bad("exponent with no digits", "1e"))
    IO.print(bad("exponent sign with no digits", "1e+"))
    IO.print(bad("two dots", "1..2"))
    IO.print(bad("NaN", "NaN"))
    IO.print(bad("nan", "nan"))
    IO.print(bad("underscore in a number", "1_000"))
    IO.print(bad("hex number", "0x10"))
    IO.print(bad("double minus", "--1"))
    IO.print(bad("half a literal", "tru"))
    IO.print(bad("half a literal, false", "fals"))
    IO.print(bad("half a literal, null", "nul"))
    IO.print(bad("text after a literal", "truex"))
    IO.print(bad("unterminated string", "\"unterminated"))
    IO.print(bad("unterminated string with a surrogate", "\"\\ud83d"))
    IO.print(bad("bad escape", "\"\\q\""))
    IO.print(bad("short \\u escape", "\"\\u12\""))
    IO.print(bad("\\u with no hex digits", "\"\\uZZZZ\""))
    IO.print(bad("member with no colon", "{\"a\" 1}"))
    IO.print(bad("member with no value", "{\"a\":}"))
    IO.print(bad("member with no name", "{:1}"))
    IO.print(bad("two values in a row", "1 2"))
    IO.print(bad("two elements with no comma", "[1 2]"))
    IO.print(bad("two members with no comma", "{\"a\":1 \"b\":2}"))
    IO.print(bad("garbage after the value", "{\"a\": 1} x"))
    IO.print(bad("two documents", "[1] [2]"))
    IO.print(bad("an extra close bracket", "[1]]"))
    IO.print(bad("an extra close brace", "{\"a\":1}}"))
    IO.print(bad("bracket closed by a brace", "[}"))
    IO.print(bad("brace closed by a bracket", "{]"))
    IO.print(bad("an object where a key goes", "{{}}"))
    IO.print(bad("an array where a member name goes", "{[1]:2}"))
    IO.print(bad.hex("raw tab in a string", "22 09 22"))
    IO.print(bad.hex("raw newline in a string", "22 0a 22"))
    IO.print(bad.hex("raw control byte in a string", "22 01 22"))
    IO.print(bad.hex("raw NUL in a string", "22 00 22"))

    # the edges: one byte, huge numbers, an unbroken string, depth on both sides
    IO.print(flat.is("one byte, a number", "1", [""], "=1|@1"))
    IO.print(flat.is("U32 and beyond as written", "{\"a\":4294967295,\"b\":12345678901234567890}", ["a", "b"], "a=4294967295|b=12345678901234567890|@2"))
    IO.print(flat.is("one character string", "\"a\"", [""], "=a|@1"))
    IO.print(T.eq("a 60000 character string, its length",
      Nat.show(String.length(at(Json.obj(b("{\"s\":\"" ++ nest.row(60000n, "") ++ "\"}")), "s"))), "60000"))
    IO.print(T.eq("2000 nested objects, the innermost scalar",
      at(Json.obj(b(nest.obj(2000n))), nest.obj.key(2000n)), "1"))
    IO.print(T.eq("2000 nested objects, one key", Nat.show(Map.size(&2, String, Json.obj(b(nest.obj(2000n))))), "1"))

    # nesting depth: one pass and an explicit stack, so this must not overflow
    IO.print(T.ok("2000 nested arrays are valid", Bool.not(String.eq(flat.of(Nil{}, Json.flat(b(nest.text(2000n)))), "none"))))
    IO.print(T.eq("the scalar of 2000 nested arrays", at(Json.obj(b(nest.text(2000n))), nest.path(2000n)), "1"))
    IO.print(T.eq("the count of 2000 nested arrays", at(Json.obj(b(nest.text(2000n))), "#"), "1"))

    # a generated page, 3000 issues in one array
    IO.print(T.eq("3000 issues, rows length", count(Json.rows(b(gen.text(3000n)))), "3000"))
    IO.print(T.eq("3000 issues, first row", row.show(Json.rows(b(gen.text(3000n))), ["id", "name"], 0n), "id=0|name=n0|@2"))
    IO.print(T.eq("3000 issues, last row", row.show(Json.rows(b(gen.text(3000n))), ["id", "name"], 2999n), "id=2999|name=n2999|@2"))

    # writing
    IO.print(T.hex("encode every escape, an array and an object",
      Bytes.of_ascii(encoded()),
      "7b 22 73 22 3a 22 5c 22 5c 5c 5c 6e 5c 74 5c 62 5c 66 5c 72 5c 75 30 30 30 31 5c 75 30 30 31 66 22 2c 22 6e 22 3a 2d 31 2e 35 65 2b 33 2c 22 74 22 3a 74 72 75 65 2c 22 66 22 3a 66 61 6c 73 65 2c 22 7a 22 3a 6e 75 6c 6c 2c 22 61 22 3a 5b 31 2c 22 74 77 6f 22 5d 2c 22 6f 22 3a 7b 22 6b 22 3a 22 76 22 7d 7d"))
    IO.print(T.eq("encode an empty object", Json.encode(Json.Obj{Nil{}}), "{}"))
    IO.print(T.eq("encode an empty array", Json.encode(Json.Arr{Nil{}}), "[]"))
    IO.print(T.eq("encode a root string", Json.encode(Json.Str{"a"}), "\"a\""))
    IO.print(T.eq("encode a number as written", Json.encode(Json.Num{"-0.5e-2"}), "-0.5e-2"))
    IO.print(T.eq("encode null", Json.encode(Json.Null{}), "null"))
    IO.print(T.eq("encode flags", Json.encode(Json.Arr{[Json.Flag{True{}}, Json.Flag{False{}}]}), "[true,false]"))
    IO.print(T.eq("encode nested", Json.encode(Json.Obj{[Json.Field{"a", Json.Arr{[Json.Obj{Nil{}}]}}]}), "{\"a\":[{}]}"))
    IO.print(T.eq("encode keys in the order given", Json.encode(Json.Obj{[Json.Field{"b", Json.Num{"1"}}, Json.Field{"a", Json.Num{"2"}}]}), "{\"b\":1,\"a\":2}"))

    # and the writer's text read back by the reader
    IO.print(cps.at("round trip: the escaped string", encoded(), "s", "34 92 10 9 8 12 13 1 31 "))
    IO.print(T.eq("round trip: the number", at(Json.obj(b(encoded())), "n"), "-1.5e+3"))
    IO.print(T.eq("round trip: the flags", at(Json.obj(b(encoded())), "t") ++ at(Json.obj(b(encoded())), "f"), "truefalse"))
    IO.print(T.eq("round trip: null is empty text", at(Json.obj(b(encoded())), "z"), ""))
    IO.print(T.eq("round trip: an array", at(Json.obj(b(encoded())), "a.0") ++ "/" ++ at(Json.obj(b(encoded())), "a.1") ++ "/" ++ at(Json.obj(b(encoded())), "a.#"), "1/two/2"))
    IO.print(T.eq("round trip: a nested object", at(Json.obj(b(encoded())), "o.k"), "v"))
    IO.print(T.eq("round trip: the whole row", Nat.show(Map.size(&2, String, Json.obj(b(encoded())))), "9"))
