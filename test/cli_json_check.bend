# offline checks for cli's --json field selection: json.of, json.strip, split.fields,
# json.unknown, json.pick and json.bad
import Base
import ../src/cli.bend as Cli

def cmds() -> List<&2, String>:
  ["issue", "pr"]

def joined(xs: List<&2, String>) -> String:
  String.join(xs, ",")

def sel(j: Cli.Json) -> String:
  match j:
    case Cli.Off{}:
      "off"
    case Cli.All{}:
      "all"
    case Cli.Only{+fs}:
      "only:" ++ joined(fs)

def check.if(+name: String, +got: String, +want: String, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      IO.print("ok  " ++ name)
    case False{}:
      do IO<Unit>:
        IO.print("bad " ++ name ++ ": got [" ++ got ++ "] want [" ++ want ++ "]")
        IO.die(Unit, 1, "")

def expect(+name: String, +got: String, +want: String) -> IO(Unit):
  check.if(name, got, want, String.eq(got, want))

def main() -> IO(Unit):
  do IO<Unit>:
    expect("json.of: the word after --json is a command", sel(Cli.json.of(["--json", "issue", "list"], cmds())), "all")
    expect("json.of: a field list after --json", sel(Cli.json.of(["issue", "list", "--json", "number,title"], cmds())), "only:number,title")
    expect("json.of: --json= trims and drops blanks", sel(Cli.json.of(["--json=a, b,"], cmds())), "only:a,b")
    expect("json.of: no --json", sel(Cli.json.of(["issue", "list"], cmds())), "off")
    expect("json.of: a flag after --json", sel(Cli.json.of(["issue", "list", "--json", "--state", "open"], cmds())), "all")
    expect("json.of: --json with nothing after it", sel(Cli.json.of(["issue", "list", "--json"], cmds())), "all")
    expect("json.of: an empty inline list", sel(Cli.json.of(["--json="], cmds())), "all")
    expect("json.strip: drops --json and its field word", joined(Cli.json.strip(["issue", "list", "--json", "number,title"], cmds())), "issue,list")
    expect("json.strip: drops a bare --json", joined(Cli.json.strip(["--json", "issue", "list"], cmds())), "issue,list")
    expect("json.strip: keeps a flag after --json", joined(Cli.json.strip(["issue", "list", "--json", "--state", "open"], cmds())), "issue,list,--state,open")
    expect("json.strip: keeps everything before a trailing --json", joined(Cli.json.strip(["issue", "list", "--json"], cmds())), "issue,list")
    expect("json.strip: drops an inline list", joined(Cli.json.strip(["issue", "--json=a,b", "list"], cmds())), "issue,list")
    expect("split.fields trims and drops blanks", joined(Cli.split.fields(" a ,,b ")), "a,b")
    expect("split.fields of nothing", joined(Cli.split.fields("")), "")
    expect("json.unknown names the first bad field", Cli.json.unknown(["number", "nope"], ["number", "title"]), "nope")
    expect("json.unknown is blank when every field is valid", Cli.json.unknown(["number"], ["number"]), "")
    expect("json.unknown of an empty selection", Cli.json.unknown(Nil{}, ["number"]), "")
    expect("json.pick falls back to the defaults", joined(Cli.json.pick(Nil{}, ["x"])), "x")
    expect("json.pick keeps a selection", joined(Cli.json.pick(["number"], ["x"])), "number")
    expect("json.bad names the valid fields", Cli.json.bad("nope", ["number", "title"]), "unknown JSON field nope; valid fields: number, title")
