# sha2: SHA-256, SHA-384 and SHA-512, HMAC, HKDF and the TLS 1.3 key schedule
# (FIPS 180-4, RFC 2104, RFC 5869, RFC 8446 7.1), over the byte strings of
# bytes.bend. A 64-bit word rides as W64{hi, lo}, since U32 mul, shifts and
# rotations are 32-bit: the pairs are added, rotated and shifted by hand.
import Base
import ./bytes.bend as Bytes

type Alg is Data:
  S256{}
  S384{}
  S512{}

# digest size in bytes: 32, 48, 64
def size(a: Alg) -> U32:
  match a:
    case S256{}:
      32
    case S384{}:
      48
    case S512{}:
      64

# compression block size in bytes: 64 for SHA-256, 128 for SHA-384 and -512
def block(a: Alg) -> U32:
  match a:
    case S256{}:
      64
    case S384{}:
      128
    case S512{}:
      128

# Padding
# -------

def be.nat.go(n: Nat, +v: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      be.nat.go(p, Nat.div(v, 256n), U32.from_nat(Nat.mod(v, 256n)) <> acc)

# the low n bytes of v, big-endian: the length field of the padding
def be.nat(+v: Nat, n: Nat) -> List<&2, U32>:
  be.nat.go(n, v, Nil{})

def pad.need(r: Nat, bs: Nat, whole: Bool) -> Nat:
  match whole:
    case True{}:
      0n
    case False{}:
      Nat.sub(bs, r)

# the message, then 0x80, zero fill and the bit length in lw big-endian bytes:
# always a whole number of bs-byte blocks
def pad.to(+msg: List<&2, U32>, +bs: Nat, +lw: Nat) -> List<&2, U32>:
  +n = U32.to_nat(Bytes.len(msg))
  +r = Nat.mod(Nat.add(Nat.add(n, 1n), lw), bs)
  +zeros = pad.need(r, bs, Nat.is_eq(r, 0n))
  Bytes.cat(Bytes.cat(Bytes.cat(msg, [128]), Bytes.zeros(zeros)), be.nat(Nat.mul(n, 8n), lw))

# The message, as words
# ---------------------

def words32.go(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      List.reverse(&2, U32, acc)
    case Con{a, Con{b, Con{c, Con{d, t}}}}:
      words32.go(t, Bytes.get.be([a, b, c, d], 4n) <> acc)
    case _:
      List.reverse(&2, U32, acc)

# the padded message as big-endian 32-bit words
def words32(xs: List<&2, U32>) -> List<&2, U32>:
  words32.go(xs, Nil{})

def words64.go(xs: List<&2, U32>, acc: List<&2, W64>) -> List<&2, W64>:
  match xs:
    case Nil{}:
      List.reverse(&2, W64, acc)
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, t}}}}}}}}:
      words64.go(t, W64{Bytes.get.be([a, b, c, d], 4n), Bytes.get.be([e, f, g, h], 4n)} <> acc)
    case _:
      List.reverse(&2, W64, acc)

# the padded message as big-endian 64-bit words
def words64(xs: List<&2, U32>) -> List<&2, W64>:
  words64.go(xs, Nil{})

# The 32-bit round functions (FIPS 180-4 4.1.2)
# ---------------------------------------------

def rot.r(+x: U32, +k: Nat) -> U32:
  U32.or(U32.shrn(x, k), U32.shln(x, Nat.sub(32n, k)))

def bsig0(+x: U32) -> U32:
  U32.xor(U32.xor(rot.r(x, 2n), rot.r(x, 13n)), rot.r(x, 22n))

def bsig1(+x: U32) -> U32:
  U32.xor(U32.xor(rot.r(x, 6n), rot.r(x, 11n)), rot.r(x, 25n))

def ssig0(+x: U32) -> U32:
  U32.xor(U32.xor(rot.r(x, 7n), rot.r(x, 18n)), U32.shrn(x, 3n))

def ssig1(+x: U32) -> U32:
  U32.xor(U32.xor(rot.r(x, 17n), rot.r(x, 19n)), U32.shrn(x, 10n))

def ch(+x: U32, +y: U32, +z: U32) -> U32:
  U32.xor(U32.and(x, y), U32.and(U32.not(x), z))

def maj(+x: U32, +y: U32, +z: U32) -> U32:
  U32.xor(U32.xor(U32.and(x, y), U32.and(x, z)), U32.and(y, z))

# SHA-256
# -------

type St256 is Data:
  St256{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}

def iv256() -> St256:
  St256{1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225}

def k256() -> List<&2, U32>:
  [1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221,
    3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580,
    3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986,
    2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895,
    666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037,
    2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344,
    430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779,
    1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298]

# one round: the schedule word w and the constant k, over the working variables
def sha256.round(+k: U32, +w: U32, st: St256) -> St256:
  match st:
    case St256{+a, +b, +c, +d, +e, +f, +g, +h}:
      +t1 = U32.add(U32.add(U32.add(h, bsig1(e)), ch(e, f, g)), U32.add(k, w))
      +t2 = U32.add(bsig0(a), maj(a, b, c))
      St256{U32.add(t1, t2), a, b, c, U32.add(d, t1), e, f, g}

def sha256.feed(a: St256, b: St256) -> St256:
  match a b:
    case St256{x0, x1, x2, x3, x4, x5, x6, x7} St256{y0, y1, y2, y3, y4, y5, y6, y7}:
      St256{U32.add(x0, y0), U32.add(x1, y1), U32.add(x2, y2), U32.add(x3, y3), U32.add(x4, y4), U32.add(x5, y5), U32.add(x6, y6), U32.add(x7, y7)}

# the 64 words of a block: the 16 given ones, then w[i-16] + s0(w[i-15]) +
# w[i-7] + s1(w[i-2]). The last 16 words ride as a window, newest last.
def sha256.sched.go(n: Nat, +ws: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, acc)
    case 1n+p:
      match ws:
        case Con{+p0, Con{+p1, Con{p2, Con{p3, Con{p4, Con{p5, Con{p6, Con{p7, Con{p8, Con{p9, Con{p10, Con{p11, Con{p12, Con{p13, Con{+p14, Con{p15, Nil{}}}}}}}}}}}}}}}}}:
          +w = U32.add(U32.add(ssig1(p14), p9), U32.add(ssig0(p1), p0))
          sha256.sched.go(p, [p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, w], w <> acc)
        case _:
          List.reverse(&2, U32, acc)

def sha256.sched(+ws: List<&2, U32>) -> List<&2, U32>:
  sha256.sched.go(48n, ws, List.reverse(&2, U32, ws))

def sha256.rounds(k: List<&2, U32>, w: List<&2, U32>, st: St256) -> St256:
  match k w:
    case Nil{} Nil{}:
      st
    case Con{kh, kt} Con{wh, wt}:
      sha256.rounds(kt, wt, sha256.round(kh, wh, st))
    case _ _:
      st

# one 16-word block, folded into the state
def sha256.block(ws: List<&2, U32>, +st: St256) -> St256:
  sha256.feed(st, sha256.rounds(k256(), sha256.sched(ws), st))

def sha256.blocks(xs: List<&2, U32>, +st: St256) -> St256:
  match xs:
    case Nil{}:
      st
    case Con{w0, Con{w1, Con{w2, Con{w3, Con{w4, Con{w5, Con{w6, Con{w7, Con{w8, Con{w9, Con{w10, Con{w11, Con{w12, Con{w13, Con{w14, Con{w15, t}}}}}}}}}}}}}}}}:
      sha256.blocks(t, sha256.block([w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15], st))
    case _:
      st

def sha256.out(st: St256) -> List<&2, U32>:
  match st:
    case St256{a, b, c, d, e, f, g, h}:
      Bytes.cat(Bytes.be32(a), Bytes.cat(Bytes.be32(b), Bytes.cat(Bytes.be32(c), Bytes.cat(Bytes.be32(d), Bytes.cat(Bytes.be32(e), Bytes.cat(Bytes.be32(f), Bytes.cat(Bytes.be32(g), Bytes.be32(h))))))))

def sha256.hash(msg: List<&2, U32>) -> List<&2, U32>:
  sha256.out(sha256.blocks(words32(pad.to(msg, 64n, 8n)), iv256()))

# 64-bit words
# ------------

type W64 is Data:
  W64{hi: U32, lo: U32}

def w.add(a: W64, b: W64) -> W64:
  match a b:
    case W64{ah, +al} W64{bh, bl}:
      +lo = U32.add(al, bl)
      W64{U32.add(U32.add(ah, bh), Bool.to_u32(U32.is_lt(lo, al))), lo}

def w.xor(a: W64, b: W64) -> W64:
  match a b:
    case W64{ah, al} W64{bh, bl}:
      W64{U32.xor(ah, bh), U32.xor(al, bl)}

def w.and(a: W64, b: W64) -> W64:
  match a b:
    case W64{ah, al} W64{bh, bl}:
      W64{U32.and(ah, bh), U32.and(al, bl)}

def w.not(a: W64) -> W64:
  match a:
    case W64{hi, lo}:
      W64{U32.not(hi), U32.not(lo)}

def w.swap(a: W64) -> W64:
  match a:
    case W64{hi, lo}:
      W64{lo, hi}

# rotate right by k, 1 <= k <= 31
def w.rot.small(a: W64, +k: Nat) -> W64:
  match a:
    case W64{+hi, +lo}:
      W64{U32.or(U32.shrn(hi, k), U32.shln(lo, Nat.sub(32n, k))), U32.or(U32.shrn(lo, k), U32.shln(hi, Nat.sub(32n, k)))}

# rotate right by k, 32 <= k <= 63: swap the halves and turn k into k - 32
def w.rot.big(a: W64, +k: Nat) -> W64:
  w.rot.small(w.swap(a), Nat.sub(k, 32n))

def w.rot.if(+a: W64, +k: Nat, small: Bool) -> W64:
  match small:
    case True{}:
      w.rot.small(a, k)
    case False{}:
      w.rot.big(a, k)

def w.rot(+a: W64, +k: Nat) -> W64:
  w.rot.if(a, k, Nat.is_lt(k, 32n))

def w.shr(a: W64, +k: Nat) -> W64:
  match a:
    case W64{+hi, +lo}:
      W64{U32.shrn(hi, k), U32.or(U32.shrn(lo, k), U32.shln(hi, Nat.sub(32n, k)))}

def w.bsig0(+x: W64) -> W64:
  w.xor(w.xor(w.rot(x, 28n), w.rot(x, 34n)), w.rot(x, 39n))

def w.bsig1(+x: W64) -> W64:
  w.xor(w.xor(w.rot(x, 14n), w.rot(x, 18n)), w.rot(x, 41n))

def w.ssig0(+x: W64) -> W64:
  w.xor(w.xor(w.rot(x, 1n), w.rot(x, 8n)), w.shr(x, 7n))

def w.ssig1(+x: W64) -> W64:
  w.xor(w.xor(w.rot(x, 19n), w.rot(x, 61n)), w.shr(x, 6n))

def w.ch(+x: W64, +y: W64, +z: W64) -> W64:
  w.xor(w.and(x, y), w.and(w.not(x), z))

def w.maj(+x: W64, +y: W64, +z: W64) -> W64:
  w.xor(w.xor(w.and(x, y), w.and(x, z)), w.and(y, z))

def w.be(w: W64) -> List<&2, U32>:
  match w:
    case W64{hi, lo}:
      Bytes.cat(Bytes.be32(hi), Bytes.be32(lo))

# SHA-384 and SHA-512
# -------------------

type St512 is Data:
  St512{a: W64, b: W64, c: W64, d: W64, e: W64, f: W64, g: W64, h: W64}

def iv512() -> St512:
  St512{W64{1779033703, 4089235720}, W64{3144134277, 2227873595}, W64{1013904242, 4271175723}, W64{2773480762, 1595750129}, W64{1359893119, 2917565137}, W64{2600822924, 725511199}, W64{528734635, 4215389547}, W64{1541459225, 327033209}}

def iv384() -> St512:
  St512{W64{3418070365, 3238371032}, W64{1654270250, 914150663}, W64{2438529370, 812702999}, W64{355462360, 4144912697}, W64{1731405415, 4290775857}, W64{2394180231, 1750603025}, W64{3675008525, 1694076839}, W64{1203062813, 3204075428}}

def k512() -> List<&2, W64>:
  [W64{1116352408, 3609767458}, W64{1899447441, 602891725}, W64{3049323471, 3964484399}, W64{3921009573, 2173295548},
    W64{961987163, 4081628472}, W64{1508970993, 3053834265}, W64{2453635748, 2937671579}, W64{2870763221, 3664609560},
    W64{3624381080, 2734883394}, W64{310598401, 1164996542}, W64{607225278, 1323610764}, W64{1426881987, 3590304994},
    W64{1925078388, 4068182383}, W64{2162078206, 991336113}, W64{2614888103, 633803317}, W64{3248222580, 3479774868},
    W64{3835390401, 2666613458}, W64{4022224774, 944711139}, W64{264347078, 2341262773}, W64{604807628, 2007800933},
    W64{770255983, 1495990901}, W64{1249150122, 1856431235}, W64{1555081692, 3175218132}, W64{1996064986, 2198950837},
    W64{2554220882, 3999719339}, W64{2821834349, 766784016}, W64{2952996808, 2566594879}, W64{3210313671, 3203337956},
    W64{3336571891, 1034457026}, W64{3584528711, 2466948901}, W64{113926993, 3758326383}, W64{338241895, 168717936},
    W64{666307205, 1188179964}, W64{773529912, 1546045734}, W64{1294757372, 1522805485}, W64{1396182291, 2643833823},
    W64{1695183700, 2343527390}, W64{1986661051, 1014477480}, W64{2177026350, 1206759142}, W64{2456956037, 344077627},
    W64{2730485921, 1290863460}, W64{2820302411, 3158454273}, W64{3259730800, 3505952657}, W64{3345764771, 106217008},
    W64{3516065817, 3606008344}, W64{3600352804, 1432725776}, W64{4094571909, 1467031594}, W64{275423344, 851169720},
    W64{430227734, 3100823752}, W64{506948616, 1363258195}, W64{659060556, 3750685593}, W64{883997877, 3785050280},
    W64{958139571, 3318307427}, W64{1322822218, 3812723403}, W64{1537002063, 2003034995}, W64{1747873779, 3602036899},
    W64{1955562222, 1575990012}, W64{2024104815, 1125592928}, W64{2227730452, 2716904306}, W64{2361852424, 442776044},
    W64{2428436474, 593698344}, W64{2756734187, 3733110249}, W64{3204031479, 2999351573}, W64{3329325298, 3815920427},
    W64{3391569614, 3928383900}, W64{3515267271, 566280711}, W64{3940187606, 3454069534}, W64{4118630271, 4000239992},
    W64{116418474, 1914138554}, W64{174292421, 2731055270}, W64{289380356, 3203993006}, W64{460393269, 320620315},
    W64{685471733, 587496836}, W64{852142971, 1086792851}, W64{1017036298, 365543100}, W64{1126000580, 2618297676},
    W64{1288033470, 3409855158}, W64{1501505948, 4234509866}, W64{1607167915, 987167468}, W64{1816402316, 1246189591}]

def sha512.round(+k: W64, +w: W64, st: St512) -> St512:
  match st:
    case St512{+a, +b, +c, +d, +e, +f, +g, +h}:
      +t1 = w.add(w.add(w.add(h, w.bsig1(e)), w.ch(e, f, g)), w.add(k, w))
      +t2 = w.add(w.bsig0(a), w.maj(a, b, c))
      St512{w.add(t1, t2), a, b, c, w.add(d, t1), e, f, g}

def sha512.feed(a: St512, b: St512) -> St512:
  match a b:
    case St512{x0, x1, x2, x3, x4, x5, x6, x7} St512{y0, y1, y2, y3, y4, y5, y6, y7}:
      St512{w.add(x0, y0), w.add(x1, y1), w.add(x2, y2), w.add(x3, y3), w.add(x4, y4), w.add(x5, y5), w.add(x6, y6), w.add(x7, y7)}

def sha512.sched.go(n: Nat, +ws: List<&2, W64>, acc: List<&2, W64>) -> List<&2, W64>:
  match n:
    case 0n:
      List.reverse(&2, W64, acc)
    case 1n+p:
      match ws:
        case Con{+p0, Con{+p1, Con{p2, Con{p3, Con{p4, Con{p5, Con{p6, Con{p7, Con{p8, Con{p9, Con{p10, Con{p11, Con{p12, Con{p13, Con{+p14, Con{p15, Nil{}}}}}}}}}}}}}}}}}:
          +w = w.add(w.add(w.ssig1(p14), p9), w.add(w.ssig0(p1), p0))
          sha512.sched.go(p, [p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, w], w <> acc)
        case _:
          List.reverse(&2, W64, acc)

def sha512.sched(+ws: List<&2, W64>) -> List<&2, W64>:
  sha512.sched.go(64n, ws, List.reverse(&2, W64, ws))

def sha512.rounds(k: List<&2, W64>, w: List<&2, W64>, st: St512) -> St512:
  match k w:
    case Nil{} Nil{}:
      st
    case Con{kh, kt} Con{wh, wt}:
      sha512.rounds(kt, wt, sha512.round(kh, wh, st))
    case _ _:
      st

def sha512.block(ws: List<&2, W64>, +st: St512) -> St512:
  sha512.feed(st, sha512.rounds(k512(), sha512.sched(ws), st))

def sha512.blocks(xs: List<&2, W64>, +st: St512) -> St512:
  match xs:
    case Nil{}:
      st
    case Con{w0, Con{w1, Con{w2, Con{w3, Con{w4, Con{w5, Con{w6, Con{w7, Con{w8, Con{w9, Con{w10, Con{w11, Con{w12, Con{w13, Con{w14, Con{w15, t}}}}}}}}}}}}}}}}:
      sha512.blocks(t, sha512.block([w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15], st))
    case _:
      st

def sha512.out(st: St512) -> List<&2, U32>:
  match st:
    case St512{a, b, c, d, e, f, g, h}:
      Bytes.cat(w.be(a), Bytes.cat(w.be(b), Bytes.cat(w.be(c), Bytes.cat(w.be(d), Bytes.cat(w.be(e), Bytes.cat(w.be(f), Bytes.cat(w.be(g), w.be(h))))))))

def sha512.hash(iv: St512, msg: List<&2, U32>) -> List<&2, U32>:
  sha512.out(sha512.blocks(words64(pad.to(msg, 128n, 16n)), iv))

# The published surface
# ---------------------

# the digest of msg: 32, 48 or 64 bytes
def hash(a: Alg, msg: List<&2, U32>) -> List<&2, U32>:
  match a:
    case S256{}:
      sha256.hash(msg)
    case S384{}:
      Bytes.take(sha512.hash(iv384(), msg), 48n)
    case S512{}:
      sha512.hash(iv512(), msg)

def fill.go(n: Nat, +b: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      fill.go(p, b, b <> acc)

# n copies of one byte: the ipad and opad fill
def fill(b: U32, n: Nat) -> List<&2, U32>:
  fill.go(n, b, Nil{})

# HMAC (RFC 2104): a key longer than one block is hashed first, then the key is
# zero-filled to a block and xored with the two pads
# --------------------------------------------------------------------------

def hmac.key.if(+a: Alg, +key: List<&2, U32>, long: Bool) -> List<&2, U32>:
  match long:
    case True{}:
      hash(a, key)
    case False{}:
      key

def hmac.k(+a: Alg, +key: List<&2, U32>) -> List<&2, U32>:
  +bs = U32.to_nat(block(a))
  +k = hmac.key.if(a, key, U32.is_gt(Bytes.len(key), block(a)))
  Bytes.cat(k, Bytes.zeros(Nat.sub(bs, U32.to_nat(Bytes.len(k)))))

def hmac(+a: Alg, key: List<&2, U32>, msg: List<&2, U32>) -> List<&2, U32>:
  +bs = U32.to_nat(block(a))
  +k = hmac.k(a, key)
  +inner = hash(a, Bytes.cat(Bytes.xor(k, fill(54, bs)), msg))
  hash(a, Bytes.cat(Bytes.xor(k, fill(92, bs)), inner))

# HKDF (RFC 5869)
# ---------------

def extract.salt.if(+a: Alg, +salt: List<&2, U32>, empty: Bool) -> List<&2, U32>:
  match empty:
    case True{}:
      Bytes.zeros(U32.to_nat(size(a)))
    case False{}:
      salt

# HKDF-Extract: the salt is the key, the input keying material the message; an
# empty salt stands for hash-size zero bytes
def extract(+a: Alg, +salt: List<&2, U32>, ikm: List<&2, U32>) -> List<&2, U32>:
  hmac(a, extract.salt.if(a, salt, U32.is_eq(Bytes.len(salt), 0)), ikm)

def expand.blocks(+hlen: Nat, +len: Nat) -> Nat:
  Nat.min(Nat.div(Nat.add(len, Nat.sub(hlen, 1n)), hlen), 255n)

def expand.go(+a: Alg, +prk: List<&2, U32>, +info: List<&2, U32>, fuel: Nat, +i: U32, prev: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      +t = hmac(a, prk, Bytes.cat(prev, Bytes.cat(info, [i])))
      expand.go(a, prk, info, p, (i + 1 : U32), t, Bytes.rev.onto(t, acc))

# HKDF-Expand: T(1) is HMAC(prk, info ++ [1]), T(n) is HMAC(prk, T(n-1) ++ info
# ++ [n]), and the output is their concatenation cut to len. The RFC caps len at
# 255 * hash size, and so does this: a longer len answers 255 blocks.
def expand(+a: Alg, prk: List<&2, U32>, info: List<&2, U32>, +len: U32) -> List<&2, U32>:
  +n = expand.blocks(U32.to_nat(size(a)), U32.to_nat(len))
  Bytes.take(Bytes.rev(expand.go(a, prk, info, n, 1, Nil{}, Nil{})), U32.to_nat(len))

# The TLS 1.3 key schedule (RFC 8446 7.1)
# ---------------------------------------

# HKDF-Expand-Label: the HkdfLabel of RFC 8446 7.1, as bytes
def expand_label(a: Alg, secret: List<&2, U32>, +label: String, +context: List<&2, U32>, +len: U32) -> List<&2, U32>:
  +info = Bytes.cat(Bytes.be16(len), Bytes.cat([U32.add(U32.from_nat(String.length(label)), 6)], Bytes.cat(Bytes.of_ascii("tls13 "), Bytes.cat(Bytes.of_ascii(label), Bytes.cat([Bytes.len(context)], context)))))
  expand(a, secret, info, len)

# Derive-Secret: expand_label of the transcript hash
def derive_secret(+a: Alg, secret: List<&2, U32>, label: String, messages: List<&2, U32>) -> List<&2, U32>:
  expand_label(a, secret, label, hash(a, messages), size(a))
