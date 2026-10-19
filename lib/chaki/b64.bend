# b64: RFC 4648 base64, padded, and the PEM blocks certificates travel in. Encoding is
# three bytes to four characters; decoding is strict, the way a certificate needs it: the
# alphabet and nothing else, padding that closes the group, and zero bits under the pad.
# Every loop here is a tail call; a CA bundle is 220 KB of PEM.
import Base
import ./bytes.bend as Bytes

# The shapes
# ----------

# what one character of base64 text carries
type B64.Ch is Data:
  B64.Data{v: U32}  # the six bits it carries
  B64.Pad{}         # '='
  B64.Skip{}        # space, tab, CR or LF: base64 text may carry them anywhere
  B64.Bad{}         # anything else

# the group being read, the bytes so far, and whether the text is still base64. n counts the
# data characters of the group and pad the pads, so the pair is one of (0,0) (1,0) (2,0)
# (3,0) (2,1): a group of two data characters still wants its second pad.
type B64.State is Data:
  B64.State{v: U32, n: Nat, pad: Nat, out: List<&2, U32>, ok: Bool}

# the line being read, built backwards, with its trailing spaces and tabs held apart, and
# the lines before it, also backwards
type Split is Data:
  Split{cur: String, spare: String, acc: List<&2, String>}

# where the PEM scan is: outside a block, or inside one, with its body and the payloads
# found so far, both built backwards
type Pem is Data:
  Pem.Scan{found: List<&2, List<&2, U32>>}
  Pem.Body{payload: String, found: List<&2, List<&2, U32>>}

# The alphabet
# ------------

# the base64 character of a 6-bit value: A-Z, a-z, 0-9, '+', '/'
def alpha.tail(+v: U32, slash: Bool) -> U32:
  match slash:
    case True{}:
      47
    case False{}:
      43

def alpha.dig(+v: U32, digit: Bool) -> U32:
  match digit:
    case True{}:
      U32.sub(v, 4)
    case False{}:
      alpha.tail(v, U32.is_eq(v, 63))

def alpha.low(+v: U32, lower: Bool) -> U32:
  match lower:
    case True{}:
      U32.add(v, 71)
    case False{}:
      alpha.dig(v, U32.is_le(v, 61))

def alpha.up(+v: U32, upper: Bool) -> U32:
  match upper:
    case True{}:
      U32.add(v, 65)
    case False{}:
      alpha.low(v, U32.is_le(v, 51))

def alpha(+v: U32) -> U32:
  alpha.up(v, U32.is_le(v, 25))

# Encoding
# --------

# the four characters of a 24-bit group, least significant first: out is built backwards
def sextets(+v: U32, out: String) -> String:
  SCon{Chr{alpha(U32.and(v, 63))}, SCon{Chr{alpha(U32.and(U32.shrn(v, 6n), 63))}, SCon{Chr{alpha(U32.and(U32.shrn(v, 12n), 63))}, SCon{Chr{alpha(U32.and(U32.shrn(v, 18n), 63))}, out}}}}

def encode.three(+x: U32, +y: U32, +z: U32, out: String) -> String:
  sextets(U32.or(U32.shln(x, 16n), U32.or(U32.shln(y, 8n), z)), out)

# one leftover byte: two characters and two pads
def encode.one(+x: U32, out: String) -> String:
  SCon{Chr{61}, SCon{Chr{61}, SCon{Chr{alpha(U32.shln(U32.and(x, 3), 4n))}, SCon{Chr{alpha(U32.shrn(x, 2n))}, out}}}}

# two leftover bytes: three characters and one pad
def encode.two(+x: U32, +y: U32, out: String) -> String:
  SCon{Chr{61}, SCon{Chr{alpha(U32.shln(U32.and(y, 15), 2n))}, SCon{Chr{alpha(U32.or(U32.shln(U32.and(x, 3), 4n), U32.shrn(y, 4n)))}, SCon{Chr{alpha(U32.shrn(x, 2n))}, out}}}}

def encode.go(b: List<&2, U32>, out: String) -> String:
  match b:
    case Nil{}:
      String.reverse(out)
    case Con{x, t}:
      match t:
        case Nil{}:
          String.reverse(encode.one(x, out))
        case Con{y, t2}:
          match t2:
            case Nil{}:
              String.reverse(encode.two(x, y, out))
            case Con{z, t3}:
              encode.go(t3, encode.three(x, y, z, out))

# RFC 4648 base64, with padding
def encode(b: List<&2, U32>) -> String:
  encode.go(b, SNil{})

# Decoding
# --------

# space, tab, CR and LF, the whitespace base64 text may carry
def blank(+c: U32) -> Bool:
  Bool.or(U32.is_eq(c, 32), Bool.or(U32.is_eq(c, 9), Bool.or(U32.is_eq(c, 13), U32.is_eq(c, 10))))

def sym.slash(+c: U32, slash: Bool) -> B64.Ch:
  match slash:
    case True{}:
      B64.Data{63}
    case False{}:
      B64.Bad{}

def sym.tail(+c: U32, plus: Bool) -> B64.Ch:
  match plus:
    case True{}:
      B64.Data{62}
    case False{}:
      sym.slash(c, U32.is_eq(c, 47))

def sym.dig(+c: U32, digit: Bool) -> B64.Ch:
  match digit:
    case True{}:
      B64.Data{U32.add(c, 4)}
    case False{}:
      sym.tail(c, U32.is_eq(c, 43))

def sym.low(+c: U32, lower: Bool) -> B64.Ch:
  match lower:
    case True{}:
      B64.Data{U32.sub(c, 71)}
    case False{}:
      sym.dig(c, Bool.and(U32.is_le(48, c), U32.is_le(c, 57)))

def sym.up(+c: U32, upper: Bool) -> B64.Ch:
  match upper:
    case True{}:
      B64.Data{U32.sub(c, 65)}
    case False{}:
      sym.low(c, Bool.and(U32.is_le(97, c), U32.is_le(c, 122)))

def sym.space(+c: U32, skip: Bool) -> B64.Ch:
  match skip:
    case True{}:
      B64.Skip{}
    case False{}:
      sym.up(c, Bool.and(U32.is_le(65, c), U32.is_le(c, 90)))

def sym.pad(+c: U32, pad: Bool) -> B64.Ch:
  match pad:
    case True{}:
      B64.Pad{}
    case False{}:
      sym.space(c, blank(c))

# the six bits one base64 character carries, and the three characters that carry none
def sym(+c: U32) -> B64.Ch:
  sym.pad(c, U32.is_eq(c, 61))

# the three bytes of a complete group, least significant first: out is built backwards
def b64.three(+v: U32, +w: U32, out: List<&2, U32>) -> List<&2, U32>:
  +x = U32.or(U32.shln(v, 6n), w)
  U32.and(x, 255) <> (U32.and(U32.shrn(x, 8n), 255) <> (U32.and(U32.shrn(x, 16n), 255) <> out))

# one leftover byte under the pad: the four bits it carries must be zero
def b64.close.one(v: U32, out: List<&2, U32>, ok: Bool, clean: Bool) -> B64.State:
  match clean:
    case True{}:
      B64.State{0, 2n, 1n, U32.and(U32.shrn(v, 4n), 255) <> out, ok}
    case False{}:
      B64.State{0, 2n, 1n, out, False{}}

# two leftover bytes under the pad: the two bits they carry must be zero
def b64.close.two(+v: U32, out: List<&2, U32>, ok: Bool, clean: Bool) -> B64.State:
  match clean:
    case True{}:
      B64.State{0, 0n, 0n, U32.and(U32.shrn(v, 2n), 255) <> (U32.and(U32.shrn(v, 10n), 255) <> out), ok}
    case False{}:
      B64.State{0, 0n, 0n, out, False{}}

# a pad: it closes the group, writing the bytes its data characters left over
def b64.pad(+v: U32, n: Nat, pad: Nat, out: List<&2, U32>, ok: Bool) -> B64.State:
  match n pad:
    case 2n 0n:
      b64.close.one(v, out, ok, U32.is_eq(U32.and(v, 15), 0))
    case 3n 0n:
      b64.close.two(v, out, ok, U32.is_eq(U32.and(v, 3), 0))
    case 2n 1n:
      B64.State{0, 0n, 0n, out, ok}
    case _ _:
      B64.State{0, 0n, 0n, out, False{}}

# six more bits: the fourth data character completes the group
def b64.grow(v: U32, n: Nat, out: List<&2, U32>, ok: Bool, +w: U32) -> B64.State:
  match n:
    case 3n:
      B64.State{0, 0n, 0n, b64.three(v, w, out), ok}
    case _:
      B64.State{U32.or(U32.shln(v, 6n), w), Nat.add(n, 1n), 0n, out, ok}

# a data character: six more bits, unless the padding already closed the group
def b64.data(v: U32, n: Nat, pad: Nat, out: List<&2, U32>, ok: Bool, +w: U32) -> B64.State:
  match pad:
    case 0n:
      b64.grow(v, n, out, ok, w)
    case _:
      B64.State{v, n, pad, out, False{}}

# one classified character, whatever the state
def feed(st: B64.State, ch: B64.Ch) -> B64.State:
  match st:
    case B64.State{v, n, pad, out, ok}:
      match ch:
        case B64.Data{w}:
          b64.data(v, n, pad, out, ok, w)
        case B64.Pad{}:
          b64.pad(v, n, pad, out, ok)
        case B64.Skip{}:
          B64.State{v, n, pad, out, ok}
        case B64.Bad{}:
          B64.State{v, n, pad, out, False{}}

# whether the text ended at a group boundary, with no pad half spent
def closed(n: Nat, pad: Nat) -> Bool:
  Bool.and(Nat.is_eq(n, 0n), Nat.is_eq(pad, 0n))

def decode.done(out: List<&2, U32>, good: Bool) -> Maybe<&2, List<&2, U32>>:
  match good:
    case True{}:
      Some{Bytes.rev(out)}
    case False{}:
      None{}

def decode.end(st: B64.State) -> Maybe<&2, List<&2, U32>>:
  match st:
    case B64.State{v, n, pad, out, ok}:
      decode.done(out, Bool.and(ok, closed(n, pad)))

def decode.go(s: String, st: B64.State) -> B64.State:
  match s:
    case SNil{}:
      st
    case SCon{Chr{+c}, t}:
      decode.go(t, feed(st, sym(c)))

# the bytes RFC 4648 padded base64 text holds. Whitespace is skipped; anything else outside
# the alphabet, a group the padding doesn't close, or non-zero bits under a pad answer None.
def decode(s: String) -> Maybe<&2, List<&2, U32>>:
  decode.end(decode.go(s, B64.State{0, 0n, 0n, Nil{}, True{}}))

# PEM
# ---

# what one character means to the line splitter: 0 ends the line (CR or LF), 1 is a space or
# a tab, 2 is anything else
def cls(+b: U32) -> Nat:
  match b:
    case 13:
      0n
    case 10:
      0n
    case 32:
      1n
    case 9:
      1n
    case _:
      2n

# a line just ended, built backwards: added to the lines unless it is empty
def split.keep(rev: String, acc: List<&2, String>) -> List<&2, String>:
  match rev:
    case SNil{}:
      acc
    case _:
      String.reverse(rev) <> acc

# one character of class k: it ends the line, waits as trailing space, or joins the line
def split.step(st: Split, +k: Nat, +b: U32) -> Split:
  match st:
    case Split{cur, spare, acc}:
      match k:
        case 0n:
          Split{SNil{}, SNil{}, split.keep(cur, acc)}
        case 1n:
          Split{cur, SCon{Chr{b}, spare}, acc}
        case _:
          Split{SCon{Chr{b}, String.append(spare, cur)}, SNil{}, acc}

# the last line, with its trailing spaces and tabs left off
def split.finish(st: Split) -> List<&2, String>:
  match st:
    case Split{cur, spare, acc}:
      split.keep(cur, acc)

# one character per step and tail recursive: a CI job log or a CA bundle is megabytes
def split.walk(text: String, st: Split) -> List<&2, String>:
  match text:
    case SNil{}:
      split.finish(st)
    case SCon{Chr{+b}, t}:
      split.walk(t, split.step(st, cls(b), b))

# xs reversed, then ys
def lines.rev.onto(xs: List<&2, String>, ys: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      ys
    case Con{h, t}:
      lines.rev.onto(t, h <> ys)

def lines.rev(xs: List<&2, String>) -> List<&2, String>:
  lines.rev.onto(xs, Nil{})

# text as lines: split on CR and LF, each without its trailing spaces and tabs
def lines(text: String) -> List<&2, String>:
  lines.rev(split.walk(text, Split{SNil{}, SNil{}, Nil{}}))

# xs reversed, then ys
def blocks.rev.onto(xs: List<&2, List<&2, U32>>, ys: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match xs:
    case Nil{}:
      ys
    case Con{h, t}:
      blocks.rev.onto(t, h <> ys)

def blocks.rev(xs: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  blocks.rev.onto(xs, Nil{})

def pem.keep.if(found: List<&2, List<&2, U32>>, got: Maybe<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match got:
    case Some{bytes}:
      bytes <> found
    case None{}:
      found

# a block's body: decoded and kept when it is base64, and skipped when it isn't
def pem.keep(payload: String, found: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  pem.keep.if(found, decode(payload))

def pem.open.if(found: List<&2, List<&2, U32>>, opens: Bool) -> Pem:
  match opens:
    case True{}:
      Pem.Body{SNil{}, found}
    case False{}:
      Pem.Scan{found}

# the state a line outside a block leaves: the BEGIN marker opens one
def pem.open(line: String, begin: String, found: List<&2, List<&2, U32>>) -> Pem:
  pem.open.if(found, String.eq(line, begin))

def pem.step.if(line: String, payload: String, found: List<&2, List<&2, U32>>, closes: Bool) -> Pem:
  match closes:
    case True{}:
      Pem.Scan{pem.keep(String.reverse(payload), found)}
    case False{}:
      Pem.Body{String.append(String.reverse(line), payload), found}

# the state a line inside a block leaves: the END marker closes it, and any other line is
# body text, kept backwards
def pem.step(+line: String, end: String, payload: String, found: List<&2, List<&2, U32>>) -> Pem:
  pem.step.if(line, payload, found, String.eq(line, end))

# the payloads of the blocks the lines hold, in order
def pem.walk(ls: List<&2, String>, st: Pem, +begin: String, +end: String) -> List<&2, List<&2, U32>>:
  match ls st:
    case Nil{} Pem.Scan{found}:
      blocks.rev(found)
    case Nil{} Pem.Body{payload, found}:
      blocks.rev(found)
    case Con{line, t} Pem.Scan{found}:
      pem.walk(t, pem.open(line, begin, found), begin, end)
    case Con{line, t} Pem.Body{payload, found}:
      pem.walk(t, pem.step(line, end, payload, found), begin, end)

# the BEGIN line of a PEM block
def pem.begin(+label: String) -> String:
  "-----BEGIN " ++ label ++ "-----"

# the END line of a PEM block
def pem.end(+label: String) -> String:
  "-----END " ++ label ++ "-----"

# the payload of every "-----BEGIN <label>-----" .. "-----END <label>-----" block in text,
# in order. Text outside them is ignored; a block that doesn't decode is skipped.
def pem(text: String, +label: String) -> List<&2, List<&2, U32>>:
  pem.walk(lines(text), Pem.Scan{Nil{}}, pem.begin(label), pem.end(label))
