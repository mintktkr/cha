# the --since window: a span like 1d, 6h or 30m, or an explicit RFC 3339 date-time.
# moved and issue list both parse --since here, so there is one parser.
import Base
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time

def whole(i: Time.Instant) -> Time.Instant:
  match i:
    case Time.Instant{s, n}:
      Time.Instant{s, 0}

# an instant as RFC 3339 in UTC, without a fraction, "" when it is out of range
def rfc(i: Time.Instant) -> String:
  Maybe.default(&2, String, Time.rfc3339(whole(i)), "")

# the seconds one unit of --since is worth: d, h, m; 0 when it is none of them
def unit.secs(+u: String) -> U32:
  Bool.pick(U32, String.eq(u, "d"), 86400, Bool.pick(U32, String.eq(u, "h"), 3600, Bool.pick(U32, String.eq(u, "m"), 60, 0)))

def without.last(+s: String) -> String:
  String.take(s, Nat.sub(String.length(s), 1n))

def last(+s: String) -> String:
  String.drop(s, Nat.sub(String.length(s), 1n))

def span.mul.at(n: Maybe<&2, U32>, +secs: U32) -> Maybe<&2, Time.Duration>:
  match n:
    case Some{k}:
      Some{Time.Duration.of_secs(Time.i64((k * secs : U32)))}
    case None{}:
      None{}

# a span like 1d, 6h or 30m, as the duration it covers
def span.mul(n: Maybe<&2, U32>, +secs: U32) -> Maybe<&2, Time.Duration>:
  Bool.pick(Maybe<&2, Time.Duration>, U32.is_eq(secs, 0), None{}, span.mul.at(n, secs))

def span(+arg: String) -> Maybe<&2, Time.Duration>:
  span.mul(U32.read(without.last(arg)), unit.secs(last(arg)))

def pick(back: Maybe<&2, Time.Duration>, +now: Time.Instant, +arg: String) -> Maybe<&2, Time.Instant>:
  match back:
    case Some{d}:
      Some{Time.Instant.add(now, Time.Duration.neg(d))}
    case None{}:
      Time.rfc3339.parse(arg)

# the window --since names: a span back from now, or an explicit RFC 3339 date-time
def of(now: Time.Instant, +arg: String) -> Maybe<&2, Time.Instant>:
  pick(span(arg), now, arg)
