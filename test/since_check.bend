# offline checks for the shared --since parser: moved and issue list both read it here
import Base
import ../lib/chaki/sys.bend as Sys
import ../src/since.bend as Since

# 2026-09-30T12:00:00Z, so every window below is fixed text
def NOW() -> U32:
  1790769600

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
def window.of(m: Maybe<&2, U32>, +none: String) -> String:
  match m:
    case Some{t}:
      Since.rfc(t)
    case None{}:
      none

def window(+arg: String) -> String:
  window.of(Since.of(NOW(), arg), "none")

def earlier.if(m: Maybe<&2, U32>, +now: U32) -> Bool:
  match m:
    case Some{t}:
      U32.is_lt(t, now)
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
    IO.print(check("a span past the epoch holds at it", window("30000d"), "1970-01-01T00:00:00Z"))
    IO.print(check("a span too big for a U32 is none", window("99999999d"), "none"))
    +now : U32 <- Sys.now()
    IO.print(check("a span lands before now", yes(earlier.if(Since.of(now, "6h"), now)), "yes"))
