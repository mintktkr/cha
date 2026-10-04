# big: big naturals for RSA and ECDSA, as BearSSL's i31 does them. A number is a
# List<&2, U32> of 16-bit limbs, least significant first, with no high zero limbs; zero
# is Nil{}. Sixteen-bit limbs make every limb product fit in a U32, so the carries are
# written out by hand. Numbers stay short (a 4096-bit modulus is 256 limbs), so the only
# loops that need care are the limb-sized ones; the rest recurse over a list, which the
# JS lane takes to about 30k deep.
import Base
import ./bytes.bend as Bytes

# Limbs
# -----

def limb(+v: U32) -> U32:
  U32.and(v, 65535)

def carry(+v: U32) -> U32:
  U32.shrn(v, 16n)

# the two bytes of a limb
def byte.lo(+h: U32) -> U32:
  U32.and(h, 255)

def byte.hi(h: U32) -> U32:
  U32.shrn(h, 8n)

# a carry as a limb list, empty when it is zero
def carry.list.if(c: U32, z: Bool) -> List<&2, U32>:
  match z:
    case True{}:
      Nil{}
    case False{}:
      c <> Nil{}

def carry.list(+c: U32) -> List<&2, U32>:
  carry.list.if(c, U32.is_eq(c, 0))

def head(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{h, t}:
      h

def tail(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      t

def top.go(xs: List<&2, U32>, best: U32) -> U32:
  match xs:
    case Nil{}:
      best
    case Con{h, t}:
      top.go(t, h)

# the most significant limb, 0 for zero
def top(xs: List<&2, U32>) -> U32:
  top.go(xs, 0)

# the high zero limbs dropped; xs must be low first
def norm.top(+h: U32, z: Bool) -> List<&2, U32>:
  match z:
    case True{}:
      Nil{}
    case False{}:
      h <> Nil{}

def norm.if(+h: U32, t: List<&2, U32>) -> List<&2, U32>:
  match t:
    case Nil{}:
      norm.top(h, U32.is_eq(h, 0))
    case Con{c, r}:
      h <> t

def norm(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      norm.if(h, norm(t))

# exactly n limbs, zero padded at the top when xs is shorter
def fit.go(n: Nat, xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      Bytes.rev(acc)
    case 1n+p:
      match xs:
        case Nil{}:
          fit.go(p, Nil{}, 0 <> acc)
        case Con{h, t}:
          fit.go(p, t, h <> acc)

def fit(xs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  fit.go(n, xs, Nil{})

# t + a*s + c, everything low first and exact. Every limb product fits in a U32, and so
# does each sum: 65535 + 65535*65535 + 65535 = 2^32 - 1.
def amul.ta(a: List<&2, U32>, +s: U32, c: U32) -> List<&2, U32>:
  match a:
    case Nil{}:
      carry.list(c)
    case Con{+g, t}:
      +v = (g * s + c : U32)
      limb(v) <> amul.ta(t, s, carry(v))

def amul.tail(t: List<&2, U32>, c: U32) -> List<&2, U32>:
  match t:
    case Nil{}:
      carry.list(c)
    case Con{+h, r}:
      +v = (h + c : U32)
      limb(v) <> amul.tail(r, carry(v))

# t + a*s + c, with h the limb of t that is pending and t the rest of it
def amul.step(t: List<&2, U32>, h: U32, a: List<&2, U32>, +s: U32, +c: U32) ->
  List<&2, U32>:
  match t a:
    case Con{+h2, r} Con{+g, u}:
      +v = (h + g * s + c : U32)
      limb(v) <> amul.step(r, h2, u, s, carry(v))
    case Con{+h2, r} Nil{}:
      +v = (h + c : U32)
      limb(v) <> amul.tail(h2 <> r, carry(v))
    case Nil{} Con{+g, u}:
      +v = (h + g * s + c : U32)
      limb(v) <> amul.ta(u, s, carry(v))
    case Nil{} Nil{}:
      +v = (h + c : U32)
      limb(v) <> carry.list(carry(v))

def amul(t: List<&2, U32>, a: List<&2, U32>, +s: U32, c: U32) -> List<&2, U32>:
  match t:
    case Nil{}:
      amul.ta(a, s, c)
    case Con{+h, r}:
      amul.step(r, h, a, s, c)

# Sizes and bits
# --------------

def bits.limb(+x: U32, +n: Nat, best: Nat) -> Nat:
  match n:
    case 0n:
      best
    case 1n+p:
      bits.limb(x, p, Nat.max(best,
        Bool.pick(Nat, U32.is_ne(U32.shrn(x, p), 0), (1n + p : Nat), 0n)))

# the bit length of one limb, 16 for a limb with its top bit set
def bits.one(+x: U32) -> Nat:
  bits.limb(x, 16n, 0n)

def bits.go(xs: List<&2, U32>, +k: Nat, acc: Nat) -> Nat:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      bits.go(t, (1n + k : Nat), Nat.add(Nat.mul(k, 16n), bits.one(h)))

# how many bits it takes to write n; 0 for zero
def bits(xs: List<&2, U32>) -> U32:
  U32.from_nat(bits.go(xs, 0n, 0n))

# n == 0
def is_zero(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      False{}

# h's top k bits, most significant first, one bit per limb
def bits.desc(+h: U32, +k: Nat) -> List<&2, U32>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      U32.and(U32.shrn(h, p), 1) <> bits.desc(h, p)

def bits.of.go(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      bits.of.go(t, Bytes.cat(bits.desc(h, 16n), acc))

# n's bits, most significant first, 16 per limb
def bits.of(xs: List<&2, U32>) -> List<&2, U32>:
  bits.of.go(xs, Nil{})

# Conversions
# -----------

def of_bytes.fin(lo: U32, have: Bool, acc: List<&2, U32>) -> List<&2, U32>:
  match have:
    case True{}:
      Bytes.rev(lo <> acc)
    case False{}:
      Bytes.rev(acc)

def of_bytes.go(xs: List<&2, U32>, lo: U32, have: Bool, acc: List<&2, U32>) ->
  List<&2, U32>:
  match xs:
    case Nil{}:
      norm(of_bytes.fin(lo, have, acc))
    case Con{+b, t}:
      match have:
        case False{}:
          of_bytes.go(t, b, True{}, acc)
        case True{}:
          of_bytes.go(t, 0, False{}, U32.or(lo, U32.shln(b, 8n)) <> acc)

# big-endian bytes to limbs
def of_bytes(b: List<&2, U32>) -> List<&2, U32>:
  of_bytes.go(Bytes.rev(b), 0, False{}, Nil{})

def to_bytes.low(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      acc
    case Con{+h, t}:
      to_bytes.low(t, byte.hi(h) <> byte.lo(h) <> acc)

# big-endian, exactly len bytes: left zero padded, high bytes dropped when it is longer
def to_bytes(n: List<&2, U32>, len: U32) -> List<&2, U32>:
  Bytes.rev(fit(Bytes.rev(to_bytes.low(n, Nil{})), U32.to_nat(len)))

# x in one limb, or two when it needs them
def of_u32(+x: U32) -> List<&2, U32>:
  norm([limb(x), carry(x)])

# Comparison
# ----------

def cmp.rest(+x: U32, +y: U32, c: Cmp) -> Cmp:
  match c:
    case EQ{}:
      U32.cmp(x, y)
    case LT{}:
      LT{}
    case GT{}:
      GT{}

# a against b; both must be normalized
def cmp(a: List<&2, U32>, b: List<&2, U32>) -> Cmp:
  match a b:
    case Nil{} Nil{}:
      EQ{}
    case Nil{} Con{h, t}:
      LT{}
    case Con{h, t} Nil{}:
      GT{}
    case Con{+x, s} Con{+y, t}:
      cmp.rest(x, y, cmp(s, t))

# Addition and subtraction
# ------------------------

# a + b; both must be normalized
def add(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  match a:
    case Nil{}:
      b
    case Con{h, r}:
      amul(h <> r, b, 1, 0)

def sub.go(a: List<&2, U32>, b: List<&2, U32>, +brw: U32, acc: List<&2, U32>) ->
  List<&2, U32>:
  match a b:
    case Con{+x, r} Con{+y, s}:
      +t = (y + brw : U32)
      sub.go(r, s, Bool.to_u32(U32.is_gt(t, x)), limb((x - t : U32)) <> acc)
    case Con{+x, r} Nil{}:
      sub.go(r, Nil{}, Bool.to_u32(U32.is_gt(brw, x)),
        limb((x - brw : U32)) <> acc)
    case Nil{} _:
      Bytes.rev(acc)

def sub.cmp(+a: List<&2, U32>, +b: List<&2, U32>, c: Cmp) -> List<&2, U32>:
  match c:
    case GT{}:
      norm(sub.go(a, b, 0, Nil{}))
    case EQ{}:
      Nil{}
    case LT{}:
      Nil{}

# a - b when a >= b, else zero
def sub(+a: List<&2, U32>, +b: List<&2, U32>) -> List<&2, U32>:
  sub.cmp(a, b, cmp(a, b))

# Multiplication
# --------------

# Schoolbook, one limb of b at a time. a * b[i] is added to the running carry, the limb it
# settles at the bottom is an answer digit, and the carry above it goes on. That shift is
# what puts row i at position i.
def mul.go(+a: List<&2, U32>, b: List<&2, U32>, t: List<&2, U32>,
  out: List<&2, U32>) -> List<&2, U32>:
  match b:
    case Nil{}:
      norm(Bytes.cat(Bytes.rev(out), t))
    case Con{s, r}:
      +t1 = amul(t, a, s, 0)
      mul.go(a, r, tail(t1), head(t1) <> out)

# a * b
def mul(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  match b:
    case Nil{}:
      Nil{}
    case Con{s, r}:
      mul.go(a, s <> r, 0 <> Nil{}, Nil{})

# Bit shifts, by fewer than 16 bits
# ---------------------------------

def shl.bits.go(xs: List<&2, U32>, hi: U32, +s: Nat) -> List<&2, U32>:
  match xs:
    case Nil{}:
      carry.list(hi)
    case Con{+h, t}:
      +v = U32.or(U32.and(U32.shln(h, s), 65535), hi)
      +hi2 = U32.shrn(h, (16n - s : Nat))
      v <> shl.bits.go(t, hi2, s)

# xs << s, and xs >> s
def shl.bits(xs: List<&2, U32>, s: Nat) -> List<&2, U32>:
  shl.bits.go(xs, 0, s)

def shr.bits.go(xs: List<&2, U32>, prev: U32, +s: Nat) -> List<&2, U32>:
  match xs:
    case Nil{}:
      carry.list(U32.shrn(prev, s))
    case Con{+h, t}:
      +v = U32.or(U32.shrn(prev, s), U32.and(U32.shln(h, (16n - s : Nat)), 65535))
      v <> shr.bits.go(t, h, s)

def shr.bits(xs: List<&2, U32>, s: Nat) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      shr.bits.go(t, h, s)

# Division
# --------

# a divided by a single limb d, walking a from the top; hi is a high first
def divmod.small.go(hi: List<&2, U32>, +d: U32, r: U32, acc: List<&2, U32>) ->
  List<&2, U32> & U32:
  match hi:
    case Nil{}:
      (norm(acc), r)
    case Con{+h, t}:
      +v = (U32.mul(r, 65536) + h : U32)
      divmod.small.go(t, d, U32.mod(v, d), U32.div(v, d) <> acc)

def divmod.small.pair(p: List<&2, U32> & U32) -> List<&2, U32> & List<&2, U32>:
  (q, r) = p
  (q, of_u32(r))

def divmod.small(a: List<&2, U32>, d: U32) -> List<&2, U32> & List<&2, U32>:
  divmod.small.pair(divmod.small.go(Bytes.rev(a), d, 0, Nil{}))

def divmod.clamp(+x: U32) -> U32:
  Bool.pick(U32, U32.is_le(x, 65535), x, 65535)

# the quotient digit from value's top two limbs and b's top limb, clamped to 15 bits
def divmod.qhat(xs: List<&2, U32>, btop: U32, last: U32, prev: U32) -> U32:
  match xs:
    case Nil{}:
      divmod.clamp(U32.div(U32.or(U32.shln(last, 16n), prev), btop))
    case Con{h, t}:
      divmod.qhat(t, btop, h, last)

# q brought down to floor(value / b): that guess is never too small, and with b normalized
# it is at most two too large
def divmod.corr(k: Nat, +q: U32, +value: List<&2, U32>, +b: List<&2, U32>, c: Cmp) ->
  U32:
  match k c:
    case 0n _:
      q
    case 1n+p GT{}:
      divmod.corr(p, (q - 1 : U32), value, b,
        cmp(norm(amul.ta(b, (q - 1 : U32), 0)), norm(value)))
    case 1n+p _:
      q

# One limb of the dividend, high first: r holds exactly len(b) limbs, value is x <> r, and
# q collects the quotient limbs low first. b is pre-shifted so its top bit is set, which is
# what keeps the guess above within two of the answer.
def divmod.big.loop(hi: List<&2, U32>, +b: List<&2, U32>, +btop: U32, +n: U32,
  r: List<&2, U32>, q: List<&2, U32>, +k: Nat) ->
  List<&2, U32> & List<&2, U32>:
  match hi:
    case Nil{}:
      (norm(q), norm(r))
    case Con{x, t}:
      +value = {Con{x, r} : List<&2, U32>}
      +guess = divmod.qhat(value, btop, 0, 0)
      +qq = divmod.corr(k, guess, value, b,
        cmp(norm(amul.ta(b, guess, 0)), norm(value)))
      divmod.big.loop(t, b, btop, n,
        fit(sub(value, amul.ta(b, qq, 0)), U32.to_nat(n)), qq <> q, k)

def divmod.big.left(p: List<&2, U32> & List<&2, U32>, s: Nat) ->
  List<&2, U32> & List<&2, U32>:
  (q, r) = p
  (q, shr.bits(r, s))

def divmod.big.run(a2: List<&2, U32>, +b2: List<&2, U32>, s: Nat) ->
  List<&2, U32> & List<&2, U32>:
  +n = Bytes.len(b2)
  divmod.big.left(divmod.big.loop(Bytes.rev(a2), b2, top(b2), n,
    Bytes.zeros(U32.to_nat(n)), Nil{}, 4n), s)

def divmod.big(+a: List<&2, U32>, +b: List<&2, U32>) ->
  List<&2, U32> & List<&2, U32>:
  +s = Nat.sub(16n, bits.one(top(b)))
  divmod.big.run(shl.bits(a, s), shl.bits(b, s), s)

# a / b and a % b; a zero b answers (0, a)
def divmod(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match b:
    case Nil{}:
      (Nil{}, a)
    case Con{d, Nil{}}:
      divmod.small(a, d)
    case Con{d, r}:
      divmod.big(a, d <> r)

def mod.if(p: List<&2, U32> & List<&2, U32>) -> List<&2, U32>:
  (q, r) = p
  r

# a mod m
def mod(a: List<&2, U32>, m: List<&2, U32>) -> List<&2, U32>:
  mod.if(divmod(a, m))

# Modular arithmetic
# ------------------

def modadd.step(s: List<&2, U32>, +m: List<&2, U32>, c: Cmp) -> List<&2, U32>:
  match c:
    case LT{}:
      s
    case EQ{}:
      sub(s, m)
    case GT{}:
      sub(s, m)

# a + b mod m, for a and b below m
def modadd(a: List<&2, U32>, b: List<&2, U32>, +m: List<&2, U32>) -> List<&2, U32>:
  +s = add(a, b)
  modadd.step(s, m, cmp(s, m))

def modsub.step(+a: List<&2, U32>, +b: List<&2, U32>, +m: List<&2, U32>, c: Cmp) ->
  List<&2, U32>:
  match c:
    case LT{}:
      sub(m, sub(b, a))
    case EQ{}:
      Nil{}
    case GT{}:
      sub(a, b)

# a - b mod m, for a and b below m
def modsub(+a: List<&2, U32>, +b: List<&2, U32>, +m: List<&2, U32>) -> List<&2, U32>:
  modsub.step(a, b, m, cmp(a, b))

# a * b mod m
def modmul(a: List<&2, U32>, b: List<&2, U32>, m: List<&2, U32>) -> List<&2, U32>:
  mod(mul(a, b), m)

# Montgomery
# ----------

# -m0^(-1) mod 2^16, for an odd m0: Newton, each round doubling the low bits that hold
def nprime.go(k: Nat, +m0: U32, +x: U32) -> U32:
  match k:
    case 0n:
      x
    case 1n+p:
      +d = limb((2 - limb(U32.mul(m0, x)) : U32))
      nprime.go(p, m0, limb(U32.mul(x, d)))

def nprime(+m0: U32) -> U32:
  limb((0 - nprime.go(4n, m0, 1) : U32))

# A modulus with what Montgomery multiplication needs: mp = -m^(-1) mod 2^16, r2 = R^2 mod m
# for R = 2^(16k), and one = R mod m, which stands for 1.
type Mont is Data:
  Mont{m: List<&2, U32>, mp: U32, r2: List<&2, U32>, one: List<&2, U32>}

# t = (a * b) / R mod m, the CIOS loop: add one limb of b, cancel the bottom limb with a
# multiple of m, drop it. Every step is exact, so no list length has to be fixed; a carry
# past the top is simply another limb.
def mont.loop(b: List<&2, U32>, +a: List<&2, U32>, +m: List<&2, U32>, +mp: U32,
  t: List<&2, U32>) -> List<&2, U32>:
  match b:
    case Nil{}:
      t
    case Con{s, r}:
      +t1 = amul(t, a, s, 0)
      mont.loop(r, a, m, mp, tail(amul(t1, m, limb(U32.mul(head(t1), mp)), 0)))

def mont.red(k: Nat, +t: List<&2, U32>, +m: List<&2, U32>, c: Cmp) -> List<&2, U32>:
  match k c:
    case 0n _:
      norm(t)
    case 1n+p LT{}:
      norm(t)
    case 1n+p EQ{}:
      norm(sub(t, m))
    case 1n+p GT{}:
      mont.red(p, sub(t, m), m, cmp(norm(sub(t, m)), m))

# (a * b) / R mod m, for a and b below m. The loop runs once per limb of m, so b is
# zero padded to that many: a short b would divide by a smaller power of two.
def mont.raw(a: List<&2, U32>, b: List<&2, U32>, +m: List<&2, U32>, mp: U32) ->
  List<&2, U32>:
  +n = Bytes.len(m)
  +t = mont.loop(fit(b, U32.to_nat(n)), a, m, mp, 0 <> Nil{})
  mont.red(Nat.mul(2n, U32.to_nat(n)), t, m, cmp(norm(t), m))

# the Montgomery context of an odd m above 1
def mont(+m: List<&2, U32>) -> Mont:
  +n = Bytes.len(m)
  +one = mod(Bytes.rev(1 <> Bytes.zeros(U32.to_nat(n))), m)
  Mont{m, nprime(head(m)), mod(mul(one, one), m), one}

# a * b mod m, for a and b below m
def mont.mul(+c: Mont, a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  Mont{m, mp, r2, one} = c
  mont.raw(a, b, m, mp)

# a * R mod m, for a below m
def mont.to(+c: Mont, a: List<&2, U32>) -> List<&2, U32>:
  Mont{m, mp, r2, one} = c
  mont.raw(a, r2, m, mp)

# a / R mod m, for a below m
def mont.from(+c: Mont, a: List<&2, U32>) -> List<&2, U32>:
  Mont{m, mp, r2, one} = c
  mont.raw(a, 1 <> Nil{}, m, mp)

# Exponentiation
# --------------

def modexp.bit.set(z: Bool, +c: Mont, +bm: List<&2, U32>,
  sq: List<&2, U32>) -> List<&2, U32>:
  match z:
    case True{}:
      mont.mul(c, sq, bm)
    case False{}:
      sq

def modexp.bits(+c: Mont, +bm: List<&2, U32>, xs: List<&2, U32>,
  +res: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      mont.from(c, res)
    case Con{x, t}:
      modexp.bits(c, bm, t,
        modexp.bit.set(U32.is_ne(x, 0), c, bm, mont.mul(c, res, res)))

def modexp.go(+c: Mont, b: List<&2, U32>, +e: List<&2, U32>) -> List<&2, U32>:
  Mont{m, mp, r2, one} = c
  modexp.bits(c, mont.to(c, mod(b, m)), bits.of(e), one)

# b^e mod m, for an odd m above 1: square and multiply from the top bit of e
def modexp(b: List<&2, U32>, e: List<&2, U32>, +m: List<&2, U32>) -> List<&2, U32>:
  modexp.go(mont(m), b, e)

# a^(-1) mod p, for an odd prime p and an a that is not a multiple of it
def modinv(a: List<&2, U32>, +p: List<&2, U32>) -> List<&2, U32>:
  modexp(a, sub(p, of_u32(2)), p)
