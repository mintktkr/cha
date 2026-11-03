# rsa: RSA signature verification, as a certificate chain and TLS 1.3's
# CertificateVerify need it: RSASSA-PKCS1-v1_5 (RFC 8017 §8.2.2) and RSASSA-PSS
# (§8.1.2) with MGF1 of the same hash and a hash-sized salt, over big.bend's modexp
# and sha2.bend's digests. The expected encoded message is rebuilt from the hash and
# the whole of it compared, never parsed: that is what keeps Bleichenbacher's
# forgeries out. Verification only, so nothing here signs and no key is generated.
import Base
import ./bytes.bend as Bytes
import ./big.bend as Big
import ./sha2.bend as Sha2

# Byte helpers
# ------------

# the first byte, 0 for an empty list
def first(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{h, t}:
      h

# the byte at index i, 0 past the end
def byte.at(xs: List<&2, U32>, i: Nat) -> U32:
  first(Bytes.drop(xs, i))

def all_zero.go(xs: List<&2, U32>, acc: Bool) -> Bool:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      all_zero.go(t, Bool.and(acc, U32.is_eq(h, 0)))

# every byte zero
def all_zero(xs: List<&2, U32>) -> Bool:
  all_zero.go(xs, True{})

# the first byte and-ed with b, the rest untouched
def mask.first(m: List<&2, U32>, b: U32) -> List<&2, U32>:
  match m:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      U32.and(h, b) <> t

# The key rules
# -------------

def cmp.lt(c: Cmp) -> Bool:
  match c:
    case LT{}:
      True{}
    case EQ{}:
      False{}
    case GT{}:
      False{}

def cmp.gt(c: Cmp) -> Bool:
  match c:
    case LT{}:
      False{}
    case EQ{}:
      False{}
    case GT{}:
      True{}

# the signature is exactly the modulus length (RFC 8017 §8.1.2 step 1, §8.2.2 step 1)
def sig.len.ok(+sig: List<&2, U32>, +n: List<&2, U32>) -> Bool:
  U32.is_eq(Bytes.len(sig), Bytes.len(n))

# the signature representative is below n (RFC 8017 §5.2.2 step 1)
def sig.below(+sig: List<&2, U32>, +n: List<&2, U32>) -> Bool:
  cmp.lt(Big.cmp(Big.of_bytes(sig), Big.of_bytes(n)))

def exp.ok(+e: List<&2, U32>, odd: Bool) -> Bool:
  match odd:
    case False{}:
      False{}
    case True{}:
      cmp.gt(Big.cmp(Big.of_bytes(e), Big.of_u32(1)))

# an exponent that is even, or 1, is not usable: e = 1 makes every signature the message,
# and an even e shares a factor with the modulus. The bytes are big-endian, so they go
# through of_bytes before any limb reads: head is the least significant limb, not the
# first byte
def exp.rule(+e: List<&2, U32>) -> Bool:
  exp.ok(e, Bool.not(U32.is_even(Big.head(Big.of_bytes(e)))))

# the bit length of a big-endian modulus: Big.bits reads limbs, so the bytes convert
# first. Reading the bytes as limbs overcounts the length almost twofold, which is
# what broke pss.emlen.
def mod.bits(+n: List<&2, U32>) -> U32:
  Big.bits(Big.of_bytes(n))

# a modulus of 2048 bits and up: below that the RSA problem is not what holds a
# certificate together
def key.ok(+n: List<&2, U32>, +e: List<&2, U32>) -> Bool:
  Bool.and(U32.is_ge(mod.bits(n), 2048), exp.rule(e))

# the shape checks both schemes share: the signature is exactly the modulus length, below
# n, and the key is at least 2048 bits with an odd exponent above 1
def input.ok(+sig: List<&2, U32>, +n: List<&2, U32>, +e: List<&2, U32>) -> Bool:
  Bool.and(Bool.and(sig.len.ok(sig, n), sig.below(sig, n)), key.ok(n, e))

# RSAVP1 (RFC 8017 §5.2.2): the message representative s^e mod n, for an s below n
def rsa.rep(+n: List<&2, U32>, +e: List<&2, U32>, +sig: List<&2, U32>) -> List<&2, U32>:
  Big.modexp(Big.of_bytes(sig), Big.of_bytes(e), Big.of_bytes(n))

# the representative as k octets against the rebuilt EM, in time that depends only on the
# length: the decrypted block itself is never read
def verify.if(ok: Bool, +n: List<&2, U32>, +e: List<&2, U32>, +sig: List<&2, U32>,
  +want: List<&2, U32>) -> Bool:
  match ok:
    case False{}:
      False{}
    case True{}:
      Bytes.ct_eq(Big.to_bytes(rsa.rep(n, e, sig), Bytes.len(n)), want)

# DigestInfo
# ----------

# the DER a DigestInfo opens with for a (RFC 8017 §9.2 note 1): the SEQUENCE, the
# AlgorithmIdentifier with its NULL parameter, and the OCTET STRING header the digest
# follows
def digest_info(a: Sha2.Alg) -> List<&2, U32>:
  match a:
    case Sha2.S256{}:
      Bytes.of_hex("3031300d060960864801650304020105000420")
    case Sha2.S384{}:
      Bytes.of_hex("3041300d060960864801650304020205000430")
    case Sha2.S512{}:
      Bytes.of_hex("3051300d060960864801650304020305000440")

# T of RFC 8017 §9.2: the DigestInfo of the digest of msg
def em.t(+a: Sha2.Alg, +msg: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(digest_info(a), Sha2.hash(a, msg))

# the length of T: the DigestInfo prefix for a and then the digest
def t.len(+a: Sha2.Alg) -> U32:
  U32.add(Bytes.len(digest_info(a)), Sha2.size(a))

# emLen must leave room for T and at least 8 0xff octets (RFC 8017 §9.2 step 3)
def pkcs1.fit(+k: U32, +tlen: U32) -> Bool:
  U32.is_ge(k, U32.add(tlen, 11))

# PKCS#1 v1.5 (RFC 8017 §8.2.2)
# -----------------------------

# the 0xff run, empty when the digest does not fit, which pkcs1.fit has already rejected
def em.ps(+k: U32, +tlen: U32, fit: Bool) -> List<&2, U32>:
  match fit:
    case True{}:
      Sha2.fill(255, U32.to_nat(U32.sub(U32.sub(k, tlen), 3)))
    case False{}:
      Nil{}

# EM of RFC 8017 §9.2: 0x00, 0x01, ps octets of 0xff, 0x00 and T
def em.build(+t: List<&2, U32>, +ps: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat([0, 1], Bytes.cat(ps, Bytes.cat([0], t)))

# the EM cha expects, rebuilt from the hash: no byte of the signature reaches the answer
def pkcs1.em(+a: Sha2.Alg, +n: List<&2, U32>, msg: List<&2, U32>) -> List<&2, U32>:
  +k = Bytes.len(n)
  +t = em.t(a, msg)
  +tlen = Bytes.len(t)
  em.build(t, em.ps(k, tlen, pkcs1.fit(k, tlen)))

# the input rules of RSASSA-PKCS1-v1_5-VERIFY: the shape checks, plus room for the
# DigestInfo of this hash
def pkcs1.ok(+a: Sha2.Alg, +n: List<&2, U32>, +e: List<&2, U32>, +sig: List<&2, U32>) ->
  Bool:
  Bool.and(input.ok(sig, n, e), pkcs1.fit(Bytes.len(n), t.len(a)))

# RSASSA-PKCS1-v1_5-VERIFY (RFC 8017 §8.2.2): EMSA-PKCS1-v1_5 with the DigestInfo for a,
# then RSAVP1 and a constant-time compare with the EM it must have produced
def pkcs1(+a: Sha2.Alg, +n: List<&2, U32>, +e: List<&2, U32>, msg: List<&2, U32>,
  +sig: List<&2, U32>) -> Bool:
  verify.if(pkcs1.ok(a, n, e, sig), n, e, sig, pkcs1.em(a, n, msg))

# MGF1 (RFC 8017 B.2.1)
# ---------------------

def mgf1.go(+a: Sha2.Alg, +seed: List<&2, U32>, fuel: Nat, +i: U32,
  acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      mgf1.go(a, seed, p, (i + 1 : U32),
        Bytes.rev.onto(Sha2.hash(a, Bytes.cat(seed, Bytes.be32(i))), acc))

# maskLen octets of Hash(seed || counter), the counter big-endian from zero
def mgf1(+a: Sha2.Alg, +seed: List<&2, U32>, +len: U32) -> List<&2, U32>:
  +hlen = Sha2.size(a)
  +blocks = U32.div(U32.add(len, U32.sub(hlen, 1)), hlen)
  Bytes.take(Bytes.rev(mgf1.go(a, seed, U32.to_nat(blocks), 0, Nil{})), U32.to_nat(len))

# PSS (RFC 8017 §8.1.2, §9.1.2)
# -----------------------------

# emBits is modBits - 1, so emLen is ceil((modBits - 1) / 8): one octet narrower than the
# signature when the modulus holds a whole number of them
def pss.emlen(+modbits: U32) -> U32:
  U32.div(U32.add(U32.sub(modbits, 1), 7), 8)

# the bits of DB that the EM does not cover: 8 * emLen - emBits, 0 to 7
def pss.unused(+emlen: U32, +modbits: U32) -> U32:
  U32.sub(U32.mul(emlen, 8), U32.sub(modbits, 1))

# step 10: those bits of DB are zero after the unmask
def pss.mask(+db: List<&2, U32>, +unused: U32) -> List<&2, U32>:
  mask.first(db, U32.shrn(255, U32.to_nat(unused)))

# step 4 and step 6: the trailing 0xbc, and the bits of the leftmost octet above emBits
def pss.frame(+em: List<&2, U32>, +unused: U32) -> Bool:
  Bool.and(
    U32.is_eq(byte.at(em, U32.to_nat(U32.sub(Bytes.len(em), 1))), 188),
    U32.is_eq(U32.shrn(first(em), Nat.sub(8n, U32.to_nat(unused))), 0))

# step 10: DB is a run of zero octets and then one 0x01, which the salt follows
def pss.sep(+db: List<&2, U32>, +pslen: U32) -> Bool:
  Bool.and(all_zero(Bytes.take(db, U32.to_nat(pslen))),
    U32.is_eq(byte.at(db, U32.to_nat(pslen)), 1))

# step 13: M' is eight zero octets, the message digest and the salt, the salt being the
# trailing hLen octets of DB
def pss.mp(+a: Sha2.Alg, +msg: List<&2, U32>, +db: List<&2, U32>, +hlen: U32) ->
  List<&2, U32>:
  Bytes.cat(Bytes.zeros(8n),
    Bytes.cat(Sha2.hash(a, msg),
      Bytes.drop(db, U32.to_nat(U32.sub(Bytes.len(db), hlen)))))

# steps 4 to 14 (RFC 8017 §9.1.2) over the EM: the trailer, the masked bits, the MGF1
# unmask, the zero run and the 0x01, and H against Hash(M')
def pss.em.ok(+a: Sha2.Alg, +msg: List<&2, U32>, +em: List<&2, U32>, +hlen: U32,
  +unused: U32) -> Bool:
  +emlen = Bytes.len(em)
  +dblen = U32.sub(U32.sub(emlen, hlen), 1)
  +masked = Bytes.take(em, U32.to_nat(dblen))
  +h = Bytes.take(Bytes.drop(em, U32.to_nat(dblen)), U32.to_nat(hlen))
  +db = pss.mask(Bytes.xor(masked, mgf1(a, h, dblen)), unused)
  +pslen = U32.sub(U32.sub(dblen, hlen), 1)
  Bool.and(Bool.and(pss.frame(em, unused), pss.sep(db, pslen)),
    Bytes.ct_eq(h, Sha2.hash(a, pss.mp(a, msg, db, hlen))))

def fit.if(+m: List<&2, U32>, +emlen: U32, ok: Bool) -> Maybe<&2, List<&2, U32>>:
  match ok:
    case True{}:
      Some{Big.to_bytes(m, emlen)}
    case False{}:
      None{}

# RSAVP1 then I2OSP to emLen octets: None when the representative does not fit, which can
# happen to a modulus with one bit more than a whole number of octets
def pss.em.of(+n: List<&2, U32>, +e: List<&2, U32>, +sig: List<&2, U32>, +emlen: U32) ->
  Maybe<&2, List<&2, U32>>:
  +m = rsa.rep(n, e, sig)
  fit.if(m, emlen, U32.is_le(Big.bits(m), U32.mul(emlen, 8)))

# steps 4 to 14 over the EM that the signature decodes to
def pss.check(+a: Sha2.Alg, +msg: List<&2, U32>, m: Maybe<&2, List<&2, U32>>,
  +modbits: U32, +hlen: U32) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{em}:
      pss.em.ok(a, msg, em, hlen, pss.unused(pss.emlen(modbits), modbits))

# the input rules of RSASSA-PSS-VERIFY: the shape checks, plus room for a salt as long as
# the hash and the two octets around it (RFC 8017 §9.1.2 step 3)
def pss.ok(+a: Sha2.Alg, +n: List<&2, U32>, +e: List<&2, U32>, +sig: List<&2, U32>) ->
  Bool:
  Bool.and(input.ok(sig, n, e),
    U32.is_ge(pss.emlen(mod.bits(n)), U32.add(U32.mul(Sha2.size(a), 2), 2)))

def pss.go(ok: Bool, +a: Sha2.Alg, +n: List<&2, U32>, +e: List<&2, U32>,
  msg: List<&2, U32>, +sig: List<&2, U32>) -> Bool:
  match ok:
    case False{}:
      False{}
    case True{}:
      pss.check(a, msg, pss.em.of(n, e, sig, pss.emlen(mod.bits(n))), mod.bits(n),
        Sha2.size(a))

# RSASSA-PSS-VERIFY (RFC 8017 §8.1.2): EMSA-PSS-VERIFY with MGF1 of the same hash and a
# salt as long as it, which is what TLS 1.3's rsa_pss_rsae_* schemes and the web PKI use
def pss(+a: Sha2.Alg, +n: List<&2, U32>, +e: List<&2, U32>, msg: List<&2, U32>,
  +sig: List<&2, U32>) -> Bool:
  pss.go(pss.ok(a, n, e, sig), a, n, e, msg, sig)
