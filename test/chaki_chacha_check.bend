# offline checks for lib/chaki/chacha.bend. Every vector is copied verbatim from RFC 8439
# and named after the section it comes from.
import Base
import ../lib/chaki/chacha.bend as C
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T

# the four words of a quarter round as the big-endian hex the RFC prints
def hex8(+n: U32) -> String:
  Bytes.to_hex([U32.and(U32.shrn(n, 24n), 255), U32.and(U32.shrn(n, 16n), 255), U32.and(U32.shrn(n, 8n), 255), U32.and(n, 255)])

def qr.hex(q: C.Qr) -> String:
  match q:
    case C.Qr{+a, +b, +c, +d}:
      hex8(a) ++ hex8(b) ++ hex8(c) ++ hex8(d)

# open's answer as hex, or "none"
def open.hex(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case Some{x}:
      Bytes.to_hex(x)
    case None{}:
      "none"

def flip.go(xs: List<&2, U32>, i: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Bytes.rev(acc)
    case Con{b, t}:
      match i:
        case 0n:
          Bytes.cat(Bytes.rev(U32.xor(b, 1) <> acc), t)
        case 1n+p:
          flip.go(t, p, b <> acc)

# xs with the low bit of byte i flipped
def flip(xs: List<&2, U32>, i: Nat) -> List<&2, U32>:
  flip.go(xs, i, Nil{})

# the inputs the RFC reuses across its sections
def key.zero() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")

def nonce.zero() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 00")

def key.seq() -> List<&2, U32>:
  Bytes.of_hex("00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f")

def nonce.n9() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 09 00 00 00 4a 00 00 00 00")

def nonce.n4a() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 4a 00 00 00 00")

def key.sun() -> List<&2, U32>:
  Bytes.of_hex("80 81 82 83 84 85 86 87 88 89 8a 8b 8c 8d 8e 8f 90 91 92 93 94 95 96 97 98 99 9a 9b 9c 9d 9e 9f")

def nonce.s3() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 01 02 03 04 05 06 07")

def nonce.a4() -> List<&2, U32>:
  Bytes.of_hex("07 00 00 00 40 41 42 43 44 45 46 47")

def aad.s8() -> List<&2, U32>:
  Bytes.of_hex("50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7")

def key.a22() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01")

def nonce.a22() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 02")

def key.a23() -> List<&2, U32>:
  Bytes.of_hex("1c 92 40 a5 eb 55 d3 8a f3 33 88 86 04 f6 b5 f0 47 39 17 c1 40 2b 80 09 9d ca 5c bc 20 70 75 c0")

def nonce.a23() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 02")

def key.a13() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01")

def key.a14() -> List<&2, U32>:
  Bytes.of_hex("00 ff 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")

def nonce.a15() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 02")

def plain.screen() -> List<&2, U32>:
  Bytes.of_hex("4c 61 64 69 65 73 20 61 6e 64 20 47 65 6e 74 6c 65 6d 65 6e 20 6f 66 20 74 68 65 20 63 6c 61 73 73 20 6f 66 20 27 39 39 3a 20 49 66 20 49 20 63 6f 75 6c 64 20 6f 66 66 65 72 20 79 6f 75 20 6f 6e 6c 79 20 6f 6e 65 20 74 69 70 20 66 6f 72 20 74 68 65 20 66 75 74 75 72 65 2c 20 73 75 6e 73 63 72 65 65 6e 20 77 6f 75 6c 64 20 62 65 20 69 74 2e")

def ct.screen() -> List<&2, U32>:
  Bytes.of_hex("6e 2e 35 9a 25 68 f9 80 41 ba 07 28 dd 0d 69 81 e9 7e 7a ec 1d 43 60 c2 0a 27 af cc fd 9f ae 0b f9 1b 65 c5 52 47 33 ab 8f 59 3d ab cd 62 b3 57 16 39 d6 24 e6 51 52 ab 8f 53 0c 35 9f 08 61 d8 07 ca 0d bf 50 0d 6a 61 56 a3 8e 08 8a 22 b6 5e 52 bc 51 4d 16 cc f8 06 81 8c e9 1a b7 79 37 36 5a f9 0b bf 74 a3 5b e6 b4 0b 8e ed f2 78 5e 42 87 4d")

def msg.any() -> List<&2, U32>:
  Bytes.of_hex("41 6e 79 20 73 75 62 6d 69 73 73 69 6f 6e 20 74 6f 20 74 68 65 20 49 45 54 46 20 69 6e 74 65 6e 64 65 64 20 62 79 20 74 68 65 20 43 6f 6e 74 72 69 62 75 74 6f 72 20 66 6f 72 20 70 75 62 6c 69 63 61 74 69 6f 6e 20 61 73 20 61 6c 6c 20 6f 72 20 70 61 72 74 20 6f 66 20 61 6e 20 49 45 54 46 20 49 6e 74 65 72 6e 65 74 2d 44 72 61 66 74 20 6f 72 20 52 46 43 20 61 6e 64 20 61 6e 79 20 73 74 61 74 65 6d 65 6e 74 20 6d 61 64 65 20 77 69 74 68 69 6e 20 74 68 65 20 63 6f 6e 74 65 78 74 20 6f 66 20 61 6e 20 49 45 54 46 20 61 63 74 69 76 69 74 79 20 69 73 20 63 6f 6e 73 69 64 65 72 65 64 20 61 6e 20 22 49 45 54 46 20 43 6f 6e 74 72 69 62 75 74 69 6f 6e 22 2e 20 53 75 63 68 20 73 74 61 74 65 6d 65 6e 74 73 20 69 6e 63 6c 75 64 65 20 6f 72 61 6c 20 73 74 61 74 65 6d 65 6e 74 73 20 69 6e 20 49 45 54 46 20 73 65 73 73 69 6f 6e 73 2c 20 61 73 20 77 65 6c 6c 20 61 73 20 77 72 69 74 74 65 6e 20 61 6e 64 20 65 6c 65 63 74 72 6f 6e 69 63 20 63 6f 6d 6d 75 6e 69 63 61 74 69 6f 6e 73 20 6d 61 64 65 20 61 74 20 61 6e 79 20 74 69 6d 65 20 6f 72 20 70 6c 61 63 65 2c 20 77 68 69 63 68 20 61 72 65 20 61 64 64 72 65 73 73 65 64 20 74 6f")

def plain.a21() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")

def plain.a23() -> List<&2, U32>:
  Bytes.of_hex("27 54 77 61 73 20 62 72 69 6c 6c 69 67 2c 20 61 6e 64 20 74 68 65 20 73 6c 69 74 68 79 20 74 6f 76 65 73 0a 44 69 64 20 67 79 72 65 20 61 6e 64 20 67 69 6d 62 6c 65 20 69 6e 20 74 68 65 20 77 61 62 65 3a 0a 41 6c 6c 20 6d 69 6d 73 79 20 77 65 72 65 20 74 68 65 20 62 6f 72 6f 67 6f 76 65 73 2c 0a 41 6e 64 20 74 68 65 20 6d 6f 6d 65 20 72 61 74 68 73 20 6f 75 74 67 72 61 62 65 2e")

def key.a42() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01")

def nonce.a42() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 02")

def key.a43() -> List<&2, U32>:
  Bytes.of_hex("1c 92 40 a5 eb 55 d3 8a f3 33 88 86 04 f6 b5 f0 47 39 17 c1 40 2b 80 09 9d ca 5c bc 20 70 75 c0")

def nonce.a43() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 02")

def key.a32() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 36 e5 f6 b5 c5 e0 60 70 f0 ef ca 96 22 7a 86 3e")

def key.a33() -> List<&2, U32>:
  Bytes.of_hex("36 e5 f6 b5 c5 e0 60 70 f0 ef ca 96 22 7a 86 3e 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")

def key.a34() -> List<&2, U32>:
  Bytes.of_hex("1c 92 40 a5 eb 55 d3 8a f3 33 88 86 04 f6 b5 f0 47 39 17 c1 40 2b 80 09 9d ca 5c bc 20 70 75 c0")

def ct.s8() -> List<&2, U32>:
  Bytes.of_hex("d3 1a 8d 34 64 8e 60 db 7b 86 af bc 53 ef 7e c2 a4 ad ed 51 29 6e 08 fe a9 e2 b5 a7 36 ee 62 d6 3d be a4 5e 8c a9 67 12 82 fa fb 69 da 92 72 8b 1a 71 de 0a 9e 06 0b 29 05 d6 a5 b6 7e cd 3b 36 92 dd bd 7f 2d 77 8b 8c 98 03 ae e3 28 09 1b 58 fa b3 24 e4 fa d6 75 94 55 85 80 8b 48 31 d7 bc 3f f4 de f0 8e 4b 7a 9d e5 76 d2 65 86 ce c6 4b 61 16")

def msg.crypto() -> List<&2, U32>:
  Bytes.of_hex("43 72 79 70 74 6f 67 72 61 70 68 69 63 20 46 6f 72 75 6d 20 52 65 73 65 61 72 63 68 20 47 72 6f 75 70")

def ct.a5() -> List<&2, U32>:
  Bytes.of_hex("64 a0 86 15 75 86 1a f4 60 f0 62 c7 9b e6 43 bd 5e 80 5c fd 34 5c f3 89 f1 08 67 0a c7 6c 8c b2 4c 6c fc 18 75 5d 43 ee a0 9e e9 4e 38 2d 26 b0 bd b7 b7 3c 32 1b 01 00 d4 f0 3b 7f 35 58 94 cf 33 2f 83 0e 71 0b 97 ce 98 c8 a8 4a bd 0b 94 81 14 ad 17 6e 00 8d 33 bd 60 f9 82 b1 ff 37 c8 55 97 97 a0 6e f4 f0 ef 61 c1 86 32 4e 2b 35 06 38 36 06 90 7b 6a 7c 02 b0 f9 f6 15 7b 53 c8 67 e4 b9 16 6c 76 7b 80 4d 46 a5 9b 52 16 cd e7 a4 e9 90 40 c5 a4 04 33 22 5e e2 82 a1 b0 a0 6c 52 3e af 45 34 d7 f8 3f a1 15 5b 00 47 71 8c bc 54 6a 0d 07 2b 04 b3 56 4e ea 1b 42 22 73 f5 48 27 1a 0b b2 31 60 53 fa 76 99 19 55 eb d6 31 59 43 4e ce bb 4e 46 6d ae 5a 10 73 a6 72 76 27 09 7a 10 49 e6 17 d9 1d 36 10 94 fa 68 f0 ff 77 98 71 30 30 5b ea ba 2e da 04 df 99 7b 71 4d 6c 6f 2c 29 a6 ad 5c b4 02 2b 02 70 9b")

def nonce.a5() -> List<&2, U32>:
  Bytes.of_hex("00 00 00 00 01 02 03 04 05 06 07 08")

def aad.a5() -> List<&2, U32>:
  Bytes.of_hex("f3 33 88 86 00 00 00 00 00 00 4e 91")

def tag.a5() -> List<&2, U32>:
  Bytes.of_hex("ee ad 9d 67 89 0c bb 22 39 23 36 fe a1 85 1f 38")

def plain.a5() -> List<&2, U32>:
  Bytes.of_hex("49 6e 74 65 72 6e 65 74 2d 44 72 61 66 74 73 20 61 72 65 20 64 72 61 66 74 20 64 6f 63 75 6d 65 6e 74 73 20 76 61 6c 69 64 20 66 6f 72 20 61 20 6d 61 78 69 6d 75 6d 20 6f 66 20 73 69 78 20 6d 6f 6e 74 68 73 20 61 6e 64 20 6d 61 79 20 62 65 20 75 70 64 61 74 65 64 2c 20 72 65 70 6c 61 63 65 64 2c 20 6f 72 20 6f 62 73 6f 6c 65 74 65 64 20 62 79 20 6f 74 68 65 72 20 64 6f 63 75 6d 65 6e 74 73 20 61 74 20 61 6e 79 20 74 69 6d 65 2e 20 49 74 20 69 73 20 69 6e 61 70 70 72 6f 70 72 69 61 74 65 20 74 6f 20 75 73 65 20 49 6e 74 65 72 6e 65 74 2d 44 72 61 66 74 73 20 61 73 20 72 65 66 65 72 65 6e 63 65 20 6d 61 74 65 72 69 61 6c 20 6f 72 20 74 6f 20 63 69 74 65 20 74 68 65 6d 20 6f 74 68 65 72 20 74 68 61 6e 20 61 73 20 2f e2 80 9c 77 6f 72 6b 20 69 6e 20 70 72 6f 67 72 65 73 73 2e 2f e2 80 9d")

# seal and open round trip at the block boundaries
def roundtrip.ver(+plain: List<&2, U32>, m: Maybe<&2, List<&2, U32>>) -> Bool:
  match m:
    case Some{x}:
      Bytes.ct_eq(x, plain)
    case None{}:
      False{}

def roundtrip(+plain: List<&2, U32>) -> Bool:
  roundtrip.ver(plain, C.open(key.sun(), nonce.a4(), aad.s8(), C.seal(key.sun(), nonce.a4(), aad.s8(), plain)))

def edges.go(lengths: List<&2, U32>, acc: Bool) -> Bool:
  match lengths:
    case Nil{}:
      acc
    case Con{n, t}:
      edges.go(t, Bool.and(acc, roundtrip(Bytes.zeros(U32.to_nat(n)))))

def edges() -> Bool:
  edges.go([0, 1, 15, 16, 17, 63, 64, 65, 127, 128], True{})
def main() -> IO(Unit):
  do IO<Unit>:
    # RFC 8439 2.1.1 the quarter round
    IO.print(T.eq("RFC 8439 2.1.1 quarter round", qr.hex(C.qr(286331153, 16909060, 2609737539, 19088743)), "ea2a92f4cb1cf8ce4581472e5881c4bb"))
    # RFC 8439 2.3.2 the block function
    IO.print(T.hex("RFC 8439 2.3.2 block", C.block(key.seq(), 1, nonce.n9()), "10 f1 e7 e4 d1 3b 59 15 50 0f dd 1f a3 20 71 c4 c7 d1 f4 c7 33 c0 68 03 04 22 aa 9a c3 d4 6c 4e d2 82 64 46 07 9f aa 09 14 c2 d7 05 d9 8b 02 a2 b5 12 9c d1 de 16 4e b9 cb d0 83 e8 a2 50 3c 4e"))
    # RFC 8439 2.4.2 the cipher
    IO.print(T.hex("RFC 8439 2.4.2 encryption", C.chacha20(key.seq(), nonce.n4a(), 1, plain.screen()), "6e 2e 35 9a 25 68 f9 80 41 ba 07 28 dd 0d 69 81 e9 7e 7a ec 1d 43 60 c2 0a 27 af cc fd 9f ae 0b f9 1b 65 c5 52 47 33 ab 8f 59 3d ab cd 62 b3 57 16 39 d6 24 e6 51 52 ab 8f 53 0c 35 9f 08 61 d8 07 ca 0d bf 50 0d 6a 61 56 a3 8e 08 8a 22 b6 5e 52 bc 51 4d 16 cc f8 06 81 8c e9 1a b7 79 37 36 5a f9 0b bf 74 a3 5b e6 b4 0b 8e ed f2 78 5e 42 87 4d"))
    # RFC 8439 2.5.2 Poly1305
    IO.print(T.hex("RFC 8439 2.5.2 Poly1305", C.poly1305(Bytes.of_hex("85 d6 be 78 57 55 6d 33 7f 44 52 fe 42 d5 06 a8 01 03 80 8a fb 0d b2 fd 4a bf f6 af 41 49 f5 1b"), msg.crypto()), "a8 06 1d c1 30 51 36 c6 c2 2b 8b af 0c 01 27 a9"))
    # RFC 8439 2.6.2 the one-time key
    IO.print(T.hex("RFC 8439 2.6.2 one-time key", Bytes.take(C.block(key.sun(), 0, nonce.s3()), 32n), "8a d5 a0 8b 90 5f 81 cc 81 50 40 27 4a b2 94 71 a8 33 b6 37 e3 fd 0d a5 08 db b8 e2 fd d1 a6 46"))
    # RFC 8439 2.8.2 the AEAD
    IO.print(T.hex("RFC 8439 2.8.2 seal", C.seal(key.sun(), nonce.a4(), aad.s8(), plain.screen()), "d3 1a 8d 34 64 8e 60 db 7b 86 af bc 53 ef 7e c2 a4 ad ed 51 29 6e 08 fe a9 e2 b5 a7 36 ee 62 d6 3d be a4 5e 8c a9 67 12 82 fa fb 69 da 92 72 8b 1a 71 de 0a 9e 06 0b 29 05 d6 a5 b6 7e cd 3b 36 92 dd bd 7f 2d 77 8b 8c 98 03 ae e3 28 09 1b 58 fa b3 24 e4 fa d6 75 94 55 85 80 8b 48 31 d7 bc 3f f4 de f0 8e 4b 7a 9d e5 76 d2 65 86 ce c6 4b 61 16 1a e1 0b 59 4f 09 e2 6a 7e 90 2e cb d0 60 06 91"))
    IO.print(T.eq("RFC 8439 2.8.2 open", open.hex(C.open(key.sun(), nonce.a4(), aad.s8(), Bytes.cat(ct.s8(), Bytes.of_hex("1a e1 0b 59 4f 09 e2 6a 7e 90 2e cb d0 60 06 91")))), Bytes.to_hex(Bytes.of_hex("4c 61 64 69 65 73 20 61 6e 64 20 47 65 6e 74 6c 65 6d 65 6e 20 6f 66 20 74 68 65 20 63 6c 61 73 73 20 6f 66 20 27 39 39 3a 20 49 66 20 49 20 63 6f 75 6c 64 20 6f 66 66 65 72 20 79 6f 75 20 6f 6e 6c 79 20 6f 6e 65 20 74 69 70 20 66 6f 72 20 74 68 65 20 66 75 74 75 72 65 2c 20 73 75 6e 73 63 72 65 65 6e 20 77 6f 75 6c 64 20 62 65 20 69 74 2e"))))
    # an empty aad and an empty plaintext still seal and open
    IO.print(T.eq("empty plaintext round trip", open.hex(C.open(key.sun(), nonce.a4(), Nil{}, C.seal(key.sun(), nonce.a4(), Nil{}, Nil{}))), ""))
    # tampering: one bit of the ciphertext, the tag or the aad, and a short tag
    IO.print(T.eq("a bit off the ciphertext", open.hex(C.open(key.sun(), nonce.a4(), aad.s8(), flip(C.seal(key.sun(), nonce.a4(), aad.s8(), plain.screen()), 0n))), "none"))
    IO.print(T.eq("a bit off the tag", open.hex(C.open(key.sun(), nonce.a4(), aad.s8(), flip(C.seal(key.sun(), nonce.a4(), aad.s8(), plain.screen()), 114n))), "none"))
    IO.print(T.eq("a bit off the aad", open.hex(C.open(key.sun(), nonce.a4(), flip(aad.s8(), 0n), C.seal(key.sun(), nonce.a4(), aad.s8(), plain.screen()))), "none"))
    IO.print(T.eq("sealed shorter than a tag", open.hex(C.open(key.sun(), nonce.a4(), aad.s8(), Bytes.zeros(15n))), "none"))
    IO.print(T.eq("sealed is an empty list", open.hex(C.open(key.sun(), nonce.a4(), aad.s8(), Nil{})), "none"))
    # RFC 8439 A.1 the block function, five keys and counters
    IO.print(T.hex("RFC 8439 A.1 #1", C.block(key.zero(), 0, nonce.zero()), "76 b8 e0 ad a0 f1 3d 90 40 5d 6a e5 53 86 bd 28 bd d2 19 b8 a0 8d ed 1a a8 36 ef cc 8b 77 0d c7 da 41 59 7c 51 57 48 8d 77 24 e0 3f b8 d8 4a 37 6a 43 b8 f4 15 18 a1 1c c3 87 b6 69 b2 ee 65 86"))
    IO.print(T.hex("RFC 8439 A.1 #2", C.block(key.zero(), 1, nonce.zero()), "9f 07 e7 be 55 51 38 7a 98 ba 97 7c 73 2d 08 0d cb 0f 29 a0 48 e3 65 69 12 c6 53 3e 32 ee 7a ed 29 b7 21 76 9c e6 4e 43 d5 71 33 b0 74 d8 39 d5 31 ed 1f 28 51 0a fb 45 ac e1 0a 1f 4b 79 4d 6f"))
    IO.print(T.hex("RFC 8439 A.1 #3", C.block(key.a13(), 1, nonce.zero()), "3a eb 52 24 ec f8 49 92 9b 9d 82 8d b1 ce d4 dd 83 20 25 e8 01 8b 81 60 b8 22 84 f3 c9 49 aa 5a 8e ca 00 bb b4 a7 3b da d1 92 b5 c4 2f 73 f2 fd 4e 27 36 44 c8 b3 61 25 a6 4a dd eb 00 6c 13 a0"))
    IO.print(T.hex("RFC 8439 A.1 #4", C.block(key.a14(), 2, nonce.zero()), "72 d5 4d fb f1 2e c4 4b 36 26 92 df 94 13 7f 32 8f ea 8d a7 39 90 26 5e c1 bb be a1 ae 9a f0 ca 13 b2 5a a2 6c b4 a6 48 cb 9b 9d 1b e6 5b 2c 09 24 a6 6c 54 d5 45 ec 1b 73 74 f4 87 2e 99 f0 96"))
    IO.print(T.hex("RFC 8439 A.1 #5", C.block(key.zero(), 0, nonce.a15()), "c2 c6 4d 37 8c d5 36 37 4a e2 04 b9 ef 93 3f cd 1a 8b 22 88 b3 df a4 96 72 ab 76 5b 54 ee 27 c7 8a 97 0e 0e 95 5c 14 f3 a8 8e 74 1b 97 c2 86 f7 5f 8f c2 99 e8 14 83 62 fa 19 8a 39 53 1b ed 6d"))
    # RFC 8439 A.2 the cipher, three plaintexts
    IO.print(T.hex("RFC 8439 A.2 #1", C.chacha20(key.zero(), nonce.zero(), 0, plain.a21()), "76 b8 e0 ad a0 f1 3d 90 40 5d 6a e5 53 86 bd 28 bd d2 19 b8 a0 8d ed 1a a8 36 ef cc 8b 77 0d c7 da 41 59 7c 51 57 48 8d 77 24 e0 3f b8 d8 4a 37 6a 43 b8 f4 15 18 a1 1c c3 87 b6 69 b2 ee 65 86"))
    IO.print(T.hex("RFC 8439 A.2 #2", C.chacha20(key.a22(), nonce.a22(), 1, msg.any()), "a3 fb f0 7d f3 fa 2f de 4f 37 6c a2 3e 82 73 70 41 60 5d 9f 4f 4f 57 bd 8c ff 2c 1d 4b 79 55 ec 2a 97 94 8b d3 72 29 15 c8 f3 d3 37 f7 d3 70 05 0e 9e 96 d6 47 b7 c3 9f 56 e0 31 ca 5e b6 25 0d 40 42 e0 27 85 ec ec fa 4b 4b b5 e8 ea d0 44 0e 20 b6 e8 db 09 d8 81 a7 c6 13 2f 42 0e 52 79 50 42 bd fa 77 73 d8 a9 05 14 47 b3 29 1c e1 41 1c 68 04 65 55 2a a6 c4 05 b7 76 4d 5e 87 be a8 5a d0 0f 84 49 ed 8f 72 d0 d6 62 ab 05 26 91 ca 66 42 4b c8 6d 2d f8 0e a4 1f 43 ab f9 37 d3 25 9d c4 b2 d0 df b4 8a 6c 91 39 dd d7 f7 69 66 e9 28 e6 35 55 3b a7 6c 5c 87 9d 7b 35 d4 9e b2 e6 2b 08 71 cd ac 63 89 39 e2 5e 8a 1e 0e f9 d5 28 0f a8 ca 32 8b 35 1c 3c 76 59 89 cb cf 3d aa 8b 6c cc 3a af 9f 39 79 c9 2b 37 20 fc 88 dc 95 ed 84 a1 be 05 9c 64 99 b9 fd a2 36 e7 e8 18 b0 4b 0b c3 9c 1e 87 6b 19 3b fe 55 69 75 3f 88 12 8c c0 8a aa 9b 63 d1 a1 6f 80 ef 25 54 d7 18 9c 41 1f 58 69 ca 52 c5 b8 3f a3 6f f2 16 b9 c1 d3 00 62 be bc fd 2d c5 bc e0 91 19 34 fd a7 9a 86 f6 e6 98 ce d7 59 c3 ff 9b 64 77 33 8f 3d a4 f9 cd 85 14 ea 99 82 cc af b3 41 b2 38 4d d9 02 f3 d1 ab 7a c6 1d d2 9c 6f 21 ba 5b 86 2f 37 30 e3 7c fd c4 fd 80 6c 22 f2 21"))
    IO.print(T.hex("RFC 8439 A.2 #3", C.chacha20(key.a23(), nonce.a23(), 42, plain.a23()), "62 e6 34 7f 95 ed 87 a4 5f fa e7 42 6f 27 a1 df 5f b6 91 10 04 4c 0d 73 11 8e ff a9 5b 01 e5 cf 16 6d 3d f2 d7 21 ca f9 b2 1e 5f b1 4c 61 68 71 fd 84 c5 4f 9d 65 b2 83 19 6c 7f e4 f6 05 53 eb f3 9c 64 02 c4 22 34 e3 2a 35 6b 3e 76 43 12 a6 1a 55 32 05 57 16 ea d6 96 25 68 f8 7d 3f 3f 77 04 c6 a8 d1 bc d1 bf 4d 50 d6 15 4b 6d a7 31 b1 87 b5 8d fd 72 8a fa 36 75 7a 79 7a c1 88 d1"))
    # RFC 8439 A.3 Poly1305, eleven cases
    IO.print(T.hex("RFC 8439 A.3 #1", C.poly1305(key.zero(), Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")), "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))
    IO.print(T.hex("RFC 8439 A.3 #2", C.poly1305(Bytes.of_hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 36 e5 f6 b5 c5 e0 60 70 f0 ef ca 96 22 7a 86 3e"), msg.any()), "36 e5 f6 b5 c5 e0 60 70 f0 ef ca 96 22 7a 86 3e"))
    IO.print(T.hex("RFC 8439 A.3 #3", C.poly1305(Bytes.of_hex("36 e5 f6 b5 c5 e0 60 70 f0 ef ca 96 22 7a 86 3e 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"), msg.any()), "f3 47 7e 7c d9 54 17 af 89 a6 b8 79 4c 31 0c f0"))
    IO.print(T.hex("RFC 8439 A.3 #4", C.poly1305(Bytes.of_hex("1c 92 40 a5 eb 55 d3 8a f3 33 88 86 04 f6 b5 f0 47 39 17 c1 40 2b 80 09 9d ca 5c bc 20 70 75 c0"), plain.a23()), "45 41 66 9a 7e aa ee 61 e7 08 dc 7c bc c5 eb 62"))
    IO.print(T.hex("RFC 8439 A.3 #5", C.poly1305(Bytes.of_hex("02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"), Bytes.of_hex("FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF")), "03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))
    IO.print(T.hex("RFC 8439 A.3 #6", C.poly1305(Bytes.of_hex("02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF"), Bytes.of_hex("02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")), "03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))
    IO.print(T.hex("RFC 8439 A.3 #7", C.poly1305(Bytes.of_hex("01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"), Bytes.of_hex("FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF F0 FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF 11 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")), "05 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))
    IO.print(T.hex("RFC 8439 A.3 #8", C.poly1305(Bytes.of_hex("01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"), Bytes.of_hex("FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FB FE FE FE FE FE FE FE FE FE FE FE FE FE FE FE 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01")), "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))
    IO.print(T.hex("RFC 8439 A.3 #9", C.poly1305(Bytes.of_hex("02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"), Bytes.of_hex("FD FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF")), "FA FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF"))
    IO.print(T.hex("RFC 8439 A.3 #10", C.poly1305(Bytes.of_hex("01 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"), Bytes.of_hex("E3 35 94 D7 50 5E 43 B9 00 00 00 00 00 00 00 00 33 94 D7 50 5E 43 79 CD 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")), "14 00 00 00 00 00 00 00 55 00 00 00 00 00 00 00"))
    IO.print(T.hex("RFC 8439 A.3 #11", C.poly1305(Bytes.of_hex("01 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"), Bytes.of_hex("E3 35 94 D7 50 5E 43 B9 00 00 00 00 00 00 00 00 33 94 D7 50 5E 43 79 CD 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")), "13 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))
    # RFC 8439 A.4 the one-time key, three cases
    IO.print(T.hex("RFC 8439 A.4 #1", Bytes.take(C.block(key.zero(), 0, nonce.zero()), 32n), "76 b8 e0 ad a0 f1 3d 90 40 5d 6a e5 53 86 bd 28 bd d2 19 b8 a0 8d ed 1a a8 36 ef cc 8b 77 0d c7"))
    IO.print(T.hex("RFC 8439 A.4 #2", Bytes.take(C.block(key.a42(), 0, nonce.a42()), 32n), "ec fa 25 4f 84 5f 64 74 73 d3 cb 14 0d a9 e8 76 06 cb 33 06 6c 44 7b 87 bc 26 66 dd e3 fb b7 39"))
    IO.print(T.hex("RFC 8439 A.4 #3", Bytes.take(C.block(key.a43(), 0, nonce.a43()), 32n), "96 5e 3b c6 f9 ec 7e d9 56 08 08 f4 d2 29 f9 4b 13 7f f2 75 ca 9b 3f cb dd 59 de aa d2 33 10 ae"))
    # RFC 8439 A.5 decrypting a message and checking its tag
    IO.print(T.eq("RFC 8439 A.5 open", open.hex(C.open(Bytes.of_hex("1c 92 40 a5 eb 55 d3 8a f3 33 88 86 04 f6 b5 f0 47 39 17 c1 40 2b 80 09 9d ca 5c bc 20 70 75 c0"), nonce.a5(), aad.a5(), Bytes.cat(ct.a5(), tag.a5()))), Bytes.to_hex(Bytes.of_hex("49 6e 74 65 72 6e 65 74 2d 44 72 61 66 74 73 20 61 72 65 20 64 72 61 66 74 20 64 6f 63 75 6d 65 6e 74 73 20 76 61 6c 69 64 20 66 6f 72 20 61 20 6d 61 78 69 6d 75 6d 20 6f 66 20 73 69 78 20 6d 6f 6e 74 68 73 20 61 6e 64 20 6d 61 79 20 62 65 20 75 70 64 61 74 65 64 2c 20 72 65 70 6c 61 63 65 64 2c 20 6f 72 20 6f 62 73 6f 6c 65 74 65 64 20 62 79 20 6f 74 68 65 72 20 64 6f 63 75 6d 65 6e 74 73 20 61 74 20 61 6e 79 20 74 69 6d 65 2e 20 49 74 20 69 73 20 69 6e 61 70 70 72 6f 70 72 69 61 74 65 20 74 6f 20 75 73 65 20 49 6e 74 65 72 6e 65 74 2d 44 72 61 66 74 73 20 61 73 20 72 65 66 65 72 65 6e 63 65 20 6d 61 74 65 72 69 61 6c 20 6f 72 20 74 6f 20 63 69 74 65 20 74 68 65 6d 20 6f 74 68 65 72 20 74 68 61 6e 20 61 73 20 2f e2 80 9c 77 6f 72 6b 20 69 6e 20 70 72 6f 67 72 65 73 73 2e 2f e2 80 9d"))))
    # 1 MB of zeros, sealed and opened
    IO.print(T.ok("1 MB seal and open round trip", roundtrip(Bytes.zeros(1048576n))))
    # short plaintexts at the block boundaries round trip too
    IO.print(T.ok("round trip at 0, 1, 15, 16, 17, 63, 64, 65, 127, 128 bytes", edges()))
