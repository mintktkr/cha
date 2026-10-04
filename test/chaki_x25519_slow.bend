# RFC 7748 §5.2's 1,000-round iterated test: about 80 s on the JS lane, so it lives here,
# run by hand, rather than in chaki_x25519_check.bend, which scripts/check.sh runs:
#   rr bend test/chaki_x25519_slow.bend
import Base
import ../lib/chaki/x25519.bend as X
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T

def iterate(n: Nat, +k: List<&2, U32>, u: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      k
    case 1n+p:
      iterate(p, X.x25519(k, u), k)

def main() -> IO(Unit):
  do IO<Unit>:
    +k0 : List<&2, U32> = Bytes.of_hex("0900000000000000000000000000000000000000000000000000000000000000")
    IO.print(T.hex("RFC 7748 5.2 iterated 1000", iterate(1000n, k0, k0),
      "684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51"))
