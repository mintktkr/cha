# chacha: ChaCha20, Poly1305 and the RFC 8439 AEAD. Pure ARX, nothing foreign, no hub
# imports. Bytes are List<&2, U32> (bytes.bend), so keys, nonces, tags and ciphertexts
# are the same shape as everything else. Poly1305 keeps h and r as 13 limbs of 10 bits
# (130 bits exactly), so every partial product fits in a U32 and the top of h folds
# back with the factor 5, since 2^130 == 5 (mod 2^130 - 5).
import Base
import ./bytes.bend as Bytes

# ChaCha20
# --------

# the 16 words of the RFC 8439 2.3 state, in one constructor so a round walks no list
type Ch is Data:
  Ch{s0: U32, s1: U32, s2: U32, s3: U32, s4: U32, s5: U32, s6: U32, s7: U32, s8: U32, s9: U32, s10: U32, s11: U32, s12: U32, s13: U32, s14: U32, s15: U32}

# the four words a quarter round answers
type Qr is Data:
  Qr{a: U32, b: U32, c: U32, d: U32}

# the four rotations of the quarter round, as constants so each is a shift and an or
def rot16(+x: U32) -> U32:
  U32.or(U32.shln(x, 16n), U32.shrn(x, 16n))

def rot12(+x: U32) -> U32:
  U32.or(U32.shln(x, 12n), U32.shrn(x, 20n))

def rot8(+x: U32) -> U32:
  U32.or(U32.shln(x, 8n), U32.shrn(x, 24n))

def rot7(+x: U32) -> U32:
  U32.or(U32.shln(x, 7n), U32.shrn(x, 25n))

# RFC 8439 2.1: a, b, c, d, in place
def qr(+a: U32, +b: U32, +c: U32, +d: U32) -> Qr:
  +a1 = (a + b : U32)
  +d1 = rot16(U32.xor(d, a1))
  +c1 = (c + d1 : U32)
  +b1 = rot12(U32.xor(b, c1))
  +a2 = (a1 + b1 : U32)
  +d2 = rot8(U32.xor(d1, a2))
  +c2 = (c1 + d2 : U32)
  +b2 = rot7(U32.xor(b1, c2))
  Qr{a2, b2, c2, d2}

# the four quarter rounds of a round, back in their places. The column round's groups
# are (0,4,8,12) (1,5,9,13) (2,6,10,14) (3,7,11,15), the diagonal's are (0,5,10,15)
# (1,6,11,12) (2,7,8,13) (3,4,9,14): the two only differ in where the words land.
def qr.col(q0: Qr, q1: Qr, q2: Qr, q3: Qr) -> Ch:
  Qr{a0, b0, c0, d0} = q0
  Qr{a1, b1, c1, d1} = q1
  Qr{a2, b2, c2, d2} = q2
  Qr{a3, b3, c3, d3} = q3
  Ch{a0, a1, a2, a3, b0, b1, b2, b3, c0, c1, c2, c3, d0, d1, d2, d3}

def qr.diag(q0: Qr, q1: Qr, q2: Qr, q3: Qr) -> Ch:
  Qr{a0, b0, c0, d0} = q0
  Qr{a1, b1, c1, d1} = q1
  Qr{a2, b2, c2, d2} = q2
  Qr{a3, b3, c3, d3} = q3
  Ch{a0, a1, a2, a3, b3, b0, b1, b2, c2, c3, c0, c1, d1, d2, d3, d0}

# RFC 8439 2.3: the four column quarter rounds
def round.col(s: Ch) -> Ch:
  match s:
    case Ch{+s0, +s1, +s2, +s3, +s4, +s5, +s6, +s7, +s8, +s9, +s10, +s11, +s12, +s13, +s14, +s15}:
      qr.col(qr(s0, s4, s8, s12), qr(s1, s5, s9, s13), qr(s2, s6, s10, s14), qr(s3, s7, s11, s15))

# RFC 8439 2.3: the four diagonal quarter rounds
def round.diag(s: Ch) -> Ch:
  match s:
    case Ch{+s0, +s1, +s2, +s3, +s4, +s5, +s6, +s7, +s8, +s9, +s10, +s11, +s12, +s13, +s14, +s15}:
      qr.diag(qr(s0, s5, s10, s15), qr(s1, s6, s11, s12), qr(s2, s7, s8, s13), qr(s3, s4, s9, s14))

def rounds(n: Nat, s: Ch) -> Ch:
  match n:
    case 0n:
      s
    case 1n+p:
      rounds(p, round.diag(round.col(s)))

# the first four bytes as a little-endian word; missing bytes read as zero
def word(xs: List<&2, U32>) -> U32:
  match xs:
    case Con{b0, Con{b1, Con{b2, Con{b3, _}}}}:
      U32.or(b0, U32.or(U32.shln(b1, 8n), U32.or(U32.shln(b2, 16n), U32.shln(b3, 24n))))
    case _:
      0

# RFC 8439 2.3: the constant, the key, the counter and the 12-byte nonce
def init(+key: List<&2, U32>, counter: U32, +nonce: List<&2, U32>) -> Ch:
  Ch{1634760805, 857760878, 2036477234, 1797285236,
     word(key),
     word(Bytes.drop(key, 4n)),
     word(Bytes.drop(key, 8n)),
     word(Bytes.drop(key, 12n)),
     word(Bytes.drop(key, 16n)),
     word(Bytes.drop(key, 20n)),
     word(Bytes.drop(key, 24n)),
     word(Bytes.drop(key, 28n)),
     counter,
     word(nonce),
     word(Bytes.drop(nonce, 4n)),
     word(Bytes.drop(nonce, 8n))}

# the state plus its starting copy, word by word (RFC 8439 2.3 step 3)
def feed(s: Ch, o: Ch) -> Ch:
  match s:
    case Ch{+s0, +s1, +s2, +s3, +s4, +s5, +s6, +s7, +s8, +s9, +s10, +s11, +s12, +s13, +s14, +s15}:
      match o:
        case Ch{+o0, +o1, +o2, +o3, +o4, +o5, +o6, +o7, +o8, +o9, +o10, +o11, +o12, +o13, +o14, +o15}:
          Ch{U32.add(s0, o0), U32.add(s1, o1), U32.add(s2, o2), U32.add(s3, o3),
             U32.add(s4, o4), U32.add(s5, o5), U32.add(s6, o6), U32.add(s7, o7),
             U32.add(s8, o8), U32.add(s9, o9), U32.add(s10, o10), U32.add(s11, o11),
             U32.add(s12, o12), U32.add(s13, o13), U32.add(s14, o14), U32.add(s15, o15)}

# four bytes, little-endian
def le32(+n: U32) -> List<&2, U32>:
  [U32.and(n, 255), U32.and(U32.shrn(n, 8n), 255), U32.and(U32.shrn(n, 16n), 255), U32.and(U32.shrn(n, 24n), 255)]

# the same four bytes, most significant first
def le32.rev(+n: U32) -> List<&2, U32>:
  [U32.and(U32.shrn(n, 24n), 255), U32.and(U32.shrn(n, 16n), 255), U32.and(U32.shrn(n, 8n), 255), U32.and(n, 255)]

# the words as little-endian bytes, gathered backwards so the cons stays cheap
def out.go(words: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match words:
    case Nil{}:
      acc
    case Con{w, t}:
      out.go(t, Bytes.cat(le32.rev(w), acc))

# RFC 8439 2.3 step 4: the 16 words as 64 little-endian bytes
def out(s: Ch) -> List<&2, U32>:
  match s:
    case Ch{+s0, +s1, +s2, +s3, +s4, +s5, +s6, +s7, +s8, +s9, +s10, +s11, +s12, +s13, +s14, +s15}:
      Bytes.rev(out.go([s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15], Nil{}))

# one 64-byte keystream block (key 32 bytes, nonce 12)
def block(+key: List<&2, U32>, +counter: U32, +nonce: List<&2, U32>) -> List<&2, U32>:
  out(feed(rounds(10n, init(key, counter, nonce)), init(key, counter, nonce)))

# how many 64-byte blocks n bytes need
def blocks64(+n: U32) -> Nat:
  U32.to_nat(U32.div(U32.add(n, 63), 64))

def chacha20.go(fuel: Nat, +key: List<&2, U32>, +nonce: List<&2, U32>, +counter: U32, +data: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n:
      Bytes.rev(acc)
    case 1n+p:
      chacha20.go(p, key, nonce, U32.add(counter, 1), Bytes.drop(data, 64n),
                  Bytes.rev.onto(Bytes.xor(Bytes.take(data, 64n), block(key, counter, nonce)), acc))

# data xor the keystream from counter on
def chacha20(+key: List<&2, U32>, +nonce: List<&2, U32>, counter: U32, +data: List<&2, U32>) -> List<&2, U32>:
  chacha20.go(blocks64(Bytes.len(data)), key, nonce, counter, data, Nil{})

# Poly1305
# --------

# a limb list beside whatever ran past 2^130. They travel together so a call can bring
# both home as a parameter: a destructuring let may not take a call's result.
type Cv is Data:
  Cv{l: List<&2, U32>, ov: U32}

# the five little-endian words of a 20-byte string as 13 limbs of 10 bits
def lim.of(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32) -> List<&2, U32>:
  [U32.and(w0, 1023),
   U32.and(U32.shrn(w0, 10n), 1023),
   U32.and(U32.shrn(w0, 20n), 1023),
   U32.and(U32.or(U32.shrn(w0, 30n), U32.shln(w1, 2n)), 1023),
   U32.and(U32.shrn(w1, 8n), 1023),
   U32.and(U32.shrn(w1, 18n), 1023),
   U32.and(U32.or(U32.shrn(w1, 28n), U32.shln(w2, 4n)), 1023),
   U32.and(U32.shrn(w2, 6n), 1023),
   U32.and(U32.shrn(w2, 16n), 1023),
   U32.and(U32.or(U32.shrn(w2, 26n), U32.shln(w3, 6n)), 1023),
   U32.and(U32.shrn(w3, 4n), 1023),
   U32.and(U32.shrn(w3, 14n), 1023),
   U32.and(U32.or(U32.shrn(w3, 24n), U32.shln(w4, 8n)), 1023)]

# the first 20 bytes, little-endian, as 13 limbs
def to13(+xs: List<&2, U32>) -> List<&2, U32>:
  lim.of(word(xs), word(Bytes.drop(xs, 4n)), word(Bytes.drop(xs, 8n)),
         word(Bytes.drop(xs, 12n)), word(Bytes.drop(xs, 16n)))

# RFC 8439 2.5: r, the first 16 key bytes, clamped
def r.of(+key: List<&2, U32>) -> List<&2, U32>:
  lim.of(U32.and(word(key), 268435455),
         U32.and(word(Bytes.drop(key, 4n)), 268435452),
         U32.and(word(Bytes.drop(key, 8n)), 268435452),
         U32.and(word(Bytes.drop(key, 12n)), 268435452),
         0)

# RFC 8439 2.5: s, the second 16 key bytes
def s.of(key: List<&2, U32>) -> List<&2, U32>:
  to13(Bytes.drop(key, 16n))

# RFC 8439 2.5.1: a block, then the 1 byte the AEAD adds above its length. 20 bytes is
# enough for the longest block plus that byte.
def pad.bytes(chunk: List<&2, U32>) -> List<&2, U32>:
  Bytes.take(Bytes.cat(chunk, Bytes.of_hex("0100000000")), 20n)

def dot.go(n: Nat, a: List<&2, U32>, b: List<&2, U32>, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      match a b:
        case Con{x, ta} Con{y, tb}:
          dot.go(p, ta, tb, U32.add(acc, U32.mul(x, y)))
        case _ _:
          acc

# the sum of x*y over two limb lists of the same length
def dot(n: Nat, a: List<&2, U32>, b: List<&2, U32>) -> U32:
  dot.go(n, a, b, 0)

# h*r, already folded: limb m is the products at m plus five times those at m+13, so
# the result is 13 limbs of under 2^29 that stand for the product modulo 2^130 - 5.
# h limbs are below 2^11 (h + a block), r limbs below 2^10. rr is r reversed.
def mul(+h: List<&2, U32>, +rr: List<&2, U32>) -> List<&2, U32>:
  d0 = dot(1n, h, Bytes.drop(rr, 12n))
  d1 = dot(2n, h, Bytes.drop(rr, 11n))
  d2 = dot(3n, h, Bytes.drop(rr, 10n))
  d3 = dot(4n, h, Bytes.drop(rr, 9n))
  d4 = dot(5n, h, Bytes.drop(rr, 8n))
  d5 = dot(6n, h, Bytes.drop(rr, 7n))
  d6 = dot(7n, h, Bytes.drop(rr, 6n))
  d7 = dot(8n, h, Bytes.drop(rr, 5n))
  d8 = dot(9n, h, Bytes.drop(rr, 4n))
  d9 = dot(10n, h, Bytes.drop(rr, 3n))
  d10 = dot(11n, h, Bytes.drop(rr, 2n))
  d11 = dot(12n, h, Bytes.drop(rr, 1n))
  d12 = dot(13n, h, rr)
  f0 = dot(12n, Bytes.drop(h, 1n), rr)
  f1 = dot(11n, Bytes.drop(h, 2n), rr)
  f2 = dot(10n, Bytes.drop(h, 3n), rr)
  f3 = dot(9n, Bytes.drop(h, 4n), rr)
  f4 = dot(8n, Bytes.drop(h, 5n), rr)
  f5 = dot(7n, Bytes.drop(h, 6n), rr)
  f6 = dot(6n, Bytes.drop(h, 7n), rr)
  f7 = dot(5n, Bytes.drop(h, 8n), rr)
  f8 = dot(4n, Bytes.drop(h, 9n), rr)
  f9 = dot(3n, Bytes.drop(h, 10n), rr)
  f10 = dot(2n, Bytes.drop(h, 11n), rr)
  f11 = dot(1n, Bytes.drop(h, 12n), rr)
  [U32.add(d0, U32.mul(5, f0)),
   U32.add(d1, U32.mul(5, f1)),
   U32.add(d2, U32.mul(5, f2)),
   U32.add(d3, U32.mul(5, f3)),
   U32.add(d4, U32.mul(5, f4)),
   U32.add(d5, U32.mul(5, f5)),
   U32.add(d6, U32.mul(5, f6)),
   U32.add(d7, U32.mul(5, f7)),
   U32.add(d8, U32.mul(5, f8)),
   U32.add(d9, U32.mul(5, f9)),
   U32.add(d10, U32.mul(5, f10)),
   U32.add(d11, U32.mul(5, f11)),
   d12]

# the limbs of a 13-limb value carried down to 10 bits each, plus whatever runs past
# 2^130
def carry.go(xs: List<&2, U32>, acc: List<&2, U32>, carry: U32) -> Cv:
  match xs:
    case Nil{}:
      Cv{Bytes.rev(acc), carry}
    case Con{x, t}:
      +v = U32.add(x, carry)
      carry.go(t, U32.and(v, 1023) <> acc, U32.shrn(v, 10n))

def carry13(xs: List<&2, U32>) -> Cv:
  carry.go(xs, Nil{}, 0)

# a carry past 2^130 is 5, since 2^130 == 5 (mod 2^130 - 5)
def fold13(c: List<&2, U32>, ov: U32) -> List<&2, U32>:
  match c:
    case Nil{}:
      Nil{}
    case Con{l0, t}:
      U32.add(l0, U32.mul(5, ov)) <> t

def cv.limbs(r: Cv) -> List<&2, U32>:
  match r:
    case Cv{l, _}:
      l

def redu.pass(r: Cv) -> Cv:
  match r:
    case Cv{l, ov}:
      carry13(fold13(l, ov))

# what one block of the multiply leaves behind: below 2^130, limbs of 10 bits. One pass
# leaves under 2^130 + 2^24, the second under 2^130, and its carry is then 0.
def redu(c: List<&2, U32>) -> List<&2, U32>:
  cv.limbs(redu.pass(redu.pass(carry13(c))))

def add.go(a: List<&2, U32>, b: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match a b:
    case Con{x, ta} Con{y, tb}:
      add.go(ta, tb, U32.add(x, y) <> acc)
    case _ _:
      Bytes.rev(acc)

# the limb-wise sum of two equally long limb lists
def add.limbs(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  add.go(a, b, Nil{})

def poly.go(fuel: Nat, h: List<&2, U32>, +rr: List<&2, U32>, +msg: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n:
      h
    case 1n+p:
      poly.go(p, redu(mul(add.limbs(h, to13(pad.bytes(Bytes.take(msg, 16n)))), rr)), rr,
              Bytes.drop(msg, 16n))

# how many 16-byte blocks n bytes need
def blocks16(+n: U32) -> Nat:
  U32.to_nat(U32.div(U32.add(n, 15), 16))

# h below p: h + 5 carries past 2^130 exactly when h >= p, and then the low 130 bits
# are h - p. Neither h nor g is secret by the time a tag is out, so a plain branch.
def sel(+t: List<&2, U32>, +f: List<&2, U32>, c: Bool) -> List<&2, U32>:
  match c:
    case True{}:
      t
    case False{}:
      f

def add5(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{l0, t}:
      U32.add(l0, 5) <> t

# 13 limbs as the 16 little-endian bytes of the tag; the top two bits of the last limb
# fall off the shift, which is the mod 2^128
def tag.bytes(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Con{+l0, Con{+l1, Con{+l2, Con{+l3, Con{+l4, Con{+l5, Con{+l6, Con{+l7, Con{+l8, Con{+l9, Con{+l10, Con{+l11, Con{+l12, _}}}}}}}}}}}}}:
      Bytes.rev(out.go([U32.or(l0, U32.or(U32.shln(l1, 10n), U32.or(U32.shln(l2, 20n), U32.shln(l3, 30n)))),
                        U32.or(U32.shrn(l3, 2n), U32.or(U32.shln(l4, 8n), U32.or(U32.shln(l5, 18n), U32.shln(l6, 28n)))),
                        U32.or(U32.shrn(l6, 4n), U32.or(U32.shln(l7, 6n), U32.or(U32.shln(l8, 16n), U32.shln(l9, 26n)))),
                        U32.or(U32.shrn(l9, 6n), U32.or(U32.shln(l10, 4n), U32.or(U32.shln(l11, 14n), U32.shln(l12, 24n))))],
                       Nil{}))
    case _:
      Nil{}

def tag.done(r: Cv) -> List<&2, U32>:
  match r:
    case Cv{t, _}:
      tag.bytes(t)

def tag.after(r: Cv, +h: List<&2, U32>, s: List<&2, U32>) -> List<&2, U32>:
  match r:
    case Cv{g, ov}:
      tag.done(carry13(add.limbs(sel(h, g, U32.is_zero(ov)), s)))

def tag13(+h: List<&2, U32>, s: List<&2, U32>) -> List<&2, U32>:
  tag.after(carry13(add5(h)), h, s)

# the 16-byte tag of msg under a one-time 32-byte key
def poly1305(+key: List<&2, U32>, +msg: List<&2, U32>) -> List<&2, U32>:
  h = poly.go(blocks16(Bytes.len(msg)), Bytes.zeros(13n), Bytes.rev(r.of(key)), msg)
  tag13(h, s.of(key))

# The AEAD
# --------

# zeros to the next multiple of 16
def pad16(xs: List<&2, U32>) -> List<&2, U32>:
  Bytes.zeros(U32.to_nat(U32.mod(U32.sub(16, U32.mod(Bytes.len(xs), 16)), 16)))

# a length as RFC 8439 2.8 writes it: 8 bytes, little-endian
def le64(+n: U32) -> List<&2, U32>:
  Bytes.cat(le32(n), Bytes.zeros(4n))

# RFC 8439 2.8: aad, its padding, the ciphertext, its padding, then both lengths
def mac.data(+aad: List<&2, U32>, +ct: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(Bytes.cat(Bytes.cat(Bytes.cat(aad, pad16(aad)), ct), pad16(ct)),
            Bytes.cat(le64(Bytes.len(aad)), le64(Bytes.len(ct))))

# the Poly1305 one-time key: the first 32 bytes of block 0
def otk(key: List<&2, U32>, nonce: List<&2, U32>) -> List<&2, U32>:
  Bytes.take(block(key, 0, nonce), 32n)

# the tag a ciphertext carries under the one-time key of this nonce
def tag.of(+key: List<&2, U32>, +nonce: List<&2, U32>, +aad: List<&2, U32>, ct: List<&2, U32>) -> List<&2, U32>:
  poly1305(otk(key, nonce), mac.data(aad, ct))

# ciphertext followed by the 16-byte tag
def seal(+key: List<&2, U32>, +nonce: List<&2, U32>, aad: List<&2, U32>, plain: List<&2, U32>) -> List<&2, U32>:
  +ct = chacha20(key, nonce, 1, plain)
  Bytes.cat(ct, tag.of(key, nonce, aad, ct))

def open.ver(c: Bool, plain: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match c:
    case True{}:
      Some{plain}
    case False{}:
      None{}

def open.if(+key: List<&2, U32>, +nonce: List<&2, U32>, +aad: List<&2, U32>, +sealed: List<&2, U32>, ok: Bool) -> Maybe<&2, List<&2, U32>>:
  match ok:
    case False{}:
      None{}
    case True{}:
      +n = U32.sub(Bytes.len(sealed), 16)
      +ct = Bytes.take(sealed, U32.to_nat(n))
      tag = Bytes.drop(sealed, U32.to_nat(n))
      open.ver(Bytes.ct_eq(tag, tag.of(key, nonce, aad, ct)), chacha20(key, nonce, 1, ct))

# the plaintext, or None when the tag doesn't match or sealed is shorter than a tag
def open(+key: List<&2, U32>, +nonce: List<&2, U32>, +aad: List<&2, U32>, +sealed: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  open.if(key, nonce, aad, sealed, U32.is_le(16, Bytes.len(sealed)))
