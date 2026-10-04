# live checks for lib/chaki/tlsio.bend, chaki's own TLS 1.3 client, run by hand:
#   rr bend test/chaki_tlsio_live.bend
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/sys.bend as Sys
import ../lib/chaki/x509v.bend as X509v
import ../lib/chaki/x509.bend as X509
import ../lib/chaki/tlsio.bend as Tlsio
import ../lib/chaki/check.bend as T

def first.line.go(xs: List<&2, U32>, acc: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      Bytes.to_ascii(Bytes.rev(acc))
    case Con{13, t}:
      Bytes.to_ascii(Bytes.rev(acc))
    case Con{h, t}:
      first.line.go(t, h <> acc)

def read.said(+host: String, g: Result<&1, &1, U32 & String, List<&2, U32>>) -> String:
  match g:
    case Done{bs}:
      "ok   " ++ host ++ " answers: " ++ first.line.go(bs, Nil{})
    case Fail{(c, m)}:
      "FAIL " ++ host ++ " read: " ++ m

def read.end(+host: String, r: Tlsio.Conn & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (c, g) = r
  do IO<Unit>:
    Tlsio.close(c)
    IO.print(read.said(host, g))

def sent(+host: String, r: Tlsio.Conn & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (c, g) = r
  do IO<Unit>:
    got : Tlsio.Conn & Result<&1, &1, U32 & String, List<&2, U32>> <- Tlsio.recv(c, 65536, 15000)
    read.end(host, got)

def shook(+host: String, +path: String, r: Result<&1, &1, U32 & String, Tlsio.Conn>) -> IO(Unit):
  match r:
    case Fail{(c, m)}:
      IO.print("FAIL " ++ host ++ " handshake: " ++ m)
    case Done{conn}:
      do IO<Unit>:
        IO.print("ok   " ++ host ++ " handshake")
        w : Tlsio.Conn & Result<&1, &1, U32 & String, Unit> <- Tlsio.send(conn, Bytes.of_ascii("GET " ++ path ++ " HTTP/1.1\r\nhost: " ++ host ++ "\r\nuser-agent: chaki\r\nconnection: close\r\n\r\n"))
        sent(host, w)

def dialed(+host: String, +path: String, +anchors: List<&2, X509.Cert>, r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Fail{(c, m)}:
      IO.print("FAIL " ++ host ++ " dial: " ++ m)
    case Done{s}:
      do IO<Unit>:
        h : Result<&1, &1, U32 & String, Tlsio.Conn> <- Tlsio.connect(s, host, anchors, 15000)
        shook(host, path, h)

def visit(+host: String, +path: String, +anchors: List<&2, X509.Cert>) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, Socket> <- Sys.dial(host, 443, 10000)
    dialed(host, path, anchors, r)

# a handshake that must be refused, with the reason it must give
def refused.of(+name: String, +want: String, r: Result<&1, &1, U32 & String, Tlsio.Conn>) -> IO(Unit):
  match r:
    case Done{c}:
      do IO<Unit>:
        Tlsio.close(c)
        IO.print("FAIL " ++ name ++ ": the handshake went through")
    case Fail{(c, +m)}:
      IO.print(T.ok(name ++ " is refused (" ++ m ++ ")", String.contains(m, want)))

def refused.dialed(+name: String, +as: String, +want: String, +anchors: List<&2, X509.Cert>, r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Fail{(c, m)}:
      IO.print("FAIL " ++ name ++ " dial: " ++ m)
    case Done{s}:
      do IO<Unit>:
        h : Result<&1, &1, U32 & String, Tlsio.Conn> <- Tlsio.connect(s, as, anchors, 15000)
        refused.of(name, want, h)

# dial host, but handshake as if it were as
def refused(+name: String, +host: String, +as: String, +want: String, +anchors: List<&2, X509.Cert>) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, Socket> <- Sys.dial(host, 443, 10000)
    refused.dialed(name, as, want, anchors, r)

def all(+anchors: List<&2, X509.Cert>) -> IO(Unit):
  do IO<Unit>:
    visit("example.com", "/", anchors)
    visit("api.github.com", "/zen", anchors)
    visit("codeberg.org", "/api/v1/version", anchors)
    visit("tea.muu.space", "/api/v1/version", anchors)
    refused("api.github.com under another name", "api.github.com", "not-github.example", "isn't for not-github.example", anchors)
    refused("api.github.com with no trust anchors", "api.github.com", "api.github.com", "doesn't lead to a trusted root", Nil{})

def loaded(r: Result<&1, &1, U32 & String, List<&2, X509.Cert>>) -> IO(Unit):
  match r:
    case Done{xs}:
      all(xs)
    case Fail{(c, w)}:
      IO.print("FAIL the trust store: " ++ w)

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, List<&2, X509.Cert>> <- X509v.load()
    loaded(r)
