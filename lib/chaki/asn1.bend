# asn1: DER, one element at a time. A Tlv is one element: the identifier octet, the
# contents, and what follows. read takes the element at the front of a byte list, items
# every element of a constructed value, oid prints an OBJECT IDENTIFIER, uint strips an
# INTEGER's sign padding, and time turns an X.509 Time into Unix seconds. Strict DER:
# low tag numbers only, definite minimal lengths up to 4 length bytes, so a value has
# exactly one encoding here.
import Base
import ./bytes.bend as Bytes
import ./time.bend as Time

# tag: the identifier octet. value: the element's contents. rest: what follows it.
type Tlv is Data:
  Tlv{tag: U32, value: List<&2, U32>, rest: List<&2, U32>}

# Cutting a byte list
# --------------------

# b cut after n bytes: the first n, then the rest
#
# (a private shape: a pair is affine, so it cannot sit inside a Maybe<&2, ..>)
type Cut is Data:
  Cut{head: List<&2, U32>, rest: List<&2, U32>}

def read.split.go(n: Nat, b: List<&2, U32>, acc: List<&2, U32>) -> Maybe<&2, Cut>:
  match n b:
    case 0n rest:
      Some{Cut{Bytes.rev(acc), rest}}
    case 1n+p Nil{}:
      None{}
    case 1n+p Con{h, t}:
      read.split.go(p, t, h <> acc)

# b cut after n bytes: the first n, then the rest. None when b is shorter than n.
def read.split(b: List<&2, U32>, n: Nat) -> Maybe<&2, Cut>:
  read.split.go(n, b, Nil{})

def read.value.split(+id: U32, m: Maybe<&2, Cut>) -> Maybe<&2, Tlv>:
  match m:
    case None{}:
      None{}
    case Some{Cut{value, rest}}:
      Some{Tlv{id, value, rest}}

# an element with contents of n bytes off the front of b
def read.value(+id: U32, n: U32, b: List<&2, U32>) -> Maybe<&2, Tlv>:
  read.value.split(id, read.split(b, U32.to_nat(n)))

# Lengths
# -------

# n length bytes of a long form, as a number, then the rest
#
# (a private shape, for the same reason as Cut)
type Len is Data:
  Len{n: U32, rest: List<&2, U32>}

def read.length.num(n: Nat, b: List<&2, U32>, acc: U32) -> Maybe<&2, Len>:
  match n b:
    case 0n rest:
      Some{Len{acc, rest}}
    case 1n+p Nil{}:
      None{}
    case 1n+p Con{h, t}:
      read.length.num(p, t, U32.or(U32.shln(acc, 8n), h))

# the length a long form gives: at least 128, or the short form would have carried it
def read.length.long.min(+id: U32, ok: Bool, +len: U32, rest: List<&2, U32>) -> Maybe<&2, Tlv>:
  match ok:
    case True{}:
      read.value(id, len, rest)
    case False{}:
      None{}

def read.length.long.num.mk(+id: U32, m: Maybe<&2, Len>) -> Maybe<&2, Tlv>:
  match m:
    case None{}:
      None{}
    case Some{Len{+len, rest}}:
      read.length.long.min(id, U32.is_le(128, len), len, rest)

def read.length.long.num(+id: U32, n: Nat, b: List<&2, U32>) -> Maybe<&2, Tlv>:
  read.length.long.num.mk(id, read.length.num(n, b, 0))

# a long form's first byte is never zero: that would be a non-minimal length
def read.length.long.zero(+id: U32, n: Nat, +h: U32, t: List<&2, U32>, ok: Bool) -> Maybe<&2, Tlv>:
  match ok:
    case True{}:
      read.length.long.num(id, n, h <> t)
    case False{}:
      None{}

def read.length.long.go(+id: U32, n: Nat, b: List<&2, U32>) -> Maybe<&2, Tlv>:
  match b:
    case Nil{}:
      None{}
    case Con{+h, t}:
      read.length.long.zero(id, n, h, t, U32.is_ne(h, 0))

# the count octet's low 7 bits say how many length bytes follow: 1..4, never 0 (that
# would be the indefinite form)
def read.length.long.ok(+h: U32) -> Bool:
  Bool.and(U32.is_ne(U32.and(h, 127), 0), U32.is_le(U32.and(h, 127), 4))

def read.length.long.if(+id: U32, ok: Bool, +h: U32, t: List<&2, U32>) -> Maybe<&2, Tlv>:
  match ok:
    case True{}:
      read.length.long.go(id, U32.to_nat(U32.and(h, 127)), t)
    case False{}:
      None{}

def read.length.long(+id: U32, +h: U32, t: List<&2, U32>) -> Maybe<&2, Tlv>:
  read.length.long.if(id, read.length.long.ok(h), h, t)

def read.length.byte(+id: U32, +h: U32, t: List<&2, U32>, short: Bool) -> Maybe<&2, Tlv>:
  match short:
    case True{}:
      read.value(id, h, t)
    case False{}:
      read.length.long(id, h, t)

def read.length(+id: U32, b: List<&2, U32>) -> Maybe<&2, Tlv>:
  match b:
    case Nil{}:
      None{}
    case Con{+h, t}:
      read.length.byte(id, h, t, U32.is_lt(h, 128))

# Tags
# ----

def read.id.if(+id: U32, b: List<&2, U32>, high: Bool) -> Maybe<&2, Tlv>:
  match high:
    case True{}:
      None{}
    case False{}:
      read.length(id, b)

def read.id(+id: U32, b: List<&2, U32>) -> Maybe<&2, Tlv>:
  read.id.if(id, b, U32.is_eq(U32.and(id, 31), 31))

# one DER element from the front of b; tag is the identifier octet, low-tag-number form only
def read(b: List<&2, U32>) -> Maybe<&2, Tlv>:
  match b:
    case Nil{}:
      None{}
    case Con{id, t}:
      read.id(id, t)

# A constructed value's elements
# ------------------------------

def items.rev.go(xs: List<&2, Tlv>, acc: List<&2, Tlv>) -> List<&2, Tlv>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      items.rev.go(t, h <> acc)

def items.rev(xs: List<&2, Tlv>) -> List<&2, Tlv>:
  items.rev.go(xs, Nil{})

# where a walk over contents is: the rest of the bytes and the elements read so far
type It is Data:
  More{b: List<&2, U32>, acc: List<&2, Tlv>}
  End{acc: List<&2, Tlv>}
  Bad{}

# one byte off the front: nil is the end, anything else must be an element
def it.empty(empty: Bool, +acc: List<&2, Tlv>) -> It:
  match empty:
    case True{}:
      End{acc}
    case False{}:
      Bad{}

def it.got(t: Tlv, rest: List<&2, U32>, acc: List<&2, Tlv>, done: Bool) -> It:
  match done:
    case True{}:
      End{t <> acc}
    case False{}:
      More{rest, t <> acc}

def it.of(+m: Maybe<&2, Tlv>, +b: List<&2, U32>, +acc: List<&2, Tlv>) -> It:
  match m:
    case None{}:
      it.empty(U32.is_zero(Bytes.len(b)), acc)
    case Some{Tlv{+tag, +value, +rest}}:
      it.got(Tlv{tag, value, rest}, rest, acc, U32.is_zero(Bytes.len(rest)))

# fuel is the byte count, so a walk over malformed contents can't spin
def items.go(fuel: Nat, st: It) -> Maybe<&2, List<&2, Tlv>>:
  match fuel st:
    case 0n End{acc}:
      Some{items.rev(acc)}
    case 0n More{_, _}:
      None{}
    case 0n Bad{}:
      None{}
    case 1n+p End{acc}:
      Some{items.rev(acc)}
    case 1n+p More{+b, acc}:
      items.go(p, it.of(read(b), b, acc))
    case 1n+p Bad{}:
      None{}

# every element of a constructed value's contents, in order; None when one doesn't parse
def items(+b: List<&2, U32>) -> Maybe<&2, List<&2, Tlv>>:
  items.go(Nat.add(U32.to_nat(Bytes.len(b)), 1n), More{b, Nil{}})

# OBJECT IDENTIFIERs
# ------------------

# one byte of an OID: its low 7 bits, tagged by whether the high bit ends the arc
type Bit is Data:
  Low{v: U32}
  High{v: U32}

def Bit.of.if(+h: U32, low: Bool) -> Bit:
  match low:
    case True{}:
      Low{U32.and(h, 127)}
    case False{}:
      High{U32.and(h, 127)}

def Bit.of(+h: U32) -> Bit:
  Bit.of.if(h, U32.is_zero(U32.and(h, 128)))

def oid.bits.rev.go(xs: List<&2, Bit>, acc: List<&2, Bit>) -> List<&2, Bit>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      oid.bits.rev.go(t, h <> acc)

def oid.bits.rev(xs: List<&2, Bit>) -> List<&2, Bit>:
  oid.bits.rev.go(xs, Nil{})

def oid.bits(xs: List<&2, U32>, acc: List<&2, Bit>) -> List<&2, Bit>:
  match xs:
    case Nil{}:
      oid.bits.rev(acc)
    case Con{h, t}:
      oid.bits(t, Bit.of(h) <> acc)

# the first arc is (x, y) with 40*x + y its value, x 0..2
def oid.head.big(v: Nat, mid: Bool) -> String:
  match mid:
    case True{}:
      "1." ++ Nat.show(Nat.sub(v, 40n))
    case False{}:
      "2." ++ Nat.show(Nat.sub(v, 80n))

def oid.head.if(+v: Nat, small: Bool) -> String:
  match small:
    case True{}:
      "0." ++ Nat.show(v)
    case False{}:
      oid.head.big(v, Nat.is_lt(v, 80n))

def oid.head(+v: Nat) -> String:
  oid.head.if(v, Nat.is_lt(v, 40n))

def oid.emit(v: Nat, +text: String, first: Bool) -> String:
  match first:
    case True{}:
      oid.head(v)
    case False{}:
      text ++ "." ++ Nat.show(v)

def oid.arcs(bs: List<&2, Bit>, acc: Nat, +text: String, first: Bool) -> String:
  match bs:
    case Nil{}:
      text
    case Con{Low{v}, t}:
      oid.arcs(t, 0n, oid.emit(Nat.add(Nat.mul(acc, 128n), U32.to_nat(v)), text, first), False{})
    case Con{High{v}, t}:
      oid.arcs(t, Nat.add(Nat.mul(acc, 128n), U32.to_nat(v)), text, first)

# an OBJECT IDENTIFIER's contents as dotted text, "1.2.840.113549.1.1.11"
def oid(value: List<&2, U32>) -> String:
  oid.arcs(oid.bits(value, Nil{}), 0n, "", True{})

# INTEGERs
# --------

# xs: the bytes after a value's first byte, h: that byte, zero: h is 0x00
def uint.pad(xs: List<&2, U32>, +h: U32, zero: Bool) -> List<&2, U32>:
  match xs zero:
    case Nil{} True{}:
      [h]
    case Nil{} False{}:
      [h]
    case Con{h2, t2} False{}:
      h <> h2 <> t2
    case Con{+h2, t2} True{}:
      uint.pad(t2, h2, U32.is_zero(h2))

# an INTEGER's contents without the sign padding: an unsigned value, big-endian. A
# value of zero keeps its one byte.
def uint(value: List<&2, U32>) -> List<&2, U32>:
  match value:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      uint.pad(t, h, U32.is_zero(h))

# Times
# -----

# one byte as a decimal digit, or not one
#
# (the byte is classified first, so the walk below can branch with one pattern per case)
type D is Data:
  Digit{v: U32}
  NotDigit{}

def D.of.if(+c: U32, ok: Bool) -> D:
  match ok:
    case True{}:
      Digit{U32.sub(c, 48)}
    case False{}:
      NotDigit{}

def D.of(+c: U32) -> D:
  D.of.if(c, Bool.and(U32.is_le(48, c), U32.is_le(c, 57)))

def digits.classify.rev(xs: List<&2, D>, acc: List<&2, D>) -> List<&2, D>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      digits.classify.rev(t, h <> acc)

def digits.classify(xs: List<&2, U32>, acc: List<&2, D>) -> List<&2, D>:
  match xs:
    case Nil{}:
      digits.classify.rev(acc, Nil{})
    case Con{h, t}:
      digits.classify(t, D.of(h) <> acc)

def digits.values(xs: List<&2, D>, acc: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match xs:
    case Nil{}:
      Some{Bytes.rev(acc)}
    case Con{Digit{v}, t}:
      digits.values(t, v <> acc)
    case Con{NotDigit{}, _}:
      None{}

# each byte as its decimal value, in order; None when one isn't a digit
def digits(xs: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  digits.values(digits.classify(xs, Nil{}), Nil{})

def num2(xs: List<&2, U32>) -> U32:
  match xs:
    case Con{a, Con{b, _}}:
      U32.add(U32.mul(a, 10), b)
    case _:
      0

def num4(xs: List<&2, U32>) -> U32:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, _}}}}:
      U32.add(U32.mul(a, 1000), U32.add(U32.mul(b, 100), U32.add(U32.mul(c, 10), d)))
    case _:
      0

# a year out of UTCTime's two digits: 00..49 is 20YY, 50..99 is 19YY
def year.short(+yy: U32) -> U32:
  Bool.pick(U32, U32.is_lt(yy, 50), (2000 + yy : U32), (1900 + yy : U32))

def in.range(+x: U32, +lo: U32, +hi: U32) -> Bool:
  Bool.and(U32.is_le(lo, x), U32.is_le(x, hi))

# days from 1970-01-01, Howard Hinnant's civil calendar, for a year at or after 1970
def days(+y0: U32, +mon: U32, +day: U32) -> U32:
  +y = Bool.pick(U32, U32.is_le(mon, 2), (y0 - 1 : U32), y0)
  m = Bool.pick(U32, U32.is_le(mon, 2), (mon + 9 : U32), (mon - 3 : U32))
  +era = U32.div(y, 400)
  +yoe = U32.sub(y, U32.mul(era, 400))
  doy = U32.add(U32.div(U32.add(U32.mul(153, m), 2), 5), U32.sub(day, 1))
  doe = U32.add(U32.sub(U32.add(U32.mul(yoe, 365), U32.div(yoe, 4)), U32.div(yoe, 100)), doy)
  U32.sub(U32.add(U32.mul(era, 146097), doe), 719468)

# a UTCTime or GeneralizedTime's fields, before they are range-checked
type Stamp is Data:
  Stamp{year: U32, mon: U32, day: U32, hour: U32, minute: U32, second: U32}

def stamp.ok(s: Stamp) -> Bool:
  match s:
    case Stamp{+year, +mon, +day, hour, minute, second}:
      Bool.and(in.range(year, 1970, 9999), Bool.and(Time.date.valid(year, mon, day), Bool.and(in.range(hour, 0, 23), Bool.and(in.range(minute, 0, 59), in.range(second, 0, 59)))))

# 2106-02-07 06:28:15 is the last second a U32 holds
def stamp.secs.max.if(+tod: U32, ok: Bool) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{U32.sub(4294967295, U32.sub(23295, tod))}
    case False{}:
      None{}

def stamp.secs.max(+tod: U32) -> Maybe<&2, U32>:
  stamp.secs.max.if(tod, U32.is_le(tod, 23295))

def stamp.secs.last.if(+d: U32, +tod: U32, last: Bool) -> Maybe<&2, U32>:
  match last:
    case True{}:
      stamp.secs.max(tod)
    case False{}:
      None{}

def stamp.secs.last(+d: U32, +tod: U32) -> Maybe<&2, U32>:
  stamp.secs.last.if(d, tod, U32.is_eq(d, 49710))

def stamp.secs.of.if(+d: U32, +tod: U32, early: Bool) -> Maybe<&2, U32>:
  match early:
    case True{}:
      Some{U32.add(U32.mul(d, 86400), tod)}
    case False{}:
      stamp.secs.last(d, tod)

# d days after the epoch and tod seconds into the day, as seconds, without wrapping the U32
def stamp.secs.of(+d: U32, +tod: U32) -> Maybe<&2, U32>:
  stamp.secs.of.if(d, tod, U32.is_lt(d, 49710))

def stamp.secs(s: Stamp) -> Maybe<&2, U32>:
  match s:
    case Stamp{year, mon, day, hour, minute, second}:
      d = days(year, mon, day)
      tod = U32.add(U32.add(U32.mul(hour, 3600), U32.mul(minute, 60)), second)
      stamp.secs.of(d, tod)

def stamp.instant.if(+s: Stamp, ok: Bool) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      stamp.secs(s)
    case False{}:
      None{}

# a stamp's Unix seconds; None for a field out of range or a time past 2106
def stamp.instant(+s: Stamp) -> Maybe<&2, U32>:
  stamp.instant.if(s, stamp.ok(s))

# yy mm dd hh mm ss of a UTCTime, as a stamp
def time.utc.make(+xs: List<&2, U32>) -> Stamp:
  Stamp{year.short(num2(xs)), num2(Bytes.drop(xs, 2n)), num2(Bytes.drop(xs, 4n)), num2(Bytes.drop(xs, 6n)), num2(Bytes.drop(xs, 8n)), num2(Bytes.drop(xs, 10n))}

# 12 digits and a Z
def time.utc.ok(+value: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(Bytes.len(value), 13), U32.is_eq(Bytes.get.be(Bytes.drop(value, 12n), 1n), 90))

def time.utc.stamp(m: Maybe<&2, List<&2, U32>>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{xs}:
      stamp.instant(time.utc.make(xs))

def time.utc.go(ok: Bool, +value: List<&2, U32>) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      time.utc.stamp(digits(Bytes.take(value, 12n)))
    case False{}:
      None{}

def time.utc(+value: List<&2, U32>) -> Maybe<&2, U32>:
  time.utc.go(time.utc.ok(value), value)

# yyyy mm dd hh mm ss of a GeneralizedTime, as a stamp
def time.gen.make(+xs: List<&2, U32>) -> Stamp:
  Stamp{num4(xs), num2(Bytes.drop(xs, 4n)), num2(Bytes.drop(xs, 6n)), num2(Bytes.drop(xs, 8n)), num2(Bytes.drop(xs, 10n)), num2(Bytes.drop(xs, 12n))}

# 14 digits and a Z
def time.gen.ok(+value: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(Bytes.len(value), 15), U32.is_eq(Bytes.get.be(Bytes.drop(value, 14n), 1n), 90))

def time.gen.stamp(m: Maybe<&2, List<&2, U32>>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{xs}:
      stamp.instant(time.gen.make(xs))

def time.gen.go(ok: Bool, +value: List<&2, U32>) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      time.gen.stamp(digits(Bytes.take(value, 14n)))
    case False{}:
      None{}

def time.gen(+value: List<&2, U32>) -> Maybe<&2, U32>:
  time.gen.go(time.gen.ok(value), value)

# UTCTime (0x17, YYMMDDHHMMSSZ) or GeneralizedTime (0x18, YYYYMMDDHHMMSSZ) as Unix
# seconds; None for another form, or a time before 1970 or past 2106
def time(tag: U32, value: List<&2, U32>) -> Maybe<&2, U32>:
  match tag:
    case 23:
      time.utc(value)
    case 24:
      time.gen(value)
    case _:
      None{}
