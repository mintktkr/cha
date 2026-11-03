# lane: time

Wall-clock arithmetic. An instant is Unix seconds in a `U32` (good until 2106-02-07), which
keeps defs narrow for native builds. Howard Hinnant's `days_from_civil` /
`civil_from_days` are the model.

## Files you own

`lib/chaki/time.bend`, `test/chaki_time_check.bend`.

## API (exact)

```python
# RFC 3339: YYYY-MM-DDTHH:MM:SS[.fraction](Z|+HH:MM|-HH:MM). 't' and 'z' are accepted, and
# so is a space for the T. The fraction is dropped and the offset applied. None when it's
# malformed, out of range (day past the month's end, hour 24, ..) or outside
# 1970-01-01T00:00:00Z .. 2106-02-07T06:28:15Z. A second of 60 reads as 59.
def parse(s: String) -> Maybe<&2, U32>

# "YYYY-MM-DDTHH:MM:SSZ"
def show(t: U32) -> String

# days since 1970-01-01 for a valid civil date from 1970 on
def days(y: U32, m: U32, d: U32) -> U32

# the civil date (y, m, d) of a day count
def civil(days: U32) -> U32 & U32 & U32
```

## Checks

`test/chaki_time_check.bend`:

- 0 is `1970-01-01T00:00:00Z`, 951782400 is `2000-03-01T00:00:00Z`, and 4294967295 is
  `2106-02-07T06:28:15Z`.
- `parse(show(t)) == Some(t)` for t every 3,000,017 seconds from 0 to the end (about 1,400
  cases), and `civil(days(y,m,d))` round-trips on the 1st, 28th and last day of every month
  from 1970 to 2105.
- Gitea's style `2026-09-30T09:00:00-03:00` is `2026-09-30T12:00:00Z`; `+05:30` too; a
  fraction (`.123456789Z`); lowercase; a space separator.
- Leap years: 2024-02-29 is valid, 2026-02-29 isn't, 2000-02-29 is, 2100-02-29 isn't.
- Invalid: month 13, day 32, hour 24, minute 60, a missing zone, trailing garbage, an empty
  string, 1969-12-31T23:59:59Z, and 2106-02-07T06:28:16Z.
