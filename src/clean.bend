# clean: forge text safe for a terminal. A title, a body, a label, a branch name or a CI
# log line arrives with whatever bytes its author put there, and a terminal that obeys
# them rewrites or spoofs what cha printed: CSI moves the cursor and clears the screen,
# OSC opens a hyperlink or retitles the window, and a carriage return redraws a line.
# Clean.text drops those and the control bytes, and keeps every other character.
#
# The walk is one character per step and tail recursive, so a CI job log of any size stays
# within the runtime's stack (a non-tail walk over a String dies at about 50k characters).
import Base

# What one character of the text means to the walk: 0 ESC, 1 '[', 2 ']', 3 newline,
# 4 tab, 5 carriage return, 6 BEL, 7 backslash, 8 a dropped control (the other C0 bytes,
# DEL, C1), 9 a CSI parameter or intermediate (0x20-0x3f), 10 a CSI final byte
# (0x40-0x7e), 11 every other character. A class comes from the code point alone, so the
# walk can be handed one instead of deciding per state.

# the class of a code point the eight named ones don't cover
def cls.range(drop: Bool, fin: Bool, mid: Bool) -> Nat:
  match drop fin mid:
    case True{} _ _:
      8n
    case False{} True{} _:
      10n
    case False{} False{} True{}:
      9n
    case False{} False{} False{}:
      11n

# what the walk must know about one code point. The code point is + because a literal
# pattern reads it once per case until one matches.
def cls(+u: U32) -> Nat:
  match u:
    case 27:
      0n
    case 91:
      1n
    case 93:
      2n
    case 10:
      3n
    case 9:
      4n
    case 13:
      5n
    case 7:
      6n
    case 92:
      7n
    case _:
      cls.range(U32.is_lt(u, 32) || (U32.is_ge(u, 127) && U32.is_le(u, 159)), U32.is_ge(u, 64) && U32.is_le(u, 126), U32.is_ge(u, 32) && U32.is_le(u, 63))

# Where the walk is: ordinary text, the character after an ESC, a CSI, an OSC, or the
# character after an ESC inside an OSC (which ends it only when it is a backslash).
type Mode is Data:
  Plain{}
  Any{}
  Csi{}
  Osc{}
  OscEsc{}

# What one character of class k does in the walk's state st: a CSI runs to its final byte
# (0x40-0x7e), an OSC to BEL or to the ESC that begins its string terminator, and an ESC
# to the character that follows it. An ESC read where a character was expected (in Any,
# or in the ESC of an OSC) opens another sequence instead of ending the one before it.
# In Plain nothing changes the state but an ESC.
def next(+k: Nat, +st: Mode) -> Mode:
  match k st:
    case 0n Plain{}:
      Any{}
    case 5n Plain{}:
      Plain{}
    case 6n Plain{}:
      Plain{}
    case 8n Plain{}:
      Plain{}
    case _ Plain{}:
      Plain{}
    case 0n Any{}:
      Any{}
    case 1n Any{}:
      Csi{}
    case 2n Any{}:
      Osc{}
    case _ Any{}:
      Plain{}
    case 10n Csi{}:
      Plain{}
    case _ Csi{}:
      Csi{}
    case 6n Osc{}:
      Plain{}
    case 0n Osc{}:
      OscEsc{}
    case _ Osc{}:
      Osc{}
    case 7n OscEsc{}:
      Plain{}
    case _ OscEsc{}:
      Osc{}

# The classes Plain keeps: everything but an ESC, a carriage return, a BEL and a dropped
# control. \r\n needs no case of its own anywhere: the carriage return is dropped and the
# newline after it is kept.
def ordinary(+k: Nat) -> Bool:
  match k:
    case 0n:
      False{}
    case 5n:
      False{}
    case 6n:
      False{}
    case 8n:
      False{}
    case _:
      True{}

# whether the walk keeps a character of class k read in state st: everything outside an
# escape sequence, and only what Plain doesn't drop. Every other state drops what it reads.
def keeps(+k: Nat, +st: Mode) -> Bool:
  match st:
    case Plain{}:
      ordinary(k)
    case _:
      False{}

def grew(keep: Bool, c: Char, acc: String) -> String:
  match keep:
    case True{}:
      SCon{c, acc}
    case False{}:
      acc

# the walk: the text left, the state, and what is kept so far, in reverse
def walk(cs: String, +st: Mode, acc: String) -> String:
  match cs:
    case SNil{}:
      String.reverse(acc)
    case SCon{+c, t}:
      +k = cls(Char.to_u32(c))
      walk(t, next(k, st), grew(keeps(k, st), c, acc))

# text safe to print: every escape sequence and control byte dropped
def text(s: String) -> String:
  walk(s, Plain{}, SNil{})
