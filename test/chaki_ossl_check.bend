# offline checks for lib/chaki/ossl.bend: libssl 3 loads, and a handshake against a
# plain-TCP listener that answers garbage fails cleanly, with an error instead of a
# crash or a hang.
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T
import ../lib/chaki/ossl.bend as Ossl

# how a probe ended: the errno (0 for Done) and the text a failure carried
type Probe is Data:
  Probe{code: U32, msg: String}

# the line a probe prints: the errno, and whether the failure came with text to show
def probe.at(+name: String, p: Probe, want: U32) -> String:
  Probe{code, msg} = p
  T.eq(name, U32.show(code) ++ " " ++ T.yes(Bool.not(String.is_empty(msg))), U32.show(want) ++ " yes")

def probe.of.unit(r: Result<&1, &1, U32 & String, Unit>) -> Probe:
  match r:
    case Done{_}:
      Probe{0, ""}
    case Fail{(c, m)}:
      Probe{c, m}

def probe.of.bytes(r: Result<&1, &1, U32 & String, List<&2, U32>>) -> Probe:
  match r:
    case Done{_}:
      Probe{0, ""}
    case Fail{(c, m)}:
      Probe{c, m}

# close on a socket that never had a session just closes it
def closing(s: Socket) -> IO(Unit):
  do IO<Unit>:
    u : Unit <- Ossl.close(s)
    IO.print("ok   close on a socket without a session closes it")

# send without a session says so, and close still closes
def sending.pair(c: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (s, g) = c
  do IO<Unit>:
    IO.print(probe.at("send without a session is EBADF", probe.of.unit(g), 9))
    closing(s)

def sending(s: Socket) -> IO(Unit):
  do IO<Unit>:
    r : Socket & Result<&1, &1, U32 & String, Unit> <- Ossl.send(s, Bytes.of_ascii("GET / HTTP/1.1\r\n\r\n"))
    sending.pair(r)

# a max of 0 fails with EINVAL before the socket is looked at, as Base's TCP.recv_bytes
def zero.pair(c: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (s, g) = c
  do IO<Unit>:
    IO.print(probe.at("recv of 0 bytes is EINVAL", probe.of.bytes(g), 22))
    sending(s)

def zero(s: Socket) -> IO(Unit):
  do IO<Unit>:
    r : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- Ossl.recv(s, 0, 1000)
    zero.pair(r)

# a failed handshake leaves no session
def rest.pair(c: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (s, g) = c
  do IO<Unit>:
    IO.print(probe.at("recv without a session is EBADF", probe.of.bytes(g), 9))
    zero(s)

def rest(s: Socket) -> IO(Unit):
  do IO<Unit>:
    r : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- Ossl.recv(s, 64, 1000)
    rest.pair(r)

def handshake.at(s: Socket, r: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match r:
    case Done{_}:
      do IO<Unit>:
        IO.print(T.eq("the handshake against garbage fails", "Done", "Fail"))
        rest(s)
    case Fail{(code, +msg)}:
      do IO<Unit>:
        IO.print(T.ok("the handshake against garbage fails", Bool.not(String.is_empty(msg))))
        IO.print("ok   it said: " ++ msg)
        IO.print(T.ok("and not by timing out", Bool.not(U32.is_eq(code, 110))))
        rest(s)

def handshake.pair(c: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (s, r) = c
  handshake.at(s, r)

def handshake(s: Socket) -> IO(Unit):
  do IO<Unit>:
    c : Socket & Result<&1, &1, U32 & String, Unit> <- Ossl.connect(s, "example.com", 2000)
    handshake.pair(c)

def dial.at(r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Fail{(c, m)}:
      IO.print(T.eq("the check reaches its own listener", U32.show(c) ++ " " ++ m, "no error"))
    case Done{s}:
      handshake(s)

# the listener's side: one connection, a text line as the answer, then close
def answer.sent(c: Socket & Result<&1, &1, U32 & String, Unit>, l: Listener) -> IO(Unit):
  (s, r) = c
  do IO<Unit>:
    Socket.close(s)
    Listener.close(l)

def answer.done(s: Socket, l: Listener) -> IO(Unit):
  do IO<Unit>:
    w : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(s, "not a TLS handshake\n")
    answer.sent(w, l)

def answer(l: Listener, r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Done{s}:
      answer.done(s, l)
    case Fail{_}:
      Listener.close(l)

# a plain-TCP listener that answers a TLS client with a text line, so no handshake can
# ever work
def garbage.accept(p: Listener & Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  (l, r) = p
  answer(l, r)

def garbage(l: Listener) -> IO(Unit):
  do IO<Unit>:
    p : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(l)
    garbage.accept(p)

def listen.at(r: Result<&1, &1, U32 & String, Listener>) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.print(T.eq("the check's own listener starts", "Fail", "Done"))
    case Done{l}:
      do IO<Unit>:
        c : Chan(Unit) <- IO.fork(Unit, garbage(l))
        d : Result<&1, &1, U32 & String, Socket> <- TCP.connect("127.0.0.1", 43117)
        dial.at(d)
        u : Unit <- IO.join(Unit, c)
        IO.print("ok   the garbage listener is done")

def main() -> IO(Unit):
  do IO<Unit>:
    up : Bool <- Ossl.available()
    IO.print(T.ok("libssl 3 loads", up))
    l : Result<&1, &1, U32 & String, Listener> <- TCP.listen("127.0.0.1", 43117)
    listen.at(l)
