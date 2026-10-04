# offline checks for lib/chaki/x25519.bend
import Base
import ../lib/chaki/x25519.bend as X
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T

# RFC 7748 §5.2's iterated test: k and u both start at 9 followed by zeros, each round
# sets k to the result and u to the old k, and the answer is what k holds at the end.
def iterate(n: Nat, +k: List<&2, U32>, u: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      k
    case 1n+p:
      iterate(p, X.x25519(k, u), k)

def iterated(n: Nat) -> List<&2, U32>:
  +k0 = Bytes.of_hex("0900000000000000000000000000000000000000000000000000000000000000")
  iterate(n, k0, k0)

# the same bytes with bit 255 set: RFC 7748 §5 says that bit is not part of the field
def set.top.head(acc: List<&2, U32>) -> List<&2, U32>:
  match acc:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Bytes.rev(U32.or(h, 128) <> t)

def set.top.go(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      set.top.head(acc)
    case Con{h, t}:
      set.top.go(t, h <> acc)

def set.top(xs: List<&2, U32>) -> List<&2, U32>:
  set.top.go(xs, Nil{})

# 77076d0a... and 5dab087e... are Alice's and Bob's private keys of RFC 7748 §6.1
def alice() -> List<&2, U32>:
  Bytes.of_hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")

def bob() -> List<&2, U32>:
  Bytes.of_hex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")

# The prime itself, edffff...7f, is not a canonical u-coordinate: it is zero.
def prime() -> List<&2, U32>:
  Bytes.of_hex("edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f")

# 2^255-1 is p+18, so it stands for the u-coordinate 18
def above() -> List<&2, U32>:
  Bytes.of_hex("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f")

# RFC 7748 §6.1's shared secret, timed: one x25519 is what the ladder costs
def time.one(+name: String, +scalar: List<&2, U32>, +u: List<&2, U32>, +want: String) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    r : List<&2, U32> = X.x25519(scalar, u)
    t1 : Nat <- IO.now()
    IO.print(T.hex(name, r, want))
    IO.print("     " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms for one x25519")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(T.hex("RFC 7748 5.2 X25519 vector 1",
      X.x25519(Bytes.of_hex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
        Bytes.of_hex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c")),
      "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552"))
    IO.print(T.hex("RFC 7748 5.2 X25519 vector 2",
      X.x25519(Bytes.of_hex("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d"),
        Bytes.of_hex("e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493")),
      "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957"))
    IO.print(T.hex("RFC 7748 5.2 iterated once", iterated(1n),
      "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079"))
    IO.print(T.hex("RFC 7748 6.1 Alice public key", X.public(alice()),
      "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"))
    IO.print(T.hex("RFC 7748 6.1 Bob public key", X.public(bob()),
      "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"))
    IO.print(T.hex("RFC 7748 6.1 shared secret from Alice", X.x25519(alice(), X.public(bob())),
      "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"))
    time.one("RFC 7748 6.1 shared secret from Bob", bob(), X.public(alice()),
      "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
    IO.print(T.hex("u = 0 answers the zero value", X.x25519(alice(), Bytes.zeros(32n)),
      "0000000000000000000000000000000000000000000000000000000000000000"))
    IO.print(T.hex("u = p answers the zero value", X.x25519(alice(), prime()),
      "0000000000000000000000000000000000000000000000000000000000000000"))
    IO.print(T.hex("u = 1 answers the zero value", X.x25519(alice(), 1 <> Bytes.zeros(31n)),
      "0000000000000000000000000000000000000000000000000000000000000000"))
    IO.print(T.hex("bit 255 of u is masked", X.x25519(alice(), set.top(X.public(bob()))),
      "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"))
    IO.print(T.hex("u = 2^255-1 is the u-coordinate 18", X.x25519(alice(), above()),
      "359668d79a67267a57ffef8f0f4a9882a7c0e3122cb1999c5626346383f9f811"))
    IO.print(T.hex("an empty input answers the zero value", X.x25519(Nil{}, Nil{}),
      "0000000000000000000000000000000000000000000000000000000000000000"))
    IO.print(T.eq("a 31-byte scalar still answers 32 bytes",
      U32.show(Bytes.len(X.x25519(Bytes.take(alice(), 31n), Bytes.zeros(32n)))), "32"))
