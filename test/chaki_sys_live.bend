# sys against a real forge: dial example.com:80, ask for / over HTTP/1.0, and read until
# the peer closes. Run by hand (`rr bend test/chaki_sys_live.bend`); it needs the network.
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T
import ../lib/chaki/sys.bend as Sys

# Reading until close is a fuel-counted state machine: a def that matches can only recurse
# through its own parameters, and recv parks and answers through an IO.bind. The bytes
# accumulate reversed and are reversed once at the end, so every step is a tail call; each
# recv, and each pure step, costs one fuel.
type Read is Type:
  Pull{sock: Socket, acc: List<&2, U32>}
  Hold{got: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, acc: List<&2, U32>}
  End{sock: Socket, acc: List<&2, U32>}

def Read.pick(sock: Socket, data: List<&2, U32>, acc: List<&2, U32>) -> Read:
  match data:
    case Nil{}:
      End{sock, acc}
    case Con{h, t}:
      Pull{sock, Bytes.rev.onto(t, h <> acc)}

def read.go(fuel: Nat, st: Read) -> IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  match fuel st:
    case 0n _:
      IO.pure(Result<&1, &1, U32 & String, List<&2, U32>>,
        Fail{(22, "sys live: read ran out of fuel")})
    case 1n+p Pull{sock, acc}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>,
        Result<&1, &1, U32 & String, List<&2, U32>>,
        Sys.recv(sock, 4096, 5000),
        r => read.go(p, Hold{r, acc}))
    case 1n+p Hold{(sock, Done{data}), acc}:
      read.go(p, Read.pick(sock, data, acc))
    case 1n+p Hold{(sock, Fail{e}), acc}:
      IO.bind(Unit, Result<&1, &1, U32 & String, List<&2, U32>>, Socket.close(sock),
        _ => IO.pure(Result<&1, &1, U32 & String, List<&2, U32>>, Fail{e}))
    case 1n+p End{sock, acc}:
      IO.bind(Unit, Result<&1, &1, U32 & String, List<&2, U32>>, Socket.close(sock),
        _ => IO.pure(Result<&1, &1, U32 & String, List<&2, U32>>, Done{Bytes.rev(acc)}))

def request() -> String:
  "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n"

def got(r: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match r:
    case Done{+data}:
      do IO<Unit>:
        +head : List<&2, U32> = Bytes.take(data, 15n)
        IO.print(T.ok("example.com answers HTTP/1.",
          Bytes.eq(Bytes.take(head, 7n), Bytes.of_ascii("HTTP/1."))))
        IO.print("ok   read " ++ U32.show(Bytes.len(data)) ++ " bytes: " ++
          Bytes.to_ascii(head))
    case Fail{(code, msg)}:
      IO.die(Unit, 1, "sys live: read: " ++ U32.show(code) ++ " " ++ msg)

def sent(w: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match w:
    case (s, Done{u}):
      do IO<Unit>:
        g : Result<&1, &1, U32 & String, List<&2, U32>> <- read.go(64n, Pull{s, Nil{}})
        got(g)
    case (s, Fail{(code, msg)}):
      do IO<Unit>:
        Socket.close(s)
        IO.die(Unit, 1, "sys live: send: " ++ U32.show(code) ++ " " ++ msg)

def dialed(r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Done{s}:
      do IO<Unit>:
        w : Socket & Result<&1, &1, U32 & String, Unit> <-
          Sys.send(s, Bytes.of_ascii(request()))
        sent(w)
    case Fail{(code, msg)}:
      IO.die(Unit, 1, "sys live: dial: " ++ U32.show(code) ++ " " ++ msg)

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, Socket> <- Sys.dial("example.com", 80, 10000)
    dialed(r)
