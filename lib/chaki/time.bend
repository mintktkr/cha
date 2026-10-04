# time: instants as Unix seconds in a U32, good until 2106-02-07T06:28:15Z, and the RFC 3339
# text around them. The calendar arithmetic is Howard Hinnant's days_from_civil and
# civil_from_days, with the year starting in March so every day count stays positive.
import Base

# Calendar
# --------

# a leap year in the proleptic Gregorian calendar
def leap(+y: U32) -> Bool:
  Bool.and(U32.is_eq((y % 4 : U32), 0),
    Bool.or(U32.is_ne((y % 100 : U32), 0), U32.is_eq((y % 400 : U32), 0)))

# the days of a month, 0 for a month outside 1..12
def month.len(+y: U32, +m: U32) -> U32:
  Bool.pick(U32, U32.is_eq(m, 2), Bool.pick(U32, leap(y), 29, 28),
    Bool.pick(U32, Bool.and(U32.is_ge(m, 1), U32.is_le(m, 12)),
      (30 + ((m + (m >> 3n)) .&. 1) : U32), 0))

# month 1..12, and a day inside that month
def date.valid(+y: U32, +mo: U32, +d: U32) -> Bool:
  Bool.and(U32.is_ge(mo, 1), Bool.and(U32.is_le(mo, 12),
    Bool.and(U32.is_ge(d, 1), U32.is_le(d, month.len(y, mo)))))

def days.era(+y: U32, +m: U32, +d: U32) -> U32:
  +era = (y / 400 : U32)
  +yoe = (y - era * 400 : U32)
  +doy = ((153 * m + 2) / 5 + d - 1 : U32)
  (era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468 : U32)

# a date whose March starts the year, so january and february belong to y - 1
def days.at(+y: U32, +m: U32, +d: U32, jan: Bool) -> U32:
  match jan:
    case True{}:
      days.era((y - 1 : U32), (m + 9 : U32), d)
    case False{}:
      days.era(y, (m - 3 : U32), d)

# days since 1970-01-01 for a valid civil date from 1970 on
def days(y: U32, +m: U32, d: U32) -> U32:
  days.at(y, m, d, U32.is_le(m, 2))

def civil.if(early: Bool, +y: U32, +mp: U32, +d: U32) -> U32 & U32 & U32:
  match early:
    case True{}:
      (y, (mp + 3 : U32), d)
    case False{}:
      ((y + 1 : U32), (mp - 9 : U32), d)

# the March-based day count 719468 is 1970-01-01
def civil.at(+z: U32) -> U32 & U32 & U32:
  +era = (z / 146097 : U32)
  +doe = (z - era * 146097 : U32)
  +yoe = ((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 : U32)
  +doy = (doe - (365 * yoe + yoe / 4 - yoe / 100) : U32)
  +mp = ((5 * doy + 2) / 153 : U32)
  civil.if(U32.is_lt(mp, 10), (yoe + era * 400 : U32), mp,
    (doy - (153 * mp + 2) / 5 + 1 : U32))

# the civil date (y, m, d) of a day count
def civil(days: U32) -> U32 & U32 & U32:
  civil.at((days + 719468 : U32))

# Text
# ----

def pad.go(k: Nat, +s: String) -> String:
  match k:
    case 0n:
      s
    case 1n+p:
      pad.go(p, SCon{Chr{48}, s})

# x in decimal, left-padded with zeros to w characters
def pad(+x: U32, +w: Nat) -> String:
  +s = U32.show(x)
  pad.go(Nat.sub(w, String.length(s)), s)

def show.civil(t: U32 & U32 & U32, +sod: U32) -> String:
  (y, mo, d) = t
  pad(y, 4n) ++ "-" ++ pad(mo, 2n) ++ "-" ++ pad(d, 2n) ++ "T" ++
    pad((sod / 3600 : U32), 2n) ++ ":" ++ pad((sod / 60 % 60 : U32), 2n) ++ ":" ++
    pad((sod % 60 : U32), 2n) ++ "Z"

def show.at(+days: U32, +sod: U32) -> String:
  show.civil(civil(days), sod)

# "YYYY-MM-DDTHH:MM:SSZ"
def show(+t: U32) -> String:
  show.at((t / 86400 : U32), (t % 86400 : U32))

# Parsing
# -------

# a stamp being read: the numbers taken so far, newest first, and the text left
type P is Data:
  P{vals: List<&2, U32>, rest: String}

# a number read, and the text left after it
type Num is Data:
  Num{val: U32, rest: String}

def is_digit(+c: U32) -> Bool:
  Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57))

# whether s starts with a decimal digit
def head.digit(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+c}, t}:
      is_digit(c)

def digits.fin(ok: Bool, +acc: U32, +rest: String) -> Maybe<&2, Num>:
  match ok:
    case True{}:
      Some{Num{acc, rest}}
    case False{}:
      None{}

# n decimal digits as a number and the rest. ok says every digit read so far was one: the
# walk reads n characters whatever they are, so a wrong one never ends it early.
def digits(n: Nat, +s: String, +acc: U32, ok: Bool) -> Maybe<&2, Num>:
  match n:
    case 0n:
      digits.fin(ok, acc, s)
    case 1n+p:
      match s:
        case SNil{}:
          None{}
        case SCon{Chr{+c}, +t}:
          digits(p, t, (acc * 10 + c - 48 : U32), Bool.and(ok, is_digit(c)))

# P with rest pushed on, or None
def keep(+vs: List<&2, U32>, +rest: String, ok: Bool) -> Maybe<&2, P>:
  match ok:
    case True{}:
      Some{P{vs, rest}}
    case False{}:
      None{}

def push(vs: List<&2, U32>, r: Maybe<&2, Num>) -> Maybe<&2, P>:
  match r:
    case None{}:
      None{}
    case Some{Num{val, rest}}:
      Some{P{Con{val, vs}, rest}}

def num(n: Nat, p: P) -> Maybe<&2, P>:
  match p:
    case P{vs, s}:
      push(vs, digits(n, s, 0, True{}))

# exactly one character equal to c
def lit(+c: U32, p: P) -> Maybe<&2, P>:
  match p:
    case P{vs, s}:
      match s:
        case SNil{}:
          None{}
        case SCon{Chr{+x}, +t}:
          keep(vs, t, U32.is_eq(x, c))

# 'T', 't' or a space, between the date and the time
def sep(p: P) -> Maybe<&2, P>:
  match p:
    case P{vs, s}:
      match s:
        case SNil{}:
          None{}
        case SCon{Chr{+c}, +t}:
          keep(vs, t, Bool.or(U32.is_eq(c, 84),
            Bool.or(U32.is_eq(c, 116), U32.is_eq(c, 32))))

# d says whether the first character of s is a digit: how many digits s starts with, and
# the text from the first character that isn't one
def frac.go(+s: String, d: Bool, +n: U32) -> U32 & String:
  match s:
    case SNil{}:
      (n, SNil{})
    case SCon{Chr{+c}, +t}:
      match d:
        case True{}:
          frac.go(t, head.digit(t), (n + 1 : U32))
        case False{}:
          (n, SCon{Chr{c}, t})

def frac.if(ok: Bool, +rest: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{rest}
    case False{}:
      None{}

# the rest after the fraction's digits, from the pair frac.go answers
def frac.at.of(p: U32 & String) -> Maybe<&2, String>:
  (n, rest) = p
  frac.if(U32.is_gt(n, 0), rest)

# one or more digits, which the fraction of a second is dropped from
def frac.at(+s: String) -> Maybe<&2, String>:
  frac.at.of(frac.go(s, head.digit(s), 0))

def dot.frac(+vs: List<&2, U32>, r: Maybe<&2, String>) -> Maybe<&2, P>:
  match r:
    case None{}:
      None{}
    case Some{rest}:
      Some{P{vs, rest}}

def dot.if(dotted: Bool, +vs: List<&2, U32>, +c: U32, +t: String) -> Maybe<&2, P>:
  match dotted:
    case True{}:
      dot.frac(vs, frac.at(t))
    case False{}:
      Some{P{vs, SCon{Chr{c}, t}}}

# '.' and the digits after it, dropped, or the stamp as it was
def dot(p: P) -> Maybe<&2, P>:
  match p:
    case P{vs, s}:
      match s:
        case SNil{}:
          Some{P{vs, SNil{}}}
        case SCon{Chr{+c}, +t}:
          dot.if(U32.is_eq(c, 46), vs, c, t)

# HH:MM of an offset, behind being 1 for a time behind UTC
def zone.num(+behind: U32, vs: List<&2, U32>, +t: String) -> Maybe<&2, P>:
  do Maybe<&2, P>:
    a : P <- num(2n, P{Con{behind, vs}, t})
    b : P <- lit(58, a)
    num(2n, b)

def zone.if(zulu: Bool, plus: Bool, minus: Bool, vs: List<&2, U32>, +t: String) -> Maybe<&2, P>:
  match zulu:
    case True{}:
      Some{P{Con{0, Con{0, Con{0, vs}}}, t}}
    case False{}:
      match plus:
        case True{}:
          zone.num(0, vs, t)
        case False{}:
          match minus:
            case True{}:
              zone.num(1, vs, t)
            case False{}:
              None{}

# Z, z, +HH:MM or -HH:MM, as (behind, hh, mm)
def zone(p: P) -> Maybe<&2, P>:
  match p:
    case P{vs, s}:
      match s:
        case SNil{}:
          None{}
        case SCon{Chr{+c}, +t}:
          zone.if(Bool.or(U32.is_eq(c, 90), U32.is_eq(c, 122)),
            U32.is_eq(c, 43), U32.is_eq(c, 45), vs, t)

# An instant
# ----------

def shift.if(+days: U32, +t: U32, over: Bool) -> U32 & U32:
  match over:
    case True{}:
      ((days + 1 : U32), (t - 86400 : U32))
    case False{}:
      (days, t)

# days and seconds of day, one day on
def shift.behind(+days: U32, +sod: U32, +off: U32) -> U32 & U32:
  +t = (sod + off : U32)
  shift.if(days, t, U32.is_ge(t, 86400))

def shift.under(+days: U32, +t: U32, under: Bool) -> U32 & U32:
  match under:
    case True{}:
      ((days - 1 : U32), (t + 86400 : U32))
    case False{}:
      (days, t)

# days and seconds of day, one day back
def shift.ahead(+days: U32, +sod: U32, +off: U32) -> U32 & U32:
  shift.under(days, (sod - off : U32), U32.is_lt(sod, off))

# the UTC day and second of day of a local wall time that is behind UTC
def shift(behind: Bool, +days: U32, +sod: U32, +off: U32) -> U32 & U32:
  match behind:
    case True{}:
      shift.behind(days, sod, off)
    case False{}:
      shift.ahead(days, sod, off)

def inside.if(+days: U32, +sod: U32, past: Bool) -> Maybe<&2, U32>:
  match past:
    case True{}:
      None{}
    case False{}:
      Some{(days * 86400 + sod : U32)}

# 49710 days is 2106-02-07 and 23295 seconds is 06:28:15, the last instant a U32 holds
def inside(+days: U32, +sod: U32) -> Maybe<&2, U32>:
  inside.if(days, sod, Bool.or(U32.is_gt(days, 49710),
    Bool.and(U32.is_eq(days, 49710), U32.is_gt(sod, 23295))))

def instant.at(p: U32 & U32) -> Maybe<&2, U32>:
  (d, s) = p
  inside(d, s)

# the instant a local wall time and its offset denote
def instant(behind: Bool, +days: U32, +sod: U32, +off: U32) -> Maybe<&2, U32>:
  instant.at(shift(behind, days, sod, off))

def stamp.day.if(+y: U32, +mo: U32, +d: U32, ok: Bool) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{days(y, mo, d)}
    case False{}:
      None{}

# the day count of a valid civil date
def stamp.day(+y: U32, +mo: U32, +d: U32) -> Maybe<&2, U32>:
  stamp.day.if(y, mo, d, date.valid(y, mo, d))

# a second of 60, a leap second, reads as 59
def stamp.sec(+s: U32) -> U32:
  Bool.pick(U32, U32.is_eq(s, 60), 59, s)

def stamp.sod.if(+h: U32, +mi: U32, +s: U32, ok: Bool) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{(h * 3600 + mi * 60 + stamp.sec(s) : U32)}
    case False{}:
      None{}

def stamp.sod(+h: U32, +mi: U32, +s: U32) -> Maybe<&2, U32>:
  stamp.sod.if(h, mi, s,
    Bool.and(U32.is_le(h, 23), Bool.and(U32.is_le(mi, 59), U32.is_le(s, 60))))

def stamp.off.if(+hh: U32, +mm: U32, ok: Bool) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{(hh * 3600 + mm * 60 : U32)}
    case False{}:
      None{}

# the seconds of a +HH:MM offset
def stamp.off(+hh: U32, +mm: U32) -> Maybe<&2, U32>:
  stamp.off.if(hh, mm, Bool.and(U32.is_le(hh, 23), U32.is_le(mm, 59)))

# the instant a stamp denotes, once its fields have been read
def stamp(+y: U32, +mo: U32, +d: U32, +h: U32, +mi: U32, +s: U32, +behind: U32,
  +hh: U32, +mm: U32) -> Maybe<&2, U32>:
  do Maybe<&2, U32>:
    day : U32 <- stamp.day(y, mo, d)
    sod : U32 <- stamp.sod(h, mi, s)
    off : U32 <- stamp.off(hh, mm)
    instant(U32.is_eq(behind, 1), day, sod, off)

def parse.fin(p: P) -> Maybe<&2, U32>:
  match p:
    case P{Con{mm, Con{hh, Con{behind, Con{s, Con{mi, Con{h, Con{d,
      Con{mo, Con{y, Nil{}}}}}}}}}}, SNil{}}:
      stamp(y, mo, d, h, mi, s, behind, hh, mm)
    case _:
      None{}

def parse.go(+s: String) -> Maybe<&2, U32>:
  do Maybe<&2, U32>:
    a : P <- num(4n, P{Nil{}, s})
    b : P <- lit(45, a)
    c : P <- num(2n, b)
    d : P <- lit(45, c)
    e : P <- num(2n, d)
    f : P <- sep(e)
    g : P <- num(2n, f)
    h : P <- lit(58, g)
    i : P <- num(2n, h)
    j : P <- lit(58, i)
    k : P <- num(2n, j)
    l : P <- dot(k)
    m : P <- zone(l)
    parse.fin(m)

# RFC 3339: YYYY-MM-DDTHH:MM:SS[.fraction](Z|+HH:MM|-HH:MM). 't' and 'z' are accepted, and
# so is a space for the T. The fraction is dropped and the offset applied. None when it's
# malformed, out of range (day past the month's end, hour 24, ..) or outside
# 1970-01-01T00:00:00Z .. 2106-02-07T06:28:15Z. A second of 60 reads as 59.
def parse(s: String) -> Maybe<&2, U32>:
  parse.go(s)
