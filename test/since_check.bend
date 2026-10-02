# offline checks for the shared --since parser: moved and issue list both read it here
import Base
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time
import ../src/since.bend as Since

# 2026-09-30T12:00:00Z, so every window below is fixed text
def NOW() -> Time.Instant:
  Time.Instant{Time.i64(1790769600), 0}

def report.if(good: Bool, +name: String, +got: String, +want: String) -> String:
  match good:
    case True{}:
      "ok   " ++ name
    case False{}:
      "FAIL " ++ name ++ ": got [" ++ got ++ "], want [" ++ want ++ "]"

def check(+name: String, +got: String, +want: String) -> String:
  report.if(String.eq(got, want), name, got, want)

# yes or no, for a check whose value is a Bool
def yes(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

# the window below as text, or none when it doesn't parse
def window.of(m: Maybe<&2, Time.Instant>, +none: String) -> String:
  match m:
    case Some{i}:
      Since.rfc(i)
    case None{}:
      none

def window(+arg: String) -> String:
  window.of(Since.of(NOW(), arg), "none")

# whether a is earlier than b
def before.if(c: Cmp) -> Bool:
  match c:
    case LT{}:
      True{}
    case x:
      False{}

def earlier.if(m: Maybe<&2, Time.Instant>, +now: Time.Instant) -> Bool:
  match m:
    case Some{i}:
      before.if(Time.Instant.cmp(i, now))
    case None{}:
      False{}

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(check("1d is a day back", window("1d"), "2026-09-29T12:00:00Z"))
    IO.print(check("6h is six hours back", window("6h"), "2026-09-30T06:00:00Z"))
    IO.print(check("30m is half an hour back", window("30m"), "2026-09-30T11:30:00Z"))
    IO.print(check("an RFC 3339 time parses", window("2026-09-30T12:00:00Z"), "2026-09-30T12:00:00Z"))
    IO.print(check("a time with an offset parses", window("2026-09-30T09:00:00-03:00"), "2026-09-30T12:00:00Z"))
    IO.print(check("5x is none", window("5x"), "none"))
    IO.print(check("1y is none", window("1y"), "none"))
    IO.print(check("an empty window is none", window(""), "none"))
    +now : Time.Instant <- Time.now()
    IO.print(check("a span lands before now", yes(earlier.if(Since.of(now, "6h"), now)), "yes"))
