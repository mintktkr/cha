# ecdsa: ECDSA verification on the NIST P-256 and P-384 curves, the two a TLS 1.3 client
# needs for ecdsa_secp256r1_sha256 and ecdsa_secp384r1_sha384. Verification only, no
# signing. u1*G + u2*Q is one joint double-and-add in Jacobian coordinates (Shamir's
# trick), with G+Q precomputed, so a bit costs one doubling and at most one addition.
# The curve constants are SEC 2 v2.0's recommended parameters for secp256r1 and
# secp384r1, the values FIPS 186-4 D.1.2 spells out as well; both curves have a = -3,
# which the doubling and the on-curve test use. The digest is truncated to the leftmost
# bits of the order, as SEC 1 v2.0 4.1.4 says. The point formulas are the standard
# Jacobian ones (EFD dbl-2001-b and add-2007-bl), with P + P and P + (-P) checked before
# the generic addition, which divides by U2 - U1.
import Base
import ./bytes.bend as Bytes
import ./big.bend as Big
import ./sha2.bend as Sha2
import ./x509.bend as X509

type Curve is Data:
  P256{}
  P384{}

# A curve's constants: the field prime p, the curve's b, the order n, the base point G in
# affine coordinates, the field length in bytes, the bit length of n, and the Montgomery
# contexts of p (the field arithmetic) and n (the two scalar products).
type Ctx is Data:
  Ctx{p: List<&2, U32>, b: List<&2, U32>, n: List<&2, U32>, gx: List<&2, U32>,
      gy: List<&2, U32>, flen: U32, qbits: U32, fp: Big.Mont, fn: Big.Mont}

# A Jacobian point: (X, Y, Z) stands for x = X/Z^2 and y = Y/Z^3. Z = 0 is infinity,
# whatever X and Y hold.
type Pt is Data:
  Pt{x: List<&2, U32>, y: List<&2, U32>, z: List<&2, U32>}

# The curves
# ----------

# a curve constant, from its big-endian hex
def num(s: String) -> List<&2, U32>:
  Big.of_bytes(Bytes.of_hex(s))

def ctx.mk(+p: List<&2, U32>, b: List<&2, U32>, +n: List<&2, U32>,
  gx: List<&2, U32>, gy: List<&2, U32>, flen: U32, qbits: U32) -> Ctx:
  Ctx{p, b, n, gx, gy, flen, qbits, Big.mont(p), Big.mont(n)}

def ctx.of(c: Curve) -> Ctx:
  match c:
    case P256{}:
      ctx.mk(num("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff"),
        num("5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b"),
        num("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"),
        num("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"),
        num("4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"),
        32, 256)
    case P384{}:
      ctx.mk(num("fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff"),
        num("b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef"),
        num("ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973"),
        num("aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7"),
        num("3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f"),
        48, 384)

def flen.of(k: Ctx) -> U32:
  match k:
    case Ctx{_, _, _, _, _, flen, _, _, _}:
      flen

# The field, in Montgomery form
# -----------------------------

# a * b mod p
def fmul(+c: Big.Mont, a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  Big.mont.mul(c, a, b)

# a + b mod p
def fadd(+c: Big.Mont, a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  match c:
    case Big.Mont{m, mp, r2, one}:
      Big.modadd(a, b, m)

# a - b mod p
def fsub(+c: Big.Mont, a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  match c:
    case Big.Mont{m, mp, r2, one}:
      Big.modsub(a, b, m)

def f3(+c: Big.Mont, +v: List<&2, U32>) -> List<&2, U32>:
  +v2 = fadd(c, v, v)
  fadd(c, v2, v)

# the prime of a Montgomery context, and 1 in its Montgomery form (R mod p)
def mont.p(c: Big.Mont) -> List<&2, U32>:
  match c:
    case Big.Mont{m, mp, r2, one}:
      m

def fone(c: Big.Mont) -> List<&2, U32>:
  match c:
    case Big.Mont{m, mp, r2, one}:
      one

# Points
# ------

def inf() -> Pt:
  Pt{Nil{}, Nil{}, Nil{}}

# the affine (x, y) as a Jacobian point with z = 1
def point.of(+c: Big.Mont, x: List<&2, U32>, y: List<&2, U32>) -> Pt:
  Pt{Big.mont.to(c, x), Big.mont.to(c, y), fone(c)}

# 2P, for a = -3: delta = Z^2, gamma = Y^2, beta = X*gamma, and
# alpha = 3(X - delta)(X + delta); X3 = alpha^2 - 8*beta, Z3 = (Y+Z)^2 - gamma - delta,
# Y3 = alpha(4*beta - X3) - 8*gamma^2. A point at infinity doubles to one: its Z stays 0.
def dbl(+c: Big.Mont, pt: Pt) -> Pt:
  match pt:
    case Pt{+x1, +y1, +z1}:
      +delta = fmul(c, z1, z1)
      +gamma = fmul(c, y1, y1)
      +beta = fmul(c, x1, gamma)
      +xd = fsub(c, x1, delta)
      +xs = fadd(c, x1, delta)
      +alpha = f3(c, fmul(c, xd, xs))
      +alpha2 = fmul(c, alpha, alpha)
      +beta2 = fadd(c, beta, beta)
      +beta4 = fadd(c, beta2, beta2)
      +beta8 = fadd(c, beta4, beta4)
      +x3 = fsub(c, alpha2, beta8)
      +yz = fadd(c, y1, z1)
      +yz2 = fmul(c, yz, yz)
      +z3 = fsub(c, fsub(c, yz2, gamma), delta)
      +gamma2 = fmul(c, gamma, gamma)
      +g2 = fadd(c, gamma2, gamma2)
      +g4 = fadd(c, g2, g2)
      +g8 = fadd(c, g4, g4)
      +b4x = fsub(c, beta4, x3)
      +y3 = fsub(c, fmul(c, alpha, b4x), g8)
      Pt{x3, y3, z3}

# The generic addition (add-2007-bl): H = U2 - U1, I = (2H)^2, J = H*I, r = 2(S2 - S1),
# V = U1*I; X3 = r^2 - J - 2V, Y3 = r(V - X3) - 2*S1*J, Z3 = 2*Z1*Z2*H. It is an answer
# only when H is not zero, so a point at infinity and an equal-x pair are caught first.
def add.generic(+c: Big.Mont, z1: List<&2, U32>, z2: List<&2, U32>,
  +u1: List<&2, U32>, +s1: List<&2, U32>, +h: List<&2, U32>,
  +r: List<&2, U32>) -> Pt:
  +i = fadd(c, h, h)
  +i2 = fmul(c, i, i)
  +j = fmul(c, h, i2)
  +r2 = fadd(c, r, r)
  +v = fmul(c, u1, i2)
  +r22 = fmul(c, r2, r2)
  +v2 = fadd(c, v, v)
  +x3 = fsub(c, fsub(c, r22, j), v2)
  +t = fsub(c, v, x3)
  +sj1 = fmul(c, s1, j)
  +sj = fadd(c, sj1, sj1)
  +y3 = fsub(c, fmul(c, r2, t), sj)
  +z12 = fmul(c, z1, z2)
  +z3 = fmul(c, fadd(c, z12, z12), h)
  Pt{x3, y3, z3}

# H == 0 puts both points at the same x: the same point (double it) or an inverse pair
def add.inverse(+c: Big.Mont, x1: List<&2, U32>, y1: List<&2, U32>,
  z1: List<&2, U32>, rzero: Bool) -> Pt:
  match rzero:
    case True{}:
      dbl(c, Pt{x1, y1, z1})
    case False{}:
      inf()

def add.same(+c: Big.Mont, x1: List<&2, U32>, y1: List<&2, U32>,
  z1: List<&2, U32>, z2: List<&2, U32>, u1: List<&2, U32>, s1: List<&2, U32>,
  h: List<&2, U32>, +r: List<&2, U32>, same: Bool) -> Pt:
  match same:
    case True{}:
      add.inverse(c, x1, y1, z1, Big.is_zero(r))
    case False{}:
      add.generic(c, z1, z2, u1, s1, h, r)

def add.go(+c: Big.Mont, +x1: List<&2, U32>, +y1: List<&2, U32>,
  +z1: List<&2, U32>, x2: List<&2, U32>, y2: List<&2, U32>,
  +z2: List<&2, U32>) -> Pt:
  +z1z1 = fmul(c, z1, z1)
  +z2z2 = fmul(c, z2, z2)
  +u1 = fmul(c, x1, z2z2)
  +u2 = fmul(c, x2, z1z1)
  +s1 = fmul(c, y1, fmul(c, z2, z2z2))
  +s2 = fmul(c, y2, fmul(c, z1, z1z1))
  +h = fsub(c, u2, u1)
  +r = fsub(c, s2, s1)
  add.same(c, x1, y1, z1, z2, u1, s1, h, r, Big.is_zero(h))

# a + b; an a at infinity is b, a b at infinity is a
def add.zero(+c: Big.Mont, x1: List<&2, U32>, y1: List<&2, U32>,
  z1: List<&2, U32>, x2: List<&2, U32>, y2: List<&2, U32>, z2: List<&2, U32>,
  z1zero: Bool, z2zero: Bool) -> Pt:
  match z1zero z2zero:
    case True{} _:
      Pt{x2, y2, z2}
    case False{} True{}:
      Pt{x1, y1, z1}
    case False{} False{}:
      add.go(c, x1, y1, z1, x2, y2, z2)

# a + b, in Jacobian coordinates
def add(+c: Big.Mont, a: Pt, b: Pt) -> Pt:
  match a b:
    case Pt{+x1, +y1, +z1} Pt{+x2, +y2, +z2}:
      add.zero(c, x1, y1, z1, x2, y2, z2, Big.is_zero(z1), Big.is_zero(z2))

# Scalar multiplication
# ---------------------

def shamir.add(+c: Big.Mont, r: Pt, +g: Pt, +q: Pt, +gq: Pt, b1: Bool,
  b2: Bool) -> Pt:
  match b1 b2:
    case True{} True{}:
      add(c, r, gq)
    case True{} False{}:
      add(c, r, g)
    case False{} True{}:
      add(c, r, q)
    case False{} False{}:
      r

# One bit of both scalars per step, most significant first: double, then add one of
# 0, G, Q or G+Q. The bit lists are both qbits long, so they run out together.
def shamir.loop(+c: Big.Mont, +g: Pt, +q: Pt, +gq: Pt, b1: List<&2, U32>,
  b2: List<&2, U32>, r: Pt) -> Pt:
  match b1 b2:
    case Con{x1, t1} Con{x2, t2}:
      shamir.loop(c, g, q, gq, t1, t2,
        shamir.add(c, dbl(c, r), g, q, gq, U32.is_ne(x1, 0), U32.is_ne(x2, 0)))
    case _ _:
      r

# u1*G + u2*Q, both scalars below n
def mul.shamir(+c: Big.Mont, u1: List<&2, U32>, u2: List<&2, U32>, +g: Pt,
  +q: Pt, +qbits: U32) -> Pt:
  +limbs = U32.to_nat(U32.div(qbits, 16))
  shamir.loop(c, g, q, add(c, g, q), Big.bits.of(Big.fit(u1, limbs)),
    Big.bits.of(Big.fit(u2, limbs)), inf())

# The signature and the key
# -------------------------

# the leftmost min(bits, qbits) bits of a digest, as a number. Both curves' orders are a
# whole number of bytes, so it takes whole bytes and never shifts.
def trunc(xs: List<&2, U32>, +qbits: U32) -> List<&2, U32>:
  Big.of_bytes(Bytes.take(xs, U32.to_nat(U32.div(qbits, 8))))

def cmp.lt(c: Cmp) -> Bool:
  match c:
    case LT{}:
      True{}
    case _:
      False{}

# a field coordinate is below p
def coord.ok(+p: List<&2, U32>, x: List<&2, U32>) -> Bool:
  cmp.lt(Big.cmp(x, p))

# a signature value is in [1, n-1]
def range.ok(+n: List<&2, U32>, +x: List<&2, U32>) -> Bool:
  Bool.and(Bool.not(Big.is_zero(x)), cmp.lt(Big.cmp(x, n)))

def sig.ok(+n: List<&2, U32>, r: List<&2, U32>, s: List<&2, U32>) -> Bool:
  Bool.and(range.ok(n, r), range.ok(n, s))

# y^2 == x^3 - 3x + b mod p, with a = -3 for both curves. x and y must be below p.
def on.curve(+c: Big.Mont, b: List<&2, U32>, x: List<&2, U32>,
  +y: List<&2, U32>) -> Bool:
  +xm = Big.mont.to(c, x)
  +ym = Big.mont.to(c, y)
  +lhs = fmul(c, ym, ym)
  +x2 = fmul(c, xm, xm)
  +x3 = fmul(c, x2, xm)
  +t = fsub(c, x3, f3(c, xm))
  +rhs = fadd(c, t, Big.mont.to(c, b))
  Bytes.eq(lhs, rhs)

# the key's coordinates are below p and satisfy the curve equation
def point.ok(+c: Big.Mont, +p: List<&2, U32>, b: List<&2, U32>,
  +x: List<&2, U32>, +y: List<&2, U32>) -> Bool:
  Bool.and(coord.ok(p, x), Bool.and(coord.ok(p, y), on.curve(c, b, x, y)))

# the two coordinates of an uncompressed public key 04 || X || Y, each exactly flen bytes
def pub.len(+rest: List<&2, U32>, +flen: U32, ok: Bool) -> Maybe<&2, X509.Two()>:
  match ok:
    case True{}:
      Some{(Big.of_bytes(Bytes.take(rest, U32.to_nat(flen))),
        Big.of_bytes(Bytes.drop(rest, U32.to_nat(flen))))}
    case False{}:
      None{}

def pub.lead(+rest: List<&2, U32>, +flen: U32, ok: Bool) -> Maybe<&2, X509.Two()>: 
  match ok:
    case True{}:
      pub.len(rest, flen, U32.is_eq(Bytes.len(rest), U32.mul(2, flen)))
    case False{}:
      None{}

def pub.split(pub: List<&2, U32>, +flen: U32) -> Maybe<&2, X509.Two()>:
  match pub:
    case Con{+tag, rest}:
      pub.lead(rest, flen, U32.is_eq(tag, 4))
    case Nil{}:
      None{}

# Verification
# ------------

# X * (Z^-1)^2 mod p, then mod n: the value a signature's r is compared against
def affine.x(+c: Big.Mont, +n: List<&2, U32>, rx: List<&2, U32>,
  rz: List<&2, U32>) -> List<&2, U32>:
  +p = mont.p(c)
  +zinv = Big.modinv(Big.mont.from(c, rz), p)
  +zi2 = Big.modmul(zinv, zinv, p)
  +xn = Big.mont.from(c, rx)
  Big.mod(Big.modmul(xn, zi2, p), n)

def verify.inf(+c: Big.Mont, +n: List<&2, U32>, rx: List<&2, U32>,
  ry: List<&2, U32>, rz: List<&2, U32>, r: List<&2, U32>, inf: Bool) -> Bool:
  match inf:
    case True{}:
      False{}
    case False{}:
      Bytes.eq(affine.x(c, n, rx, rz), r)

def verify.fin(+c: Big.Mont, +n: List<&2, U32>, pt: Pt, r: List<&2, U32>) -> Bool:
  match pt:
    case Pt{rx, ry, +rz}:
      verify.inf(c, n, rx, ry, rz, r, Big.is_zero(rz))

def verify.math(+k: Ctx, x: List<&2, U32>, y: List<&2, U32>,
  digest: List<&2, U32>, +r: List<&2, U32>, s: List<&2, U32>) -> Bool:
  match k:
    case Ctx{_, _, +n, +gx, +gy, _, +qbits, +fp, fn}:
      +w = Big.modinv(s, n)
      +u1 = Big.modmul(w, Big.mod(trunc(digest, qbits), n), n)
      +u2 = Big.modmul(w, r, n)
      verify.fin(fp, n,
        mul.shamir(fp, u1, u2, point.of(fp, gx, gy), point.of(fp, x, y), qbits), r)

def verify.go(+k: Ctx, x: List<&2, U32>, y: List<&2, U32>,
  digest: List<&2, U32>, r: List<&2, U32>, s: List<&2, U32>, ok: Bool) -> Bool:
  match ok:
    case True{}:
      verify.math(k, x, y, digest, r, s)
    case False{}:
      False{}

# r and s in [1, n-1], and the key on the curve
def verify.ok(+k: Ctx, x: List<&2, U32>, +y: List<&2, U32>,
  r: List<&2, U32>, s: List<&2, U32>) -> Bool:
  match k:
    case Ctx{+p, b, +n, _, _, _, _, +fp, _}:
      Bool.and(sig.ok(n, r, s), point.ok(fp, p, b, x, y))

def verify.point(+k: Ctx, +x: List<&2, U32>, +y: List<&2, U32>,
  digest: List<&2, U32>, +r: List<&2, U32>, +s: List<&2, U32>) -> Bool:
  verify.go(k, x, y, digest, r, s, verify.ok(k, x, y, r, s))

def verify.key(+k: Ctx, m: Maybe<&2, X509.Two()>, digest: List<&2, U32>,
  r: List<&2, U32>, s: List<&2, U32>) -> Bool:
  match m:
    case Some{p}:
      (x, y) = p
      verify.point(k, x, y, digest, r, s)
    case None{}:
      False{}

# is (r, s) a signature of pub over the digest? pub is the uncompressed point
# 04 || X || Y; the digest is the message hash, of any length (its leftmost bits are
# used); r and s are big-endian byte strings.
def verify(c: Curve, +pub: List<&2, U32>, digest: List<&2, U32>,
  r: List<&2, U32>, s: List<&2, U32>) -> Bool:
  +k = ctx.of(c)
  verify.key(k, pub.split(pub, flen.of(k)), digest, Big.of_bytes(r), Big.of_bytes(s))

# hash msg with a, take r and s from a DER ECDSA-Sig-Value, and verify
def der.sig(c: Curve, pub: List<&2, U32>, digest: List<&2, U32>,
  m: Maybe<&2, X509.Two()>) -> Bool:
  match m:
    case Some{p}:
      (r, s) = p
      verify(c, pub, digest, r, s)
    case None{}:
      False{}

def verify.der(c: Curve, a: Sha2.Alg, pub: List<&2, U32>, msg: List<&2, U32>,
  sig: List<&2, U32>) -> Bool:
  der.sig(c, pub, Sha2.hash(a, msg), X509.ecdsa_sig(sig))

# Naming
# ------

def curve.p384(ok: Bool) -> Maybe<&2, Curve>:
  match ok:
    case True{}:
      Some{P384{}}
    case False{}:
      None{}

def curve.p256(ok: Bool, +oid: String) -> Maybe<&2, Curve>:
  match ok:
    case True{}:
      Some{P256{}}
    case False{}:
      curve.p384(String.eq(oid, "1.3.132.0.34"))

# the curve of a namedCurve OID: prime256v1 or secp384r1
def curve(+oid: String) -> Maybe<&2, Curve>:
  curve.p256(String.eq(oid, "1.2.840.10045.3.1.7"), oid)
