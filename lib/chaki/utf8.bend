# utf8: UTF-8, the encoding every request and response travels in. encode turns a String
# into bytes; decode turns bytes back into text, repairing ill-formed input the way the
# Unicode Standard's chapter 3 ("U+FFFD Substitution of Maximal Subparts") and WHATWG's
# decoder do, one U+FFFD for each maximal ill-formed subpart. The decoder is Björn
# Höhrmann's DFA: a byte is first mapped to a class, because Bend cannot match a U32, and
# one tableless state machine then walks the classes. Every loop here is a tail call; a CA
# bundle is 220 KB of PEM.
import Base
import ./bytes.bend as Bytes

# The classes, and the state of a sequence being read
# --------------------------------------------------

# a byte's class. 0xE0, 0xED, 0xF0 and 0xF4 need no class of their own: the decoder reads
# their range from the byte itself when it starts a sequence.
type Utf8.Cell is Data:
  Utf8.Ascii{}  # 0x00..0x7F
  Utf8.Cont{}   # 0x80..0xBF, a continuation byte
  Utf8.Two{}    # 0xC2..0xDF
  Utf8.Three{}  # 0xE0..0xEF
  Utf8.Four{}   # 0xF0..0xF4
  Utf8.Bad{}    # 0xC0, 0xC1, 0xF5..0xFF: never a valid start

# the sequence being read: S0 is a boundary, and Pend is a sequence missing `need`
# continuation bytes, whose next one must fall in lo..hi
type Utf8.Part is Data:
  Utf8.S0{}
  Utf8.Pend{need: Nat, cp: U32, lo: U32, hi: U32}

# everything one byte moves: the sequence being read, the text so far built backwards, and
# whether every byte so far was well-formed
type Utf8.State is Data:
  Utf8.State{part: Utf8.Part, out: String, ok: Bool}

# U+FFFD, the replacement character
def replacement() -> U32:
  65533

# Classifying
# -----------
# A def only sees the defs above it, so the deepest helper of the classifier comes first:
# each one reads one comparison off the ladder and hands the byte down.

# 0xF5..0xFF would name a value past U+10FFFF
def kind.four(+b: U32, four: Bool) -> Utf8.Cell:
  match four:
    case True{}:
      Utf8.Four{}
    case False{}:
      Utf8.Bad{}

def kind.three(+b: U32, three: Bool) -> Utf8.Cell:
  match three:
    case True{}:
      Utf8.Three{}
    case False{}:
      kind.four(b, U32.is_le(b, 244))

# 0xC0 and 0xC1 would only name an overlong two-byte sequence
def kind.two(+b: U32, overlong: Bool) -> Utf8.Cell:
  match overlong:
    case True{}:
      Utf8.Bad{}
    case False{}:
      Utf8.Two{}

# 0xC0..0xFF: a lead byte at last, or one too large to be a lead byte
def kind.lead(+b: U32, two: Bool) -> Utf8.Cell:
  match two:
    case True{}:
      kind.two(b, U32.is_le(b, 193))
    case False{}:
      kind.three(b, U32.is_le(b, 239))

# 0x80..0xBF is a continuation byte: never the start of a sequence
def kind.hi(+b: U32, cont: Bool) -> Utf8.Cell:
  match cont:
    case True{}:
      Utf8.Cont{}
    case False{}:
      kind.lead(b, U32.is_le(b, 223))

# 0x00..0x7F is ASCII: a sequence of one
def kind.ascii(+b: U32, ascii: Bool) -> Utf8.Cell:
  match ascii:
    case True{}:
      Utf8.Ascii{}
    case False{}:
      kind.hi(b, U32.is_le(b, 191))

# a byte's class
def kind(+b: U32) -> Utf8.Cell:
  kind.ascii(b, U32.is_le(b, 127))

# Encoding
# --------

# whether a Char's code is a Unicode scalar value: not a surrogate, not past U+10FFFF.
# Bend's runtime refuses to build any other kind of Char, so this is what keeps encode's
# promise to U+FFFD for a Char that slipped in from elsewhere.
def scalar.ok(+c: U32) -> Bool:
  Bool.and(U32.is_le(c, 1114111), Bool.not(Bool.and(U32.is_le(55296, c), U32.is_le(c, 57343))))

# the low six bits of c as a continuation byte
def sextet(+c: U32) -> U32:
  U32.or(128, U32.and(c, 63))

def encode.four(+c: U32, acc: List<&2, U32>) -> List<&2, U32>:
  sextet(c) <> (sextet(U32.shrn(c, 6n)) <> (sextet(U32.shrn(c, 12n)) <> (U32.or(240, U32.shrn(c, 18n)) <> acc)))

def encode.three.if(+c: U32, acc: List<&2, U32>, three: Bool) -> List<&2, U32>:
  match three:
    case True{}:
      sextet(c) <> (sextet(U32.shrn(c, 6n)) <> (U32.or(224, U32.shrn(c, 12n)) <> acc))
    case False{}:
      encode.four(c, acc)

def encode.three(+c: U32, acc: List<&2, U32>) -> List<&2, U32>:
  encode.three.if(c, acc, U32.is_le(c, 65535))

def encode.two.if(+c: U32, acc: List<&2, U32>, two: Bool) -> List<&2, U32>:
  match two:
    case True{}:
      sextet(c) <> (U32.or(192, U32.shrn(c, 6n)) <> acc)
    case False{}:
      encode.three(c, acc)

def encode.two(+c: U32, acc: List<&2, U32>) -> List<&2, U32>:
  encode.two.if(c, acc, U32.is_le(c, 2047))

def encode.scalar.if(+c: U32, acc: List<&2, U32>, ascii: Bool) -> List<&2, U32>:
  match ascii:
    case True{}:
      c <> acc
    case False{}:
      encode.two(c, acc)

# a scalar value's UTF-8 bytes, least significant first: acc holds the output backwards
def encode.scalar(+c: U32, acc: List<&2, U32>) -> List<&2, U32>:
  encode.scalar.if(c, acc, U32.is_le(c, 127))

def encode.pick(+c: U32, acc: List<&2, U32>, good: Bool) -> List<&2, U32>:
  match good:
    case True{}:
      encode.scalar(c, acc)
    case False{}:
      encode.scalar(replacement(), acc)

# one Char's UTF-8 bytes into a reversed accumulator; a code that isn't a scalar value
# becomes U+FFFD's bytes
def encode.one(+c: U32, acc: List<&2, U32>) -> List<&2, U32>:
  encode.pick(c, acc, scalar.ok(c))

def encode.go(s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      encode.go(t, encode.one(c, acc))

# a String's UTF-8 bytes
def encode(s: String) -> List<&2, U32>:
  Bytes.rev(encode.go(s, Nil{}))

# Decoding
# --------

# whether b falls in lo..hi, the range a pending sequence's next byte must fall in
def fits(+b: U32, lo: U32, hi: U32) -> Bool:
  Bool.and(U32.is_le(lo, b), U32.is_le(b, hi))

# the six bits b adds to a pending sequence
def combine(cp: U32, +b: U32) -> U32:
  U32.or(U32.shln(cp, 6n), U32.and(b, 63))

# a continuation byte in range: it completes the sequence, or leaves a shorter one pending
def consumes(need: Nat, cp: U32, b: U32, out: String, ok: Bool) -> Utf8.State:
  match need:
    case 1n:
      Utf8.State{Utf8.S0{}, SCon{Chr{combine(cp, b)}, out}, ok}
    case 2n:
      Utf8.State{Utf8.Pend{1n, combine(cp, b), 128, 191}, out, ok}
    case 3n:
      Utf8.State{Utf8.Pend{2n, combine(cp, b), 128, 191}, out, ok}
    case _:
      Utf8.State{Utf8.S0{}, out, False{}}

def lead.three.ed(b: U32, out: String, ok: Bool, ed: Bool) -> Utf8.State:
  match ed:
    case True{}:
      Utf8.State{Utf8.Pend{2n, U32.and(b, 15), 128, 159}, out, ok}
    case False{}:
      Utf8.State{Utf8.Pend{2n, U32.and(b, 15), 128, 191}, out, ok}

# a three-byte lead: 0xE0 must be followed by 0xA0..0xBF, or it would name an overlong
# sequence, and 0xED by 0x80..0x9F, leaving the surrogates out
def lead.three(+b: U32, out: String, ok: Bool, e0: Bool) -> Utf8.State:
  match e0:
    case True{}:
      Utf8.State{Utf8.Pend{2n, U32.and(b, 15), 160, 191}, out, ok}
    case False{}:
      lead.three.ed(b, out, ok, U32.is_eq(b, 237))

def lead.four.f4(b: U32, out: String, ok: Bool, f4: Bool) -> Utf8.State:
  match f4:
    case True{}:
      Utf8.State{Utf8.Pend{3n, U32.and(b, 7), 128, 143}, out, ok}
    case False{}:
      Utf8.State{Utf8.Pend{3n, U32.and(b, 7), 128, 191}, out, ok}

# a four-byte lead: 0xF0 must be followed by 0x90..0xBF, or it would name an overlong
# sequence, and 0xF4 stays below 0x90, so nothing names a value past U+10FFFF
def lead.four(+b: U32, out: String, ok: Bool, f0: Bool) -> Utf8.State:
  match f0:
    case True{}:
      Utf8.State{Utf8.Pend{3n, U32.and(b, 7), 144, 191}, out, ok}
    case False{}:
      lead.four.f4(b, out, ok, U32.is_eq(b, 244))

# a byte at a boundary: the sequence it opens, and the characters it adds. A stray
# continuation byte, or one that can never start a sequence, is one U+FFFD.
def fresh(c: Utf8.Cell, +b: U32, out: String, ok: Bool) -> Utf8.State:
  match c:
    case Utf8.Ascii{}:
      Utf8.State{Utf8.S0{}, SCon{Chr{b}, out}, ok}
    case Utf8.Cont{}:
      Utf8.State{Utf8.S0{}, SCon{Chr{replacement()}, out}, False{}}
    case Utf8.Bad{}:
      Utf8.State{Utf8.S0{}, SCon{Chr{replacement()}, out}, False{}}
    case Utf8.Two{}:
      Utf8.State{Utf8.Pend{1n, U32.and(b, 31), 128, 191}, out, ok}
    case Utf8.Three{}:
      lead.three(b, out, ok, U32.is_eq(b, 224))
    case Utf8.Four{}:
      lead.four(b, out, ok, U32.is_eq(b, 240))

def cont.if(c: Utf8.Cell, +b: U32, need: Nat, cp: U32, out: String, ok: Bool, inside: Bool) -> Utf8.State:
  match inside:
    case True{}:
      consumes(need, cp, b, out, ok)
    case False{}:
      fresh(c, b, SCon{Chr{replacement()}, out}, False{})

# a byte while a sequence is pending: in the state's range it continues the sequence;
# outside it the pending sequence ends as one U+FFFD and the byte starts a new sequence
def cont(c: Utf8.Cell, +b: U32, need: Nat, cp: U32, lo: U32, hi: U32, out: String, ok: Bool) -> Utf8.State:
  cont.if(c, b, need, cp, out, ok, fits(b, lo, hi))

# one byte, whatever the state: everything it moves
def feed(st: Utf8.State, c: Utf8.Cell, +b: U32) -> Utf8.State:
  match st:
    case Utf8.State{part, out, ok}:
      match part:
        case Utf8.S0{}:
          fresh(c, b, out, ok)
        case Utf8.Pend{need, cp, lo, hi}:
          cont(c, b, need, cp, lo, hi, out, ok)

# a sequence left open by the end of the input is one more maximal subpart
def decode.tail(part: Utf8.Part, out: String) -> String:
  match part:
    case Utf8.S0{}:
      out
    case _:
      SCon{Chr{replacement()}, out}

def decode.flush(st: Utf8.State) -> String:
  match st:
    case Utf8.State{part, out, ok}:
      String.reverse(decode.tail(part, out))

def decode.go(b: List<&2, U32>, st: Utf8.State) -> String:
  match b:
    case Nil{}:
      decode.flush(st)
    case Con{+x, t}:
      decode.go(t, feed(st, kind(x), x))

# bytes as text: each maximal ill-formed subpart becomes one U+FFFD
def decode(b: List<&2, U32>) -> String:
  decode.go(b, Utf8.State{Utf8.S0{}, SNil{}, True{}})

# Validation
# ----------

# whether the decoder is at a boundary: no sequence is pending
def at.start(part: Utf8.Part) -> Bool:
  match part:
    case Utf8.S0{}:
      True{}
    case _:
      False{}

def valid.end(st: Utf8.State) -> Bool:
  match st:
    case Utf8.State{part, out, ok}:
      Bool.and(ok, at.start(part))

def valid.go(b: List<&2, U32>, st: Utf8.State) -> Bool:
  match b:
    case Nil{}:
      valid.end(st)
    case Con{+x, t}:
      valid.go(t, feed(st, kind(x), x))

# whether b is well-formed UTF-8: no overlongs, no surrogates, nothing past U+10FFFF
def valid(b: List<&2, U32>) -> Bool:
  valid.go(b, Utf8.State{Utf8.S0{}, SNil{}, True{}})
