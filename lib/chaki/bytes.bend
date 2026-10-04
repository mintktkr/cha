# bytes: byte strings as List<&2, U32>, one byte (0..255) per cell. That is the shape
# Base's TCP.send_bytes, TCP.recv_bytes, File.read_bytes and File.write_bytes already
# use, so nothing converts at the edges. Every loop here is a tail call: a body can be
# megabytes, and non-tail recursion that deep overflows the JS lane.
import Base

# Length and comparison
# ---------------------

def len.go(xs: List<&2, U32>, n: U32) -> U32:
  match xs:
    case Nil{}:
      n
    case Con{h, t}:
      len.go(t, (n + 1 : U32))

def len(xs: List<&2, U32>) -> U32:
  len.go(xs, 0)

def eq.go(a: List<&2, U32>, b: List<&2, U32>, same: Bool) -> Bool:
  match a b:
    case Nil{} Nil{}:
      same
    case Con{x, s} Con{y, t}:
      eq.go(s, t, Bool.and(same, U32.is_eq(x, y)))
    case _ _:
      False{}

def eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  eq.go(a, b, True{})

def ct.go(a: List<&2, U32>, b: List<&2, U32>, acc: U32) -> U32:
  match a b:
    case Nil{} Nil{}:
      acc
    case Con{x, s} Con{y, t}:
      ct.go(s, t, U32.or(acc, U32.xor(x, y)))
    case _ _:
      1

# equal bytes, in time that depends only on the length: for MACs and Finished messages
def ct_eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  U32.is_eq(ct.go(a, b, 0), 0)

# Building
# --------

# xs reversed, then ys: the tail-call way to put two lists together
def rev.onto(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      ys
    case Con{h, t}:
      rev.onto(t, h <> ys)

def rev(xs: List<&2, U32>) -> List<&2, U32>:
  rev.onto(xs, Nil{})

def cat(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  rev.onto(rev(a), b)

def zeros.go(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      zeros.go(p, 0 <> acc)

def zeros(n: Nat) -> List<&2, U32>:
  zeros.go(n, Nil{})

def take.go(n: Nat, xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n xs:
    case 0n _:
      rev(acc)
    case 1n+p Nil{}:
      rev(acc)
    case 1n+p Con{h, t}:
      take.go(p, t, h <> acc)

# the first n bytes (all of them when there are fewer)
def take(xs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  take.go(n, xs, Nil{})

def drop.go(n: Nat, xs: List<&2, U32>) -> List<&2, U32>:
  match n xs:
    case 0n _:
      xs
    case 1n+p Nil{}:
      Nil{}
    case 1n+p Con{h, t}:
      drop.go(p, t)

# all but the first n bytes
def drop(xs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  drop.go(n, xs)

def xor.go(a: List<&2, U32>, b: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match a b:
    case Con{x, s} Con{y, t}:
      xor.go(s, t, U32.xor(x, y) <> acc)
    case _ _:
      rev(acc)

# byte-wise xor, as long as the shorter input
def xor(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  xor.go(a, b, Nil{})

# Big-endian integers
# -------------------

def byte(+n: U32, +shift: Nat) -> U32:
  U32.and(U32.shrn(n, shift), 255)

def be16(+n: U32) -> List<&2, U32>:
  [byte(n, 8n), byte(n, 0n)]

def be24(+n: U32) -> List<&2, U32>:
  [byte(n, 16n), byte(n, 8n), byte(n, 0n)]

def be32(+n: U32) -> List<&2, U32>:
  [byte(n, 24n), byte(n, 16n), byte(n, 8n), byte(n, 0n)]

def get.be.go(n: Nat, xs: List<&2, U32>, acc: U32) -> U32:
  match n xs:
    case 0n _:
      acc
    case 1n+p Nil{}:
      U32.shln(acc, 8n)
    case 1n+p Con{h, t}:
      get.be.go(p, t, U32.or(U32.shln(acc, 8n), h))

# the first n bytes (n at most 4) as a big-endian number; missing bytes read as 0
def get.be(xs: List<&2, U32>, n: Nat) -> U32:
  get.be.go(n, xs, 0)

# Text
# ----

def of_ascii.go(s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}:
      rev(acc)
    case SCon{Chr{c}, t}:
      of_ascii.go(t, U32.and(c, 255) <> acc)

# each Char's low 8 bits: right for protocol text (HTTP heads, hex, PEM), which is ASCII.
# For text that may hold anything else, use utf8.bend.
def of_ascii(s: String) -> List<&2, U32>:
  of_ascii.go(s, Nil{})

def to_ascii.go(xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}:
      String.reverse(acc)
    case Con{b, t}:
      to_ascii.go(t, SCon{Chr{b}, acc})

# one Char per byte
def to_ascii(xs: List<&2, U32>) -> String:
  to_ascii.go(xs, SNil{})

# Hex
# ---

def hex.in(+c: U32, +lo: U32, +hi: U32) -> Bool:
  Bool.and(U32.is_le(lo, c), U32.is_le(c, hi))

# a hex digit's value, 16 when c isn't one
def hex.val(+c: U32) -> U32:
  Bool.pick(U32, hex.in(c, 48, 57), (c - 48 : U32), Bool.pick(U32, hex.in(c, 97, 102), (c - 87 : U32), Bool.pick(U32, hex.in(c, 65, 70), (c - 55 : U32), 16)))

def hex.put(+v: U32, +hi: U32, acc: List<&2, U32>, skip: Bool, have: Bool) -> List<&2, U32> & U32:
  match skip have:
    case True{} _:
      (acc, hi)
    case False{} True{}:
      (U32.or(U32.shln(hi, 4n), v) <> acc, 16)
    case False{} False{}:
      (acc, v)

def of_hex.go(s: String, st: List<&2, U32> & U32) -> List<&2, U32>:
  match s:
    case SNil{}:
      (acc, hi) = st
      rev(acc)
    case SCon{Chr{+c}, t}:
      (acc, +hi) = st
      +v = hex.val(c)
      of_hex.go(t, hex.put(v, hi, acc, U32.is_le(16, v), U32.is_lt(hi, 16)))

# hex text to bytes. Anything that isn't a hex digit is skipped, so test vectors can be
# copied from an RFC with their spaces and line breaks; an odd digit at the end is dropped.
def of_hex(s: String) -> List<&2, U32>:
  of_hex.go(s, (Nil{}, 16))

def hex.digit(+n: U32) -> U32:
  Bool.pick(U32, U32.is_le(n, 9), (48 + n : U32), (87 + n : U32))

def to_hex.go(xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}:
      String.reverse(acc)
    case Con{+b, t}:
      to_hex.go(t, SCon{Chr{hex.digit(U32.and(b, 15))}, SCon{Chr{hex.digit(U32.shrn(b, 4n))}, acc}})

# lowercase hex, two digits a byte, no spaces
def to_hex(xs: List<&2, U32>) -> String:
  to_hex.go(xs, SNil{})
