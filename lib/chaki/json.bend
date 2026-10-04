# json: a flat JSON reader and a small writer, after jsmn. The reader walks the bytes once
# with an explicit stack of open containers instead of building a tree, and answers the
# dotted-key rows cha's commands read: {"user": {"login": "a"}, "labels": [{"name": "x"}]}
# gives user.login = a, labels.0.name = x and labels.# = 1. Strict RFC 8259: any syntax
# error makes the whole document invalid. Strings are decoded UTF-8, with U+FFFD for
# anything that isn't. Every loop is a tail call, so a page of a hundred issues (half a
# megabyte) parses in one pass and no nesting depth can overflow the stack.
import Base
import ./bytes.bend as Bytes

# One member of a written object. A pair is always affine in this Bend (Base's
# Pair(-A: Type, -B: Type) -> Type), so a member of a Data list needs a Data type of its
# own: the lane's Obj{List<&2, String & Val>} doesn't type-check, this does.
type Field is Data:
  Field{key: String, value: Val}

# A value to write. Text is decoded; a number keeps the digits it was written with, so a
# number read and written back is unchanged.
type Val is Data:
  Null{}
  Flag{on: Bool}
  Num{text: String}
  Str{text: String}
  Arr{xs: List<&2, Val>}
  Obj{kvs: List<&2, Field>}

# the writer's work list: a value to expand, punctuation to copy, a string to quote
type Job is Type:
  JVal{v: Val}
  JText{text: String}
  JStr{text: String}

# A byte's class. Bend won't match on a byte value, so every byte is classified once and
# the reader matches on the class.
type Cls is Data:
  CSpace{}
  CWsv{}
  CCtl{}
  CQuote{}
  CEsc{}
  CSign{}
  CComma{}
  CDot{}
  CDig{}
  CColon{}
  CExp{}
  CLBrack{}
  CRBrack{}
  CLBrace{}
  CRBrace{}
  COther{}

# which string a quote or a backslash is inside: a member name or a value
type Role is Data:
  RKey{}
  RVal{}

# how much of the document is answered: one flat map, or one map per element of an array
type Mode is Data:
  MAll{}
  MRows{}
  MAt{key: String}

# Where an open object stands: fresh, expecting a name after a comma, or holding the name
# of the member whose value is being read. An open array only needs its next index.
type FSt is Data:
  FFirst{}
  FName{}
  FValue{key: String}

# An open container: an object with its state, or an array at its next index. An array
# flagged as rows holds the elements that are answered, one map each.
type Frame is Data:
  FObj{prefix: String, st: FSt}
  FArr{prefix: String, next: U32, rows: Bool}

# A number token, one constructor per place in RFC 8259's spelling of one:
# -?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
type NSt is Data:
  NBegin{}
  NIntStart{}
  NZero{}
  NInt{}
  NFracStart{}
  NFrac{}
  NExpStart{}
  NExpSign{}
  NExp{}

# what a byte does to a number token: joins it, ends it, or makes it invalid
type NAct is Data:
  NKeep{sub: NSt}
  NDone{}
  NBad{}

# an escape's byte after the backslash: one of the short escapes, the start of \uXXXX, or
# neither
type Esc is Data:
  EShort{byte: U32}
  EUni{}
  ENone{}

# a byte's role in UTF-8: a one-byte character, a continuation byte, the start of a
# sequence, or a byte no sequence can hold
type UByte is Data:
  UAscii{cp: U32}
  UCont{bits: U32}
  UStart{n: Nat, cp: U32, min: U32}
  UBad{}
  UEof{}

# the decoder's state: the continuations a sequence still owes, what it has spelled, and
# the text so far, held backwards
type DSt is Type:
  DGo{n: Nat, cp: U32, min: U32, acc: String}
  DDone{acc: String}

# The reader's state: one constructor per place in the grammar, each carrying the flat map
# so far, the rows finished, the open containers and the bytes left.
type St is Type:
  Bad{}
  Want{map: Map<&2, String>, done: List<&2, Map<&2, String>>, stack: List<&2, Frame>, b: List<&2, U32>, mode: Mode}
  Member{map: Map<&2, String>, done: List<&2, Map<&2, String>>, stack: List<&2, Frame>, b: List<&2, U32>, mode: Mode}
  Colon{map: Map<&2, String>, done: List<&2, Map<&2, String>>, stack: List<&2, Frame>, b: List<&2, U32>, mode: Mode}
  InStr{map: Map<&2, String>, done: List<&2, Map<&2, String>>, stack: List<&2, Frame>, b: List<&2, U32>, acc: List<&2, U32>, role: Role, mode: Mode}
  InEsc{map: Map<&2, String>, done: List<&2, Map<&2, String>>, stack: List<&2, Frame>, b: List<&2, U32>, acc: List<&2, U32>, role: Role, pend: Maybe<&2, U32>, mode: Mode}
  InSur{map: Map<&2, String>, done: List<&2, Map<&2, String>>, stack: List<&2, Frame>, b: List<&2, U32>, acc: List<&2, U32>, role: Role, pend: Maybe<&2, U32>, mode: Mode}
  InUni{map: Map<&2, String>, done: List<&2, Map<&2, String>>, stack: List<&2, Frame>, b: List<&2, U32>, acc: List<&2, U32>, role: Role, cp: U32, left: Nat, pend: Maybe<&2, U32>, mode: Mode}
  InNum{map: Map<&2, String>, done: List<&2, Map<&2, String>>, stack: List<&2, Frame>, b: List<&2, U32>, tok: List<&2, U32>, sub: NSt, mode: Mode}
  InLit{map: Map<&2, String>, done: List<&2, Map<&2, String>>, stack: List<&2, Frame>, b: List<&2, U32>, want: String, text: String, mode: Mode}
  After{map: Map<&2, String>, done: List<&2, Map<&2, String>>, stack: List<&2, Frame>, b: List<&2, U32>, mode: Mode}
  AtTop{map: Map<&2, String>, done: List<&2, Map<&2, String>>, b: List<&2, U32>}
  End{map: Map<&2, String>, done: List<&2, Map<&2, String>>}

# Bytes
# -----

# JSON whitespace other than space: tab, CR and LF, which must be escaped inside a string
def byte.wsv(+h: U32) -> Bool:
  Bool.or(U32.is_eq(h, 9), Bool.or(U32.is_eq(h, 10), U32.is_eq(h, 13)))

def byte.dig(+h: U32) -> Bool:
  Bool.and(U32.is_ge(h, 48), U32.is_le(h, 57))

def byte.zero(+h: U32) -> Bool:
  U32.is_eq(h, 48)

# e or E
def byte.exp(+h: U32) -> Bool:
  Bool.or(U32.is_eq(h, 101), U32.is_eq(h, 69))

# + or -
def byte.sign(+h: U32) -> Bool:
  Bool.or(U32.is_eq(h, 43), U32.is_eq(h, 45))

# Byte classes
# ------------
# The class of a byte, one rung of the ladder at a time. They are written from the
# deepest question up, since a def here sees only what is above it.

def cls.brace.close(+h: U32, +close: Bool) -> Cls:
  match close:
    case True{}: CRBrace{}
    case False{}: COther{}

def cls.brace(+h: U32, +open: Bool) -> Cls:
  match open:
    case True{}: CLBrace{}
    case False{}: cls.brace.close(h, U32.is_eq(h, 125))

def cls.exp(+exp: Bool) -> Cls:
  match exp:
    case True{}: CExp{}
    case False{}: COther{}

# 0x61..0x7a: only e is anything but text
def cls.lower(+h: U32, +below: Bool) -> Cls:
  match below:
    case True{}: cls.exp(byte.exp(h))
    case False{}: cls.brace(h, U32.is_eq(h, 123))

def cls.brack.close(+h: U32, +close: Bool) -> Cls:
  match close:
    case True{}: CRBrack{}
    case False{}: COther{}

def cls.back(+h: U32, +back: Bool) -> Cls:
  match back:
    case True{}: CEsc{}
    case False{}: cls.brack.close(h, U32.is_eq(h, 93))

def cls.brack.open(+h: U32, +open: Bool) -> Cls:
  match open:
    case True{}: CLBrack{}
    case False{}: cls.back(h, U32.is_eq(h, 92))

# 0x5b..0x60: the two brackets and the backslash
def cls.brack(+h: U32, +below: Bool) -> Cls:
  match below:
    case True{}: cls.brack.open(h, U32.is_eq(h, 91))
    case False{}: cls.lower(h, U32.is_lt(h, 123))

def cls.colon(+h: U32, +colon: Bool) -> Cls:
  match colon:
    case True{}: CColon{}
    case False{}: cls.exp(byte.exp(h))

def cls.num.colon(+h: U32, +below: Bool) -> Cls:
  match below:
    case True{}: cls.colon(h, U32.is_eq(h, 58))
    case False{}: cls.brack(h, U32.is_lt(h, 97))

def cls.num(+h: U32, +dig: Bool) -> Cls:
  match dig:
    case True{}: CDig{}
    case False{}: cls.num.colon(h, U32.is_lt(h, 91))

def cls.pun.dot(+h: U32, +dot: Bool) -> Cls:
  match dot:
    case True{}: CDot{}
    case False{}: COther{}

def cls.pun.sign(+h: U32, +sign: Bool) -> Cls:
  match sign:
    case True{}: CSign{}
    case False{}: cls.pun.dot(h, U32.is_eq(h, 46))

def cls.pun.comma(+h: U32, +comma: Bool) -> Cls:
  match comma:
    case True{}: CComma{}
    case False{}: cls.pun.sign(h, byte.sign(h))

def cls.pun(+h: U32, +quote: Bool) -> Cls:
  match quote:
    case True{}: CQuote{}
    case False{}: cls.pun.comma(h, U32.is_eq(h, 44))

def cls.space(+h: U32, +space: Bool) -> Cls:
  match space:
    case True{}: CSpace{}
    case False{}: cls.pun(h, U32.is_eq(h, 34))

def cls.wsv(+wsv: Bool) -> Cls:
  match wsv:
    case True{}: CWsv{}
    case False{}: CCtl{}

def cls.ctl(+h: U32, +ctl: Bool) -> Cls:
  match ctl:
    case True{}: cls.wsv(byte.wsv(h))
    case False{}: cls.space(h, U32.is_eq(h, 32))

def cls.low(+h: U32, +low: Bool) -> Cls:
  match low:
    case True{}: cls.ctl(h, U32.is_lt(h, 32))
    case False{}: cls.num(h, U32.is_lt(h, 58))

def cls.ascii(+h: U32, +ascii: Bool) -> Cls:
  match ascii:
    case False{}: COther{}
    case True{}: cls.low(h, U32.is_lt(h, 48))

# The class of a byte. One test for anything above ASCII, three for a digit and four or
# five for a letter, which is what a body is mostly made of.
def cls.of(+h: U32) -> Cls:
  cls.ascii(h, U32.is_lt(h, 128))

# the class of a byte list's head; COther when it is empty, which no step reads (each
# matches on the list itself first)
def cls.at(xs: List<&2, U32>) -> Cls:
  match xs:
    case Nil{}: COther{}
    case Con{h, t}: cls.of(h)

# Keys
# ----

def child.if(+prefix: String, +k: String, +root: Bool) -> String:
  match root:
    case True{}: k
    case False{}: prefix ++ "." ++ k

# the key of a value below prefix: prefix.member, or just member at the root. Keys are not
# escaped, so a member named a.b and a nested a.b name the same key.
def child(+prefix: String, +k: String) -> String:
  child.if(prefix, k, String.is_empty(prefix))

# the key of the value being read in an object: its member's name, or the object's own key
# when no name is pending, which the state machine never asks for
def fobj.key(+prefix: String, st: FSt) -> String:
  match st:
    case FValue{+key}: child(prefix, key)
    case x: prefix

# An element of a rows array is the root of its own map, so its key is empty; any other
# element's key is its array's prefix and its index.
def farr.key(+prefix: String, +next: U32, rows: Bool) -> String:
  match rows:
    case True{}: ""
    case False{}: child(prefix, U32.show(next))

def frame.key(top: Frame) -> String:
  match top:
    case FObj{prefix, st}: fobj.key(prefix, st)
    case FArr{prefix, next, rows}: farr.key(prefix, next, rows)

# the key of the value being parsed: "" at the root, else the frame below it
def value.key(stack: List<&2, Frame>) -> String:
  match stack:
    case Nil{}: ""
    case Con{top, rest}: frame.key(top)

# The frame below after a value opens in it: an array's index moves past it, an object
# keeps its member's name until the value ends.
def advance(top: Frame) -> Frame:
  match top:
    case FObj{prefix, st}: FObj{prefix, st}
    case FArr{prefix, next, rows}: FArr{prefix, U32.add(next, 1), rows}

def advance.stack(stack: List<&2, Frame>) -> List<&2, Frame>:
  match stack:
    case Nil{}: Nil{}
    case Con{top, rest}: Con{advance(top), rest}

# UTF-8
# -----

def utf8.bytes.four(+cp: U32) -> List<&2, U32>:
  [U32.or(240, U32.shrn(cp, 18n)), U32.or(128, U32.and(U32.shrn(cp, 12n), 63)), U32.or(128, U32.and(U32.shrn(cp, 6n), 63)), U32.or(128, U32.and(cp, 63))]

def utf8.bytes.three(+cp: U32) -> List<&2, U32>:
  [U32.or(224, U32.shrn(cp, 12n)), U32.or(128, U32.and(U32.shrn(cp, 6n), 63)), U32.or(128, U32.and(cp, 63))]

def utf8.bytes.more(+cp: U32, +three: Bool) -> List<&2, U32>:
  match three:
    case True{}: utf8.bytes.three(cp)
    case False{}: utf8.bytes.four(cp)

def utf8.bytes.two(+cp: U32, +two: Bool) -> List<&2, U32>:
  match two:
    case True{}: [U32.or(192, U32.shrn(cp, 6n)), U32.or(128, U32.and(cp, 63))]
    case False{}: utf8.bytes.more(cp, U32.is_lt(cp, 65536))

def utf8.bytes.ascii(+cp: U32, +ascii: Bool) -> List<&2, U32>:
  match ascii:
    case True{}: [cp]
    case False{}: utf8.bytes.two(cp, U32.is_lt(cp, 2048))

# the UTF-8 encoding of a code point, one to four bytes
def utf8.bytes(+cp: U32) -> List<&2, U32>:
  utf8.bytes.ascii(cp, U32.is_lt(cp, 128))

# xs prepended to a string held backwards: prepending in order keeps the build a tail call
def bytes.push(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case Con{h, t}: bytes.push(t, h <> acc)

# a code point appended to a string held backwards
def utf8.push(+cp: U32, acc: List<&2, U32>) -> List<&2, U32>:
  bytes.push(utf8.bytes(cp), acc)

# U+FFFD appended to a string held backwards
def utf8.fffd(acc: List<&2, U32>) -> List<&2, U32>:
  bytes.push([239, 191, 189], acc)

# U+FFFD appended to a decoded string
def utf8.bad(acc: String) -> String:
  SCon{Chr{65533}, acc}

def ubyte.of.four(+h: U32, +ok: Bool) -> UByte:
  match ok:
    case True{}: UStart{3n, U32.and(h, 7), 65536}
    case False{}: UBad{}

def ubyte.of.more(+h: U32, +three: Bool) -> UByte:
  match three:
    case True{}: UStart{2n, U32.and(h, 15), 2048}
    case False{}: ubyte.of.four(h, U32.is_le(h, 244))

def ubyte.of.two(+h: U32, +ok: Bool) -> UByte:
  match ok:
    case True{}: UStart{1n, U32.and(h, 31), 128}
    case False{}: UBad{}

# 0xc0 and 0xc1 only spell overlong sequences and 0xf5 and up are above U+10FFFF: both are
# bad bytes
def ubyte.of.start(+h: U32, +two: Bool) -> UByte:
  match two:
    case True{}: ubyte.of.two(h, U32.is_ge(h, 194))
    case False{}: ubyte.of.more(h, U32.is_lt(h, 240))

def ubyte.of.cont(+h: U32, +cont: Bool) -> UByte:
  match cont:
    case True{}: UCont{U32.and(h, 63)}
    case False{}: ubyte.of.start(h, U32.is_lt(h, 224))

def ubyte.of.ascii(+h: U32, +ascii: Bool) -> UByte:
  match ascii:
    case True{}: UAscii{h}
    case False{}: ubyte.of.cont(h, U32.is_lt(h, 192))

# a byte's role in UTF-8
def ubyte.of(+h: U32) -> UByte:
  ubyte.of.ascii(h, U32.is_lt(h, 128))

# the class of a byte list's head, UEof when there are no bytes left
def ubyte.head(xs: List<&2, U32>) -> UByte:
  match xs:
    case Nil{}: UEof{}
    case Con{h, t}: ubyte.of(h)

def utf8.surrogate(+cp: U32) -> Bool:
  Bool.and(U32.is_ge(cp, 55296), U32.is_le(cp, 57343))

# a code point a string may hold: not a surrogate, not above U+10FFFF
def utf8.scalar(+cp: U32) -> Bool:
  Bool.and(U32.is_le(cp, 1114111), Bool.not(utf8.surrogate(cp)))

def utf8.chr.if(+cp: U32, acc: String, +ok: Bool) -> String:
  match ok:
    case True{}: SCon{Chr{cp}, acc}
    case False{}: utf8.bad(acc)

# a code point appended to a decoded string, U+FFFD when it isn't one
def utf8.chr(+cp: U32, acc: String) -> String:
  utf8.chr.if(cp, acc, utf8.scalar(cp))

def utf8.seq.if(+cp: U32, acc: String, +ok: Bool) -> String:
  match ok:
    case True{}: utf8.chr(cp, acc)
    case False{}: utf8.bad(acc)

# a finished sequence appended to a decoded string: the code point it spells, or U+FFFD
# when the sequence was overlong
def utf8.seq(+cp: U32, +min: U32, acc: String) -> String:
  utf8.seq.if(cp, acc, U32.is_ge(cp, min))

# A finished continuation byte: the sequence ends when nothing more is owed, and p is how
# many continuations this byte leaves behind.
def decode.cont(+p: Nat, +cp2: U32, min: U32, acc: String, +done: Bool) -> DSt:
  match done:
    case True{}: DGo{0n, 0, 0, utf8.seq(cp2, min, acc)}
    case False{}: DGo{p, cp2, min, acc}

# A byte while a sequence still owes continuations. A byte that can't continue it appends
# U+FFFD and is read as a sequence's start in the same step.
def decode.more(c: UByte, +p: Nat, cp: U32, min: U32, acc: String) -> DSt:
  match c:
    case UCont{bits}: decode.cont(p, U32.or(U32.shln(cp, 6n), bits), min, acc, Nat.is_eq(p, 0n))
    case UAscii{+cp2}: DGo{0n, 0, 0, SCon{Chr{cp2}, utf8.bad(acc)}}
    case UStart{n2, cp2, min2}: DGo{n2, cp2, min2, utf8.bad(acc)}
    case x: DGo{0n, 0, 0, utf8.bad(acc)}

# a byte that begins something, or is one of the bytes no sequence can hold
def decode.head(c: UByte, acc: String) -> DSt:
  match c:
    case UAscii{+cp2}: DGo{0n, 0, 0, SCon{Chr{cp2}, acc}}
    case UStart{n2, cp2, min2}: DGo{n2, cp2, min2, acc}
    case x: DGo{0n, 0, 0, utf8.bad(acc)}

# one step: n is the continuation bytes the sequence still owes
def decode.step(c: UByte, n: Nat, cp: U32, min: U32, acc: String) -> DSt:
  match n:
    case 0n: decode.head(c, acc)
    case 1n+p: decode.more(c, p, cp, min, acc)

# a sequence cut off by the end of the bytes is one U+FFFD
def decode.eof.n(n: Nat, acc: String) -> DSt:
  match n:
    case 0n: DDone{acc}
    case 1n+p: DDone{utf8.bad(acc)}

def decode.eof(st: DSt) -> DSt:
  match st:
    case DGo{n, cp, min, acc}: decode.eof.n(n, acc)
    case DDone{acc}: DDone{acc}

# The text of UTF-8 bytes, one byte per step: the byte list is the fuel, since every step
# peels one.
def decode.go(xs: List<&2, U32>, st: DSt) -> DSt:
  match xs:
    case Nil{}: decode.eof(st)
    case Con{h, +t}:
      match st:
        case DGo{n, cp, min, acc}: decode.go(t, decode.step(ubyte.of(h), n, cp, min, acc))
        case DDone{acc}: DDone{acc}

def decode.fin(st: DSt) -> String:
  match st:
    case DGo{n, cp, min, acc}: String.reverse(acc)
    case DDone{acc}: String.reverse(acc)

# the text of UTF-8 bytes: valid input decodes, and a byte that can't begin or continue a
# sequence is one U+FFFD
def decode(xs: List<&2, U32>) -> String:
  decode.fin(decode.go(xs, DGo{0n, 0, 0, SNil{}}))

# The reader
# ----------
# These run in the order the machine reads them, deepest helper first: a def sees only the
# defs above it.

# a scalar is done: it goes under the current frame's key, and that frame moves on
def place.arr.rows(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  +prefix: String,
  +next: U32,
  rest: List<&2, Frame>,
  b: List<&2, U32>,
  text: String,
  mode: Mode,
  +rows: Bool
) -> St:
  match rows:
    case False{}: After{Map.set(&2, String, map, child(prefix, U32.show(next)), text), done, Con{FArr{prefix, U32.add(next, 1), rows}, rest}, b, mode}
    case True{}: After{Map.new(&2, String), Con{Map.set(&2, String, map, "", text), done}, Con{FArr{prefix, U32.add(next, 1), rows}, rest}, b, mode}

def place.arr(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  prefix: String,
  next: U32,
  rows: Bool,
  rest: List<&2, Frame>,
  b: List<&2, U32>,
  text: String,
  mode: Mode
) -> St:
  place.arr.rows(map, done, prefix, next, rest, b, text, mode, rows)

def place.top(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  top: Frame,
  rest: List<&2, Frame>,
  b: List<&2, U32>,
  text: String,
  mode: Mode
) -> St:
  match top:
    case FObj{+prefix, +st}: After{Map.set(&2, String, map, fobj.key(prefix, st), text), done, Con{FObj{prefix, st}, rest}, b, mode}
    case FArr{prefix, next, rows}: place.arr(map, done, prefix, next, rows, rest, b, text, mode)

def place(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  text: String,
  mode: Mode
) -> St:
  match stack:
    case Nil{}: AtTop{Map.set(&2, String, map, "", text), done, b}
    case Con{top, rest}: place.top(map, done, top, rest, b, text, mode)

# a container ended: an array records its length as prefix.#, then its value completes in
# the frame below it
def close.done.rows(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  prefix: String,
  next: U32,
  rest: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode,
  +rows: Bool
) -> St:
  match rows:
    case False{}: After{map, done, Con{FArr{prefix, next, rows}, rest}, b, mode}
    case True{}: After{Map.new(&2, String), Con{map, done}, Con{FArr{prefix, next, rows}, rest}, b, mode}

def close.done.top(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  top: Frame,
  rest: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode
) -> St:
  match top:
    case FObj{prefix, st}: After{map, done, Con{FObj{prefix, st}, rest}, b, mode}
    case FArr{prefix, next, rows}: close.done.rows(map, done, prefix, next, rest, b, mode, rows)

def close.done(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode
) -> St:
  match stack:
    case Nil{}: AtTop{map, done, b}
    case Con{top, rest}: close.done.top(map, done, top, rest, b, mode)

def close.arr(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  prefix: String,
  next: U32,
  rows: Bool,
  rest: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode
) -> St:
  close.done(Map.set(&2, String, map, child(prefix, "#"), U32.show(next)), done, rest, b, mode)

def close.top(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  top: Frame,
  rest: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode
) -> St:
  match top:
    case FObj{prefix, st}: close.done(map, done, rest, b, mode)
    case FArr{prefix, next, rows}: close.arr(map, done, prefix, next, rows, rest, b, mode)

def close(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode
) -> St:
  match stack:
    case Nil{}: Bad{}
    case Con{top, rest}: close.top(map, done, top, rest, b, mode)

# a container opens: its key comes from the frame below, which moves on first
def open.rows(mode: Mode, stack: List<&2, Frame>, key: String) -> Bool:
  match mode:
    case MAll{}: False{}
    case MRows{}: List.is_empty(&2, Frame, stack)
    case MAt{+k}: String.eq(k, key)

# An array that holds the rows starts them from an empty map: what the document put under
# the array's own key belongs to no row.
def open.push.arr(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  b: List<&2, U32>,
  mode: Mode,
  +prefix: String,
  +next: U32,
  +rows: Bool,
  stack: List<&2, Frame>
) -> St:
  match rows:
    case True{}: Want{Map.new(&2, String), done, Con{FArr{prefix, next, rows}, stack}, b, mode}
    case False{}: Want{map, done, Con{FArr{prefix, next, rows}, stack}, b, mode}

def open.push.go(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  b: List<&2, U32>,
  mode: Mode,
  frame: Frame,
  stack: List<&2, Frame>
) -> St:
  match frame:
    case FObj{prefix, st}: Member{map, done, Con{FObj{prefix, st}, stack}, b, mode}
    case FArr{prefix, next, rows}: open.push.arr(map, done, b, mode, prefix, next, rows, stack)

def open.push(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode,
  frame: Frame
) -> St:
  open.push.go(map, done, b, mode, frame, advance.stack(stack))

def open.mark(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  +stack: List<&2, Frame>,
  b: List<&2, U32>,
  +mode: Mode,
  +key: String
) -> St:
  open.push(map, done, stack, b, mode, FArr{key, 0, open.rows(mode, stack, key)})

def open.arr(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  +stack: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode
) -> St:
  open.mark(map, done, stack, b, mode, value.key(stack))

def open.obj(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  +stack: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode
) -> St:
  open.push(map, done, stack, b, mode, FObj{value.key(stack), FFirst{}})

# Number tokens
# -------------

def num.digit.if(+zero: Bool) -> NAct:
  match zero:
    case True{}: NKeep{NZero{}}
    case False{}: NKeep{NInt{}}

# the digit that opens the integer part: 0 is complete on its own
def num.digit(+h: U32) -> NAct:
  num.digit.if(byte.zero(h))

def num.begin.minus(+h: U32, +minus: Bool) -> NAct:
  match minus:
    case True{}: NKeep{NIntStart{}}
    case False{}: NBad{}

def num.begin.dig(+h: U32, +dig: Bool) -> NAct:
  match dig:
    case True{}: num.digit(h)
    case False{}: num.begin.minus(h, U32.is_eq(h, 45))

# the integer part opens with '-', '0' alone, or 1-9 then more digits
def num.begin(+h: U32) -> NAct:
  num.begin.dig(h, byte.dig(h))

def num.start.if(+h: U32, +dig: Bool) -> NAct:
  match dig:
    case True{}: num.digit.if(byte.zero(h))
    case False{}: NBad{}

# the digit after '-': the same, and '-' twice is not a number
def num.start(+h: U32) -> NAct:
  num.start.if(h, byte.dig(h))

def num.zero.exp(+h: U32, +exp: Bool) -> NAct:
  match exp:
    case True{}: NKeep{NExpStart{}}
    case False{}: NDone{}

def num.zero.dot(+h: U32, +dot: Bool) -> NAct:
  match dot:
    case True{}: NKeep{NFracStart{}}
    case False{}: num.zero.exp(h, byte.exp(h))

# 0 is the whole integer part: a following digit would be a leading zero
def num.zero(+h: U32) -> NAct:
  num.zero.dot(h, U32.is_eq(h, 46))

def num.int.dig(+h: U32, +dig: Bool) -> NAct:
  match dig:
    case True{}: NKeep{NInt{}}
    case False{}: num.zero.dot(h, U32.is_eq(h, 46))

# 1-9 then more digits, an optional fraction and an optional exponent
def num.int(+h: U32) -> NAct:
  num.int.dig(h, byte.dig(h))

def num.frac.start.if(+dig: Bool) -> NAct:
  match dig:
    case True{}: NKeep{NFrac{}}
    case False{}: NBad{}

def num.frac.start(+h: U32) -> NAct:
  num.frac.start.if(byte.dig(h))

def num.frac.dig(+h: U32, +dig: Bool) -> NAct:
  match dig:
    case True{}: NKeep{NFrac{}}
    case False{}: num.zero.exp(h, byte.exp(h))

def num.frac(+h: U32) -> NAct:
  num.frac.dig(h, byte.dig(h))

def num.exp.dig(+h: U32, +dig: Bool) -> NAct:
  match dig:
    case True{}: NKeep{NExp{}}
    case False{}: NBad{}

# NExp is complete: a byte that isn't a digit is not part of the token
def num.exp.end(+h: U32, +dig: Bool) -> NAct:
  match dig:
    case True{}: NKeep{NExp{}}
    case False{}: NDone{}

def num.exp.start.sign(+h: U32, +sign: Bool) -> NAct:
  match sign:
    case True{}: NKeep{NExpSign{}}
    case False{}: num.exp.dig(h, byte.dig(h))

def num.exp.start(+h: U32) -> NAct:
  num.exp.start.sign(h, byte.sign(h))

def num.exp.sign(+h: U32) -> NAct:
  num.exp.dig(h, byte.dig(h))

def num.exp(+h: U32) -> NAct:
  num.exp.end(h, byte.dig(h))

def num.act(sub: NSt, +h: U32) -> NAct:
  match sub:
    case NBegin{}: num.begin(h)
    case NIntStart{}: num.start(h)
    case NZero{}: num.zero(h)
    case NInt{}: num.int(h)
    case NFracStart{}: num.frac.start(h)
    case NFrac{}: num.frac(h)
    case NExpStart{}: num.exp.start(h)
    case NExpSign{}: num.exp.sign(h)
    case NExp{}: num.exp(h)

# is the token a complete number, so that a byte that isn't one of its own ends it?
def num.done(sub: NSt) -> Bool:
  match sub:
    case NZero{}: True{}
    case NInt{}: True{}
    case NFrac{}: True{}
    case NExp{}: True{}
    case x: False{}

# Escapes
# -------

def esc.of.u(+h: U32, +hit: Bool) -> Esc:
  match hit:
    case True{}: EUni{}
    case False{}: ENone{}

def esc.of.t(+h: U32, +hit: Bool) -> Esc:
  match hit:
    case True{}: EShort{9}
    case False{}: esc.of.u(h, U32.is_eq(h, 117))

def esc.of.r(+h: U32, +hit: Bool) -> Esc:
  match hit:
    case True{}: EShort{13}
    case False{}: esc.of.t(h, U32.is_eq(h, 116))

def esc.of.n(+h: U32, +hit: Bool) -> Esc:
  match hit:
    case True{}: EShort{10}
    case False{}: esc.of.r(h, U32.is_eq(h, 114))

def esc.of.f(+h: U32, +hit: Bool) -> Esc:
  match hit:
    case True{}: EShort{12}
    case False{}: esc.of.n(h, U32.is_eq(h, 110))

def esc.of.b(+h: U32, +hit: Bool) -> Esc:
  match hit:
    case True{}: EShort{8}
    case False{}: esc.of.f(h, U32.is_eq(h, 102))

def esc.of.slash(+h: U32, +hit: Bool) -> Esc:
  match hit:
    case True{}: EShort{47}
    case False{}: esc.of.b(h, U32.is_eq(h, 98))

def esc.of.back(+h: U32, +hit: Bool) -> Esc:
  match hit:
    case True{}: EShort{92}
    case False{}: esc.of.slash(h, U32.is_eq(h, 47))

def esc.of.quote(+h: U32, +hit: Bool) -> Esc:
  match hit:
    case True{}: EShort{34}
    case False{}: esc.of.back(h, U32.is_eq(h, 92))

# the byte after a backslash, if it is one of the short escapes
def esc.of(+h: U32) -> Esc:
  esc.of.quote(h, U32.is_eq(h, 34))

# a high surrogate, waiting for the low half of its pair
def utf8.high(+cp: U32) -> Bool:
  Bool.and(U32.is_ge(cp, 55296), U32.is_le(cp, 56319))

def utf8.low(+cp: U32) -> Bool:
  Bool.and(U32.is_ge(cp, 56320), U32.is_le(cp, 57343))

# the code point a surrogate pair spells
def utf8.pair(+hi: U32, +lo: U32) -> U32:
  U32.add(U32.add(65536, U32.shln(U32.sub(hi, 55296), 10n)), U32.sub(lo, 56320))

def uni.plain.low(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  cp: U32,
  mode: Mode,
  +low: Bool
) -> St:
  match low:
    case True{}: InStr{map, done, stack, b, utf8.fffd(acc), role, mode}
    case False{}: InStr{map, done, stack, b, utf8.push(cp, acc), role, mode}

def uni.plain.high(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  +cp: U32,
  mode: Mode,
  +high: Bool
) -> St:
  match high:
    case True{}: InEsc{map, done, stack, b, acc, role, Some{cp}, mode}
    case False{}: uni.plain.low(map, done, stack, b, acc, role, cp, mode, utf8.low(cp))

def uni.plain(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  +cp: U32,
  mode: Mode
) -> St:
  uni.plain.high(map, done, stack, b, acc, role, cp, mode, utf8.high(cp))

def uni.pair.low(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  cp: U32,
  +hi: U32,
  mode: Mode,
  +low: Bool
) -> St:
  match low:
    case True{}: InStr{map, done, stack, b, utf8.push(utf8.pair(hi, cp), acc), role, mode}
    case False{}: uni.plain(map, done, stack, b, utf8.fffd(acc), role, cp, mode)

def uni.pair(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  +cp: U32,
  +hi: U32,
  mode: Mode
) -> St:
  uni.pair.low(map, done, stack, b, acc, role, cp, hi, mode, utf8.low(cp))

# a \uXXXX escape finished: a high surrogate waits for its pair, a lone half is U+FFFD, and
# anything else is the character it spells
def uni.done(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  cp: U32,
  mode: Mode,
  pend: Maybe<&2, U32>
) -> St:
  match pend:
    case None{}: uni.plain(map, done, stack, b, acc, role, cp, mode)
    case Some{+hi}: uni.pair(map, done, stack, b, acc, role, cp, hi, mode)

# Closing a container
# -------------------

def read.close.ok.obj.st(st: FSt, +fresh: Bool) -> Bool:
  match st:
    case FFirst{}: fresh
    case FName{}: False{}
    case FValue{key}: Bool.not(fresh)

def read.close.ok.obj(st: FSt, +obj: Bool, +fresh: Bool) -> Bool:
  match obj:
    case False{}: False{}
    case True{}: read.close.ok.obj.st(st, fresh)

def read.close.ok.arr.next(+next: U32, +fresh: Bool) -> Bool:
  match fresh:
    case True{}: U32.is_zero(next)
    case False{}: U32.is_ge(next, 1)

def read.close.ok.arr(+next: U32, +obj: Bool, +fresh: Bool) -> Bool:
  match obj:
    case True{}: False{}
    case False{}: read.close.ok.arr.next(next, fresh)

# a ']' after '[' or a '}' after '{' may close an empty container; after a member or an
# element was read, only the matching bracket may close it
def read.close.ok(top: Frame, +obj: Bool, +fresh: Bool) -> Bool:
  match top:
    case FObj{prefix, st}: read.close.ok.obj(st, obj, fresh)
    case FArr{prefix, next, rows}: read.close.ok.arr(next, obj, fresh)

def read.close.if(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  t: List<&2, U32>,
  mode: Mode,
  +ok: Bool
) -> St:
  match ok:
    case True{}: close(map, done, stack, t, mode)
    case False{}: Bad{}

def read.close.top(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  +top: Frame,
  rest: List<&2, Frame>,
  t: List<&2, U32>,
  mode: Mode,
  +obj: Bool,
  +fresh: Bool
) -> St:
  read.close.if(map, done, Con{top, rest}, t, mode, read.close.ok(top, obj, fresh))

def read.close(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  t: List<&2, U32>,
  mode: Mode,
  +obj: Bool,
  +fresh: Bool
) -> St:
  match stack:
    case Nil{}: Bad{}
    case Con{top, rest}: read.close.top(map, done, top, rest, t, mode, obj, fresh)

# a comma after a member wants a name, after an element wants a value
def read.comma.top(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  top: Frame,
  rest: List<&2, Frame>,
  t: List<&2, U32>,
  mode: Mode
) -> St:
  match top:
    case FObj{prefix, st}: Member{map, done, Con{FObj{prefix, FName{}}, rest}, t, mode}
    case FArr{prefix, next, rows}: Want{map, done, Con{FArr{prefix, next, rows}, rest}, t, mode}

def read.comma(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  t: List<&2, U32>,
  mode: Mode
) -> St:
  match stack:
    case Nil{}: Bad{}
    case Con{top, rest}: read.comma.top(map, done, top, rest, t, mode)

# Strings
# -------

def read.str.key.top(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  top: Frame,
  rest: List<&2, Frame>,
  b: List<&2, U32>,
  text: String,
  mode: Mode
) -> St:
  match top:
    case FObj{prefix, st}: Colon{map, done, Con{FObj{prefix, FValue{text}}, rest}, b, mode}
    case FArr{prefix, next, rows}: Bad{}

def read.str.key(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  text: String,
  mode: Mode
) -> St:
  match stack:
    case Nil{}: Bad{}
    case Con{top, rest}: read.str.key.top(map, done, top, rest, b, text, mode)

# a quote closed a string: a name sets the frame's member, a value is answered
def read.str.close(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  text: String,
  role: Role,
  mode: Mode
) -> St:
  match role:
    case RKey{}: read.str.key(map, done, stack, b, text, mode)
    case RVal{}: place(map, done, stack, b, text, mode)

def read.str(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  mode: Mode,
  c: Cls
) -> St:
  match b:
    case Nil{}: Bad{}
    case Con{h, t}:
      match c:
        case CQuote{}: read.str.close(map, done, stack, t, decode(Bytes.rev(acc)), role, mode)
        case CEsc{}: InEsc{map, done, stack, t, acc, role, None{}, mode}
        case CSpace{}: InStr{map, done, stack, t, 32 <> acc, role, mode}
        case CWsv{}: Bad{}
        case CCtl{}: Bad{}
        case x: InStr{map, done, stack, t, h <> acc, role, mode}

# The byte after a backslash, with no surrogate waiting: an escape, or invalid.
def read.esc.of(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  h: U32,
  t: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  mode: Mode,
  e: Esc
) -> St:
  match e:
    case EShort{byte}: InStr{map, done, stack, t, byte <> acc, role, mode}
    case EUni{}: InUni{map, done, stack, t, acc, role, 0, 4n, None{}, mode}
    case ENone{}: Bad{}

# In the escape state with a surrogate still waiting, the byte is string content again --
# and the surrogate is closed out as U+FFFD -- unless it is the backslash of the pair's
# low half, which stays pending.
def read.esc.pend.if(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  +h: U32,
  t: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  mode: Mode,
  +hi: U32,
  +back: Bool
) -> St:
  match back:
    case True{}: InSur{map, done, stack, t, acc, role, Some{hi}, mode}
    case False{}: read.str(map, done, stack, Con{h, t}, utf8.fffd(acc), role, mode, cls.of(h))

def read.esc.pend(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  +h: U32,
  t: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  mode: Mode,
  +hi: U32
) -> St:
  read.esc.pend.if(map, done, stack, h, t, acc, role, mode, hi, U32.is_eq(h, 92))

def read.esc.p(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  +h: U32,
  t: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  mode: Mode,
  pend: Maybe<&2, U32>
) -> St:
  match pend:
    case None{}: read.esc.of(map, done, stack, h, t, acc, role, mode, esc.of(h))
    case Some{hi}: read.esc.pend(map, done, stack, h, t, acc, role, mode, hi)

# A backslash seen while a surrogate waits: only a u continues the pair. Anything else is
# an escape byte after all, with the surrogate closed out as U+FFFD.
def read.sur.u(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  +h: U32,
  t: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  pend: Maybe<&2, U32>,
  mode: Mode,
  +is_u: Bool
) -> St:
  match is_u:
    case True{}: InUni{map, done, stack, t, acc, role, 0, 4n, pend, mode}
    case False{}: read.esc.of(map, done, stack, h, t, utf8.fffd(acc), role, mode, esc.of(h))

def read.sur(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  pend: Maybe<&2, U32>,
  mode: Mode
) -> St:
  match b:
    case Nil{}: Bad{}
    case Con{+h, t}: read.sur.u(map, done, stack, h, t, acc, role, pend, mode, U32.is_eq(h, 117))

def read.esc(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  pend: Maybe<&2, U32>,
  mode: Mode
) -> St:
  match b:
    case Nil{}: Bad{}
    case Con{h, t}: read.esc.p(map, done, stack, h, t, acc, role, mode, pend)

# \uXXXX
# ------

def read.uni.last.if(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  t: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  cp: U32,
  left: Nat,
  pend: Maybe<&2, U32>,
  mode: Mode,
  +last: Bool
) -> St:
  match last:
    case True{}: uni.done(map, done, stack, t, acc, role, cp, mode, pend)
    case False{}: InUni{map, done, stack, t, acc, role, cp, Nat.sub(left, 1n), pend, mode}

def read.uni.last(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  t: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  cp: U32,
  +left: Nat,
  pend: Maybe<&2, U32>,
  mode: Mode
) -> St:
  read.uni.last.if(map, done, stack, t, acc, role, cp, left, pend, mode, Nat.is_eq(left, 1n))

def read.uni.dig(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  t: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  cp: U32,
  left: Nat,
  pend: Maybe<&2, U32>,
  mode: Mode,
  +v: U32,
  +bad: Bool
) -> St:
  match bad:
    case True{}: Bad{}
    case False{}: read.uni.last(map, done, stack, t, acc, role, U32.or(U32.shln(cp, 4n), v), left, pend, mode)

def read.uni.take(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  t: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  cp: U32,
  left: Nat,
  pend: Maybe<&2, U32>,
  mode: Mode,
  +v: U32
) -> St:
  read.uni.dig(map, done, stack, t, acc, role, cp, left, pend, mode, v, U32.is_le(16, v))

def read.uni(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  acc: List<&2, U32>,
  role: Role,
  cp: U32,
  left: Nat,
  pend: Maybe<&2, U32>,
  mode: Mode
) -> St:
  match b:
    case Nil{}: Bad{}
    case Con{h, t}: read.uni.take(map, done, stack, t, acc, role, cp, left, pend, mode, Bytes.hex.val(h))

# Numbers
# -------

def read.num.dig.if(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  h: U32,
  t: List<&2, U32>,
  mode: Mode,
  +zero: Bool
) -> St:
  match zero:
    case True{}: InNum{map, done, stack, t, [h], NZero{}, mode}
    case False{}: InNum{map, done, stack, t, [h], NInt{}, mode}

def read.num.dig(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  +h: U32,
  t: List<&2, U32>,
  mode: Mode
) -> St:
  read.num.dig.if(map, done, stack, h, t, mode, byte.zero(h))

def read.num.sign.if(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  h: U32,
  t: List<&2, U32>,
  mode: Mode,
  +minus: Bool
) -> St:
  match minus:
    case True{}: InNum{map, done, stack, t, [h], NIntStart{}, mode}
    case False{}: Bad{}

# only '-' may open a number: JSON has no +0
def read.num.sign(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  +h: U32,
  t: List<&2, U32>,
  mode: Mode
) -> St:
  read.num.sign.if(map, done, stack, h, t, mode, U32.is_eq(h, 45))

# the bytes ran out: the token must be a complete number
def read.num.nil.if(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  tok: List<&2, U32>,
  +ok: Bool,
  mode: Mode
) -> St:
  match ok:
    case True{}: place(map, done, stack, Nil{}, Bytes.to_ascii(Bytes.rev(tok)), mode)
    case False{}: Bad{}

def read.num.nil(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  tok: List<&2, U32>,
  sub: NSt,
  mode: Mode
) -> St:
  read.num.nil.if(map, done, stack, tok, num.done(sub), mode)

def read.num.act(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  h: U32,
  t: List<&2, U32>,
  tok: List<&2, U32>,
  sub: NSt,
  mode: Mode,
  a: NAct
) -> St:
  match a:
    case NKeep{sub2}: InNum{map, done, stack, t, h <> tok, sub2, mode}
    case NBad{}: Bad{}
    case NDone{}: place(map, done, stack, Con{h, t}, Bytes.to_ascii(Bytes.rev(tok)), mode)

def read.num(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  tok: List<&2, U32>,
  +sub: NSt,
  mode: Mode
) -> St:
  match b:
    case Nil{}: read.num.nil(map, done, stack, tok, sub, mode)
    case Con{+h, t}: read.num.act(map, done, stack, h, t, tok, sub, mode, num.act(sub, h))

# Literals
# --------

def read.lit.n(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  t: List<&2, U32>,
  mode: Mode,
  +hit: Bool
) -> St:
  match hit:
    case True{}: InLit{map, done, stack, t, "ull", "", mode}
    case False{}: Bad{}

def read.lit.f(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  h: U32,
  t: List<&2, U32>,
  mode: Mode,
  +hit: Bool
) -> St:
  match hit:
    case True{}: InLit{map, done, stack, t, "alse", "false", mode}
    case False{}: read.lit.n(map, done, stack, t, mode, U32.is_eq(h, 110))

def read.lit.t(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  +h: U32,
  t: List<&2, U32>,
  mode: Mode,
  +hit: Bool
) -> St:
  match hit:
    case True{}: InLit{map, done, stack, t, "rue", "true", mode}
    case False{}: read.lit.f(map, done, stack, h, t, mode, U32.is_eq(h, 102))

def read.lit.begin(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  +h: U32,
  t: List<&2, U32>,
  mode: Mode
) -> St:
  read.lit.t(map, done, stack, h, t, mode, U32.is_eq(h, 116))

def read.lit.rest(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  t: List<&2, U32>,
  r: String,
  text: String,
  mode: Mode,
  +empty: Bool
) -> St:
  match empty:
    case True{}: place(map, done, stack, t, text, mode)
    case False{}: InLit{map, done, stack, t, r, text, mode}

def read.lit.eq(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  h: U32,
  t: List<&2, U32>,
  +r: String,
  text: String,
  mode: Mode,
  +same: Bool
) -> St:
  match same:
    case False{}: Bad{}
    case True{}: read.lit.rest(map, done, stack, t, r, text, mode, String.is_empty(r))

def read.lit(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  want: String,
  text: String,
  mode: Mode
) -> St:
  match b:
    case Nil{}: Bad{}
    case Con{+h, t}:
      match want:
        case SNil{}: Bad{}
        case SCon{Chr{c}, r}: read.lit.eq(map, done, stack, h, t, r, text, mode, U32.is_eq(h, c))

# The document
# ------------

def read.top(map: Map<&2, String>, done: List<&2, Map<&2, String>>, b: List<&2, U32>, c: Cls) -> St:
  match b:
    case Nil{}: End{map, done}
    case Con{h, t}:
      match c:
        case CSpace{}: AtTop{map, done, t}
        case CWsv{}: AtTop{map, done, t}
        case x: Bad{}

def read.after(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode,
  c: Cls
) -> St:
  match b:
    case Nil{}: Bad{}
    case Con{h, t}:
      match c:
        case CSpace{}: After{map, done, stack, t, mode}
        case CWsv{}: After{map, done, stack, t, mode}
        case CComma{}: read.comma(map, done, stack, t, mode)
        case CRBrace{}: read.close(map, done, stack, t, mode, True{}, False{})
        case CRBrack{}: read.close(map, done, stack, t, mode, False{}, False{})
        case x: Bad{}

def read.member(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode,
  c: Cls
) -> St:
  match b:
    case Nil{}: Bad{}
    case Con{h, t}:
      match c:
        case CSpace{}: Member{map, done, stack, t, mode}
        case CWsv{}: Member{map, done, stack, t, mode}
        case CQuote{}: InStr{map, done, stack, t, Nil{}, RKey{}, mode}
        case CRBrace{}: read.close(map, done, stack, t, mode, True{}, True{})
        case x: Bad{}

def read.colon(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode,
  c: Cls
) -> St:
  match b:
    case Nil{}: Bad{}
    case Con{h, t}:
      match c:
        case CSpace{}: Colon{map, done, stack, t, mode}
        case CWsv{}: Colon{map, done, stack, t, mode}
        case CColon{}: Want{map, done, stack, t, mode}
        case x: Bad{}

def read.want(
  map: Map<&2, String>,
  done: List<&2, Map<&2, String>>,
  stack: List<&2, Frame>,
  b: List<&2, U32>,
  mode: Mode,
  c: Cls
) -> St:
  match b:
    case Nil{}: Bad{}
    case Con{h, t}:
      match c:
        case CSpace{}: Want{map, done, stack, t, mode}
        case CWsv{}: Want{map, done, stack, t, mode}
        case CQuote{}: InStr{map, done, stack, t, Nil{}, RVal{}, mode}
        case CLBrace{}: open.obj(map, done, stack, t, mode)
        case CLBrack{}: open.arr(map, done, stack, t, mode)
        case CRBrack{}: read.close(map, done, stack, t, mode, False{}, True{})
        case CDig{}: read.num.dig(map, done, stack, h, t, mode)
        case CSign{}: read.num.sign(map, done, stack, h, t, mode)
        case COther{}: read.lit.begin(map, done, stack, h, t, mode)
        case x: Bad{}

# The machine: one dispatch per state, and every step is a tail call on the fuel, which
# starts at several times the body's byte count. Running out answers the state as it
# stands, which no caller reads as a document (flat answers None, rows answers []).
def read.go(fuel: Nat, st: St) -> St:
  match fuel:
    case 0n:
      st
    case 1n+p:
      match st:
        case Bad{}: Bad{}
        case End{map, done}: End{map, done}
        case AtTop{map, done, +b}: read.go(p, read.top(map, done, b, cls.at(b)))
        case Want{map, done, stack, +b, mode}: read.go(p, read.want(map, done, stack, b, mode, cls.at(b)))
        case Member{map, done, stack, +b, mode}: read.go(p, read.member(map, done, stack, b, mode, cls.at(b)))
        case Colon{map, done, stack, +b, mode}: read.go(p, read.colon(map, done, stack, b, mode, cls.at(b)))
        case After{map, done, stack, +b, mode}: read.go(p, read.after(map, done, stack, b, mode, cls.at(b)))
        case InStr{map, done, stack, +b, acc, role, mode}: read.go(p, read.str(map, done, stack, b, acc, role, mode, cls.at(b)))
        case InEsc{map, done, stack, b, acc, role, pend, mode}: read.go(p, read.esc(map, done, stack, b, acc, role, pend, mode))
        case InSur{map, done, stack, b, acc, role, pend, mode}: read.go(p, read.sur(map, done, stack, b, acc, role, pend, mode))
        case InUni{map, done, stack, b, acc, role, cp, left, pend, mode}: read.go(p, read.uni(map, done, stack, b, acc, role, cp, left, pend, mode))
        case InNum{map, done, stack, b, tok, sub, mode}: read.go(p, read.num(map, done, stack, b, tok, sub, mode))
        case InLit{map, done, stack, b, want, text, mode}: read.go(p, read.lit(map, done, stack, b, want, text, mode))

def read.fuel(+b: List<&2, U32>) -> Nat:
  # one step per byte, with room for the byte a token hands back
  Nat.add(Nat.mul(4n, U32.to_nat(Bytes.len(b))), 16n)

def read.run(+b: List<&2, U32>, mode: Mode) -> St:
  read.go(read.fuel(b), Want{Map.new(&2, String), Nil{}, Nil{}, b, mode})

# Reading
# -------

def flat.of(st: St) -> Maybe<&2, Map<&2, String>>:
  match st:
    case End{map, done}: Some{map}
    case x: None{}

# a whole document flattened; None when it isn't valid JSON
def flat(b: List<&2, U32>) -> Maybe<&2, Map<&2, String>>:
  flat.of(read.run(b, MAll{}))

def rows.of(st: St) -> List<&2, Map<&2, String>>:
  match st:
    case End{map, done}: List.reverse(&2, Map<&2, String>, done)
    case x: Nil{}

# the elements of a top-level array, each flattened from its own root; [] when the document
# isn't an array or isn't valid
def rows(b: List<&2, U32>) -> List<&2, Map<&2, String>>:
  rows.of(read.run(b, MRows{}))

# the elements of the array at member key of a top-level object ({"workflow_runs": [..]})
def rows.at(b: List<&2, U32>, key: String) -> List<&2, Map<&2, String>>:
  rows.of(read.run(b, MAt{key}))

def obj.of(st: St) -> Map<&2, String>:
  match st:
    case End{map, done}: map
    case x: Map.new(&2, String)

# a top-level document flattened; an empty map when it isn't valid
def obj(b: List<&2, U32>) -> Map<&2, String>:
  obj.of(read.run(b, MAll{}))

# Writing
# -------

# the text's characters prepended to a string held backwards, in order
def str.push(s: String, acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}: str.push(t, SCon{Chr{c}, acc})

# the rest of the controls below 0x20: \u00XX, lowercase
def encode.ctl.hex(+c: U32, acc: String) -> String:
  SCon{Chr{Bytes.hex.digit(U32.and(c, 15))}, SCon{Chr{Bytes.hex.digit(U32.shrn(c, 4n))}, SCon{Chr{48}, SCon{Chr{48}, SCon{Chr{117}, SCon{Chr{92}, acc}}}}}}

def encode.ctl.r(+c: U32, acc: String, +hit: Bool) -> String:
  match hit:
    case True{}: SCon{Chr{114}, SCon{Chr{92}, acc}}
    case False{}: encode.ctl.hex(c, acc)

def encode.ctl.f(+c: U32, acc: String, +hit: Bool) -> String:
  match hit:
    case True{}: SCon{Chr{102}, SCon{Chr{92}, acc}}
    case False{}: encode.ctl.r(c, acc, U32.is_eq(c, 13))

def encode.ctl.n(+c: U32, acc: String, +hit: Bool) -> String:
  match hit:
    case True{}: SCon{Chr{110}, SCon{Chr{92}, acc}}
    case False{}: encode.ctl.f(c, acc, U32.is_eq(c, 12))

def encode.ctl.t(+c: U32, acc: String, +hit: Bool) -> String:
  match hit:
    case True{}: SCon{Chr{116}, SCon{Chr{92}, acc}}
    case False{}: encode.ctl.n(c, acc, U32.is_eq(c, 10))

def encode.ctl.b(+c: U32, acc: String, +hit: Bool) -> String:
  match hit:
    case True{}: SCon{Chr{98}, SCon{Chr{92}, acc}}
    case False{}: encode.ctl.t(c, acc, U32.is_eq(c, 9))

# A control character below 0x20, prepended to a string held backwards: the short escape
# where JSON has one, \u00XX for the rest.
def encode.ctl(+c: U32, acc: String) -> String:
  encode.ctl.b(c, acc, U32.is_eq(c, 8))

def encode.chr.ctl(+c: U32, acc: String, +ctl: Bool) -> String:
  match ctl:
    case True{}: encode.ctl(c, acc)
    case False{}: SCon{Chr{c}, acc}

def encode.chr.back(+c: U32, acc: String, +hit: Bool) -> String:
  match hit:
    case True{}: SCon{Chr{92}, SCon{Chr{92}, acc}}
    case False{}: encode.chr.ctl(c, acc, U32.is_lt(c, 32))

def encode.chr.quote(+c: U32, acc: String, +hit: Bool) -> String:
  match hit:
    case True{}: SCon{Chr{34}, SCon{Chr{92}, acc}}
    case False{}: encode.chr.back(c, acc, U32.is_eq(c, 92))

# one character, escaped if it must be, prepended to a string held backwards
def encode.chr(+c: U32, acc: String) -> String:
  encode.chr.quote(c, acc, U32.is_eq(c, 34))

def encode.esc(s: String, acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}: encode.esc(t, encode.chr(c, acc))

# a JSON string, quotes and escapes included, prepended to a string held backwards
def encode.str(s: String, acc: String) -> String:
  SCon{Chr{34}, encode.esc(s, SCon{Chr{34}, acc})}

# an array's elements with the comma after each but the last, built backwards
def encode.items.more(xs: List<&2, Val>, acc: List<&1, Job>) -> List<&1, Job>:
  match xs:
    case Nil{}: acc
    case Con{x, t}: encode.items.more(t, Con{JVal{x}, Con{JText{","}, acc}})

def encode.arr.items(xs: List<&2, Val>, acc: List<&1, Job>) -> List<&1, Job>:
  match xs:
    case Nil{}: acc
    case Con{x, t}: encode.items.more(t, Con{JVal{x}, acc})

# an object's members with the comma before each but the first, built backwards
def encode.obj.more(kvs: List<&2, Field>, acc: List<&1, Job>) -> List<&1, Job>:
  match kvs:
    case Nil{}: acc
    case Field{k, v} <> t: encode.obj.more(t, Con{JVal{v}, Con{JText{":"}, Con{JStr{k}, Con{JText{","}, acc}}}})

def encode.obj.items(kvs: List<&2, Field>, acc: List<&1, Job>) -> List<&1, Job>:
  match kvs:
    case Nil{}: acc
    case Field{k, v} <> t: encode.obj.more(t, Con{JVal{v}, Con{JText{":"}, Con{JStr{k}, acc}}})

# the jobs of a bracketed body: close it, reverse what was built backwards, then the work
def encode.body(jobs: List<&1, Job>, close: String, work: List<&1, Job>) -> List<&1, Job>:
  List.append(&1, Job, List.reverse(&1, Job, jobs), Con{JText{close}, work})

def encode.flag(work: List<&1, Job>, +on: Bool) -> List<&1, Job>:
  match on:
    case True{}: Con{JText{"true"}, work}
    case False{}: Con{JText{"false"}, work}

# a value's jobs, in front of the work still to do
def encode.val(v: Val, work: List<&1, Job>) -> List<&1, Job>:
  match v:
    case Null{}: Con{JText{"null"}, work}
    case Flag{on}: encode.flag(work, on)
    case Num{text}: Con{JText{text}, work}
    case Str{text}: Con{JStr{text}, work}
    case Arr{xs}: encode.body(encode.arr.items(xs, Con{JText{"["}, Nil{}}), "]", work)
    case Obj{kvs}: encode.body(encode.obj.items(kvs, Con{JText{"{"}, Nil{}}), "}", work)

# One job per step, the text built backwards. @unsafe because the loop walks a work list
# rather than the value: each step writes text or swaps a container for its strictly
# smaller parts, which is a shape bend can't prove. This is how cha's old json writer did
# it too.
@unsafe
def encode.go(work: List<&1, Job>, acc: String) -> String:
  match work:
    case Nil{}: acc
    case Con{JText{text}, t}: encode.go(t, str.push(text, acc))
    case Con{JStr{text}, t}: encode.go(t, encode.str(text, acc))
    case Con{JVal{v}, t}: encode.go(encode.val(v, t), acc)

# compact RFC 8259 text, keys in the order given
def encode(v: Val) -> String:
  String.reverse(encode.go(Con{JVal{v}, Nil{}}, SNil{}))
