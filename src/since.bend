# the --since window: a span like 1d, 6h or 30m, or an explicit RFC 3339 date-time.
# moved and issue list both parse --since here, so there is one parser.
import Base
import ../lib/chaki/time.bend as Time

# an instant (Unix seconds) as RFC 3339 in UTC
def rfc(+t: U32) -> String:
  Time.show(t)

# the seconds one unit of --since is worth: d, h, m; 0 when it is none of them
def unit.secs(+u: String) -> U32:
  Bool.pick(U32, String.eq(u, "d"), 86400, Bool.pick(U32, String.eq(u, "h"), 3600, Bool.pick(U32, String.eq(u, "m"), 60, 0)))

def without.last(+s: String) -> String:
  String.take(s, Nat.sub(String.length(s), 1n))

def last(+s: String) -> String:
  String.drop(s, Nat.sub(String.length(s), 1n))

# k units of secs, or none when the unit is unknown or the product won't fit a U32
def span.mul.at(+k: U32, +secs: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, Bool.or(U32.is_eq(secs, 0), U32.is_gt(k, U32.div(4294967295, secs))), None{}, Some{(k * secs : U32)})

def span.mul(n: Maybe<&2, U32>, +secs: U32) -> Maybe<&2, U32>:
  match n:
    case Some{+k}:
      span.mul.at(k, secs)
    case None{}:
      None{}

# a span like 1d, 6h or 30m, as the seconds it covers
def span(+arg: String) -> Maybe<&2, U32>:
  span.mul(U32.read(without.last(arg)), unit.secs(last(arg)))

# now less d, held at the epoch
def back(+now: U32, +d: U32) -> U32:
  Bool.pick(U32, U32.is_lt(now, d), 0, (now - d : U32))

def pick(got: Maybe<&2, U32>, +now: U32, +arg: String) -> Maybe<&2, U32>:
  match got:
    case Some{+d}:
      Some{back(now, d)}
    case None{}:
      Time.parse(arg)

# the window --since names: a span back from now, or an explicit RFC 3339 date-time
def of(+now: U32, +arg: String) -> Maybe<&2, U32>:
  pick(span(arg), now, arg)
