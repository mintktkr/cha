# offline checks for cli's flag checks: a flag that takes a value and is given none is
# named, so the command fails loud instead of dropping the flag and its value
import Base
import ../src/cli.bend as Cli

def flags() -> List<&2, String>:
  ["--state", "--limit", "--json"]

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
    expect("missing: --limit at the end of the line", Cli.missing(flags(), ["list", "--limit"]), "--limit")
    expect("missing: --limit before a flag the command reads", Cli.missing(flags(), ["list", "--limit", "--json"]), "--limit")
    expect("missing: --limit= has no value", Cli.missing(flags(), ["list", "--limit="]), "--limit")
    expect("missing: runs logs --step= has no value", Cli.missing(["--job", "--step", "--failed"], ["7", "--step="]), "--step")
    expect("missing: runs rerun --job= has no value", Cli.missing(["--job", "--failed"], ["7", "--job="]), "--job")
    expect("missing: --limit=3 has one", Cli.missing(flags(), ["list", "--limit=3"]), "")
    expect("missing: --limit 3 has one", Cli.missing(flags(), ["list", "--limit", "3"]), "")
    expect("missing: a value that starts with a dash is a value", Cli.missing(flags(), ["list", "--state", "-1 from me"]), "")
    expect("missing: a flag that stands alone needs none", Cli.missing(flags(), ["list", "--json"]), "")
    expect("missing: a word the command doesn't read is a value", Cli.missing(flags(), ["list", "--limit", "--bogus"]), "")
    expect("missing: another command's flag is a value", Cli.missing(["--title"], ["create", "--title", "--limit"]), "")
    expect("missing: the same word when the command reads it", Cli.missing(["--title", "--limit"], ["create", "--title", "--limit"]), "--title")
    expect("missing: -R is a flag everywhere, so it needs a value", Cli.missing(flags(), ["list", "--limit", "-R"]), "--limit")
    expect("missing: no flags at all", Cli.missing(flags(), ["list", "7"]), "")
    expect("missing: every valued flag has one", Cli.missing(flags(), ["list", "--state", "open", "--limit", "2", "--json"]), "")
    expect("missing.msg: the error names the flag", Cli.missing.msg("--limit"), "--limit needs a value")
    expect("missing.msg: runs logs --step= names --step", Cli.missing.msg(Cli.missing(["--job", "--step", "--failed"], ["7", "--step="])), "--step needs a value")
