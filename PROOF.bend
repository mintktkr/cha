# proof: every claim in LAWS.bend. `bend PROOF.bend` prints ALL PROOFS CHECK once this holds.
import Base
import ./src/clean.bend as Clean
import ./src/ui.bend as Ui
import ./src/ctx.bend as Ctx
import ./src/cli.bend as Cli
import ./src/api.bend as Api
import ./LAWS.bend as Laws

# Colour off
# ----------

def Laws.styled_off(o, c, s):
  {==}

# fg takes the colour apart before it styles, so the proof takes it apart too
def Laws.fg_off(c, s):
  match c:
    case Ui.Rgb{r, g, b}:
      {==}

# the colour of one glow step, as glow spells it
def step_color(i: U32, n: U32) -> Ui.Rgb:
  Ui.stop(((i * 6) / n : U32))

# fg with colour off is the text, for a colour that is not yet a constructor
def fg_off_at(i: U32, n: U32, s: String) -> {Ui.fg(False{}, step_color(i, n), s) == s : String}:
  Laws.fg_off(step_color(i, n), s)

def Laws.bold_off(s):
  {==}

def Laws.dim_off(s):
  {==}

# state.of is the branch after the label is classified: colour off there means every branch
# returns the text
def state_of_off(s: String, k: Nat) -> {Ui.state.of(False{}, s, k) == s : String}:
  match k:
    case 0n:
      {==}
    case 1n:
      {==}
    case 2n:
      {==}
    case 3n:
      {==}
    case 4n+p:
      {==}

def Laws.state_off(s):
  state_of_off(s, Ui.state.kind(String.to_lower(s)))

# glow colours one character at a time: induction is on the character list, the head step
# leans on fg_off, and the from_list of the whole list is the text again
def chars_of(cs: List<&2, Char>) -> String:
  match cs:
    case Nil{}:
      ""
    case Con{c, t}:
      SCon{c, chars_of(t)}

def glow_step(c: Char, t: List<&2, Char>, +i: U32, +n: U32) ->
  {Ui.glow.go(Con{c, t}, False{}, i, n) == SCon{c, Ui.glow.go(t, False{}, (i + 1 : U32), n)} : String}:
  Equal.trans(
    String,
    String.append(Ui.fg(False{}, step_color(i, n), SCon{c, ""}), Ui.glow.go(t, False{}, (i + 1 : U32), n)),
    String.append(SCon{c, ""}, Ui.glow.go(t, False{}, (i + 1 : U32), n)),
    SCon{c, Ui.glow.go(t, False{}, (i + 1 : U32), n)},
    Equal.cong(
      String, String,
      y => String.append(y, Ui.glow.go(t, False{}, (i + 1 : U32), n)),
      Ui.fg(False{}, step_color(i, n), SCon{c, ""}),
      SCon{c, ""},
      fg_off_at(i, n, SCon{c, ""})
    ),
    {==}
  )

def glow_go_off(cs: List<&2, Char>, +i: U32, +n: U32) -> {Ui.glow.go(cs, False{}, i, n) == chars_of(cs) : String}:
  match cs:
    case Nil{}:
      {==}
    case Con{+c, +t}:
      Equal.trans(
        String,
        Ui.glow.go(Con{c, t}, False{}, i, n),
        SCon{c, Ui.glow.go(t, False{}, (i + 1 : U32), n)},
        SCon{c, chars_of(t)},
        glow_step(c, t, i, n),
        Equal.cong(String, String, x => SCon{c, x}, Ui.glow.go(t, False{}, (i + 1 : U32), n), chars_of(t), glow_go_off(t, (i + 1 : U32), n))
      )

def chars_roundtrip(s: String) -> {chars_of(String.to_list(s)) == s : String}:
  match s:
    case SNil{}:
      {==}
    case SCon{+c, +t}:
      Equal.cong(String, String, x => SCon{c, x}, chars_of(String.to_list(t)), t, chars_roundtrip(t))

def Laws.glow_off(s):
  +n = (U32.max(U32.from_nat(Nat.sub(String.length(s), 1n)), 1) : U32)
  Equal.trans(String, Ui.glow.go(String.to_list(s), False{}, 0, n), chars_of(String.to_list(s)), s, glow_go_off(String.to_list(s), 0, n), chars_roundtrip(s))

# or
# --

def Laws.or_left(c, t, b):
  {==}

def Laws.or_empty(b):
  {==}

# Flags
# -----

def Laws.has_nil(name):
  {==}

def Laws.flag_empty(name, dflt):
  {==}

# Concrete examples
# -----------------

def Laws.parse_remote_scp():
  {==}

def Laws.parse_remote_drops_credentials():
  {==}

def Laws.parse_remote_drops_token():
  {==}

def Laws.link_no_next():
  {==}

def Laws.link_next_url():
  {==}

# Terminal escape
# ---------------
# Each law is one path through the walk, so reflexivity is the whole proof: both sides
# normalize to the same text once Clean.text has dropped what the walk drops.

def Laws.clean_csi():
  {==}

def Laws.clean_osc_bel():
  {==}

def Laws.clean_osc_st():
  {==}

def Laws.clean_esc_esc():
  {==}

def Laws.clean_cr():
  {==}

def Laws.clean_controls():
  {==}

def Laws.clean_plain():
  {==}
