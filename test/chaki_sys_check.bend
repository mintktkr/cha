# offline checks for lib/chaki/sys.bend: a listener on loopback, a dial to it, and the
# clock and the terminal. Nothing here leaves this machine. Each scenario reads bottom up,
# since a def only sees the defs above it: its deep helper comes first, its server and
# client last.
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T
import ../lib/chaki/sys.bend as Sys

# 0..255, the bytes an echo must return: as hex, and of_hex reads them back
def payload() -> String:
  "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f" ++
  "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f" ++
  "404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f" ++
  "606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f" ++
  "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f" ++
  "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf" ++
  "c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf" ++
  "e0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"

# a listener on 127.0.0.1, with the port it answers on. These ports sit below the ephemeral
# range, so a connection this check makes as a client can never have taken one; a port
# something else already holds fails the check, loudly, rather than pretending.
def bind(+port: U32) -> IO(Listener & U32):
  do IO<Listener & U32>:
    l : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", port))
    return (l, port)

def bad(+name: String, code: U32, +msg: String) -> IO(Unit):
  IO.print("FAIL " ++ name ++ ": " ++ U32.show(code) ++ " " ++ msg)

# Echo
# ----
# The server accepts one connection, echoes the one chunk it reads, then closes. The client
# dials by name, so the dial has to fall back from ::1 to 127.0.0.1 when localhost answers
# the v6 address first.

def echo.got(ch: Chan(Unit), g: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) ->
  IO(Unit):
  match g:
    case (s, Done{data}):
      do IO<Unit>:
        Socket.close(s)
        IO.print(T.hex("echo of 0..255", data, payload()))
        j : Unit <- IO.join(Unit, ch)
        return j
    case (s, Fail{(code, msg)}):
      do IO<Unit>:
        Socket.close(s)
        j : Unit <- IO.join(Unit, ch)
        bad("echo client recv", code, msg)

def echo.client.sent(ch: Chan(Unit), w: Socket & Result<&1, &1, U32 & String, Unit>) ->
  IO(Unit):
  match w:
    case (s, Done{u}):
      do IO<Unit>:
        g : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- Sys.recv(s, 512, 2000)
        echo.got(ch, g)
    case (s, Fail{(code, msg)}):
      do IO<Unit>:
        Socket.close(s)
        j : Unit <- IO.join(Unit, ch)
        bad("echo client send", code, msg)

def echo.dialed(ch: Chan(Unit), r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Done{s}:
      do IO<Unit>:
        w : Socket & Result<&1, &1, U32 & String, Unit> <-
          Sys.send(s, Bytes.of_hex(payload()))
        echo.client.sent(ch, w)
    case Fail{(code, msg)}:
      do IO<Unit>:
        j : Unit <- IO.join(Unit, ch)
        bad("echo dial by name", code, msg)

def echo.sent(w: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match w:
    case (s, Done{u}):
      Socket.close(s)
    case (s, Fail{(code, msg)}):
      do IO<Unit>:
        Socket.close(s)
        bad("echo server send", code, msg)

def echo.back(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match r:
    case (s, Done{data}):
      do IO<Unit>:
        w : Socket & Result<&1, &1, U32 & String, Unit> <- Sys.send(s, data)
        echo.sent(w)
    case (s, Fail{(code, msg)}):
      do IO<Unit>:
        Socket.close(s)
        bad("echo server recv", code, msg)

def echo.accepted(a: Listener & Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match a:
    case (l, Done{s}):
      do IO<Unit>:
        Listener.close(l)
        r : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- Sys.recv(s, 512, 2000)
        echo.back(r)
    case (l, Fail{(code, msg)}):
      do IO<Unit>:
        Listener.close(l)
        bad("echo accept", code, msg)

def echo.serve(l: Listener) -> IO(Unit):
  do IO<Unit>:
    a : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(l)
    echo.accepted(a)

def echo.client(lp: Listener & U32) -> IO(Unit):
  (l, p) = lp
  do IO<Unit>:
    ch : Chan(Unit) <- IO.fork(Unit, echo.serve(l))
    r : Result<&1, &1, U32 & String, Socket> <- Sys.dial("localhost", p, 2000)
    echo.dialed(ch, r)

# Close
# -----
# The server closes the moment it accepts: recv then answers Done{[]}, an empty list, not a
# failure.

def closed.got(ch: Chan(Unit), g: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) ->
  IO(Unit):
  match g:
    case (s, Done{data}):
      do IO<Unit>:
        Socket.close(s)
        IO.print(T.eq("recv after the peer closed",
          U32.show(Bytes.len(data)) ++ " bytes", "0 bytes"))
        j : Unit <- IO.join(Unit, ch)
        return j
    case (s, Fail{(code, msg)}):
      do IO<Unit>:
        Socket.close(s)
        j : Unit <- IO.join(Unit, ch)
        bad("recv after the peer closed", code, msg)

def closed.dialed(ch: Chan(Unit), r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Done{s}:
      do IO<Unit>:
        g : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- Sys.recv(s, 64, 2000)
        closed.got(ch, g)
    case Fail{(code, msg)}:
      do IO<Unit>:
        j : Unit <- IO.join(Unit, ch)
        bad("closed dial", code, msg)

def closed.accepted(a: Listener & Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match a:
    case (l, Done{s}):
      do IO<Unit>:
        Socket.close(s)
        Listener.close(l)
    case (l, Fail{(code, msg)}):
      do IO<Unit>:
        Listener.close(l)
        bad("close accept", code, msg)

def closed.serve(l: Listener) -> IO(Unit):
  do IO<Unit>:
    a : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(l)
    closed.accepted(a)

def closed.client(lp: Listener & U32) -> IO(Unit):
  (l, p) = lp
  do IO<Unit>:
    ch : Chan(Unit) <- IO.fork(Unit, closed.serve(l))
    r : Result<&1, &1, U32 & String, Socket> <- Sys.dial("127.0.0.1", p, 2000)
    closed.dialed(ch, r)

# Deadline
# --------
# The server holds the connection open and silent; recv misses its 300 ms deadline, and waits
# about that long.

def quiet.got(ch: Chan(Unit), t: Nat, u: Nat,
  g: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match g:
    case (s, Fail{(code, msg)}):
      do IO<Unit>:
        Socket.close(s)
        +spent : Nat = Nat.sub(u, t)
        IO.print(T.eq("recv misses its deadline", U32.show(code), "110"))
        IO.print(T.ok("recv waits about the deadline",
          Bool.and(Nat.is_ge(spent, 250n), Nat.is_le(spent, 1500n))))
        j : Unit <- IO.join(Unit, ch)
        return j
    case (s, Done{data}):
      do IO<Unit>:
        Socket.close(s)
        IO.print(T.eq("recv from a silent peer", U32.show(Bytes.len(data)) ++ " bytes",
          "ETIMEDOUT"))
        j : Unit <- IO.join(Unit, ch)
        return j

def quiet.dialed(ch: Chan(Unit), t: Nat, r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Done{s}:
      do IO<Unit>:
        g : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- Sys.recv(s, 64, 300)
        u : Nat <- IO.now()
        quiet.got(ch, t, u, g)
    case Fail{(code, msg)}:
      do IO<Unit>:
        j : Unit <- IO.join(Unit, ch)
        bad("quiet dial", code, msg)

def quiet.accepted(a: Listener & Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match a:
    case (l, Done{s}):
      do IO<Unit>:
        Listener.close(l)
        IO.sleep(800)
        Socket.close(s)
    case (l, Fail{(code, msg)}):
      do IO<Unit>:
        Listener.close(l)
        bad("quiet accept", code, msg)

def quiet.serve(l: Listener) -> IO(Unit):
  do IO<Unit>:
    a : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(l)
    quiet.accepted(a)

def quiet.client(lp: Listener & U32) -> IO(Unit):
  (l, p) = lp
  do IO<Unit>:
    ch : Chan(Unit) <- IO.fork(Unit, quiet.serve(l))
    t : Nat <- IO.now()
    r : Result<&1, &1, U32 & String, Socket> <- Sys.dial("127.0.0.1", p, 2000)
    quiet.dialed(ch, t, r)

# Refused
# -------
# A port with nothing listening: the dial is refused rather than waiting for the deadline.

def refused.got(t: Nat, u: Nat, r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Fail{(code, msg)}:
      do IO<Unit>:
        IO.print(T.eq("dial to a closed port", U32.show(code), "111"))
        IO.print(T.ok("a refused dial fails fast", Nat.is_le(Nat.sub(u, t), 900n)))
    case Done{s}:
      do IO<Unit>:
        Socket.close(s)
        IO.print(T.eq("dial to a closed port", "connected", "ECONNREFUSED"))

def refused.client(lp: Listener & U32) -> IO(Unit):
  (l, p) = lp
  do IO<Unit>:
    Listener.close(l)
    t : Nat <- IO.now()
    r : Result<&1, &1, U32 & String, Socket> <- Sys.dial("127.0.0.1", p, 1000)
    u : Nat <- IO.now()
    refused.got(t, u, r)

# A name that cannot resolve: the failure names it.

def resolve.got(r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Fail{(code, msg)}:
      IO.print(T.ok("a name that cannot resolve fails",
        String.contains(msg, "no-such-host.invalid")))
    case Done{s}:
      do IO<Unit>:
        Socket.close(s)
        IO.print(T.eq("a name that cannot resolve", "connected", "a failure naming it"))

def resolve.check() -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, Socket> <- Sys.dial("no-such-host.invalid", 80, 2000)
    resolve.got(r)

def main() -> IO(Unit):
  do IO<Unit>:
    +t : U32 <- Sys.now()
    IO.print(T.ok("now is a Unix second",
      Bool.and(U32.is_gt(t, 1790000000), U32.is_lt(t, 2000000000))))
    no : U32 <- Sys.isatty.raw(99)
    IO.print(T.ok("isatty(99) is false", U32.is_eq(no, 0)))
    b : Bool <- Sys.isatty(99)
    IO.print(T.ok("isatty answers a Bool", Bool.not(b)))
    +tty : U32 <- Sys.isatty.raw(1)
    +cols : U32 <- Sys.cols()
    IO.print(T.ok(Bool.pick(String, U32.is_ne(tty, 0),
      "cols > 0 on a tty", "cols == 0 off a tty"),
      Bool.pick(Bool, U32.is_ne(tty, 0), U32.is_ne(cols, 0), U32.is_eq(cols, 0))))
    lp : Listener & U32 <- bind(14711)
    echo.client(lp)
    lp : Listener & U32 <- bind(14721)
    closed.client(lp)
    lp : Listener & U32 <- bind(14731)
    quiet.client(lp)
    lp : Listener & U32 <- bind(14741)
    refused.client(lp)
    resolve.check()
