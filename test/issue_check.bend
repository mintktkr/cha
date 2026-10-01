# offline checks for issue's pure helpers: names, percent-encoding, label ids and op codes
import Base
import ../src/cmd/issue.bend as Issue

def row.of(+id: String, +name: String) -> Map<&2, String>:
  Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), "id", id), "name", name)

def report.if(good: Bool, +name: String, +got: String, +want: String) -> String:
  match good:
    case True{}:
      "ok   " ++ name
    case False{}:
      "FAIL " ++ name ++ ": got [" ++ got ++ "], want [" ++ want ++ "]"

def report(good: Bool, +name: String, +got: String, +want: String) -> String:
  report.if(good, name, got, want)

def check(+name: String, +got: String, +want: String) -> String:
  report(String.eq(got, want), name, got, want)

def main() -> IO(Unit):
  do IO<Unit>:
    +rows : List<&2, Map<&2, String>> = Con{row.of("34", "bug"), Con{row.of("35", "ready"), Nil{}}}
    IO.print(check("split.names trims, drops blanks", String.join(Issue.split.names(" bug ,, ready "), ","), "bug,ready"))
    IO.print(check("split.names of nothing", String.join(Issue.split.names(""), ","), ""))
    IO.print(check("enc.seg keeps unreserved", Issue.enc.seg("bug_1.2~3"), "bug_1.2~3"))
    IO.print(check("enc.seg encodes space and slash", Issue.enc.seg("good first issue/a"), "good%20first%20issue%2Fa"))
    IO.print(check("labels.op add", Nat.show(Issue.labels.op("add")), "0"))
    IO.print(check("labels.op remove", Nat.show(Issue.labels.op("remove")), "1"))
    IO.print(check("labels.op set", Nat.show(Issue.labels.op("set")), "2"))
    IO.print(check("labels.op unknown", Nat.show(Issue.labels.op("nope")), "3"))
    IO.print(check("ids.of finds each name", String.join(Issue.ids.of(Con{"ready", Con{"bug", Nil{}}}, rows), ","), "35,34"))
    IO.print(check("ids.of leaves an unknown name blank", String.join(Issue.ids.of(Con{"nope", Con{"bug", Nil{}}}, rows), ","), ",34"))
    IO.print(check("miss names the unknown ones", Issue.miss(Con{"bug", Con{"nope", Con{"x", Nil{}}}}, Con{"34", Con{"", Con{"", Nil{}}}}), "nope, x"))
