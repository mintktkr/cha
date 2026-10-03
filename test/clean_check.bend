# offline checks for the terminal sanitizer: escape sequences and control bytes in forge
# text never reach a terminal. Run: bend test/clean_check.bend
import Base
import 0xcfc8be7b076f41f95c8e118383892d55/encoding.bend as Enc
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time
import ../src/clean.bend as Clean
import ../src/api.bend as Api
import ../src/cli.bend as Cli
import ../src/ctx.bend as Ctx
import ../src/cmd/repo.bend as Repo
import ../src/cmd/pr.bend as Diff
import ../src/cmd/runs.bend as Runs
import ../src/cmd/runners.bend as Runners
import ../src/cmd/moved.bend as Moved

def expect.if(+label: String, +got: String, +want: String, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      IO.print("ok  " ++ label)
    case False{}:
      do IO<Unit>:
        IO.print("bad " ++ label ++ ": " ++ got ++ " != " ++ want)
        IO.die(Unit, 1, "")

def expect(+label: String, +got: String, +want: String) -> IO(Unit):
  expect.if(label, got, want, String.eq(got, want))

# one field row, as Api.rows flattens one
def row(+title: String) -> Map<&2, String>:
  Map.set(&2, String, Map.new(&2, String), "title", title)

# a source row as the forge answers one: one raw field under k
def src(+k: String, +v: String) -> Map<&2, String>:
  Map.set(&2, String, Map.new(&2, String), k, v)

# a row a command built itself, not one the forge sent
def built.run(+name: String) -> Map<&2, String>:
  Runs.run.row(src("name", name), "", Ctx.GitHub{}, Time.Instant.epoch())

def built.runner(+name: String) -> Map<&2, String>:
  Runners.runner.row(src("name", name), "")

def built.commit(+message: String) -> Map<&2, String>:
  Moved.with.subject(src("commit.message", message))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("sequences")
    expect("CSI colour is dropped whole", Clean.text("a\u{1b}[1;31mred\u{1b}[0m"), "ared")
    expect("CSI clear screen is dropped whole", Clean.text("x\u{1b}[2Jy"), "xy")
    expect("CSI cursor home is dropped whole", Clean.text("\u{1b}[10;20Hok"), "ok")
    expect("CSI with a leading parameter byte", Clean.text("a\u{1b}[?25lb"), "ab")
    expect("OSC 8 hyperlink ends at BEL", Clean.text("\u{1b}]8;;https://example.com\u{7}link\u{1b}]8;;\u{7}"), "link")
    expect("OSC 8 hyperlink ends at ESC backslash", Clean.text("\u{1b}]8;;https://example.com\u{1b}\\link\u{1b}]8;;\u{1b}\\"), "link")
    expect("OSC title ends at BEL", Clean.text("\u{1b}]0;spoofed\u{7}ok"), "ok")
    expect("an OSC that never ends drops the rest", Clean.text("a\u{1b}]8;;x"), "a")
    expect("any other ESC and its character", Clean.text("a\u{1b}cb"), "ab")
    expect("two ESCs before a CSI", Clean.text("a\u{1b}\u{1b}[2Jb"), "ab")
    expect("a C1 CSI loses its introducer", Clean.text("a\u{9b}2Jb"), "a2Jb")
    expect("an ESC at the end", Clean.text("a\u{1b}"), "a")
    IO.print("bytes")
    expect("a bare carriage return is dropped", Clean.text("a\rb"), "ab")
    expect("a carriage return before a newline is that newline", Clean.text("a\r\nb"), "a\nb")
    expect("NUL is dropped", Clean.text("a\u{0}b"), "ab")
    expect("DEL is dropped", Clean.text("a\u{7f}b"), "ab")
    expect("a C1 control is dropped", Clean.text("a\u{85}b"), "ab")
    expect("tab is kept", Clean.text("a\tb"), "a\tb")
    expect("newline is kept", Clean.text("a\nb"), "a\nb")
    expect("emoji and CJK are kept", Clean.text("茶 (´∀｀)♡ 🍵"), "茶 (´∀｀)♡ 🍵")
    expect("plain text is unchanged", Clean.text("hello world"), "hello world")
    expect("nothing left to print", Clean.text("\u{1b}[2J"), "")
    expect("cleaning twice changes nothing", Clean.text(Clean.text("a\u{1b}[31mred")), "ared")
    IO.print("boundaries")
    expect("a row field is clean for a terminal", Api.f(row("a\u{1b}[31mred"), "title"), "ared")
    expect("--json keeps the field as the forge sent it, escaped", Cli.json.row(row("a\u{1b}[31mred"), ["title"]), "{\"title\":\"a\\u001b[31mred\"}")
    expect("a reply body is clean for a terminal", Api.text(Enc.utf8.encode("a\u{1b}[2Jb")), "ab")
    expect("raw.text keeps the body byte-exact", Api.raw.text(Enc.utf8.encode("a\u{1b}[2Jb")), "a\u{1b}[2Jb")
    IO.print("raw content")
    expect("a file printed to a terminal is cleaned", Repo.file.text(Enc.utf8.encode("a\u{1b}[2Jb"), True{}), "ab")
    expect("a file redirected keeps its bytes", Repo.file.text(Enc.utf8.encode("a\u{1b}[2Jb"), False{}), "a\u{1b}[2Jb")
    expect("a diff printed to a terminal is cleaned", Diff.diff.text(Enc.utf8.encode("+\u{1b}[32mgreen"), True{}), "+green")
    expect("a diff redirected keeps its bytes", Diff.diff.text(Enc.utf8.encode("+\u{1b}[32mgreen"), False{}), "+\u{1b}[32mgreen")
    IO.print("built rows")
    expect("a built run row holds the forge's bytes", Cli.json.row(built.run("a\u{1b}[2Jb"), ["name"]), "{\"name\":\"a\\u001b[2Jb\"}")
    expect("a built run row prints clean", Api.f(built.run("a\u{1b}[2Jb"), "name"), "ab")
    expect("a built runner row holds the forge's bytes", Cli.json.row(built.runner("a\u{1b}[31mred"), ["name"]), "{\"name\":\"a\\u001b[31mred\"}")
    expect("a built runner row prints clean", Api.f(built.runner("a\u{1b}[31mred"), "name"), "ared")
    expect("a built commit row holds the forge's bytes", Cli.json.row(built.commit("a\u{1b}[31mred"), ["subject"]), "{\"subject\":\"a\\u001b[31mred\"}")
    expect("a built commit row prints clean", Api.f(built.commit("a\u{1b}[31mred"), "subject"), "ared")
