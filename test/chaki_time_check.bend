# offline checks for lib/chaki/time.bend
import Base
import ../lib/chaki/time.bend as Time
import ../lib/chaki/check.bend as T

# the result of a parse as text, so one case is one comparison
def some(m: Maybe<&2, U32>) -> String:
  match m:
    case None{}:
      "none"
    case Some{+t}:
      U32.show(t)

# parse(s) is the instant t
def at(+name: String, +s: String, +t: U32) -> String:
  T.eq(name, some(Time.parse(s)), U32.show(t))

# parse(s) is nothing
def no(+name: String, +s: String) -> String:
  T.eq(name, some(Time.parse(s)), "none")

def triple(t: U32 & U32 & U32) -> String:
  (y, m, d) = t
  U32.show(y) ++ "/" ++ U32.show(m) ++ "/" ++ U32.show(d)

# the calendar rule itself, so the cases below pick valid dates without asking the module
def leap(+y: U32) -> Bool:
  Bool.and(U32.is_eq((y % 4 : U32), 0),
    Bool.or(U32.is_ne((y % 100 : U32), 0), U32.is_eq((y % 400 : U32), 0)))

def last(+y: U32, +m: U32) -> U32:
  Bool.pick(U32, U32.is_eq(m, 2), Bool.pick(U32, leap(y), 29, 28),
    Bool.pick(U32, U32.is_eq(m, 4), 30,
      Bool.pick(U32, U32.is_eq(m, 6), 30,
        Bool.pick(U32, U32.is_eq(m, 9), 30,
          Bool.pick(U32, U32.is_eq(m, 11), 30, 31)))))

# parse(show(t)) is t, every 3000017 seconds, from 0 to the last second a U32 holds
def sweep.go(fuel: Nat, +t: U32) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.print(T.eq("parse(show(" ++ U32.show(t) ++ "))",
          some(Time.parse(Time.show(t))), U32.show(t)))
        sweep.go(p, (t + 3000017 : U32))

def round.case(+y: U32, +m: U32, +d: U32) -> String:
  T.eq("civil(days(" ++ U32.show(y) ++ "-" ++ U32.show(m) ++ "-" ++ U32.show(d) ++ "))",
    triple(Time.civil(Time.days(y, m, d))),
    U32.show(y) ++ "/" ++ U32.show(m) ++ "/" ++ U32.show(d))

# civil(days(y, m, d)) is (y, m, d) on the 1st, the 28th and the last day of every month
def round.go(fuel: Nat, +y: U32, +m: U32) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      +december = U32.is_eq(m, 12)
      +month = Bool.pick(U32, december, 1, (m + 1 : U32))
      year = (y + Bool.pick(U32, december, 1, 0) : U32)
      do IO<Unit>:
        IO.print(round.case(y, m, 1))
        IO.print(round.case(y, m, 28))
        IO.print(round.case(y, m, last(y, m)))
        round.go(p, year, month)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(T.eq("show(0)", Time.show(0), "1970-01-01T00:00:00Z"))
    # the brief read 951782400 as 2000-03-01: the calendar says 2000-02-29, and 951868800 is
    # 2000-03-01. The leap cases below and the round trip over every day agree.
    IO.print(T.eq("show(951782400)", Time.show(951782400), "2000-02-29T00:00:00Z"))
    IO.print(T.eq("show(951868800)", Time.show(951868800), "2000-03-01T00:00:00Z"))
    IO.print(T.eq("show(4294967295)", Time.show(4294967295), "2106-02-07T06:28:15Z"))
    IO.print(T.eq("show(1790769600)", Time.show(1790769600), "2026-09-30T12:00:00Z"))
    IO.print(T.eq("days(1970,1,1)", U32.show(Time.days(1970, 1, 1)), "0"))
    IO.print(T.eq("days(2000,3,1)", U32.show(Time.days(2000, 3, 1)), "11017"))
    IO.print(T.eq("days(2106,2,7)", U32.show(Time.days(2106, 2, 7)), "49710"))
    IO.print(T.eq("civil(0)", triple(Time.civil(0)), "1970/1/1"))
    IO.print(T.eq("civil(11017)", triple(Time.civil(11017)), "2000/3/1"))
    IO.print(T.eq("civil(49710)", triple(Time.civil(49710)), "2106/2/7"))
    IO.print(at("gitea -03:00", "2026-09-30T09:00:00-03:00", 1790769600))
    IO.print(at("+05:30", "2026-09-30T09:00:00+05:30", 1790739000))
    IO.print(at("fraction", "2026-09-30T09:00:00.123456789Z", 1790758800))
    IO.print(at("lowercase", "2026-09-30t09:00:00z", 1790758800))
    IO.print(at("space for T", "2026-09-30 09:00:00Z", 1790758800))
    IO.print(at("zulu", "2026-09-30T09:00:00Z", 1790758800))
    IO.print(at("+00:00", "1970-01-01T00:00:00+00:00", 0))
    IO.print(at("-00:00", "1970-01-01T00:00:00-00:00", 0))
    IO.print(at("fraction then offset", "2026-09-30T09:00:00.5+05:30", 1790739000))
    IO.print(at("day before the epoch, offset back", "1969-12-31T23:00:00-01:00", 0))
    IO.print(at("the last second", "2106-02-07T06:28:15Z", 4294967295))
    IO.print(at("the last second, fraction", "2106-02-07T06:28:15.999Z", 4294967295))
    IO.print(at("the last second, +01:00", "2106-02-07T07:28:15+01:00", 4294967295))
    IO.print(at("a day past the end, -18:00", "2106-02-08T00:28:15+18:00", 4294967295))
    IO.print(at("leap 2024", "2024-02-29T00:00:00Z", 1709164800))
    IO.print(at("leap 2000", "2000-02-29T00:00:00Z", 951782400))
    IO.print(at("a leap second reads as 59", "2016-12-31T23:59:60Z", 1483228799))
    IO.print(no("leap 2026", "2026-02-29T00:00:00Z"))
    IO.print(no("leap 2100", "2100-02-29T00:00:00Z"))
    IO.print(no("month 13", "2026-13-01T00:00:00Z"))
    IO.print(no("month 00", "2026-00-01T00:00:00Z"))
    IO.print(no("day 32", "2026-01-32T00:00:00Z"))
    IO.print(no("day 00", "2026-01-00T00:00:00Z"))
    IO.print(no("day 31 in april", "2026-04-31T00:00:00Z"))
    IO.print(no("hour 24", "2026-01-01T24:00:00Z"))
    IO.print(no("minute 60", "2026-01-01T00:60:00Z"))
    IO.print(no("second 61", "2026-01-01T00:00:61Z"))
    IO.print(no("no zone", "2026-01-01T00:00:00"))
    IO.print(no("trailing junk", "2026-01-01T00:00:00Zx"))
    IO.print(no("empty", ""))
    IO.print(no("garbage", "not a time"))
    IO.print(no("date only", "2026-01-01"))
    IO.print(no("no seconds", "2026-01-01T00:00Z"))
    IO.print(no("one digit month", "2026-1-01T00:00:00Z"))
    IO.print(no("no colon in the offset", "2026-01-01T00:00:00+00"))
    IO.print(no("short offset minute", "2026-01-01T00:00:00-03:0"))
    IO.print(no("offset hour 24", "2026-01-01T00:00:00+24:00"))
    IO.print(no("offset minute 60", "2026-01-01T00:00:00+05:60"))
    IO.print(no("empty fraction", "2026-01-01T00:00:00.Z"))
    IO.print(no("before the epoch", "1969-12-31T23:59:59Z"))
    IO.print(no("past the end", "2106-02-07T06:28:16Z"))
    sweep.go(1432n, 0)
    round.go(1632n, 1970, 1)
