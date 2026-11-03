# x25519: the key exchange chaki's TLS offers, from RFC 7748. A field element mod
# 2^255-19 is 16 limbs of 16 bits, little-endian: limb k holds bits 16k..16k+15.
# U32.mul keeps only 32 bits, so one limb product fits whole but no sum of products
# does: a multiply splits every product into its low and high 16 bits and carries the
# pile by hand. TweetNaCl's 16-limb ladder is the model.
#
# Bend matches a parameter or a pattern-bound field, never a computed value, so no
# helper here answers two lists: the borrow the arithmetic carries out is folded back
# in where it belongs, and a conditional swap is read one side at a time.
import Base
import ./bytes.bend as Bytes

# The ladder state: the four running field elements with the base point x1, so one
# step needs no other argument.
type St is Data:
  St{x1: List<&2, U32>, x2: List<&2, U32>, x3: List<&2, U32>, z2: List<&2, U32>, z3: List<&2, U32>}

# Constants
# ---------

# 2^255-19, the field prime, as 0x7fff...ffed
def fp() -> List<&2, U32>:
  [65517, 65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535, 32767]

def fzero() -> List<&2, U32>:
  Bytes.zeros(16n)

def fone() -> List<&2, U32>:
  1 <> Bytes.zeros(15n)

# 121665 = (486662 - 2) / 4, the a24 of RFC 7748 §5
def fa24() -> List<&2, U32>:
  56129 <> (1 <> Bytes.zeros(14n))

# Reducing
# --------

def car.top(xs: List<&2, U32>, k: U32) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      (h + k : U32) <> t

# one carry pass: every limb left below 2^16, and the carry out of the top limb folded
# back into limb 0 as 38, since 2^256 = 38 (mod 2^255-19)
def car.go(xs: List<&2, U32>, c: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      car.top(Bytes.rev(acc), (38 * c : U32))
    case Con{h, t}:
      +s = (h + c : U32)
      car.go(t, U32.shrn(s, 16n), U32.and(s, 65535) <> acc)

def car(xs: List<&2, U32>) -> List<&2, U32>:
  car.go(xs, 0, Nil{})

# every limb below 2^16, which is what a multiply needs of both of its operands. Three
# passes: the first leaves limb 0 under 2^16+38, the second either settles or folds a
# whole cascade of carries back into limb 0, and the third settles that one.
def fnorm(xs: List<&2, U32>) -> List<&2, U32>:
  car(car(car(xs)))

# Adding and subtracting
# ----------------------

def fadd.go(a: List<&2, U32>, b: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match a b:
    case Nil{} _:
      Bytes.rev(acc)
    case Con{x, s} Con{y, t}:
      fadd.go(s, t, (x + y : U32) <> acc)
    case _ _:
      Bytes.rev(acc)

# a + b, limbs below 2^16 on both sides, so below 2^17 here
def fadd(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  fnorm(fadd.go(a, b, Nil{}))

# w - k as an integer, for a small k (below 2^16): only the first limb is charged, and
# the borrow climbs the rest. The caller has made sure w is at least k.
def sub.small.go(xs: List<&2, U32>, k: U32, borrow: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Bytes.rev(acc)
    case Con{h, t}:
      +d = (h - k - borrow : U32)
      sub.small.go(t, 0, U32.shrn(d, 31n), U32.and(d, 65535) <> acc)

# a - b as limbs of a - b mod 2^256, then 38 taken back off when the subtraction
# borrowed: 2^256 = 38, so the wrapped value stands 38 too high and 2^255 <= a - b + 2^256
# always leaves room for the integer subtraction. Every limb stays below 2^16.
def fsub.go(a: List<&2, U32>, b: List<&2, U32>, borrow: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match a b:
    case Nil{} _:
      sub.small.go(Bytes.rev(acc), (38 * borrow : U32), 0, Nil{})
    case Con{x, s} Con{y, t}:
      +d = (x - y - borrow : U32)
      fsub.go(s, t, U32.shrn(d, 31n), U32.and(d, 65535) <> acc)
    case _ _:
      sub.small.go(Bytes.rev(acc), (38 * borrow : U32), 0, Nil{})

# a - b mod 2^255-19. The borrow is the top bit of the wrapped difference and every
# limb below 2^17, so it is exact and branch-free.
def fsub(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  fsub.go(a, b, 0, Nil{})

# 1 when a < p: the borrow out of a - p, for the canonical reduction
def below.p.go(a: List<&2, U32>, b: List<&2, U32>, borrow: U32) -> U32:
  match a b:
    case Nil{} _:
      borrow
    case Con{x, s} Con{y, t}:
      d = (x - y - borrow : U32)
      below.p.go(s, t, U32.shrn(d, 31n))
    case _ _:
      borrow

def below.p(a: List<&2, U32>) -> U32:
  below.p.go(a, fp(), 0)

# Swapping
# --------

def cswap.side.go(a: List<&2, U32>, b: List<&2, U32>, +mask: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match a b:
    case Nil{} _:
      Bytes.rev(acc)
    case Con{+x, s} Con{+y, t}:
      d = U32.and(mask, U32.xor(x, y))
      cswap.side.go(s, t, mask, U32.xor(x, d) <> acc)
    case _ _:
      Bytes.rev(acc)

# a when mask is 0 and b when it is all ones, limb by limb: one side of the conditional
# swap the ladder needs. Asking for the other side means passing a and b the other way
# round. No branch reads a bit.
def cswap.side(a: List<&2, U32>, b: List<&2, U32>, +mask: U32) -> List<&2, U32>:
  cswap.side.go(a, b, mask, Nil{})

# Multiplying
# -----------

# the slots one limb of the left operand contributes to a product: slot k holds
# hi(a*b[k-1]) + lo(a*b[k]), so every slot stays below 2^17
def frow(b: List<&2, U32>, +ai: U32, prev: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match b:
    case Nil{}:
      Bytes.rev(prev <> acc)
    case Con{y, t}:
      +p = (ai * y : U32)
      frow(t, ai, U32.shrn(p, 16n), (U32.and(p, 65535) + prev : U32) <> acc)

# limbwise add of two slot lists that may differ in length: the longer tail rides along
def fadd.wide(x: List<&2, U32>, y: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match x y:
    case Nil{} _:
      Bytes.rev(acc)
    case Con{xh, xt} Nil{}:
      Bytes.rev.onto(acc, xh <> xt)
    case Con{xh, xt} Con{yh, yt}:
      fadd.wide(xt, yt, (xh + yh : U32) <> acc)

# Horner over the rows of the left operand, most significant limb first: every row
# lands one slot higher than the one before, so no slot holds more than 16
# contributions and the whole 32-slot result stays below 2^21
def fmul.rows(ar: List<&2, U32>, +b: List<&2, U32>, acc: List<&2, U32>, first: Bool) -> List<&2, U32>:
  match ar first:
    case Nil{} _:
      acc
    case Con{ai, t} True{}:
      fmul.rows(t, b, frow(b, ai, 0, Nil{}), False{})
    case Con{ai, t} False{}:
      fmul.rows(t, b, fadd.wide(0 <> acc, frow(b, ai, 0, Nil{}), Nil{}), False{})

def fmul.fold.zip(low: List<&2, U32>, hi: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match low hi:
    case Con{h, s} Con{y, t}:
      fmul.fold.zip(s, t, (h + 38 * y : U32) <> acc)
    case _ _:
      acc

# slots 16..31 folded back into 0..15: they stand 2^256 high, which is 38
def fmul.fold(+xs: List<&2, U32>) -> List<&2, U32>:
  Bytes.rev(fmul.fold.zip(Bytes.take(xs, 16n), Bytes.drop(xs, 16n), Nil{}))

# a * b mod 2^255-19, limbs below 2^16 on both sides
def fmul(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  fnorm(fmul.fold(fmul.rows(Bytes.rev(a), b, Nil{}, True{})))

# x^2
def fsq(+x: List<&2, U32>) -> List<&2, U32>:
  fmul(x, x)

# x^(2^n)
def fsq.n(n: Nat, x: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      x
    case 1n+p:
      fsq.n(p, fsq(x))

# Inverting
# ---------

# z^(p-2), which is z^-1 for z other than 0: ref10's chain, 253 squarings and 11
# multiplies rather than the 507 a plain square-and-multiply would take
def finv(+z: List<&2, U32>) -> List<&2, U32>:
  +t0 = fsq(z)
  +t1 = fmul(fsq(fsq(t0)), z)
  +t0 = fmul(t0, t1)
  +t2 = fsq(t0)
  +t1 = fmul(t1, t2)
  +t2 = fsq.n(5n, t1)
  +t1 = fmul(t2, t1)
  +t2 = fsq.n(10n, t1)
  +t2 = fmul(t2, t1)
  +t3 = fsq.n(20n, t2)
  +t2 = fmul(t3, t2)
  t2 = fsq.n(10n, t2)
  +t1 = fmul(t2, t1)
  t2 = fsq.n(50n, t1)
  +t2 = fmul(t2, t1)
  +t3 = fsq.n(100n, t2)
  +t2 = fmul(t3, t2)
  t2 = fsq.n(50n, t2)
  +t1 = fmul(t2, t1)
  t1 = fsq.n(5n, t1)
  fmul(t1, t0)

# Bytes
# -----

# 16 limbs from 32 little-endian bytes
def decode.go(xs: List<&2, U32>, pending: U32, half: Bool, acc: List<&2, U32>) -> List<&2, U32>:
  match xs half:
    case Nil{} _:
      Bytes.rev(acc)
    case Con{b, t} False{}:
      decode.go(t, b, True{}, acc)
    case Con{b, t} True{}:
      decode.go(t, 0, False{}, (U32.or(pending, U32.shln(b, 8n)) : U32) <> acc)

def mask.last.done(acc: List<&2, U32>, k: U32) -> List<&2, U32>:
  match acc:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Bytes.rev(U32.and(h, k) <> t)

def mask.last.go(xs: List<&2, U32>, +k: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      mask.last.done(acc, k)
    case Con{h, t}:
      mask.last.go(t, k, h <> acc)

# xs with its last element masked by k, everything else untouched. The accumulator is the
# list reversed, so the last element is the one it starts with.
def mask.last(xs: List<&2, U32>, k: U32) -> List<&2, U32>:
  mask.last.go(xs, k, Nil{})

# the u-coordinate of 32 bytes: bit 255 is not part of a field element, so it is
# masked (RFC 7748 §5). A short input reads as the shorter number.
def decode(xs: List<&2, U32>) -> List<&2, U32>:
  mask.last(decode.go(xs, 0, False{}, Nil{}), 32767)

def fsel(c: Bool, a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  match c:
    case True{}:
      a
    case False{}:
      b

# a - p when a >= p, a itself otherwise: the least residue of a field element
def reduce.p(+a: List<&2, U32>) -> List<&2, U32>:
  fsel(U32.is_eq(below.p(a), 1), a, fsub(a, fp()))

def reduce2(a: List<&2, U32>) -> List<&2, U32>:
  reduce.p(reduce.p(a))

def bytes.of.go(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Bytes.rev(acc)
    case Con{h, t}:
      +h = h
      bytes.of.go(t, U32.shrn(h, 8n) <> (U32.and(h, 255) <> acc))

# 32 little-endian bytes: the least residue of a field element
def encode(a: List<&2, U32>) -> List<&2, U32>:
  bytes.of.go(reduce2(fnorm(a)), Nil{})

# RFC 7748 §5: k[0] &= 248, k[31] &= 127, k[31] |= 64
def clamp.msb(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      U32.or(U32.and(h, 127), 64) <> t

def clamp.lsb(xs: List<&2, U32>) -> List<&2, U32>:
  mask.last(xs, 248)

def clamp(xs: List<&2, U32>) -> List<&2, U32>:
  Bytes.rev(clamp.msb(clamp.lsb(Bytes.rev(xs))))

# the bits of one byte, most significant first, pushed onto acc: the last one pushed
# (bit 0, at the head) is what leaves them in order once the walk reverses at the end
def bits.byte.go(k: Nat, +b: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n:
      U32.and(U32.shrn(b, 7n), 1) <> acc
    case 1n+p:
      bits.byte.go(p, U32.shl(b), U32.and(U32.shrn(b, 7n), 1) <> acc)

def bits.go(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Bytes.rev(acc)
    case Con{b, t}:
      bits.go(t, bits.byte.go(7n, b, acc))

# the 255 bits of the clamped scalar, bit 254 first: what the ladder walks
def scalar.bits(scalar: List<&2, U32>) -> List<&2, U32>:
  Bytes.drop(bits.go(Bytes.rev(clamp(scalar)), Nil{}), 1n)

# The ladder
# ----------

# One bit of RFC 7748 §5's ladder: the conditional swaps, then
# A = x2+z2, B = x2-z2, C = x3+z3, D = x3-z3, AA = A^2, BB = B^2, E = AA-BB,
# DA = D*A, CB = C*B, x3 = (DA+CB)^2, z3 = x1*(DA-CB)^2, x2 = AA*BB,
# z2 = E*(AA + a24*E). The swaps bracket the step so that the pair holding the answer
# is the one the bit names.
def step(st: St, bit: U32) -> St:
  St{+x1, +x2, +x3, +z2, +z3} = st
  +mask = U32.sub(0, bit)
  +s2 = cswap.side(x2, x3, mask)
  +s3 = cswap.side(x3, x2, mask)
  +t2 = cswap.side(z2, z3, mask)
  +t3 = cswap.side(z3, z2, mask)
  +sum = fadd(s2, t2)
  +dif = fsub(s2, t2)
  +s34 = fadd(s3, t3)
  +d34 = fsub(s3, t3)
  +aa = fsq(sum)
  +bb = fsq(dif)
  +cb = fmul(s34, dif)
  +da = fmul(d34, sum)
  +add = fadd(cb, da)
  sub = fsub(cb, da)
  dd = fsq(sub)
  +e = fsub(aa, bb)
  t = fmul(e, fa24())
  u = fadd(t, aa)
  +z2n = fmul(e, u)
  +x2n = fmul(aa, bb)
  +z3n = fmul(dd, x1)
  +x3n = fsq(add)
  fx2 = cswap.side(x2n, x3n, mask)
  fx3 = cswap.side(x3n, x2n, mask)
  fz2 = cswap.side(z2n, z3n, mask)
  fz3 = cswap.side(z3n, z2n, mask)
  St{x1, fx2, fx3, fz2, fz3}

def ladder.go(bits: List<&2, U32>, st: St) -> St:
  match bits:
    case Nil{}:
      st
    case Con{bit, t}:
      ladder.go(t, step(st, bit))

# (x2, z2) = (1, 0), (x3, z3) = (x1, 1), the RFC 7748 §5 starting point
def start(+x1: List<&2, U32>) -> St:
  St{x1, fone(), x1, fzero(), fone()}

def ladder(bits: List<&2, U32>, x1: List<&2, U32>) -> St:
  ladder.go(bits, start(x1))

def affine(st: St) -> List<&2, U32>:
  St{x1, x2, x3, z2, z3} = st
  encode(fmul(x2, finv(z2)))

# The function
# ------------

# the 32-byte shared value of a 32-byte scalar and a 32-byte u-coordinate: the scalar
# is clamped and the top bit of u masked as RFC 7748 §5 says, and the answer is
# x2 * z2^-1 in least residue, which is zero when the point has small order
def x25519(scalar: List<&2, U32>, u: List<&2, U32>) -> List<&2, U32>:
  affine(ladder(scalar.bits(scalar), decode(u)))

# x25519(scalar, 9)
def public(scalar: List<&2, U32>) -> List<&2, U32>:
  x25519(scalar, 9 <> Bytes.zeros(31n))
