import Base
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time
import ../src/cmd/moved.bend as Moved

# 2026-09-30T12:00:00Z, so every window below is fixed text
def NOW() -> Time.Instant:
  Time.Instant{Time.i64(1790769600), 0}

# a key and a value, so the rows below stay one line each
type KV is Data:
  KV{k: String, v: String}

def window.of(m: Maybe<&2, Time.Instant>, +none: String) -> String:
  match m:
    case Some{i}:
      Moved.rfc(i)
    case None{}:
      none

def window(+arg: String) -> String:
  window.of(Moved.since.of(NOW(), arg), "none")

def put.all(kvs: List<&2, KV>, m: Map<&2, String>) -> Map<&2, String>:
  match kvs:
    case Nil{}:
      m
    case Con{KV{k, v}, t}:
      put.all(t, Map.set(&2, String, m, k, v))

def row(kvs: List<&2, KV>) -> Map<&2, String>:
  put.all(kvs, Map.new(&2, String))

def sweep() -> Moved.Sections:
  Moved.Sections{
    Moved.Section{"issues and pull requests", [row([KV{"number", "7"}, KV{"state", "open"}, KV{"title", "a title"}, KV{"user.login", "memu"}])], ""},
    Moved.Section{"new comments", Nil{}, ""},
    Moved.Section{"commits on main", [row([KV{"short", "abc1234"}, KV{"author", "memu"}, KV{"subject", "a subject"}])], ""},
    Moved.Section{"actions runs", [row([KV{"state", "failure"}, KV{"workflow", "ci.yml"}, KV{"branch", "main"}])], ""},
  }

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("1d   " ++ window("1d"))
    IO.print("6h   " ++ window("6h"))
    IO.print("30m  " ++ window("30m"))
    IO.print("iso  " ++ window("2026-09-30T12:00:00Z"))
    IO.print("bad  " ++ window("5x"))
    IO.print(Moved.text(False{}, "2026-09-30T12:00:00Z", sweep()))
    IO.print(Moved.json.text("2026-09-30T12:00:00Z", sweep()))
