# laws: what the pure core must keep. Each law is a claim; PROOF.bend proves it.
# They cover the three things a wrong turn would break quietly: colour off must leave text
# unchanged, the string and flag helpers must behave at their edges, and a remote URL must
# parse to the repo it names.
import Base
import ./src/ui.bend as Ui
import ./src/ctx.bend as Ctx
import ./src/cli.bend as Cli
import ./src/api.bend as Api

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
