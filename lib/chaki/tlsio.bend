# tlsio: chaki's TLS 1.3 client on a socket. tls.bend is the protocol with no IO; this file
# adds the socket, the randomness and the clock, and makes the trust decision the core
# leaves out: x509v for the chain, then ecdsa or rsa for the server's CertificateVerify
# signature over the handshake. Nothing flows before both hold.
import Base
import ./bytes.bend as Bytes
import ./sha2.bend as Sha2
import ./sys.bend as Sys
import ./tls.bend as Core
import ./x509.bend as X509
import ./x509v.bend as X509v
import ./rsa.bend as Rsa
import ./ecdsa.bend as Ecdsa

# Trust
# -----

def EC() -> String:
  "1.2.840.10045.2.1"

def RSA() -> String:
  "1.2.840.113549.1.1.1"

def P256() -> String:
  "1.2.840.10045.3.1.7"

def P384() -> String:
  "1.3.132.0.34"

# the CertificateVerify schemes the core lets through (RFC 8446 4.4.3)
type Scheme is Data:
  EcP256{}
  EcP384{}
  Pss256{}
  Pss384{}
  Other{}

def scheme.of(+s: U32) -> Scheme:
  Bool.pick(Scheme, U32.is_eq(s, 1027), EcP256{}, Bool.pick(Scheme, U32.is_eq(s, 1283), EcP384{},
    Bool.pick(Scheme, U32.is_eq(s, 2052), Pss256{}, Bool.pick(Scheme, U32.is_eq(s, 2053), Pss384{}, Other{}))))

def ec.if(c: Ecdsa.Curve, a: Sha2.Alg, key: List<&2, U32>, signed: List<&2, U32>, sig: List<&2, U32>, ok: Bool) -> Bool:
  match ok:
    case True{}:
      Ecdsa.verify.der(c, a, key, signed, sig)
    case False{}:
      False{}

def rsa.of(a: Sha2.Alg, m: Maybe<&2, X509.Two()>, signed: List<&2, U32>, sig: List<&2, U32>) -> Bool:
  match m:
    case Some{(n, e)}:
      Rsa.pss(a, n, e, signed, sig)
    case None{}:
      False{}

def rsa.if(a: Sha2.Alg, key: List<&2, U32>, signed: List<&2, U32>, sig: List<&2, U32>, ok: Bool) -> Bool:
  match ok:
    case True{}:
      rsa.of(a, X509.rsa_key(key), signed, sig)
    case False{}:
      False{}

# the scheme must match the leaf's key: an ecdsa scheme an EC key on its curve, rsa_pss an
# RSA key
def leaf.check(sc: Scheme, +alg: String, +curve: String, key: List<&2, U32>, signed: List<&2, U32>, sig: List<&2, U32>) -> Bool:
  match sc:
    case EcP256{}:
      ec.if(Ecdsa.P256{}, Sha2.S256{}, key, signed, sig, Bool.and(String.eq(alg, EC()), String.eq(curve, P256())))
    case EcP384{}:
      ec.if(Ecdsa.P384{}, Sha2.S384{}, key, signed, sig, Bool.and(String.eq(alg, EC()), String.eq(curve, P384())))
    case Pss256{}:
      rsa.if(Sha2.S256{}, key, signed, sig, String.eq(alg, RSA()))
    case Pss384{}:
      rsa.if(Sha2.S384{}, key, signed, sig, String.eq(alg, RSA()))
    case Other{}:
      False{}

def leaf.signed(+scheme: U32, c: X509.Cert, signed: List<&2, U32>, sig: List<&2, U32>) -> Bool:
  match c:
    case X509.Cert{d, t, sa, s, i, su, nb, na, +alg, +curve, key, dns, ca, pl, ku, uc, st}:
      leaf.check(scheme.of(scheme), alg, curve, key, signed, sig)

def trust.sig(ok: Bool) -> Result<&1, &1, String, Unit>:
  match ok:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{"the server's CertificateVerify signature doesn't verify"}

def trust.leaf(+scheme: U32, m: Maybe<&2, X509.Cert>, signed: List<&2, U32>, sig: List<&2, U32>) -> Result<&1, &1, String, Unit>:
  match m:
    case None{}:
      Fail{"the server's certificate doesn't parse"}
    case Some{c}:
      trust.sig(leaf.signed(scheme, c, signed, sig))

def trust.chain(r: Result<&1, &1, String, Unit>, +scheme: U32, +leaf: List<&2, U32>, signed: List<&2, U32>, sig: List<&2, U32>) -> Result<&1, &1, String, Unit>:
  match r:
    case Fail{w}:
      Fail{w}
    case Done{u}:
      trust.leaf(scheme, X509.parse(leaf), signed, sig)

def first(xs: List<&2, List<&2, U32>>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      h

# the chain is trusted for host now, and the server holds the leaf's key
def trust(+certs: List<&2, List<&2, U32>>, +scheme: U32, signed: List<&2, U32>, sig: List<&2, U32>, anchors: List<&2, X509.Cert>, +host: String, +now: U32) -> Result<&1, &1, String, Unit>:
  trust.chain(X509v.verify(certs, anchors, host, now), scheme, first(certs), signed, sig)

def trusted(r: Result<&1, &1, String, Unit>) -> Bool:
  match r:
    case Done{u}:
      True{}
    case Fail{w}:
      False{}

def why.of(r: Result<&1, &1, String, Unit>) -> String:
  match r:
    case Done{u}:
      ""
    case Fail{w}:
      w

# Time and randomness
# -------------------

def deadline(+now: U32, +ms: U32) -> U32:
  (now + ((ms + 999 : U32) / 1000 : U32) : U32)

def left.ms(+deadline: U32, +now: U32) -> U32:
  Bool.pick(U32, U32.is_lt(now, deadline), ((deadline - now : U32) * 1000 : U32), 1)

def rand.push(r: Result<&1, &1, U32 & String, U32>, acc: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match r acc:
    case Done{+w} Some{xs}:
      Some{Bytes.cat(Bytes.be32(w), xs)}
    case _ _:
      None{}

# 4n bytes from getrandom, or None if any read failed: a handshake never runs on less
def rand.go(n: Nat, acc: Maybe<&2, List<&2, U32>>) -> IO(Maybe<&2, List<&2, U32>>):
  match n:
    case 0n:
      IO.pure(Maybe<&2, List<&2, U32>>, acc)
    case 1n+k:
      IO.bind(Result<&1, &1, U32 & String, U32>, Maybe<&2, List<&2, U32>>, IO.random_u32(), r => rand.go(k, rand.push(r, acc)))

# The wire
# --------
# One machine runs both the handshake and the reads after it. It ends in Ready (the
# handshake is done, or data came in: buf), Eof (close_notify, with any data that came
# before it), or Bad.

type Sh is Type:
  Wait{sock: Socket, st: Core.Hs}
  Send{sock: Socket, st: Core.Hs, out: List<&2, U32>, evs: List<&2, Core.Reply>, buf: List<&2, U32>}
  Events{sock: Socket, st: Core.Hs, evs: List<&2, Core.Reply>, buf: List<&2, U32>}
  Ready{sock: Socket, st: Core.Hs, buf: List<&2, U32>}
  Eof{sock: Socket, st: Core.Hs, buf: List<&2, U32>}
  Bad{sock: Socket, st: Core.Hs, code: U32, why: String}

# records to write first, unless there are none
def sh.out.if(sock: Socket, st: Core.Hs, out: List<&2, U32>, evs: List<&2, Core.Reply>, buf: List<&2, U32>, none: Bool) -> Sh:
  match none:
    case True{}:
      Events{sock, st, evs, buf}
    case False{}:
      Send{sock, st, out, evs, buf}

def sh.out(sock: Socket, st: Core.Hs, +out: List<&2, U32>, evs: List<&2, Core.Reply>, buf: List<&2, U32>) -> Sh:
  sh.out.if(sock, st, out, evs, buf, List.is_empty(&2, U32, out))

# the core's answer to some bytes: its new state, records to write, and events
def sh.after(sock: Socket, r: Core.Hs & List<&2, U32> & List<&2, Core.Reply>, rest: List<&2, Core.Reply>, buf: List<&2, U32>) -> Sh:
  (st, more) = r
  (out, evs) = more
  sh.out(sock, st, out, List.append(&2, Core.Reply, evs, rest), buf)

def sh.feed(sock: Socket, st: Core.Hs, bs: List<&2, U32>) -> Sh:
  sh.after(sock, Core.hs.input(st, bs), Nil{}, Nil{})

def sh.fed.if(sock: Socket, st: Core.Hs, bs: List<&2, U32>, empty: Bool) -> Sh:
  match empty:
    case True{}:
      Bad{sock, st, 104, "the server closed the connection"}
    case False{}:
      sh.feed(sock, st, bs)

def sh.fed(sock: Socket, st: Core.Hs, g: Result<&1, &1, U32 & String, List<&2, U32>>) -> Sh:
  match g:
    case Done{+bs}:
      sh.fed.if(sock, st, bs, List.is_empty(&2, U32, bs))
    case Fail{(+c, m)}:
      Bad{sock, st, c, Bool.pick(String, U32.is_eq(c, 110), "timed out", "read failed: " ++ m)}

def sh.input(st: Core.Hs, r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> Sh:
  (sock, g) = r
  sh.fed(sock, st, g)

def sh.sent.of(sock: Socket, st: Core.Hs, evs: List<&2, Core.Reply>, buf: List<&2, U32>, g: Result<&1, &1, U32 & String, Unit>) -> Sh:
  match g:
    case Done{u}:
      Events{sock, st, evs, buf}
    case Fail{(c, m)}:
      Bad{sock, st, c, "write failed: " ++ m}

def sh.sent(st: Core.Hs, evs: List<&2, Core.Reply>, buf: List<&2, U32>, w: Socket & Result<&1, &1, U32 & String, Unit>) -> Sh:
  (sock, g) = w
  sh.sent.of(sock, st, evs, buf, g)

# the bytes of every data event in evs
def data.of(evs: List<&2, Core.Reply>, acc: List<&2, U32>) -> List<&2, U32>:
  match evs:
    case Nil{}:
      acc
    case Con{Core.Reply.data{bs}, t}:
      data.of(t, Bytes.cat(acc, bs))
    case Con{e, t}:
      data.of(t, acc)

# the shell's verdict on the Check: the core's next records, or Bad with the reason
def sh.verdict(sock: Socket, st: Core.Hs, r: Result<&1, &1, String, Unit>, rest: List<&2, Core.Reply>, buf: List<&2, U32>) -> Sh:
  match r:
    case Fail{w}:
      Bad{sock, st, 71, w}
    case Done{u}:
      sh.after(sock, Core.hs.trusted(st, True{}), rest, buf)

def sh.one(sock: Socket, st: Core.Hs, e: Core.Reply, rest: List<&2, Core.Reply>, buf: List<&2, U32>, +anchors: List<&2, X509.Cert>, +host: String, +now: U32) -> Sh:
  match e:
    case Core.Reply.need{}:
      Events{sock, st, rest, buf}
    case Core.Reply.check{certs, scheme, signed, sig}:
      sh.verdict(sock, st, trust(certs, scheme, signed, sig, anchors, host, now), rest, buf)
    case Core.Reply.ready{}:
      Ready{sock, st, data.of(rest, buf)}
    case Core.Reply.data{bs}:
      Events{sock, st, rest, Bytes.cat(buf, bs)}
    case Core.Reply.closed{}:
      Eof{sock, st, buf}
    case Core.Reply.failed{w}:
      Bad{sock, st, 71, w}

def sh.events.end(sock: Socket, st: Core.Hs, +buf: List<&2, U32>, empty: Bool) -> Sh:
  match empty:
    case True{}:
      Wait{sock, st}
    case False{}:
      Ready{sock, st, buf}

def sh.events(sock: Socket, st: Core.Hs, evs: List<&2, Core.Reply>, +buf: List<&2, U32>, +anchors: List<&2, X509.Cert>, +host: String, +now: U32) -> Sh:
  match evs:
    case Nil{}:
      sh.events.end(sock, st, buf, List.is_empty(&2, U32, buf))
    case Con{e, rest}:
      sh.one(sock, st, e, rest, buf, anchors, host, now)

def sh.go(fuel: Nat, +deadline: U32, +anchors: List<&2, X509.Cert>, +host: String, +now: U32, s: Sh) -> IO(Sh):
  match fuel s:
    case 0n x:
      IO.pure(Sh, x)
    case 1n+k Wait{sock, st}:
      do IO<Sh>:
        t : U32 <- Sys.now()
        r : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- Sys.recv(sock, 65536, left.ms(deadline, t))
        sh.go(k, deadline, anchors, host, now, sh.input(st, r))
    case 1n+k Send{sock, st, out, evs, buf}:
      IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Sh, Sys.send(sock, out), w => sh.go(k, deadline, anchors, host, now, sh.sent(st, evs, buf, w)))
    case 1n+k Events{sock, st, evs, buf}:
      sh.go(k, deadline, anchors, host, now, sh.events(sock, st, evs, buf, anchors, host, now))
    case 1n+k Ready{sock, st, buf}:
      IO.pure(Sh, Ready{sock, st, buf})
    case 1n+k Eof{sock, st, buf}:
      IO.pure(Sh, Eof{sock, st, buf})
    case 1n+k Bad{sock, st, c, w}:
      IO.pure(Sh, Bad{sock, st, c, w})

# The connection
# --------------

# buf: plaintext not handed out yet; eof: the server's close_notify has come
type Conn is Type:
  Conn{sock: Socket, st: Core.Hs, buf: List<&2, U32>, eof: Bool}

def connect.end(s: Sh) -> IO(Result<&1, &1, U32 & String, Conn>):
  match s:
    case Ready{sock, st, buf}:
      IO.pure(Result<&1, &1, U32 & String, Conn>, Done{Conn{sock, st, buf, False{}}})
    case Eof{sock, st, buf}:
      do IO<Result<&1, &1, U32 & String, Conn>>:
        Socket.close(sock)
        return Fail{(104, "the server closed the connection during the handshake")}
    case Bad{sock, st, c, w}:
      do IO<Result<&1, &1, U32 & String, Conn>>:
        Socket.close(sock)
        return Fail{(c, w)}
    case Wait{sock, st}:
      do IO<Result<&1, &1, U32 & String, Conn>>:
        Socket.close(sock)
        return Fail{(110, "the handshake took too long")}
    case Send{sock, st, out, evs, buf}:
      do IO<Result<&1, &1, U32 & String, Conn>>:
        Socket.close(sock)
        return Fail{(110, "the handshake took too long")}
    case Events{sock, st, evs, buf}:
      do IO<Result<&1, &1, U32 & String, Conn>>:
        Socket.close(sock)
        return Fail{(110, "the handshake took too long")}

def connect.go(sock: Socket, +host: String, +anchors: List<&2, X509.Cert>, +now: U32, +deadline: U32, r: Core.Hs & List<&2, U32>) -> IO(Result<&1, &1, U32 & String, Conn>):
  (st, out) = r
  do IO<Result<&1, &1, U32 & String, Conn>>:
    s : Sh <- sh.go(200n, deadline, anchors, host, now, Send{sock, st, out, Nil{}, Nil{}})
    connect.end(s)

def connect.with(sock: Socket, +host: String, +anchors: List<&2, X509.Cert>, +now: U32, +deadline: U32, rnd: Maybe<&2, List<&2, U32>>) -> IO(Result<&1, &1, U32 & String, Conn>):
  match rnd:
    case None{}:
      do IO<Result<&1, &1, U32 & String, Conn>>:
        Socket.close(sock)
        return Fail{(5, "no randomness for the handshake")}
    case Some{+bs}:
      connect.go(sock, host, anchors, now, deadline, Core.hs.start(Bytes.take(bs, 32n), Bytes.take(Bytes.drop(bs, 32n), 32n), Bytes.drop(bs, 64n), host))

# a TLS 1.3 handshake on a connected socket: the chain must verify for host against anchors
# at Sys.now(), and the server must prove it holds the leaf's key. On failure the socket is
# closed. ms bounds the handshake.
def connect(sock: Socket, host: String, anchors: List<&2, X509.Cert>, ms: U32) -> IO(Result<&1, &1, U32 & String, Conn>):
  do IO<Result<&1, &1, U32 & String, Conn>>:
    +now : U32 <- Sys.now()
    rnd : Maybe<&2, List<&2, U32>> <- rand.go(24n, Some{Nil{}})
    connect.with(sock, host, anchors, now, deadline(now, ms), rnd)

def send.back(st: Core.Hs, buf: List<&2, U32>, eof: Bool, w: Socket & Result<&1, &1, U32 & String, Unit>) -> Conn & Result<&1, &1, U32 & String, Unit>:
  (sock, r) = w
  (Conn{sock, st, buf, eof}, r)

def send.go(sock: Socket, buf: List<&2, U32>, eof: Bool, r: Core.Hs & List<&2, U32>) -> IO(Conn & Result<&1, &1, U32 & String, Unit>):
  (st, out) = r
  do IO<Conn & Result<&1, &1, U32 & String, Unit>>:
    w : Socket & Result<&1, &1, U32 & String, Unit> <- Sys.send(sock, out)
    return send.back(st, buf, eof, w)

def send(c: Conn, data: List<&2, U32>) -> IO(Conn & Result<&1, &1, U32 & String, Unit>):
  match c:
    case Conn{sock, +st, buf, eof}:
      send.go(sock, buf, eof, Core.hs.send(st, data))

def give(sock: Socket, st: Core.Hs, +buf: List<&2, U32>, eof: Bool, +max: U32) -> Conn & Result<&1, &1, U32 & String, List<&2, U32>>:
  (Conn{sock, st, Bytes.drop(buf, U32.to_nat(max)), eof}, Done{Bytes.take(buf, U32.to_nat(max))})

def recv.end(+max: U32, s: Sh) -> IO(Conn & Result<&1, &1, U32 & String, List<&2, U32>>):
  match s:
    case Ready{sock, st, buf}:
      IO.pure(Conn & Result<&1, &1, U32 & String, List<&2, U32>>, give(sock, st, buf, False{}, max))
    case Eof{sock, st, buf}:
      IO.pure(Conn & Result<&1, &1, U32 & String, List<&2, U32>>, give(sock, st, buf, True{}, max))
    case Bad{sock, st, c, w}:
      IO.pure(Conn & Result<&1, &1, U32 & String, List<&2, U32>>, (Conn{sock, st, Nil{}, False{}}, Fail{(c, w)}))
    case Wait{sock, st}:
      IO.pure(Conn & Result<&1, &1, U32 & String, List<&2, U32>>, (Conn{sock, st, Nil{}, False{}}, Fail{(110, "timed out")}))
    case Send{sock, st, out, evs, buf}:
      IO.pure(Conn & Result<&1, &1, U32 & String, List<&2, U32>>, (Conn{sock, st, Nil{}, False{}}, Fail{(110, "timed out")}))
    case Events{sock, st, evs, buf}:
      IO.pure(Conn & Result<&1, &1, U32 & String, List<&2, U32>>, (Conn{sock, st, Nil{}, False{}}, Fail{(110, "timed out")}))

# after close_notify there's nothing more to wait for
def recv.read(sock: Socket, st: Core.Hs, +max: U32, +ms: U32, eof: Bool) -> IO(Conn & Result<&1, &1, U32 & String, List<&2, U32>>):
  match eof:
    case True{}:
      IO.pure(Conn & Result<&1, &1, U32 & String, List<&2, U32>>, (Conn{sock, st, Nil{}, True{}}, Done{Nil{}}))
    case False{}:
      do IO<Conn & Result<&1, &1, U32 & String, List<&2, U32>>>:
        +now : U32 <- Sys.now()
        s : Sh <- sh.go(200n, deadline(now, ms), Nil{}, "", now, Wait{sock, st})
        recv.end(max, s)

def recv.at(sock: Socket, st: Core.Hs, +buf: List<&2, U32>, eof: Bool, +max: U32, +ms: U32, empty: Bool) -> IO(Conn & Result<&1, &1, U32 & String, List<&2, U32>>):
  match empty:
    case False{}:
      IO.pure(Conn & Result<&1, &1, U32 & String, List<&2, U32>>, give(sock, st, buf, eof, max))
    case True{}:
      recv.read(sock, st, max, ms, eof)

# up to max plaintext bytes, waiting at most ms; Done{[]} after the server's close_notify
def recv(c: Conn, +max: U32, +ms: U32) -> IO(Conn & Result<&1, &1, U32 & String, List<&2, U32>>):
  match c:
    case Conn{sock, st, +buf, eof}:
      recv.at(sock, st, buf, eof, max, ms, List.is_empty(&2, U32, buf))

def close.end(w: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (sock, r) = w
  Socket.close(sock)

# close_notify, then the socket
def close(c: Conn) -> IO(Unit):
  match c:
    case Conn{sock, st, buf, eof}:
      do IO<Unit>:
        w : Socket & Result<&1, &1, U32 & String, Unit> <- Sys.send(sock, Core.hs.close(st))
        close.end(w)
