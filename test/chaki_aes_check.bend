# offline checks for lib/chaki/aes.bend. The AES vectors are FIPS-197 Appendix C.1
# and C.3; the GCM vectors are test cases 1-4 and 13-16 of McGrew and Viega, "The
# Galois/Counter Mode of Operation (GCM)" (those are the 96-bit IV cases).
import Base
import ../lib/chaki/aes.bend as Aes
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T

def plain.of(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case Some{p}:
      Bytes.to_hex(p)
    case None{}:
      "none"

def plain.ok(m: Maybe<&2, List<&2, U32>>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

# xs with the low bit of byte k flipped
def flip.byte(ys: List<&2, U32>) -> List<&2, U32>:
  match ys:
    case Con{h, t}:
      U32.xor(h, 1) <> t
    case Nil{}:
      Nil{}

def flip(+xs: List<&2, U32>, +k: Nat) -> List<&2, U32>:
  Bytes.cat(Bytes.take(xs, k), Bytes.cat(flip.byte(Bytes.drop(xs, k)), Bytes.drop(xs, Nat.add(k, 1n))))

# GCM test case 4: a 128-bit key, AAD, and a plaintext that is not a whole block
def tc4.key() -> List<&2, U32>:
  Bytes.of_hex("feffe9928665731c6d6a8f9467308308")

def tc4.iv() -> List<&2, U32>:
  Bytes.of_hex("cafebabefacedbaddecaf888")

def tc4.aad() -> List<&2, U32>:
  Bytes.of_hex("feedfacedeadbeeffeedfacedeadbeefabaddad2")

def tc4.plain() -> List<&2, U32>:
  Bytes.of_hex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39")

def tc4.sealed() -> List<&2, U32>:
  Bytes.of_hex("42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e0915bc94fbc3221a5db94fae95ae7121a47")

# GCM test case 16: the same shapes under a 256-bit key
def tc16.key() -> List<&2, U32>:
  Bytes.of_hex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308")

def tc16.sealed() -> List<&2, U32>:
  Bytes.of_hex("522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f66276fc6ece0f4e1768cddf8853bb2d551b")

# a 256 KB message, all zeros
def big.key() -> List<&2, U32>:
  Bytes.of_hex("000102030405060708090a0b0c0d0e0f")

def big.iv() -> List<&2, U32>:
  Bytes.of_hex("cafebabefacedbaddecaf888")

# Bytes.eq is not a tail call, so a 256 KB message needs one that is
def same.go(a: List<&2, U32>, b: List<&2, U32>, ok: Bool) -> Bool:
  match a b:
    case Nil{} Nil{}:
      ok
    case Con{x, s} Con{y, t}:
      same.go(s, t, Bool.and(ok, U32.is_eq(x, y)))
    case _ _:
      False{}

def big.check(m: Maybe<&2, List<&2, U32>>, pt: List<&2, U32>) -> Bool:
  match m:
    case Some{p}:
      same.go(p, pt, True{})
    case None{}:
      False{}

def big.round() -> Bool:
  +pt = Bytes.zeros(262144n)
  +sealed = Aes.seal(big.key(), big.iv(), Nil{}, pt)
  Bool.and(U32.is_eq(Bytes.len(sealed), 262160), big.check(Aes.open(big.key(), big.iv(), Nil{}, sealed), pt))

# fixtures for the lengths the GCM spec does not cover, generated with this machine's
# OpenSSL (through bun's node:crypto) and round-tripped there
def fx.key128() -> List<&2, U32>:
  Bytes.of_hex("0f0e0d0c0b0a09080706050403020100")

def fx.key256() -> List<&2, U32>:
  Bytes.of_hex("0f0e0d0c0b0a090807060504030201000f0e0d0c0b0a09080706050403020100")

def fx.iv() -> List<&2, U32>:
  Bytes.of_hex("0102030405060708090a0b0c")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(T.hex("FIPS-197 C.1 encrypt", Aes.encrypt(Bytes.of_hex("000102030405060708090a0b0c0d0e0f"), Bytes.of_hex("00112233445566778899aabbccddeeff")), "69c4e0d86a7b0430d8cdb78070b4c55a"))
    IO.print(T.hex("FIPS-197 C.3 encrypt", Aes.encrypt(Bytes.of_hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"), Bytes.of_hex("00112233445566778899aabbccddeeff")), "8ea2b7ca516745bfeafc49904b496089"))
    IO.print(T.ok("encrypt, a short key is refused", Bytes.eq(Aes.encrypt(Bytes.of_hex("00010203"), Bytes.of_hex("00112233445566778899aabbccddeeff")), Nil{})))
    IO.print(T.ok("encrypt, a short block is refused", Bytes.eq(Aes.encrypt(Bytes.of_hex("000102030405060708090a0b0c0d0e0f"), Bytes.of_hex("00112233")), Nil{})))
    IO.print(T.hex("GCM test case 1 seal", Aes.seal(Bytes.of_hex("00000000000000000000000000000000"), Bytes.of_hex("000000000000000000000000"), Nil{}, Nil{}), "58e2fccefa7e3061367f1d57a4e7455a"))
    IO.print(T.hex("GCM test case 2 seal", Aes.seal(Bytes.of_hex("00000000000000000000000000000000"), Bytes.of_hex("000000000000000000000000"), Nil{}, Bytes.of_hex("00000000000000000000000000000000")), "0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf"))
    IO.print(T.hex("GCM test case 3 seal", Aes.seal(Bytes.of_hex("feffe9928665731c6d6a8f9467308308"), Bytes.of_hex("cafebabefacedbaddecaf888"), Nil{}, Bytes.of_hex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255")), "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f59854d5c2af327cd64a62cf35abd2ba6fab4"))
    IO.print(T.hex("GCM test case 4 seal", Aes.seal(tc4.key(), tc4.iv(), tc4.aad(), tc4.plain()), "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e0915bc94fbc3221a5db94fae95ae7121a47"))
    IO.print(T.hex("GCM test case 13 seal", Aes.seal(Bytes.of_hex("0000000000000000000000000000000000000000000000000000000000000000"), Bytes.of_hex("000000000000000000000000"), Nil{}, Nil{}), "530f8afbc74536b9a963b4f1c4cb738b"))
    IO.print(T.hex("GCM test case 14 seal", Aes.seal(Bytes.of_hex("0000000000000000000000000000000000000000000000000000000000000000"), Bytes.of_hex("000000000000000000000000"), Nil{}, Bytes.of_hex("00000000000000000000000000000000")), "cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919"))
    IO.print(T.hex("GCM test case 15 seal", Aes.seal(Bytes.of_hex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"), Bytes.of_hex("cafebabefacedbaddecaf888"), Nil{}, Bytes.of_hex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255")), "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015adb094dac5d93471bdec1a502270e3cc6c"))
    IO.print(T.hex("GCM test case 16 seal", Aes.seal(tc16.key(), tc4.iv(), tc4.aad(), tc4.plain()), "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f66276fc6ece0f4e1768cddf8853bb2d551b"))
    IO.print(T.eq("GCM test case 1 open", plain.of(Aes.open(Bytes.of_hex("00000000000000000000000000000000"), Bytes.of_hex("000000000000000000000000"), Nil{}, Bytes.of_hex("58e2fccefa7e3061367f1d57a4e7455a"))), ""))
    IO.print(T.eq("GCM test case 3 open", plain.of(Aes.open(Bytes.of_hex("feffe9928665731c6d6a8f9467308308"), Bytes.of_hex("cafebabefacedbaddecaf888"), Nil{}, Bytes.of_hex("42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f59854d5c2af327cd64a62cf35abd2ba6fab4"))), "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255"))
    IO.print(T.eq("GCM test case 4 open", plain.of(Aes.open(tc4.key(), tc4.iv(), tc4.aad(), tc4.sealed())), "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"))
    IO.print(T.eq("GCM test case 16 open", plain.of(Aes.open(tc16.key(), tc4.iv(), tc4.aad(), tc16.sealed())), "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"))
    IO.print(T.hex("GCM, a one-byte message", Aes.seal(fx.key128(), fx.iv(), Nil{}, Bytes.of_hex("a1")), "b2188d2cc9d801c51e2231b715b19288a1"))
    IO.print(T.eq("GCM, a one-byte message open", plain.of(Aes.open(fx.key128(), fx.iv(), Nil{}, Bytes.of_hex("b2188d2cc9d801c51e2231b715b19288a1"))), "a1"))
    IO.print(T.hex("GCM, 17 bytes under 4 bytes of AAD", Aes.seal(fx.key128(), fx.iv(), Bytes.of_hex("b0b1b2b3"), Bytes.of_hex("c1c2c3c4c5c6c7c8c9cacbcccdcecfd011")), "d2070318454d7bd1e57b717d1c70e42a9ed1c9375a2bbc81d5fa5fa9af9f1b8005"))
    IO.print(T.eq("GCM, 17 bytes under 4 bytes of AAD open", plain.of(Aes.open(fx.key128(), fx.iv(), Bytes.of_hex("b0b1b2b3"), Bytes.of_hex("d2070318454d7bd1e57b717d1c70e42a9ed1c9375a2bbc81d5fa5fa9af9f1b8005"))), "c1c2c3c4c5c6c7c8c9cacbcccdcecfd011"))
    IO.print(T.hex("GCM, 48 bytes under a 256-bit key", Aes.seal(fx.key256(), fx.iv(), Nil{}, Bytes.of_hex("a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0")), "f291ade23b83dd039b209b38a87ac2e9c65e3b566e12e96c5bc98f97f3acfbb1fedd0017b023ff3850afb804481da209"))
    IO.print(T.eq("GCM, 48 bytes under a 256-bit key open", plain.of(Aes.open(fx.key256(), fx.iv(), Nil{}, Bytes.of_hex("f291ade23b83dd039b209b38a87ac2e9c65e3b566e12e96c5bc98f97f3acfbb1fedd0017b023ff3850afb804481da209"))), "a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0"))
    IO.print(T.hex("GCM, an empty message under AAD", Aes.seal(fx.key128(), fx.iv(), Bytes.of_hex("deadbeef"), Nil{}), "8a0f92ebd7b7fda574cf02963735b22c"))
    IO.print(T.eq("GCM, an empty message under AAD open", plain.of(Aes.open(fx.key128(), fx.iv(), Bytes.of_hex("deadbeef"), Bytes.of_hex("8a0f92ebd7b7fda574cf02963735b22c"))), ""))
    IO.print(T.ok("open, one ciphertext bit flipped", Bool.not(plain.ok(Aes.open(tc4.key(), tc4.iv(), tc4.aad(), flip(tc4.sealed(), 0n))))))
    IO.print(T.ok("open, one tag bit flipped", Bool.not(plain.ok(Aes.open(tc4.key(), tc4.iv(), tc4.aad(), flip(tc4.sealed(), U32.to_nat(Bytes.len(tc4.plain()))))))))
    IO.print(T.ok("open, one AAD bit flipped", Bool.not(plain.ok(Aes.open(tc4.key(), tc4.iv(), flip(tc4.aad(), 0n), tc4.sealed())))))
    IO.print(T.ok("open, a shorter-than-tag message", Bool.not(plain.ok(Aes.open(tc4.key(), tc4.iv(), tc4.aad(), Bytes.take(tc4.sealed(), 10n))))))
    IO.print(T.ok("open, the wrong key length", Bool.not(plain.ok(Aes.open(Bytes.of_hex("000102030405060708090a0b0c0d0e0f1011121314151617"), tc4.iv(), tc4.aad(), tc4.sealed())))))
    IO.print(T.ok("open, the wrong nonce length", Bool.not(plain.ok(Aes.open(tc4.key(), Bytes.of_hex("cafebabefacedbaddecaf88"), tc4.aad(), tc4.sealed())))))
    IO.print(T.ok("seal, the wrong key length", Bytes.eq(Aes.seal(Bytes.of_hex("000102030405060708090a0b0c0d0e0f1011121314151617"), tc4.iv(), tc4.aad(), tc4.plain()), Nil{})))
    IO.print(T.ok("seal, the wrong nonce length", Bytes.eq(Aes.seal(tc4.key(), Bytes.of_hex("cafebabefacedbaddecaf88"), tc4.aad(), tc4.plain()), Nil{})))
    IO.print(T.ok("a 256 KB round trip", big.round()))
