# ui: the palette, the colour decision and styled text. Every style takes `on`, the colour
# decision, so piped output stays plain and tests need no terminal.
import Base
import 0xd60fd658d4bdabf892f8041a7a731848/tty.bend as Tty
import ./ctx.bend as Ctx

type Rgb is Data:
  Rgb{r: U32, g: U32, b: U32}

def pink() -> Rgb:
  Rgb{255, 110, 180}

def lemon() -> Rgb:
  Rgb{255, 225, 77}

def aqua() -> Rgb:
  Rgb{110, 243, 255}

def mint() -> Rgb:
  Rgb{110, 242, 184}

def lavender() -> Rgb:
  Rgb{214, 127, 232}

# colour when stdout is a terminal, NO_COLOR is unset and TERM isn't dumb
def color() -> IO(Bool):
  do IO<Bool>:
    tty : Bool <- Tty.color_enabled()
    term : String <- Ctx.env("TERM")
    return tty && Bool.not(String.eq(term, "dumb"))

def esc(code: String) -> String:
  "\u{1b}[" ++ code ++ "m"

def styled(+on: Bool, +open: String, +close: String, s: String) -> String:
  match on:
    case True{}:
      esc(open) ++ s ++ esc(close)
    case False{}:
      s

def fg(+on: Bool, c: Rgb, s: String) -> String:
  match c:
    case Rgb{r, g, b}:
      styled(on, "38;2;" ++ U32.show(r) ++ ";" ++ U32.show(g) ++ ";" ++ U32.show(b), "39", s)

def bold(+on: Bool, s: String) -> String:
  styled(on, "1", "22", s)

def dim(+on: Bool, s: String) -> String:
  styled(on, "2", "22", s)

# the glow gradient, pink -> mint, as 7 stops
def stop.of(n: Nat) -> Rgb:
  match n:
    case 0n:
      pink()
    case 1n:
      Rgb{255, 143, 195}
    case 2n:
      Rgb{240, 144, 240}
    case 3n:
      lavender()
    case 4n:
      Rgb{168, 188, 255}
    case 5n:
      aqua()
    case 6n+k:
      mint()

def stop(+i: U32) -> Rgb:
  stop.of(U32.to_nat(i))

# one channel t of the way from a to b, t in 0..1
def blend(a: U32, b: U32, +t: F32) -> U32:
  U32.from_nat(F32.to_nat(F32.round(F32.lerp(F32.from_nat(U32.to_nat(a)), F32.from_nat(U32.to_nat(b)), t))))

def mix(x: Rgb, y: Rgb, +t: F32) -> Rgb:
  match x y:
    case Rgb{r, g, b} Rgb{r2, g2, b2}:
      Rgb{blend(r, r2, t), blend(g, g2, t), blend(b, b2, t)}

def gradient.at(+p: F32, +i: Nat) -> Rgb:
  mix(stop.of(i), stop.of(1n+i), (p - F32.from_nat(i) : F32))

# the glow at t in 0..1, blended between the stops instead of snapping to one
def gradient(+t: F32) -> Rgb:
  +p = (F32.clamp(t, 0.0, 1.0) * 6.0 : F32)
  gradient.at(p, F32.to_nat(p))

def tri.if(+u: F32, rising: Bool) -> F32:
  match rising:
    case True{}:
      (u * 2.0 : F32)
    case False{}:
      (2.0 - (u * 2.0 : F32) : F32)

# the flow at column x and time t seconds: a triangle wave, so pink -> mint -> pink
# loops without a seam (ito's wave). 8 columns a cycle, 1.2 cycles a second.
def wave(+x: F32, +t: F32) -> Rgb:
  +u = F32.mod((((x / 8.0 : F32) + 100.0 : F32) - (t * 1.2 : F32) : F32), 1.0)
  gradient(tri.if(u, F32.is_lt(u, 0.5)))

def glow.go(cs: List<&2, Char>, +on: Bool, +i: U32, +n: U32) -> String:
  match cs:
    case Nil{}:
      ""
    case Con{c, t}:
      fg(on, stop(((i * 6) / n : U32)), String.from_list([c])) ++ glow.go(t, on, (i + 1 : U32), n)

# text walked along the gradient, one colour per character
def glow(+on: Bool, +s: String) -> String:
  glow.go(String.to_list(s), on, 0, U32.max(U32.from_nat(Nat.sub(String.length(s), 1n)), 1))

def prefix(+on: Bool) -> String:
  glow(on, "cha 茶")

def state.kind.of(good: Bool, bad: Bool, busy: Bool, merged: Bool) -> Nat:
  match good bad busy merged:
    case True{} b u m:
      1n
    case False{} True{} u m:
      2n
    case False{} False{} True{} m:
      3n
    case False{} False{} False{} True{}:
      4n
    case False{} False{} False{} False{}:
      0n

def state.kind(+l: String) -> Nat:
  state.kind.of(String.eq(l, "success") || String.eq(l, "open") || String.eq(l, "completed"), String.eq(l, "failure") || String.eq(l, "failed") || String.eq(l, "error") || String.eq(l, "cancelled"), String.eq(l, "running") || String.eq(l, "in_progress") || String.eq(l, "pending") || String.eq(l, "waiting"), String.eq(l, "merged"))

def state.of(+on: Bool, +s: String, k: Nat) -> String:
  match k:
    case 0n:
      dim(on, s)
    case 1n:
      fg(on, mint(), s)
    case 2n:
      fg(on, pink(), s)
    case 3n:
      fg(on, lemon(), s)
    case 4n+x:
      fg(on, lavender(), s)

def state.pick(+on: Bool, +s: String, +l: String) -> String:
  state.of(on, s, state.kind(l))

# a forge state as its colour: success/open mint, failure pink, running lemon, merged
# lavender, everything else (queued, closed, skipped) dim
def state(+on: Bool, +s: String) -> String:
  state.pick(on, s, String.to_lower(s))

# a line for stderr: the glowing prefix, then msg
def info(+on: Bool, msg: String) -> IO(Unit):
  IO.print_err(prefix(on) ++ " " ++ msg)

# a line for stderr: the prefix, a pink ✗ and msg in pink
def error(+on: Bool, msg: String) -> IO(Unit):
  IO.print_err(prefix(on) ++ " " ++ fg(on, pink(), "✗ " ++ msg))

# a mint ✓ line for stderr
def done(+on: Bool, msg: String) -> IO(Unit):
  IO.print_err(fg(on, mint(), "✓ " ++ msg))
