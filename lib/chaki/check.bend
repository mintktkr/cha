# check: the line format every test/chaki_*_check.bend prints. scripts/check.sh fails a
# run on any line that starts with FAIL.
import Base
import ./bytes.bend as Bytes

def report.if(good: Bool, +name: String, +got: String, +want: String) -> String:
  match good:
    case True{}:
      "ok   " ++ name
    case False{}:
      "FAIL " ++ name ++ ": got [" ++ got ++ "], want [" ++ want ++ "]"

def eq(+name: String, +got: String, +want: String) -> String:
  report.if(String.eq(got, want), name, got, want)

def yes(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

def ok(+name: String, b: Bool) -> String:
  eq(name, yes(b), "yes")

# bytes against expected hex; spaces and case in want don't matter
def hex(+name: String, got: List<&2, U32>, want: String) -> String:
  eq(name, Bytes.to_hex(got), Bytes.to_hex(Bytes.of_hex(want)))
