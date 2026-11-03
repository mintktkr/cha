# live checks for lib/chaki/ossl.bend, against real forges. Run by hand:
#   bend test/chaki_ossl_live.bend
#   bend test/chaki_ossl_live.bend -o out/live && ./out/live
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T
import ../lib/chaki/ossl.bend as Ossl

# the sys lane's dial lands later; until then, resolve with getent and let Base's
# TCP.connect dial the literal
def ipv4.head(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      h

def ipv4.of(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Done{(status, (out, err))}:
      ipv4.head(String.split(out, ' '))
    case Fail{(c, m)}:
      ""

def ipv4(+host: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("getent", ["ahostsv4", host], "", 65536, 5000)
    return ipv4.of(r)

# one line per step: what the step did, and the errno and text when it failed
def said(+name: String, r: Result<&1, &1, U32 & String, Unit>) -> String:
  match r:
    case Done{_}:
      "ok   " ++ name
    case Fail{(c, m)}:
      "FAIL " ++ name ++ ": " ++ U32.show(c) ++ " " ++ m

def answer.said(+name: String, +text: String, ok: Bool) -> String:
  match ok:
    case True{}:
      "ok   " ++ name
    case False{}:
      "FAIL " ++ name ++ ": " ++ String.take(text, 60n)

def gets.said(+name: String, r: Result<&1, &1, U32 & String, List<&2, U32>>) -> String:
  match r:
    case Done{+bs}:
      answer.said(name, Bytes.to_ascii(bs), String.starts_with(Bytes.to_ascii(bs), "HTTP/1.1 200"))
    case Fail{(c, m)}:
      "FAIL " ++ name ++ ": " ++ U32.show(c) ++ " " ++ m

def refused.said(+name: String, r: Result<&1, &1, U32 & String, Unit>) -> String:
  match r:
    case Done{_}:
      "FAIL " ++ name ++ ": the handshake answered Done"
    case Fail{(c, m)}:
      "ok   " ++ name ++ ": " ++ U32.show(c) ++ " " ++ m

# reading on to the peer's close: Done{[]} is what the close has to be
type Drain is Type:
  Reading{sock: Socket}
  Closing{sock: Socket, +line: String}

def drain.closed(+host: String, s: Socket, empty: Bool) -> Drain:
  match empty:
    case True{}:
      Closing{s, "ok   " ++ host ++ " closed"}
    case False{}:
      Reading{s}

def drain.of(+host: String, c: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> Drain:
  (s, g) = c
  match g:
    case Done{+bs}:
      drain.closed(host, s, List.is_empty(&2, U32, bs))
    case Fail{(c, m)}:
      Closing{s, "FAIL " ++ host ++ " reading to the close: " ++ U32.show(c) ++ " " ++ m}

def drain.end(+host: String, s: Socket, +line: String) -> IO(Unit):
  do IO<Unit>:
    u : Unit <- Ossl.close(s)
    IO.print(line)

def drain.give(+host: String, st: Drain) -> IO(Unit):
  match st:
    case Reading{sock}:
      drain.end(host, sock, "FAIL " ++ host ++ " never closed")
    case Closing{sock, +line}:
      drain.end(host, sock, line)

# read until the peer's close, a few reads at most
def drain(fuel: Nat, +host: String, st: Drain) -> IO(Unit):
  match fuel:
    case 0n:
      drain.give(host, st)
    case 1n+p:
      match st:
        case Reading{sock}:
          do IO<Unit>:
            r : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- Ossl.recv(sock, 65536, 10000)
            drain(p, host, drain.of(host, r))
        case Closing{sock, +line}:
          drain.end(host, sock, line)

# a site that must answer 200: resolve, connect, handshake, ask, read, close
def gets.last(+host: String, r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (s, g) = r
  do IO<Unit>:
    IO.print(gets.said(host ++ " answers", g))
    drain(8n, host, Reading{s})

def gets.read(+host: String, s: Socket) -> IO(Unit):
  do IO<Unit>:
    r : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- Ossl.recv(s, 8192, 10000)
    gets.last(host, r)

def gets.sent(+host: String, w: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (s, r) = w
  do IO<Unit>:
    IO.print(said(host ++ " takes the request", r))
    gets.read(host, s)

def gets.write(+host: String, +request: String, s: Socket) -> IO(Unit):
  do IO<Unit>:
    w : Socket & Result<&1, &1, U32 & String, Unit> <- Ossl.send(s, Bytes.of_ascii(request))
    gets.sent(host, w)

def gets.hand(+host: String, +request: String, c: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (s, r) = c
  do IO<Unit>:
    IO.print(said(host ++ " handshakes", r))
    gets.write(host, request, s)

def gets.tls(+host: String, +request: String, s: Socket) -> IO(Unit):
  do IO<Unit>:
    c : Socket & Result<&1, &1, U32 & String, Unit> <- Ossl.connect(s, host, 10000)
    gets.hand(host, request, c)

def gets.dial(+host: String, +request: String, r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Done{s}:
      gets.tls(host, request, s)
    case Fail{(c, m)}:
      IO.print("FAIL " ++ host ++ " connects: " ++ U32.show(c) ++ " " ++ m)

def gets(+host: String, +request: String) -> IO(Unit):
  do IO<Unit>:
    ip : String <- ipv4(host)
    r : Result<&1, &1, U32 & String, Socket> <- TCP.connect(ip, 443)
    gets.dial(host, request, r)

# a site whose handshake must fail: resolve, connect, and expect a refusal
def refused.close(+host: String, s: Socket) -> IO(Unit):
  do IO<Unit>:
    u : Unit <- Ossl.close(s)
    IO.print("ok   " ++ host ++ " closed")

def refused.hand(+host: String, c: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (s, r) = c
  do IO<Unit>:
    IO.print(refused.said(host ++ " is refused", r))
    refused.close(host, s)

def refused.tls(+host: String, s: Socket) -> IO(Unit):
  do IO<Unit>:
    c : Socket & Result<&1, &1, U32 & String, Unit> <- Ossl.connect(s, host, 10000)
    refused.hand(host, c)

def refused.dial(+host: String, r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Done{s}:
      refused.tls(host, s)
    case Fail{(c, m)}:
      IO.print("FAIL " ++ host ++ " connects: " ++ U32.show(c) ++ " " ++ m)

def refused(+host: String, port: U32) -> IO(Unit):
  do IO<Unit>:
    ip : String <- ipv4(host)
    r : Result<&1, &1, U32 & String, Socket> <- TCP.connect(ip, port)
    refused.dial(host, r)

def main() -> IO(Unit):
  do IO<Unit>:
    up : Bool <- Ossl.available()
    IO.print(T.ok("libssl 3 loads", up))
    IO.print("-- example.com:443")
    gets("example.com", "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n")
    IO.print("-- api.github.com:443")
    gets("api.github.com", "GET /zen HTTP/1.1\r\nHost: api.github.com\r\nUser-Agent: chaki\r\nConnection: close\r\n\r\n")
    IO.print("-- badssl, each must fail")
    refused("expired.badssl.com", 443)
    refused("wrong.host.badssl.com", 443)
    refused("self-signed.badssl.com", 443)
    refused("untrusted-root.badssl.com", 443)
    refused("tls-v1-0.badssl.com", 1010)
