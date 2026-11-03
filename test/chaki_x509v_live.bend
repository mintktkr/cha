# live checks for lib/chaki/x509v.bend, run by hand: the system trust store loads
#   bend test/chaki_x509v_live.bend
import Base
import ../lib/chaki/x509.bend as X509
import ../lib/chaki/x509v.bend as V
import ../lib/chaki/check.bend as T

def loaded(r: Result<&1, &1, U32 & String, List<&2, X509.Cert>>) -> String:
  match r:
    case Done{+xs}:
      T.ok("the system store loads (" ++ Nat.show(List.length(&2, X509.Cert, xs)) ++ " anchors)", Nat.is_gt(List.length(&2, X509.Cert, xs), 100n))
    case Fail{(c, w)}:
      "FAIL the system store: " ++ w

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    r : Result<&1, &1, U32 & String, List<&2, X509.Cert>> <- V.load()
    t1 : Nat <- IO.now()
    IO.print(loaded(r))
    IO.print("load took " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
