# tls: the TLS 1.3 client core of RFC 8446, with no IO. One key exchange (x25519) and two
# suites, TLS_CHACHA20_POLY1305_SHA256 and TLS_AES_128_GCM_SHA256: no PSK, no 0-RTT, no
# client certificates, no TLS 1.2. The handshake and the record layer are one pure state
# machine over bytes, so RFC 8448's recorded trace drives it offline. The shell owns the
# socket, the randomness and the clock; the chain and the CertificateVerify's signature
# never reach this file, they leave through one Check event for x509v and the signature
# modules to settle. (tls.md calls that event type Event, and Base already declares one, so
# it is Reply here, with the same six cases.)
import Base
import ./bytes.bend as Bytes
import ./tlsmsg.bend as Tls
import ./sha2.bend as Sha2
import ./chacha.bend as Chacha
import ./aes.bend as Aes
import ./x25519.bend as X

# Numbers and strings
# -------------------

# both suites hash with SHA-256 (RFC 8446 4.1.2)
def alg() -> Sha2.Alg:
  Sha2.S256{}

# 2^14: the most plaintext one record carries (RFC 8446 5.2)
def send.max() -> U32:
  16384

# the four signature schemes a CertificateVerify may use (RFC 8446 4.4.3): ecdsa over
# P-256 or P-384, and rsa_pss. The pkcs1 schemes are refused.
def scheme.ok(+s: U32) -> Bool:
  U32.is_eq(s, 1027) || U32.is_eq(s, 1283) || U32.is_eq(s, 2052) || U32.is_eq(s, 2053)

# the 64 spaces and the context string that open a CertificateVerify's signed content
def verify.spaces() -> List<&2, U32>:
  Sha2.fill(32, 64n)

def verify.context() -> List<&2, U32>:
  Bytes.of_ascii("TLS 1.3, server CertificateVerify")

# the ClientHello offers only http/1.1, and a server may send no ALPN extension at all
def alpn.ok(+p: String) -> Bool:
  String.is_empty(p) || String.eq(p, "http/1.1")

# The AEAD
# --------

# the two suites' AEADs
type Aead is Data:
  Aead.chacha{}
  Aead.aes128{}

# the AEAD of a suite. tlsmsg.suite.ok only lets the two through, so anything else here is
# the AES one.
def aead.of(+suite: U32) -> Aead:
  match suite:
    case 4867:
      Aead.chacha{}
    case _:
      Aead.aes128{}

# 32 bytes for ChaCha20-Poly1305, 16 for AES-128-GCM (RFC 8446 5.1)
def aead.key.len(+a: Aead) -> U32:
  match a:
    case Aead.chacha{}:
      32
    case Aead.aes128{}:
      16

# Traffic keys
# ------------

# one traffic key: the secret it came from (a KeyUpdate and the client's Finished both need
# it again), the key, the IV, and the record sequence number it is due
type Traffic is Data:
  Traffic{secret: List<&2, U32>, k: List<&2, U32>, iv: List<&2, U32>, n: U32}

def traffic.none() -> Traffic:
  Traffic{Nil{}, Nil{}, Nil{}, 0}

# the key and IV of one traffic secret, at sequence number 0 (RFC 8446 7.3)
def traffic.of(+secret: List<&2, U32>, +a: Aead) -> Traffic:
  Traffic{secret, Sha2.expand_label(alg(), secret, "key", Nil{}, aead.key.len(a)), Sha2.expand_label(alg(), secret, "iv", Nil{}, 12), 0}

# the same key at its next sequence number
def traffic.next(t: Traffic) -> Traffic:
  Traffic{secret, k, iv, n} = t
  Traffic{secret, k, iv, (n + 1 : U32)}

# the next traffic secret of a KeyUpdate (RFC 8446 7.2)
def traffic.up(t: Traffic, a: Aead) -> Traffic:
  Traffic{secret, k, iv, n} = t
  traffic.of(Sha2.expand_label(alg(), secret, "traffic upd", Nil{}, 32), a)

# what a connection holds: the suite's AEAD, the master secret (the application keys come
# from it once the server's Finished fixes the transcript), and the four traffic keys
type Keys is Data:
  Keys{aead: Aead, master: List<&2, U32>, rd: Traffic, wr: Traffic, ard: Traffic, awr: Traffic}

def keys.none() -> Keys:
  Keys{Aead.aes128{}, Nil{}, traffic.none(), traffic.none(), traffic.none(), traffic.none()}

# Phases, proof and events
# ------------------------

# how far the handshake is: each name is the message that is due, asked means the shell's
# verdict is due, and dead means it is over
type Phase is Data:
  Phase.hello{}
  Phase.ee{}
  Phase.cert{}
  Phase.verify{}
  Phase.fin{}
  Phase.asked{}
  Phase.ready{}
  Phase.closed{}
  Phase.dead{why: String}

# what the shell has to check: the chain leaf first, the scheme, the signed content (the 64
# spaces, the context string, a 0 byte and the transcript hash) and the signature
type Proof is Data:
  Proof{certs: List<&2, List<&2, U32>>, scheme: U32, signed: List<&2, U32>, sig: List<&2, U32>}

def proof.none() -> Proof:
  Proof{Nil{}, 0, Nil{}, Nil{}}

# what the core answers with, and the shell acts on: feed more bytes, check this, the
# handshake is done, here is application data, the peer is done, or the connection failed
type Reply is Data:
  Reply.need{}
  Reply.check{certs: List<&2, List<&2, U32>>, scheme: U32, signed: List<&2, U32>, sig: List<&2, U32>}
  Reply.ready{}
  Reply.data{bytes: List<&2, U32>}
  Reply.closed{}
  Reply.failed{why: String}

# The state
# ---------

# the whole core: the phase, the transcript (the raw handshake messages, RFC 8446 4.4.1),
# the keys, the client's private key, the proof the shell checks, the wire bytes that
# aren't a whole record yet, the decrypted bytes that aren't a whole message yet, the
# records still to go out, and the events so far
type Hs is Data:
  Hs{
    phase: Phase,
    tx: List<&2, U32>,
    keys: Keys,
    priv: List<&2, U32>,
    proof: Proof,
    buf: List<&2, U32>,
    msgs: List<&2, U32>,
    out: List<&2, U32>,
    evs: List<&2, Reply>,
  }

# Reading bytes
# -------------

# the content types of RFC 8446 5, and everything else, which is a bad header
type Ctype is Data:
  Ctype.ccs{}
  Ctype.alert{}
  Ctype.handshake{}
  Ctype.app{}
  Ctype.other{}

def ctype.of(+t: U32) -> Ctype:
  match t:
    case 20:
      Ctype.ccs{}
    case 21:
      Ctype.alert{}
    case 22:
      Ctype.handshake{}
    case 23:
      Ctype.app{}
    case _:
      Ctype.other{}

# the handshake messages this client acts on (RFC 8446 4), and the rest
type Note is Data:
  Note.hello{}
  Note.ee{}
  Note.cert{}
  Note.verify{}
  Note.fin{}
  Note.ticket{}
  Note.update{}
  Note.other{}

def note.of(+t: U32) -> Note:
  match t:
    case 2:
      Note.hello{}
    case 4:
      Note.ticket{}
    case 8:
      Note.ee{}
    case 11:
      Note.cert{}
    case 15:
      Note.verify{}
    case 20:
      Note.fin{}
    case 24:
      Note.update{}
    case _:
      Note.other{}

def rec.ctype(r: Tls.Rec) -> U32:
  match r:
    case Tls.Rec{ctype, body}:
      ctype

def rec.body(r: Tls.Rec) -> List<&2, U32>:
  match r:
    case Tls.Rec{ctype, body}:
      body

def msg.kind(m: Tls.Msg) -> U32:
  match m:
    case Tls.Msg{htype, body, raw}:
      htype

def msg.body(m: Tls.Msg) -> List<&2, U32>:
  match m:
    case Tls.Msg{htype, body, raw}:
      body

def msg.raw(m: Tls.Msg) -> List<&2, U32>:
  match m:
    case Tls.Msg{htype, body, raw}:
      raw

def msg.note(m: Tls.Msg) -> Note:
  note.of(msg.kind(m))

# whether a list of bytes is empty
def empty.of(+xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case _:
      False{}

# what a record wants: the plaintext ServerHello, an encrypted record, or nothing (the
# flight is complete, or the connection is over)
type Want is Data:
  Want.plain{}
  Want.enc{}
  Want.refuse{}

def want.of(p: Phase) -> Want:
  match p:
    case Phase.hello{}:
      Want.plain{}
    case Phase.asked{}:
      Want.refuse{}
    case Phase.closed{}:
      Want.refuse{}
    case Phase.dead{why}:
      Want.refuse{}
    case _:
      Want.enc{}

# The record layer
# ----------------

# the record nonce: the static IV with the 64-bit sequence number big-endian in its low
# half (RFC 8446 5.3)
def nonce(+iv: List<&2, U32>, n: U32) -> List<&2, U32>:
  Bytes.cat(Bytes.take(iv, 4n), Bytes.xor(Bytes.drop(iv, 4n), Bytes.cat(Bytes.be32(0), Bytes.be32(n))))

# the ciphertext length of one record: the plaintext, the inner content type and the tag
def sealed.len(+plain: List<&2, U32>) -> U32:
  (Bytes.len(plain) + 17 : U32)

def sealed(+a: Aead, +k: List<&2, U32>, +n: List<&2, U32>, +aad: List<&2, U32>, +plain: List<&2, U32>) -> List<&2, U32>:
  match a:
    case Aead.chacha{}:
      Chacha.seal(k, n, aad, plain)
    case Aead.aes128{}:
      Aes.seal(k, n, aad, plain)

def opened(+a: Aead, +k: List<&2, U32>, +n: List<&2, U32>, +aad: List<&2, U32>, +c: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match a:
    case Aead.chacha{}:
      Chacha.open(k, n, aad, c)
    case Aead.aes128{}:
      Aes.open(k, n, aad, c)

# one record of plaintext: content type 23 outside, the real one appended inside the
# plaintext, and the five header bytes as the AAD (RFC 8446 5.2)
def seal.rec(t: Traffic, a: Aead, ctype: U32, +plain: List<&2, U32>) -> List<&2, U32>:
  Traffic{secret, k, iv, n} = t
  Tls.record(23, sealed(a, k, nonce(iv, n), Tls.record.head(23, sealed.len(plain)), Bytes.cat(plain, [ctype])))

# the plaintext of one encrypted record, and nothing when its tag doesn't check. The AAD is
# the header as it came in.
def open.rec(a: Aead, t: Traffic, +r: Tls.Rec) -> Maybe<&2, List<&2, U32>>:
  Traffic{secret, k, iv, n} = t
  opened(a, k, nonce(iv, n), Tls.record.head(rec.ctype(r), Bytes.len(rec.body(r))), rec.body(r))

# The walk's steps
# ----------------

# the record at the front of a buffer: nothing whole yet, a header we can't use, or one
# record with its own bytes and what follows them
type Head is Data:
  Head.short{}
  Head.bad{}
  Head.one{rec: Tls.Rec, raw: List<&2, U32>, rest: List<&2, U32>}

def head.at(f: Tls.First, +buf: List<&2, U32>) -> Head:
  match f:
    case Tls.First.short{}:
      Head.short{}
    case Tls.First.bad{}:
      Head.bad{}
    case Tls.First.rec{rec, +after, have}:
      Head.one{rec, Bytes.take(buf, Nat.sub(U32.to_nat(Bytes.len(buf)), U32.to_nat(Bytes.len(after)))), after}

def head.of(+buf: List<&2, U32>) -> Head:
  head.at(Tls.first.of(buf, U32.to_nat(Bytes.len(buf))), buf)

# the handshake message at the front of a buffer: nothing whole yet, or one message
type Mhead is Data:
  Mhead.short{}
  Mhead.one{msg: Tls.Msg, rest: List<&2, U32>}

def mhead.at(e: Tls.Each) -> Mhead:
  match e:
    case Tls.Each.short{}:
      Mhead.short{}
    case Tls.Each.msg{msg, after, have}:
      Mhead.one{msg, after}

def mhead.of(+buf: List<&2, U32>) -> Mhead:
  mhead.at(Tls.each.of(buf, U32.to_nat(Bytes.len(buf))))

# State updates and flags
# -----------------------

# close_notify is the alert level warning and description 0 (RFC 8446 6)
def close.of(+body: List<&2, U32>) -> Bool:
  Bytes.eq(body, [1, 0])

# a legacy ChangeCipherSpec is ignored only while the handshake runs (RFC 8446 D.4)
def ccs.open(p: Phase) -> Bool:
  match p:
    case Phase.ready{}:
      False{}
    case Phase.closed{}:
      False{}
    case Phase.dead{why}:
      False{}
    case _:
      True{}

def phase.of(st: Hs) -> Phase:
  match st:
    case Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      phase

def keys.of(st: Hs) -> Keys:
  match st:
    case Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      keys

def asked.of(p: Phase) -> Bool:
  match p:
    case Phase.asked{}:
      True{}
    case _:
      False{}

def ready.of(p: Phase) -> Bool:
  match p:
    case Phase.ready{}:
      True{}
    case _:
      False{}

# one byte, 0 (update_not_requested) or 1 (update_requested) (RFC 8446 4.6.3)
def update.ok(+body: List<&2, U32>) -> Bool:
  Bytes.eq(body, [0]) || Bytes.eq(body, [1])

# the connection is over: the reason is for the shell, and holds no key and no plaintext
def hs.die(st: Hs, +why: String) -> Hs:
  Hs{phase, tx, keys, priv, proof, buf, msgs, out, +evs} = st
  Hs{Phase.dead{why}, tx, keys, priv, proof, buf, msgs, out, List.append(&2, Reply, evs, [Reply.failed{why}])}

# a state with the phase moved on and one more message in the transcript
def hs.next(st: Hs, m: Tls.Msg, p: Phase) -> Hs:
  Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
  Hs{p, Bytes.cat(tx, msg.raw(m)), keys, priv, proof, buf, msgs, out, evs}

# a state with these records queued after what was queued before
def hs.out(st: Hs, b: List<&2, U32>) -> Hs:
  Hs{phase, tx, keys, priv, proof, buf, msgs, +out, evs} = st
  Hs{phase, tx, keys, priv, proof, buf, msgs, Bytes.cat(out, b), evs}

# a state with one more event
def hs.say(st: Hs, e: Reply) -> Hs:
  Hs{phase, tx, keys, priv, proof, buf, msgs, out, +evs} = st
  Hs{phase, tx, keys, priv, proof, buf, msgs, out, List.append(&2, Reply, evs, [e])}

# a state with different keys
def hs.keys(st: Hs, k: Keys) -> Hs:
  Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
  Hs{phase, tx, k, priv, proof, buf, msgs, out, evs}

# close_notify: the peer is done sending
def hs.closed(st: Hs) -> Hs:
  Hs{phase, tx, keys, priv, proof, buf, msgs, out, +evs} = st
  Hs{Phase.closed{}, tx, keys, priv, proof, buf, msgs, out, List.append(&2, Reply, evs, [Reply.closed{}])}

# a boolean gate that ends the connection instead of moving on
def hs.gate(ok: Bool, +st: Hs, +why: String) -> Hs:
  match ok:
    case True{}:
      st
    case False{}:
      hs.die(st, why)

# the bytes the walk didn't use wait in the state for the next feed
def hs.park(st: Hs, tail: List<&2, U32>) -> Hs:
  Hs{phase, tx, keys, priv, proof, +buf, msgs, out, evs} = st
  Hs{phase, tx, keys, priv, proof, Bytes.cat(buf, tail), msgs, out, evs}

# the decrypted bytes that aren't a whole message yet wait for the next record
def hs.mpark(st: Hs, tail: List<&2, U32>) -> Hs:
  Hs{phase, tx, keys, priv, proof, buf, +msgs, out, evs} = st
  Hs{phase, tx, keys, priv, proof, buf, Bytes.cat(msgs, tail), out, evs}

# Handshake messages
# ------------------

# an all-zero shared secret means the server's share has small order (RFC 7748 6.1)
def hs.server.zero(zero: Bool, +st: Hs) -> Hs:
  match zero:
    case True{}:
      hs.die(st, "the server's x25519 share has small order")
    case False{}:
      st

# the suite and the server's x25519 share, then the handshake and the master secrets of
# RFC 8446 7.1 over the ClientHello and the ServerHello
def hs.server.keys(suite: U32, share: List<&2, U32>, st: Hs, m: Tls.Msg) -> Hs:
  Hs{phase, tx, keys, +priv, proof, buf, msgs, out, evs} = st
  +shared = X.x25519(priv, share)
  early = Sha2.extract(alg(), Nil{}, Bytes.zeros(32n))
  +sec = Sha2.extract(alg(), Sha2.derive_secret(alg(), early, "derived", Nil{}), shared)
  +tx2 = Bytes.cat(tx, msg.raw(m))
  +a = aead.of(suite)
  +ch = Sha2.derive_secret(alg(), sec, "c hs traffic", tx2)
  +sh = Sha2.derive_secret(alg(), sec, "s hs traffic", tx2)
  master = Sha2.extract(alg(), Sha2.derive_secret(alg(), sec, "derived", Nil{}), Bytes.zeros(32n))
  hs.server.zero(Bytes.eq(shared, Bytes.zeros(32n)), Hs{Phase.ee{}, tx2, Keys{a, master, traffic.of(sh, a), traffic.of(ch, a), traffic.none(), traffic.none()}, priv, proof, buf, msgs, out, evs})

def hs.server.retry(retry: Bool, suite: U32, share: List<&2, U32>, +st: Hs, m: Tls.Msg) -> Hs:
  match retry:
    case True{}:
      hs.die(st, "the server sent a HelloRetryRequest, and x25519 is all we offer")
    case False{}:
      hs.server.keys(suite, share, st, m)

def hs.server.ok(h: Tls.Hello, st: Hs, m: Tls.Msg) -> Hs:
  match h:
    case Tls.Hello{suite, share, retry}:
      hs.server.retry(retry, suite, share, st, m)

def hs.server.res(r: Result<&1, &1, String, Tls.Hello>, +st: Hs, m: Tls.Msg) -> Hs:
  match r:
    case Fail{e}:
      hs.die(st, e)
    case Done{v}:
      hs.server.ok(v, st, m)

# the ServerHello: the suite, the share and whether it was really a HelloRetryRequest
def hs.server(+st: Hs, +m: Tls.Msg) -> Hs:
  hs.server.res(Tls.server_hello(msg.body(m)), st, m)

# EncryptedExtensions: the ALPN protocol the server picked, which must be the one offered
def hs.ee.alpn(ok: Bool, +st: Hs, m: Tls.Msg) -> Hs:
  match ok:
    case True{}:
      hs.next(st, m, Phase.cert{})
    case False{}:
      hs.die(st, "the server picked an ALPN protocol we didn't offer")

def hs.ee.res(r: Result<&1, &1, String, String>, +st: Hs, m: Tls.Msg) -> Hs:
  match r:
    case Fail{e}:
      hs.die(st, e)
    case Done{v}:
      hs.ee.alpn(alpn.ok(v), st, m)

def hs.ee(+st: Hs, +m: Tls.Msg) -> Hs:
  hs.ee.res(Tls.encrypted_extensions(msg.body(m)), st, m)

# Certificate: the server's chain, leaf first (RFC 8446 4.4.2)
def hs.cert.set(certs: List<&2, List<&2, U32>>, st: Hs, m: Tls.Msg) -> Hs:
  Hs{phase, tx, keys, priv, Proof{certs0, scheme, signed, sig}, buf, msgs, out, evs} = st
  Hs{Phase.verify{}, Bytes.cat(tx, msg.raw(m)), keys, priv, Proof{certs, scheme, signed, sig}, buf, msgs, out, evs}

def hs.cert.by(without: Bool, certs: List<&2, List<&2, U32>>, +st: Hs, m: Tls.Msg) -> Hs:
  match without:
    case True{}:
      hs.die(st, "the server sent no certificate")
    case False{}:
      hs.cert.set(certs, st, m)

def hs.cert.res(r: Result<&1, &1, String, List<&2, List<&2, U32>>>, +st: Hs, m: Tls.Msg) -> Hs:
  match r:
    case Fail{e}:
      hs.die(st, e)
    case Done{+v}:
      hs.cert.by(List.is_empty(&2, List<&2, U32>, v), v, st, m)

def hs.cert(+st: Hs, +m: Tls.Msg) -> Hs:
  hs.cert.res(Tls.certificate(msg.body(m)), st, m)

# CertificateVerify: the 64 spaces, the context string, a 0 byte and the transcript hash up
# to the Certificate are what the shell checks the signature over (RFC 8446 4.4.3), and
# the pkcs1 schemes are refused here
def hs.verify.sig(v: Tls.Verify, st: Hs, m: Tls.Msg) -> Hs:
  Tls.Verify{+scheme, sig} = v
  Hs{phase, +tx, keys, priv, Proof{certs, scheme0, signed0, sig0}, buf, msgs, out, evs} = st
  +signed = Bytes.cat(verify.spaces(), Bytes.cat(verify.context(), Bytes.cat([0], Sha2.hash(alg(), tx))))
  hs.gate(scheme.ok(scheme), Hs{Phase.fin{}, Bytes.cat(tx, msg.raw(m)), keys, priv, Proof{certs, scheme, signed, sig}, buf, msgs, out, evs}, "the server used a pkcs1 or an unknown signature scheme")

def hs.verify.res(r: Result<&1, &1, String, Tls.Verify>, +st: Hs, m: Tls.Msg) -> Hs:
  match r:
    case Fail{e}:
      hs.die(st, e)
    case Done{v}:
      hs.verify.sig(v, st, m)

def hs.verify(+st: Hs, +m: Tls.Msg) -> Hs:
  hs.verify.res(Tls.certificate_verify(msg.body(m)), st, m)

# Finished: HMAC(finished key, transcript hash), compared in constant time, then the
# application traffic secrets (RFC 8446 4.4.4, 7.1)
def hs.fin.keys(st: Hs, m: Tls.Msg) -> Hs:
  Hs{phase, tx, Keys{+aead, +master, rd, wr, ard, awr}, priv, Proof{+certs, +scheme, +signed, +sig}, buf, msgs, out, +evs} = st
  +tx2 = Bytes.cat(tx, msg.raw(m))
  +cap = Sha2.derive_secret(alg(), master, "c ap traffic", tx2)
  +sap = Sha2.derive_secret(alg(), master, "s ap traffic", tx2)
  Hs{Phase.asked{}, tx2, Keys{aead, master, rd, wr, traffic.of(sap, aead), traffic.of(cap, aead)}, priv, Proof{certs, scheme, signed, sig}, buf, msgs, out, List.append(&2, Reply, evs, [Reply.check{certs, scheme, signed, sig}])}

def hs.fin.by(ok: Bool, +st: Hs, m: Tls.Msg) -> Hs:
  match ok:
    case True{}:
      hs.fin.keys(st, m)
    case False{}:
      hs.die(st, "the server's Finished doesn't check")

def hs.fin.mac(st: Hs, body: List<&2, U32>) -> Bool:
  Hs{phase, tx, Keys{aead, master, Traffic{secret, k, iv, n}, wr, ard, awr}, priv, proof, buf, msgs, out, evs} = st
  Bytes.ct_eq(Sha2.hmac(alg(), Sha2.expand_label(alg(), secret, "finished", Nil{}, 32), Sha2.hash(alg(), tx)), body)

def hs.fin(+st: Hs, +m: Tls.Msg) -> Hs:
  hs.fin.by(hs.fin.mac(st, msg.body(m)), st, m)

# KeyUpdate: the read key rotates, and when the peer asked for an update our own message
# goes out under the old write key and the write key follows it (RFC 8446 4.6.3)
def hs.update.record(k: Keys) -> List<&2, U32>:
  Keys{aead, master, rd, wr, ard, awr} = k
  seal.rec(wr, aead, 22, Tls.handshake(24, [0]))

def hs.update.rot(k: Keys) -> Keys:
  Keys{+aead, master, rd, wr, ard, awr} = k
  Keys{aead, master, rd, traffic.up(wr, aead), ard, awr}

def hs.update.answer(st: Hs) -> Hs:
  Hs{phase, tx, +keys, priv, proof, buf, msgs, out, evs} = st
  Hs{phase, tx, hs.update.rot(keys), priv, proof, buf, msgs, Bytes.cat(out, hs.update.record(keys)), evs}

def hs.update.asked(asked: Bool, +st: Hs) -> Hs:
  match asked:
    case False{}:
      st
    case True{}:
      hs.update.answer(st)

def hs.update.read(k: Keys) -> Keys:
  Keys{+aead, master, rd, wr, ard, awr} = k
  Keys{aead, master, traffic.up(rd, aead), wr, ard, awr}

def hs.update.go(st: Hs, asked: Bool) -> Hs:
  Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
  hs.update.asked(asked, Hs{phase, tx, hs.update.read(keys), priv, proof, buf, msgs, out, evs})

def hs.update.ok(ok: Bool, +st: Hs, m: Tls.Msg) -> Hs:
  match ok:
    case False{}:
      hs.die(st, "a KeyUpdate that isn't one byte of 0 or 1")
    case True{}:
      hs.update.go(st, Bytes.eq(msg.body(m), [1]))

def hs.update(+st: Hs, +m: Tls.Msg) -> Hs:
  hs.update.ok(update.ok(msg.body(m)), st, m)

# What the wire bytes hold
# ------------------------

# one message: the phase and its type say which one it may be
def hs.msg.at(p: Phase, n: Note, +st: Hs, +m: Tls.Msg) -> Hs:
  match p n:
    case Phase.ee{} Note.ee{}:
      hs.ee(st, m)
    case Phase.cert{} Note.cert{}:
      hs.cert(st, m)
    case Phase.verify{} Note.verify{}:
      hs.verify(st, m)
    case Phase.fin{} Note.fin{}:
      hs.fin(st, m)
    case Phase.ready{} Note.ticket{}:
      st
    case Phase.ready{} Note.update{}:
      hs.update(st, m)
    case _ _:
      hs.die(st, "an unexpected handshake message")

def hs.msg(+st: Hs, +m: Tls.Msg) -> Hs:
  hs.msg.at(phase.of(st), msg.note(m), st, m)

# one message per step: fuel is the buffer's byte count, and every message eats at least a
# four-byte header
def hs.msgs.walk(fuel: Nat, +st: Hs, +buf: List<&2, U32>, m: Mhead) -> Hs:
  match fuel m:
    case 0n _:
      hs.mpark(st, buf)
    case 1n+p Mhead.short{}:
      hs.mpark(st, buf)
    case 1n+p Mhead.one{msg, +rest}:
      hs.msgs.walk(p, hs.msg(st, msg), rest, mhead.of(rest))

# the decrypted handshake bytes: append them, then walk every whole message in them
def hs.msgs(st: Hs, bytes: List<&2, U32>) -> Hs:
  Hs{phase, tx, keys, priv, proof, buf, +msgs, out, evs} = st
  +all = Bytes.cat(msgs, bytes)
  hs.msgs.walk(U32.to_nat(Bytes.len(all)), Hs{phase, tx, keys, priv, proof, buf, Nil{}, out, evs}, all, mhead.of(all))

# application data: the shell's, once the handshake is done
def hs.app(p: Phase, +k: Keys, +st: Hs, body: List<&2, U32>) -> Hs:
  match p:
    case Phase.ready{}:
      hs.say(hs.keys(st, k), Reply.data{body})
    case _:
      hs.die(hs.keys(st, k), "application data before the handshake ended")

# an encrypted alert: close_notify ends the stream, anything else ends the connection with
# its name
def hs.alert.ready(close: Bool, +k: Keys, +st: Hs, +body: List<&2, U32>) -> Hs:
  match close:
    case True{}:
      hs.closed(hs.keys(st, k))
    case False{}:
      hs.die(hs.keys(st, k), "the server sent " ++ Tls.alert(body))

def hs.alert(p: Phase, +k: Keys, +st: Hs, +body: List<&2, U32>) -> Hs:
  match p:
    case Phase.ready{}:
      hs.alert.ready(close.of(body), k, st, body)
    case _:
      hs.die(hs.keys(st, k), "the server sent " ++ Tls.alert(body))

# the decrypted content of an encrypted record, by its real content type
def hs.inner(+st: Hs, +k: Keys, c: Ctype, +body: List<&2, U32>) -> Hs:
  match c:
    case Ctype.handshake{}:
      hs.msgs(hs.keys(st, k), body)
    case Ctype.app{}:
      hs.app(phase.of(st), k, st, body)
    case Ctype.alert{}:
      hs.alert(phase.of(st), k, st, body)
    case _:
      hs.die(hs.keys(st, k), "an encrypted record with an unexpected content type")

def hs.plaintext(m: Maybe<&2, Tls.Rec>, k: Keys, +st: Hs) -> Hs:
  match m:
    case None{}:
      hs.die(st, "an encrypted record with no content")
    case Some{Tls.Rec{ctype0, body}}:
      hs.inner(st, k, ctype.of(ctype0), body)

def hs.opened.at(m: Maybe<&2, List<&2, U32>>, k: Keys, +st: Hs) -> Hs:
  match m:
    case None{}:
      hs.die(st, "a record that didn't authenticate")
    case Some{v}:
      hs.plaintext(Tls.inner(v), k, st)

def hs.decrypt.by(k: Keys, st: Hs, r: Tls.Rec) -> Hs:
  Keys{+aead, master, +rd, wr, ard, awr} = k
  hs.opened.at(open.rec(aead, rd, r), Keys{aead, master, traffic.next(rd), wr, ard, awr}, st)

# an encrypted record: the read key's turn, then whatever its plaintext holds
def hs.decrypt(+st: Hs, r: Tls.Rec) -> Hs:
  hs.decrypt.by(keys.of(st), st, r)

# a legacy ChangeCipherSpec: one byte, 0x01, and nothing else
def hs.ccs.at(during: Bool, one: Bool, +st: Hs) -> Hs:
  match during one:
    case True{} True{}:
      st
    case False{} _:
      hs.die(st, "a legacy ChangeCipherSpec after the handshake")
    case _ _:
      hs.die(st, "a legacy ChangeCipherSpec that isn't one byte of 0x01")

def hs.ccs(+st: Hs, +r: Tls.Rec) -> Hs:
  hs.ccs.at(ccs.open(phase.of(st)), Bytes.eq(rec.body(r), [1]), st)

# the plaintext handshake record: one whole ServerHello message and nothing else
def hs.hello.one(one: Bool, n: Note, +st: Hs, +m: Tls.Msg) -> Hs:
  match one n:
    case True{} Note.hello{}:
      hs.server(st, m)
    case False{} _:
      hs.die(st, "more than a ServerHello in one plaintext record")
    case _ _:
      hs.die(st, "the first handshake message isn't a ServerHello")

def hs.hello.at(m: Mhead, +st: Hs, r: Tls.Rec) -> Hs:
  match m:
    case Mhead.short{}:
      hs.die(st, "the ServerHello isn't whole in its record")
    case Mhead.one{+m, rest}:
      hs.hello.one(empty.of(rest), msg.note(m), st, m)

def hs.hello(st: Hs, +r: Tls.Rec) -> Hs:
  hs.hello.at(mhead.of(rec.body(r)), st, r)

# the plaintext record before the ServerHello
def hs.plain.at(c: Ctype, +st: Hs, +r: Tls.Rec) -> Hs:
  match c:
    case Ctype.ccs{}:
      hs.ccs(st, r)
    case Ctype.alert{}:
      hs.die(st, "the server sent " ++ Tls.alert(rec.body(r)))
    case Ctype.handshake{}:
      hs.hello(st, r)
    case _:
      hs.die(st, "an unexpected record before the ServerHello")

def hs.plain(st: Hs, +r: Tls.Rec) -> Hs:
  hs.plain.at(ctype.of(rec.ctype(r)), st, r)

# an encrypted record during the handshake or after it
def hs.enc.at(c: Ctype, +st: Hs, +r: Tls.Rec) -> Hs:
  match c:
    case Ctype.ccs{}:
      hs.ccs(st, r)
    case Ctype.app{}:
      hs.decrypt(st, r)
    case _:
      hs.die(st, "an unexpected record")

def hs.enc(st: Hs, +r: Tls.Rec) -> Hs:
  hs.enc.at(ctype.of(rec.ctype(r)), st, r)

# one record: the phase says whether it is the plaintext ServerHello, an encrypted record,
# or one to keep for later
def hs.one.at(w: Want, +st: Hs, +r: Tls.Rec, raw: List<&2, U32>) -> Hs:
  match w:
    case Want.plain{}:
      hs.plain(st, r)
    case Want.enc{}:
      hs.enc(st, r)
    case Want.refuse{}:
      hs.park(st, raw)

def hs.one(+st: Hs, r: Tls.Rec, raw: List<&2, U32>) -> Hs:
  hs.one.at(want.of(phase.of(st)), st, r, raw)

# one record per step: fuel is the buffer's byte count, and every record eats at least a
# five-byte header
def hs.walk(fuel: Nat, +st: Hs, +buf: List<&2, U32>, h: Head) -> Hs:
  match fuel h:
    case 0n _:
      hs.park(st, buf)
    case 1n+p Head.short{}:
      hs.park(st, buf)
    case 1n+p Head.bad{}:
      hs.die(st, "a record header we can't use")
    case 1n+p Head.one{r, +raw, +rest}:
      hs.walk(p, hs.one(st, r, raw), rest, head.of(rest))

# The surface
# -----------

# the events, or the one that asks for more bytes
def needs(evs: List<&2, Reply>) -> List<&2, Reply>:
  match evs:
    case Nil{}:
      [Reply.need{}]
    case e <> t:
      e <> t

# what one step answers: the state, the records to send and the events, with Need when
# nothing else happened
def hs.answer(st: Hs) -> Hs & List<&2, U32> & List<&2, Reply>:
  Hs{phase, tx, keys, priv, proof, buf, msgs, out, +evs} = st
  (Hs{phase, tx, keys, priv, proof, buf, msgs, Nil{}, Nil{}}, (out, needs(evs)))

# feed bytes from the wire: the new state, the records to send, and what happened
def hs.input(st: Hs, bytes: List<&2, U32>) -> Hs & List<&2, U32> & List<&2, Reply>:
  Hs{phase, tx, keys, priv, proof, +buf, msgs, out, evs} = st
  +all = Bytes.cat(buf, bytes)
  hs.answer(hs.walk(U32.to_nat(Bytes.len(all)), Hs{phase, tx, keys, priv, proof, Nil{}, msgs, out, evs}, all, head.of(all)))

# the records that arrived while the shell was checking the chain, now that the handshake
# is done
def hs.resume(st: Hs) -> Hs:
  Hs{phase, tx, keys, priv, proof, +buf, msgs, out, evs} = st
  hs.walk(U32.to_nat(Bytes.len(buf)), Hs{phase, tx, keys, priv, proof, Nil{}, msgs, out, evs}, buf, head.of(buf))

# the client's Finished: a legacy ChangeCipherSpec, then the MAC of the transcript under
# the client's handshake key, and then the application keys take over (RFC 8446 4.4.4, D.4)
def hs.finish.sent(st: Hs) -> Hs:
  Hs{phase, +tx, Keys{+aead, master, rd, Traffic{+secret, k, iv, n}, ard, awr}, priv, proof, buf, msgs, out, +evs} = st
  +sent = Tls.handshake(20, Sha2.hmac(alg(), Sha2.expand_label(alg(), secret, "finished", Nil{}, 32), Sha2.hash(alg(), tx)))
  +rec = seal.rec(Traffic{secret, k, iv, n}, aead, 22, sent)
  Hs{Phase.ready{}, Bytes.cat(tx, sent), Keys{aead, master, ard, awr, traffic.none(), traffic.none()}, priv, proof, buf, msgs, Bytes.cat(out, Bytes.cat(Tls.record(20, [1]), rec)), List.append(&2, Reply, evs, [Reply.ready{}])}

def hs.trusted.ok(ok: Bool, +st: Hs) -> Hs & List<&2, U32> & List<&2, Reply>:
  match ok:
    case False{}:
      hs.answer(hs.die(st, "the server's certificate was rejected"))
    case True{}:
      hs.answer(hs.resume(hs.finish.sent(st)))

def hs.trusted.at(when.asked: Bool, +st: Hs, ok: Bool) -> Hs & List<&2, U32> & List<&2, Reply>:
  match when.asked:
    case False{}:
      hs.answer(hs.die(st, "hs.trusted before the server's flight is in"))
    case True{}:
      hs.trusted.ok(ok, st)

# the shell's verdict on Check: True sends the client Finished and answers Ready, False
# answers Failed. Nothing but the end of the server's flight can come before it.
def hs.trusted(+st: Hs, ok: Bool) -> Hs & List<&2, U32> & List<&2, Reply>:
  hs.trusted.at(asked.of(phase.of(st)), st, ok)

# application data to send: one record per 2^14 bytes, each under the next write key
def hs.send.go(fuel: Nat, done: Bool, +st: Hs, +data: List<&2, U32>, +acc: List<&2, U32>) -> Hs & List<&2, U32>:
  match fuel done:
    case _ True{}:
      (st, acc)
    case 0n False{}:
      (st, acc)
    case 1n+p False{}:
      Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
      Keys{+aead, master, rd, +wr, ard, awr} = keys
      +n = Nat.min(U32.to_nat(Bytes.len(data)), U32.to_nat(send.max()))
      +plain = Bytes.take(data, n)
      +rest = Bytes.drop(data, n)
      hs.send.go(p, empty.of(rest), Hs{phase, tx, Keys{aead, master, rd, traffic.next(wr), ard, awr}, priv, proof, buf, msgs, out, evs}, rest, Bytes.cat(acc, seal.rec(wr, aead, 23, plain)))

def hs.send.at(during: Bool, +st: Hs, +data: List<&2, U32>) -> Hs & List<&2, U32>:
  match during:
    case False{}:
      (st, Nil{})
    case True{}:
      hs.send.go(U32.to_nat(Bytes.len(data)), empty.of(data), st, data, Nil{})

def hs.send(+st: Hs, data: List<&2, U32>) -> Hs & List<&2, U32>:
  hs.send.at(ready.of(phase.of(st)), st, data)

# a close_notify alert record, empty when the handshake never finished
def hs.close.with(k: Keys) -> List<&2, U32>:
  Keys{aead, master, rd, wr, ard, awr} = k
  seal.rec(wr, aead, 21, [1, 0])

def hs.close.at(during: Bool, st: Hs) -> List<&2, U32>:
  match during:
    case False{}:
      Nil{}
    case True{}:
      hs.close.with(keys.of(st))

def hs.close(+st: Hs) -> List<&2, U32>:
  hs.close.at(ready.of(phase.of(st)), st)

# a fresh handshake over a ClientHello that has already been built: the shell gets one from
# hs.start, and the offline check replays a recorded trace through this
def hs.over(hello: List<&2, U32>, priv: List<&2, U32>) -> Hs:
  Hs{Phase.hello{}, hello, keys.none(), priv, proof.none(), Nil{}, Nil{}, Nil{}, Nil{}}

def hs.start.by(+hello: List<&2, U32>, priv: List<&2, U32>) -> Hs & List<&2, U32>:
  (hs.over(hello, priv), Tls.record(22, hello))

def hs.start(random: List<&2, U32>, session: List<&2, U32>, +priv: List<&2, U32>, host: String) -> Hs & List<&2, U32>:
  hs.start.by(Tls.client_hello(random, session, host, X.public(priv)), priv)
