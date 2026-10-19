# laws: what the pure core must keep. Each law is a claim; PROOF.bend proves it.
# They cover the four things a wrong turn would break quietly: colour off must leave text
# unchanged, the string and flag helpers must behave at their edges, a remote URL must
# parse to the repo it names, and a runner id must not reach a path with anything but digits.
import Base
import ./src/clean.bend as Clean
import ./src/ui.bend as Ui
import ./src/ctx.bend as Ctx
import ./src/cli.bend as Cli
import ./src/api.bend as Api
import ./src/cmd/runners.bend as Runners

# Colour off
# ----------
# With colour off every style is the identity, so piped output stays plain and no escape
# sequence can leak.

# LAW: styled text with colour off is the text.
law styled_off:
  for o: String
  for c: String
  for s: String
  {Ui.styled(False{}, o, c, s) == s : String}

# LAW: fg with colour off is the text.
law fg_off:
  for c: Ui.Rgb
  for s: String
  {Ui.fg(False{}, c, s) == s : String}

# LAW: bold with colour off is the text.
law bold_off:
  for s: String
  {Ui.bold(False{}, s) == s : String}

# LAW: dim with colour off is the text.
law dim_off:
  for s: String
  {Ui.dim(False{}, s) == s : String}

# LAW: a forge state with colour off is its label.
law state_off:
  for +s: String
  {Ui.state(False{}, s) == s : String}

# LAW: the glow gradient with colour off is the text.
law glow_off:
  for +s: String
  {Ui.glow(False{}, s) == s : String}

# or
# --
# or picks a unless it is empty.

# LAW: a non-empty a wins.
law or_left:
  for c: Char
  for t: String
  for b: String
  {Ctx.or(SCon{c, t}, b) == SCon{c, t} : String}

# LAW: an empty a falls through to b.
law or_empty:
  for b: String
  {Ctx.or("", b) == b : String}

# Flags
# -----
# An absent argument list means the flag is missing and takes its default.

# LAW: has is False when there is nothing to search.
law has_nil:
  for name: String
  {Cli.has(Nil{}, name) == False{} : Bool}

# LAW: flag gives the default when there is nothing to search.
law flag_empty:
  for name: String
  for dflt: String
  {Cli.flag(Nil{}, name, dflt) == dflt : String}

# LAW: a flag the command doesn't read is named, so it can fail loud instead of vanishing
# with its value.
law unknown_flag:
  {Cli.unknown(["--state"], ["--state", "open", "--limit", "3"]) == ["--limit"] : List<&2, String>}

# LAW: a flag is judged by its name before any =, so --limit=3 can't slip past as one word.
law unknown_flag_eq:
  {Cli.unknown(["--state"], ["--state=open", "--limit=3"]) == ["--limit"] : List<&2, String>}

# LAW: -h and --help are never unknown, even to a command that reads no flags.
law unknown_flag_help:
  {Cli.unknown(Nil{}, ["-h", "--help"]) == Nil{} : List<&2, String>}

# LAW: a flag that takes a value and is given none is named, so it can fail loud instead of
# vanishing. At the end of the line:
law missing_flag_end:
  {Cli.missing(["--limit"], ["list", "--limit"]) == "--limit" : String}

# LAW: ...or before a flag the command reads:
law missing_flag_next:
  {Cli.missing(["--limit", "--json"], ["list", "--limit", "--json"]) == "--limit" : String}

# LAW: ...or with nothing after its =:
law missing_flag_blank:
  {Cli.missing(["--limit"], ["list", "--limit="]) == "--limit" : String}

# LAW: a value that starts with a dash is a value, not a flag without one.
law missing_flag_dash:
  {Cli.missing(["--body"], ["--body", "-1 from me"]) == "" : String}

# LAW: a word that is not a flag the command reads is a value, so --title "--limit" keeps
# its title.
law missing_flag_other:
  {Cli.missing(["--title"], ["--title", "--limit"]) == "" : String}

# Concrete examples
# -----------------

# LAW: a scp-shaped remote parses to its forge, host, owner and name.
law parse_remote_scp:
  {Ctx.parse_remote("git@github.com:mintktkr/cha.git") == Some{Ctx.Repo{Ctx.GitHub{}, "github.com", "mintktkr", "cha"}} : Maybe<&2, Ctx.Repo>}

# Secrets
# -------
# A token can sit in a remote URL (https://user:token@host/...). The repo parsed from it
# must not carry it, since the host reaches URLs and error messages.

# LAW: an https remote's user and token are dropped.
law parse_remote_drops_credentials:
  {Ctx.parse_remote("https://x:SECRET@github.com/o/r.git") == Some{Ctx.Repo{Ctx.GitHub{}, "github.com", "o", "r"}} : Maybe<&2, Ctx.Repo>}

# LAW: a bare token before the host is dropped too.
law parse_remote_drops_token:
  {Ctx.parse_remote("https://SECRET@example.org/o/r") == Some{Ctx.Repo{Ctx.Gitea{}, "example.org", "o", "r"}} : Maybe<&2, Ctx.Repo>}

# LAW: a Link header without rel="next" has no next page.
law link_no_next:
  {Api.link.next("</issues?page=2>; rel=\"last\"") == "" : String}

# LAW: a Link header with rel="next" yields that URL.
law link_next_url:
  {Api.link.next("</issues?page=2>; rel=\"next\", </issues?page=5>; rel=\"last\"") == "/issues?page=2" : String}

# Terminal escape
# ---------------
# Forge text reaches a terminal through Clean.text, which drops escape sequences and
# control bytes, so a title, a body, a label or a CI log line cannot move the cursor,
# clear the screen, retitle the window or open a hyperlink, and cannot redraw a line.

# LAW: a CSI (an SGR colour, a screen clear) is dropped whole.
law clean_csi:
  {Clean.text("a\u{1b}[1;31mred\u{1b}[2Jb") == "aredb" : String}

# LAW: an OSC is dropped whole, up to its BEL.
law clean_osc_bel:
  {Clean.text("\u{1b}]8;;https://example.com\u{7}link") == "link" : String}

# LAW: an OSC ends at ESC backslash too.
law clean_osc_st:
  {Clean.text("\u{1b}]0;title\u{1b}\\ok") == "ok" : String}

# LAW: an escape inside an escape sequence opens another one, so a doubled ESC cannot
# hide the sequence after it.
law clean_esc_esc:
  {Clean.text("a\u{1b}\u{1b}[2Jb") == "ab" : String}

# LAW: a carriage return is dropped, and one before a newline is that newline.
law clean_cr:
  {Clean.text("a\rb\r\nc\rd") == "ab\ncd" : String}

# LAW: control bytes, DEL and a C1 control are dropped; tab and newline are kept.
law clean_controls:
  {Clean.text("a\u{0}b\tc\nd\u{7f}e\u{85}f") == "ab\tc\ndef" : String}

# LAW: a character that is neither a control nor an escape is kept.
law clean_plain:
  {Clean.text("茶 (´∀｀)♡ 🍵") == "茶 (´∀｀)♡ 🍵" : String}

# LAW: a field printed on one line keeps to it: a newline or a tab becomes a space, after
# the escapes are gone, so a title can't start a row of its own.
law clean_line:
  {Clean.line("a\nb\tc\r\nd\u{1b}[2J") == "a b c d" : String}

# Runner ids
# ----------
# A runner id reaches a URL path, so it must be digits only: "1/registration-token"
# would otherwise name one of the scope's other endpoints.

# LAW: a digit string is a runner id.
law runner_id_digits:
  {Runners.digits("1234") == True{} : Bool}

# LAW: a path, a letter or a space in a runner id is refused.
law runner_id_not_digits:
  {Runners.digits("1/registration-token") == False{} : Bool}
