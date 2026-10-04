# aes: AES-128, AES-256 and GCM, after BearSSL. GCM needs the forward cipher only,
# so there is no inverse cipher here. The S-box is a 256-slot Array<U32>: an Array is
# affine, so every read hands it back, and the array is threaded through every def
# that looks a byte up. A 128-bit block is four 32-bit words, most significant word
# first, each word four bytes most significant first, so block bytes 0..15 are the
# four words big-endian. One word of the AES state holds one column.
import Base
import ./bytes.bend as Bytes

# Words
# -----

def w.b0(+w: U32) -> U32:
  U32.shrn(w, 24n)

def w.b1(+w: U32) -> U32:
  U32.and(U32.shrn(w, 16n), 255)

def w.b2(+w: U32) -> U32:
  U32.and(U32.shrn(w, 8n), 255)

def w.b3(+w: U32) -> U32:
  U32.and(w, 255)

def w.pack(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(U32.shln(U32.and(a, 255), 24n), U32.or(U32.shln(U32.and(b, 255), 16n), U32.or(U32.shln(U32.and(c, 255), 8n), U32.and(d, 255))))

# the four bytes of w, most significant first
def w.quad(+w: U32) -> List<&2, U32>:
  [w.b0(w), w.b1(w), w.b2(w), w.b3(w)]

# the four bytes of vs, packed into one word
def w.pack4(+vs: List<&2, U32>) -> U32:
  match vs:
    case Con{a, Con{b, Con{c, Con{d, _}}}}:
      w.pack(a, b, c, d)
    case _:
      0

def zeros4() -> List<&2, U32>:
  [0, 0, 0, 0]

# Fields
# ------

# multiplication by 2 in GF(2^8), modulo x^8 + x^4 + x^3 + x + 1
def xtime(+x: U32) -> U32:
  U32.xor(U32.and(U32.shln(x, 1n), 255), Bool.pick(U32, U32.is_lt(x, 128), 0, 27))

# MixColumns on one column
def mix.col(+w: U32) -> U32:
  +a = w.b0(w)
  +b = w.b1(w)
  +c = w.b2(w)
  +d = w.b3(w)
  +t = U32.xor(U32.xor(a, b), U32.xor(c, d))
  w.pack(U32.xor(a, U32.xor(t, xtime(U32.xor(a, b)))), U32.xor(b, U32.xor(t, xtime(U32.xor(b, c)))), U32.xor(c, U32.xor(t, xtime(U32.xor(c, d)))), U32.xor(d, U32.xor(t, xtime(U32.xor(d, a)))))

def mix.cols(+ws: List<&2, U32>) -> List<&2, U32>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{w, t}:
      mix.col(w) <> mix.cols(t)

# ShiftRows: row r moves left by r columns
def shift.rows(+ws: List<&2, U32>) -> List<&2, U32>:
  match ws:
    case Con{w0, Con{w1, Con{w2, Con{w3, _}}}}:
      [w.pack(w.b0(w0), w.b1(w1), w.b2(w2), w.b3(w3)),
       w.pack(w.b0(w1), w.b1(w2), w.b2(w3), w.b3(w0)),
       w.pack(w.b0(w2), w.b1(w3), w.b2(w0), w.b3(w1)),
       w.pack(w.b0(w3), w.b1(w0), w.b2(w1), w.b3(w2))]
    case _:
      ws

# Bytes and blocks
# -----------------

def words.of.bytes.go(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Bytes.rev(acc)
    case Con{b0, Con{b1, Con{b2, Con{b3, t}}}}:
      words.of.bytes.go(t, w.pack(b0, b1, b2, b3) <> acc)
    case _:
      Bytes.rev(acc)

# 16 bytes as four words
def words.of.bytes(xs: List<&2, U32>) -> List<&2, U32>:
  words.of.bytes.go(xs, Nil{})

def bytes.of.words.go(ws: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ws:
    case Nil{}:
      Bytes.rev(acc)
    case Con{+w, t}:
      bytes.of.words.go(t, w.b3(w) <> w.b2(w) <> w.b1(w) <> w.b0(w) <> acc)
    case _:
      Bytes.rev(acc)

# four words as 16 bytes
def bytes.of.words(ws: List<&2, U32>) -> List<&2, U32>:
  bytes.of.words.go(ws, Nil{})

def xor4.go(a: List<&2, U32>, b: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match a b:
    case Con{x, s} Con{y, t}:
      xor4.go(s, t, U32.xor(x, y) <> acc)
    case _ _:
      Bytes.rev(acc)

# word-wise xor, as long as the shorter list
def xor4(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  xor4.go(a, b, Nil{})

# The S-box
# ---------

# FIPS-197 Figure 7, row by row. A lookup is not constant-time: the index decides
# which nodes of the array's tree a read walks.
def box.hex() -> List<&2, U32>:
  Bytes.of_hex("637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b27509832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cfd0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdbe0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9ee1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16")

def box.fill(xs: List<&2, U32>, +i: U32, a: Array<U32>) -> Array<U32>:
  match xs:
    case Nil{}:
      a
    case Con{h, t}:
      box.fill(t, U32.add(i, 1), Array.set(U32, a, i, h))

# the 256-slot S-box
def box.mk() -> Array<U32>:
  box.fill(box.hex(), 0, [0 : U32*256n])

# every index of xs, in order, handing the array back
def box.look(xs: List<&2, U32>, r: Array<U32> & U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match xs:
    case Nil{}:
      match r:
        case (box, v):
          (box, Bytes.rev(v <> acc))
    case Con{x, t}:
      match r:
        case (box, v):
          box.look(t, Array.get(U32, box, x), v <> acc)

def box.look.at(xs: List<&2, U32>, box: Array<U32>) -> Array<U32> & List<&2, U32>:
  match xs:
    case Nil{}:
      (box, Nil{})
    case Con{x, t}:
      box.look(t, Array.get(U32, box, x), Nil{})

# SubBytes
# --------
# The S-box on every word of the state. The pending pair carries the array and the
# four values of the word looked up just before.

def sub.words(xs: List<&2, U32>, r: Array<U32> & List<&2, U32>, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match xs:
    case Nil{}:
      match r:
        case (box, vs):
          (box, Bytes.rev(w.pack4(vs) <> acc))
    case Con{w, t}:
      match r:
        case (box, vs):
          sub.words(t, box.look.at(w.quad(w), box), w.pack4(vs) <> acc)

def sub.words.start(xs: List<&2, U32>, box: Array<U32>) -> Array<U32> & List<&2, U32>:
  match xs:
    case Nil{}:
      (box, Nil{})
    case Con{w, t}:
      sub.words(t, box.look.at(w.quad(w), box), Nil{})

# AddRoundKey
# -----------

def add.key4(+k0: U32, +k1: U32, +k2: U32, +k3: U32, +ws: List<&2, U32>) -> List<&2, U32>:
  match ws:
    case Con{w0, Con{w1, Con{w2, Con{w3, _}}}}:
      [U32.xor(k0, w0), U32.xor(k1, w1), U32.xor(k2, w2), U32.xor(k3, w3)]
    case _:
      ws

# Rounds
# ------

# ks points at the round's four key words, r carries the array and the state with
# SubBytes already applied. The second pattern is the round after this one, four
# words on; without it this is the last round and MixColumns is left out.
def rounds(ks: List<&2, U32>, r: Array<U32> & List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match ks:
    case Con{k0, Con{k1, Con{k2, Con{k3, +rest}}}}:
      match rest:
        case Con{q0, Con{q1, Con{q2, Con{q3, _}}}}:
          match r:
            case (box, ws):
              rounds(rest, sub.words.start(add.key4(k0, k1, k2, k3, mix.cols(shift.rows(ws))), box))
        case _:
          match r:
            case (box, ws):
              (box, add.key4(k0, k1, k2, k3, shift.rows(ws)))
    case _:
      r

# one block under the expanded key
def ct.block(ks: List<&2, U32>, box: Array<U32>, ws: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match ks:
    case Con{k0, Con{k1, Con{k2, Con{k3, rest}}}}:
      rounds(rest, sub.words.start(add.key4(k0, k1, k2, k3, ws), box))
    case _:
      (box, ws)

# The key schedule
# ----------------

# RotWord: the four bytes shift left by one
def rot.word(+w: U32) -> U32:
  w.pack(w.b1(w), w.b2(w), w.b3(w), w.b0(w))

def rcon.go(n: Nat, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      rcon.go(p, xtime(acc))

# the round constant as a word: x^(k-1) in GF(2^8) in the top byte, 1, 2, 4, 8, ...
# for k from 1
def rcon(k: Nat) -> U32:
  match k:
    case 0n:
      0
    case 1n+p:
      U32.shln(rcon.go(p, 1), 24n)

# the k-th word of xs from the head
def nth(xs: List<&2, U32>, k: Nat) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{h, t}:
      match k:
        case 0n:
          h
        case 1n+p:
          nth(t, p)

# temp: SubWord of the word just rotated, with the round constant when this index
# starts a group, SubWord alone in the middle of an eight-word key, and the word
# itself in the plain case
def sched.temp(+prev: U32, +vals: List<&2, U32>, +r: U32, rot: Bool, mid: Bool) -> U32:
  match rot:
    case True{}:
      U32.xor(w.pack4(vals), r)
    case False{}:
      match mid:
        case True{}:
          w.pack4(vals)
        case False{}:
          prev

def sched.next(+w: U32, cond: Bool) -> U32:
  match cond:
    case True{}:
      rot.word(w)
    case False{}:
      w

# acc holds the words so far, most recent first, and r the array with the S-box of
# the next word's RotWord. Every step pays for those four lookups, even a step that
# never uses them.
def sched(n: Nat, r: Array<U32> & List<&2, U32>, +nk: U32, +i: U32, +acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match n:
    case 0n:
      match r:
        case (box, _):
          (box, Bytes.rev(acc))
    case 1n+p:
      match r:
        case (box, vals):
          match acc:
            case Con{prev, _}:
              +b = U32.mod(i, nk)
              rot = U32.is_eq(b, 0)
              mid = Bool.and(U32.is_eq(nk, 8), U32.is_eq(b, 4))
              +t = sched.temp(prev, vals, rcon(U32.to_nat(U32.div(i, nk))), rot, mid)
              +new = U32.xor(nth(acc, U32.to_nat(U32.sub(nk, 1))), t)
              +ni = U32.add(i, 1)
              sched(p, box.look.at(w.quad(sched.next(new, U32.is_eq(U32.mod(ni, nk), 0))), box), nk, ni, new <> acc)
            case Nil{}:
              (box, Nil{})

def sched.start(+acc: List<&2, U32>, box: Array<U32>, +nk: U32, n: Nat) -> Array<U32> & List<&2, U32>:
  match acc:
    case Con{prev, _}:
      sched(n, box.look.at(w.quad(rot.word(prev)), box), nk, nk, acc)
    case Nil{}:
      (box, Nil{})

# the round keys, 4*(Nr+1) words in order, with the array
def expand(big: Bool, box: Array<U32>, key: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match big:
    case True{}:
      sched.start(Bytes.rev(words.of.bytes(key)), box, 8, 52n)
    case False{}:
      sched.start(Bytes.rev(words.of.bytes(key)), box, 4, 40n)

# GHASH
# -----
# Multiplication in GF(2^128) bit by bit, Algorithm 1 of "The Galois/Counter Mode of
# Operation (GCM)": R is e1 followed by 120 zero bits.

# halve the 128-bit value, folding in R when a bit falls off
def gh.shr(+ws: List<&2, U32>) -> List<&2, U32>:
  match ws:
    case Con{a, Con{b, Con{c, Con{d, _}}}}:
      +r = Bool.pick(U32, U32.is_eq(U32.and(d, 1), 1), 3774873600, 0)  # e1000000
      [U32.xor(U32.shrn(a, 1n), r),
       U32.or(U32.shrn(b, 1n), U32.shln(a, 31n)),
       U32.or(U32.shrn(c, 1n), U32.shln(b, 31n)),
       U32.or(U32.shrn(d, 1n), U32.shln(c, 31n))]
    case _:
      ws

type Gh is Data:
  Gh{z: List<&2, U32>, v: List<&2, U32>}

def gh.z(s: Gh) -> List<&2, U32>:
  Gh{z, _} = s
  z

# one bit: add v into z when it is set, then halve v
def gh.step(+bit: Bool, s: Gh) -> Gh:
  match bit:
    case True{}:
      Gh{z, +v} = s
      Gh{xor4(z, v), gh.shr(v)}
    case False{}:
      Gh{z, v} = s
      Gh{z, gh.shr(v)}

# the top k bits of x, most significant first
def gh.bits(k: Nat, +x: U32, s: Gh) -> Gh:
  match k:
    case 0n:
      s
    case 1n+p:
      gh.bits(p, U32.shln(x, 1n), gh.step(U32.is_eq(U32.shrn(x, 31n), 1), s))

# Z = X times Y in GF(2^128)
def gh.mul(x: List<&2, U32>, +y: List<&2, U32>) -> List<&2, U32>:
  match x:
    case Con{x0, Con{x1, Con{x2, Con{x3, _}}}}:
      s1 = gh.bits(32n, x0, Gh{zeros4(), y})
      s2 = gh.bits(32n, x1, s1)
      s3 = gh.bits(32n, x2, s2)
      s4 = gh.bits(32n, x3, s3)
      gh.z(s4)
    case _:
      zeros4()

# Blocks of bytes
# ---------------

# the bytes of xs and then zeros, out to n bytes
def pad.go(n: Nat, xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      Bytes.rev(acc)
    case 1n+p:
      match xs:
        case Con{h, t}:
          pad.go(p, t, h <> acc)
        case Nil{}:
          pad.go(p, Nil{}, 0 <> acc)

# the first 16 bytes of xs, zero-padded, as four words
def block.of(xs: List<&2, U32>) -> List<&2, U32>:
  words.of.bytes(pad.go(16n, xs, Nil{}))

def blocks.rev.go(xs: List<&2, List<&2, U32>>, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      blocks.rev.go(t, h <> acc)

def blocks.rev(xs: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  blocks.rev.go(xs, Nil{})

def chunks.go(+xs: List<&2, U32>, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match xs:
    case Nil{}:
      blocks.rev(acc)
    case Con{b0, Con{b1, Con{b2, Con{b3, Con{b4, Con{b5, Con{b6, Con{b7, Con{b8, Con{b9, Con{b10, Con{b11, Con{b12, Con{b13, Con{b14, Con{b15, t}}}}}}}}}}}}}}}}:
      chunks.go(t, words.of.bytes([b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15]) <> acc)
    case _:
      blocks.rev(block.of(xs) <> acc)

# the bytes of xs as four-word blocks, the last one zero-padded
def chunks(xs: List<&2, U32>) -> List<&2, List<&2, U32>>:
  chunks.go(xs, Nil{})

# fold the blocks of a byte string into y, under H
def gh.fold(bs: List<&2, List<&2, U32>>, y: List<&2, U32>, +h: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case Nil{}:
      y
    case Con{b, t}:
      gh.fold(t, gh.mul(xor4(y, b), h), h)

# len(aad) and len(ct) in bits, each 64 bits big-endian
def gh.lens(+aad: List<&2, U32>, +ct: List<&2, U32>) -> List<&2, U32>:
  [0, U32.shln(Bytes.len(aad), 3n), 0, U32.shln(Bytes.len(ct), 3n)]

# GHASH(H, A, C)
def ghash(+aad: List<&2, U32>, +ct: List<&2, U32>, +h: List<&2, U32>) -> List<&2, U32>:
  gh.mul(xor4(gh.fold(chunks(ct), gh.fold(chunks(aad), zeros4(), h), h), gh.lens(aad, ct)), h)

# The counter
# -----------

# nonce followed by the counter c, 96-bit nonces only
def ctr.block(nonce: List<&2, U32>, c: U32) -> List<&2, U32>:
  words.of.bytes(Bytes.cat(nonce, Bytes.be32(c)))

# XOR the plaintext blocks with their keystream. r carries the array and the
# keystream block of the block about to be taken, c its counter.
def ct.ctr(bs: List<&2, List<&2, U32>>, +c: U32, +ks: List<&2, U32>, +nonce: List<&2, U32>, r: Array<U32> & List<&2, U32>, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match bs:
    case Nil{}:
      match r:
        case (box, _):
          (box, Bytes.rev(acc))
    case Con{b, t}:
      match r:
        case (box, kb):
          ct.ctr(t, U32.add(c, 1), ks, nonce, ct.block(ks, box, ctr.block(nonce, U32.add(c, 1))), Bytes.rev.onto(bytes.of.words(xor4(b, kb)), acc))

# seal
# ----

def seal.out(+ct: List<&2, U32>, h: List<&2, U32>, aad: List<&2, U32>, e0: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(ct, bytes.of.words(xor4(ghash(aad, ct, h), e0)))

def seal.tag(r: Array<U32> & List<&2, U32>, ct: List<&2, U32>, h: List<&2, U32>, aad: List<&2, U32>) -> List<&2, U32>:
  match r:
    case (box, e0):
      seal.out(ct, h, aad, e0)

def seal.ct(r: Array<U32> & List<&2, U32>, ks: List<&2, U32>, h: List<&2, U32>, nonce: List<&2, U32>, aad: List<&2, U32>, plain: List<&2, U32>) -> List<&2, U32>:
  match r:
    case (box, raw):
      seal.tag(ct.block(ks, box, ctr.block(nonce, 1)), Bytes.take(raw, U32.to_nat(Bytes.len(plain))), h, aad)

def seal.h(r: Array<U32> & List<&2, U32>, +ks: List<&2, U32>, +nonce: List<&2, U32>, aad: List<&2, U32>, +plain: List<&2, U32>) -> List<&2, U32>:
  match r:
    case (box, h):
      seal.ct(ct.ctr(chunks(plain), 2, ks, nonce, ct.block(ks, box, ctr.block(nonce, 2)), Nil{}), ks, h, nonce, aad, plain)

def seal.keys(r: Array<U32> & List<&2, U32>, nonce: List<&2, U32>, aad: List<&2, U32>, plain: List<&2, U32>) -> List<&2, U32>:
  match r:
    case (box, +ks):
      seal.h(ct.block(ks, box, zeros4()), ks, nonce, aad, plain)

def seal.size(+key: List<&2, U32>, nonce: List<&2, U32>, aad: List<&2, U32>, plain: List<&2, U32>, ok: Bool) -> List<&2, U32>:
  match ok:
    case True{}:
      seal.keys(expand(U32.is_eq(Bytes.len(key), 32), box.mk(), key), nonce, aad, plain)
    case False{}:
      Nil{}

# open
# ----

def open.plain(r: Array<U32> & List<&2, U32>, ct: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match r:
    case (box, raw):
      Some{Bytes.take(raw, U32.to_nat(Bytes.len(ct)))}

# the plaintext when the tag checks out, None when it does not
def open.dec(box: Array<U32>, +ks: List<&2, U32>, +nonce: List<&2, U32>, +ct: List<&2, U32>, ok: Bool) -> Maybe<&2, List<&2, U32>>:
  match ok:
    case True{}:
      open.plain(ct.ctr(chunks(ct), 2, ks, nonce, ct.block(ks, box, ctr.block(nonce, 2)), Nil{}), ct)
    case False{}:
      None{}

def open.check(r: Array<U32> & List<&2, U32>, ks: List<&2, U32>, nonce: List<&2, U32>, +ct: List<&2, U32>, +tag: List<&2, U32>, +h: List<&2, U32>, aad: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match r:
    case (box, e0):
      open.dec(box, ks, nonce, ct, Bytes.ct_eq(bytes.of.words(xor4(ghash(aad, ct, h), e0)), tag))

def open.tag(r: Array<U32> & List<&2, U32>, +ks: List<&2, U32>, +nonce: List<&2, U32>, ct: List<&2, U32>, tag: List<&2, U32>, h: List<&2, U32>, aad: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match r:
    case (box, e0):
      open.check(ct.block(ks, box, ctr.block(nonce, 1)), ks, nonce, ct, tag, h, aad)

def open.h(r: Array<U32> & List<&2, U32>, +ks: List<&2, U32>, +nonce: List<&2, U32>, ct: List<&2, U32>, tag: List<&2, U32>, aad: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match r:
    case (box, h):
      open.tag(ct.block(ks, box, ctr.block(nonce, 1)), ks, nonce, ct, tag, h, aad)

def open.keys(r: Array<U32> & List<&2, U32>, nonce: List<&2, U32>, ct: List<&2, U32>, tag: List<&2, U32>, aad: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match r:
    case (box, +ks):
      open.h(ct.block(ks, box, zeros4()), ks, nonce, ct, tag, aad)

def open.size(+key: List<&2, U32>, nonce: List<&2, U32>, aad: List<&2, U32>, ct: List<&2, U32>, tag: List<&2, U32>, ok: Bool) -> Maybe<&2, List<&2, U32>>:
  match ok:
    case True{}:
      open.keys(expand(U32.is_eq(Bytes.len(key), 32), box.mk(), key), nonce, ct, tag, aad)
    case False{}:
      None{}

# The API
# -------

def ok.len(+key: U32, nonce: U32) -> Bool:
  Bool.and(Bool.or(U32.is_eq(key, 16), U32.is_eq(key, 32)), U32.is_eq(nonce, 12))

def ok.open(sealed: U32, key: U32, nonce: U32) -> Bool:
  Bool.and(U32.is_le(16, sealed), ok.len(key, nonce))

def encrypt.block(r: Array<U32> & List<&2, U32>) -> List<&2, U32>:
  match r:
    case (box, ws):
      bytes.of.words(ws)

def encrypt.keys(r: Array<U32> & List<&2, U32>, block: List<&2, U32>) -> List<&2, U32>:
  match r:
    case (box, ks):
      encrypt.block(ct.block(ks, box, words.of.bytes(block)))

def encrypt.size(+key: List<&2, U32>, block: List<&2, U32>, ok: Bool) -> List<&2, U32>:
  match ok:
    case True{}:
      encrypt.keys(expand(U32.is_eq(Bytes.len(key), 32), box.mk(), key), block)
    case False{}:
      Nil{}

# one 16-byte block under a 16- or 32-byte key. An empty answer means the key or the
# block is a length this module does not take.
def encrypt(+key: List<&2, U32>, +block: List<&2, U32>) -> List<&2, U32>:
  encrypt.size(key, block, Bool.and(Bool.or(U32.is_eq(Bytes.len(key), 16), U32.is_eq(Bytes.len(key), 32)), U32.is_eq(Bytes.len(block), 16)))

# the ciphertext followed by the 16-byte tag. An empty answer means the key is not 16
# or 32 bytes, or the nonce is not 12.
def seal(+key: List<&2, U32>, +nonce: List<&2, U32>, aad: List<&2, U32>, plain: List<&2, U32>) -> List<&2, U32>:
  seal.size(key, nonce, aad, plain, ok.len(Bytes.len(key), Bytes.len(nonce)))

# the plaintext, None when the tag does not match, the sealed message is shorter than
# a tag, or the key or nonce is a length this module does not take
def open(+key: List<&2, U32>, +nonce: List<&2, U32>, aad: List<&2, U32>, +sealed: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  +n = Nat.sub(U32.to_nat(Bytes.len(sealed)), 16n)
  open.size(key, nonce, aad, Bytes.take(sealed, n), Bytes.drop(sealed, n), ok.open(Bytes.len(sealed), Bytes.len(key), Bytes.len(nonce)))
