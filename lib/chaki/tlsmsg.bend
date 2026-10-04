# tlsmsg: TLS 1.3 records and handshake messages, as bytes. Building the ClientHello,
# splitting records and handshake messages, and reading what a server sends. No crypto and
# no IO: the client that uses this comes in a later lane. RFC 8446 section 5 is the record
# layer and section 4 the handshake messages, RFC 8448 the traces the checks come from.
# Every number below is one of theirs, written in decimal because Bend has no hex literals.
import Base
import ./bytes.bend as Bytes

# Numbers
# -------

# 0x0301: an initial ClientHello's record may still carry it (RFC 8446 5.1)
def ver.tls10() -> U32:
  769

# 0x0303: every other record's legacy version, and a ServerHello's legacy_version
def ver.tls12() -> U32:
  771

# 0x0304: supported_versions
def ver.tls13() -> U32:
  772

# 0x001d: the one group this client speaks (RFC 8446 4.2.7)
def group.x25519() -> U32:
  29

# 0x1301 TLS_AES_128_GCM_SHA256
def suite.aes128() -> U32:
  4865

# 0x1303 TLS_CHACHA20_POLY1305_SHA256
def suite.chacha() -> U32:
  4867

# the suites the ClientHello offers, and so the only ones a ServerHello may pick
def suite.ok(+s: U32) -> Bool:
  Bool.or(U32.is_eq(s, suite.aes128()), U32.is_eq(s, suite.chacha()))

# Records
# -------

# 2^14 plaintext plus 256 for the inner content type and the AEAD tag (RFC 8446 5.2)
def record.max() -> U32:
  16640

# change_cipher_spec(20), alert(21), handshake(22), application_data(23) and the heartbeat
# type RFC 6520 keeps registered; any other content type is a bad header
def record.type.ok(+t: U32) -> Bool:
  Bool.and(U32.is_le(20, t), U32.is_le(t, 24))

def record.ver.ok(+v: U32) -> Bool:
  Bool.or(U32.is_eq(v, ver.tls12()), U32.is_eq(v, ver.tls10()))

def record.hdr.ok(+t: U32, +v: U32, +n: U32) -> Bool:
  Bool.and(record.type.ok(t), Bool.and(record.ver.ok(v), U32.is_le(n, record.max())))

# the five header bytes: content type, legacy version 0x0303, 16-bit length
def record.head(ctype: U32, +len: U32) -> List<&2, U32>:
  ctype <> (3 <> (3 <> Bytes.be16(len)))

# one record: content type, legacy version 0x0303, 16-bit length, payload
def record(ctype: U32, +payload: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(record.head(ctype, Bytes.len(payload)), payload)

type Rec is Data:
  Rec{ctype: U32, body: List<&2, U32>}

# the record at the front of a buffer, when the buffer holds all of it
type First is Data:
  First.rec{rec: Rec, after: List<&2, U32>, have: Nat}
  First.short{}
  First.bad{}

# the payload length a record's header claims
def first.len(+buf: List<&2, U32>) -> Nat:
  U32.to_nat(Bytes.get.be(Bytes.drop(buf, 3n), 2n))

def first.rec(+buf: List<&2, U32>, +have: Nat) -> First:
  +n = first.len(buf)
  First.rec{Rec{Bytes.get.be(buf, 1n), Bytes.take(Bytes.drop(buf, 5n), n)}, Bytes.drop(buf, Nat.add(5n, n)), Nat.sub(have, Nat.add(5n, n))}

# the whole record is there: it holds a record, a header we can't use, or too few bytes yet
def first.fits(+buf: List<&2, U32>, +have: Nat) -> First:
  Bool.pick(First, Nat.is_le(Nat.add(5n, first.len(buf)), have), first.rec(buf, have), First.short{})

def first.hdr(+buf: List<&2, U32>, +have: Nat) -> First:
  +n = Bytes.get.be(Bytes.drop(buf, 3n), 2n)
  Bool.pick(First, record.hdr.ok(Bytes.get.be(buf, 1n), Bytes.get.be(Bytes.drop(buf, 1n), 2n), n), first.fits(buf, have), First.bad{})

def first.of(+buf: List<&2, U32>, +have: Nat) -> First:
  Bool.pick(First, Nat.is_lt(have, 5n), First.short{}, first.hdr(buf, have))

# where the record walk is. rest is the buffer from here on and left how many bytes it
# holds: each step eats a whole record, so the count bounds the walk.
type Recs is Data:
  Recs.more{first: First, rest: List<&2, U32>, left: Nat, acc: List<&2, Rec>}

def records.give(st: Recs) -> Maybe<&1, List<&2, Rec> & List<&2, U32>>:
  match st:
    case Recs.more{First.rec{rec, after, have}, rest, left, acc}:
      Some{(List.reverse(&2, Rec, rec <> acc), after)}
    case Recs.more{First.short{}, rest, left, acc}:
      Some{(List.reverse(&2, Rec, acc), rest)}
    case Recs.more{First.bad{}, rest, left, acc}:
      None{}

def records.go(fuel: Nat, st: Recs) -> Maybe<&1, List<&2, Rec> & List<&2, U32>>:
  match fuel st:
    case 0n s:
      records.give(s)
    case 1n+p Recs.more{First.bad{}, rest, left, acc}:
      None{}
    case 1n+p Recs.more{First.short{}, rest, left, acc}:
      Some{(List.reverse(&2, Rec, acc), rest)}
    case 1n+p Recs.more{First.rec{rec, +after, +have}, rest, left, acc}:
      records.go(p, Recs.more{first.of(after, have), after, have, rec <> acc})

def records.start(+buf: List<&2, U32>, +have: Nat) -> Maybe<&1, List<&2, Rec> & List<&2, U32>>:
  records.go(have, Recs.more{first.of(buf, have), buf, have, Nil{}})

# the whole records at the front of buf, and the rest. None when a header is malformed: a
# bad type, a bad version, or a length past 2^14 + 256. A buffer that stops inside a record
# answers what it holds so far and hands the cut record back as the rest. The pair makes
# the Maybe affine: Bend's `A & B` is Pair, Sigma<&1, &1, ..>, so `Maybe<&2, A & B>` is
# not a type a module can write down.
def records(+buf: List<&2, U32>) -> Maybe<&1, List<&2, Rec> & List<&2, U32>>:
  records.start(buf, U32.to_nat(Bytes.len(buf)))

# Handshake messages
# ------------------

# a handshake message: type, 24-bit length, body
def handshake(htype: U32, +body: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(htype <> Bytes.be24(Bytes.len(body)), body)

# raw is the header and the body as they came in, which is what goes into the transcript
# hash (RFC 8446 4.4.1)
type Msg is Data:
  Msg{htype: U32, body: List<&2, U32>, raw: List<&2, U32>}

# the handshake message at the front of a buffer, when the buffer holds all of it
type Each is Data:
  Each.msg{msg: Msg, after: List<&2, U32>, have: Nat}
  Each.short{}

# the 24-bit length a handshake header claims
def each.len(+buf: List<&2, U32>) -> Nat:
  U32.to_nat(Bytes.get.be(Bytes.drop(buf, 1n), 3n))

def each.msg(+buf: List<&2, U32>, +have: Nat) -> Each:
  +need = Nat.add(4n, each.len(buf))
  +raw = Bytes.take(buf, need)
  Each.msg{Msg{Bytes.get.be(buf, 1n), Bytes.drop(raw, 4n), raw}, Bytes.drop(buf, need), Nat.sub(have, need)}

def each.fits(+buf: List<&2, U32>, +have: Nat) -> Each:
  Bool.pick(Each, Nat.is_le(Nat.add(4n, each.len(buf)), have), each.msg(buf, have), Each.short{})

def each.of(+buf: List<&2, U32>, +have: Nat) -> Each:
  Bool.pick(Each, Nat.is_lt(have, 4n), Each.short{}, each.fits(buf, have))

type Msgs is Data:
  Msgs.more{each: Each, rest: List<&2, U32>, left: Nat, acc: List<&2, Msg>}

def messages.give(st: Msgs) -> List<&2, Msg> & List<&2, U32>:
  match st:
    case Msgs.more{Each.msg{msg, after, have}, rest, left, acc}:
      (List.reverse(&2, Msg, msg <> acc), after)
    case Msgs.more{Each.short{}, rest, left, acc}:
      (List.reverse(&2, Msg, acc), rest)

def messages.go(fuel: Nat, st: Msgs) -> List<&2, Msg> & List<&2, U32>:
  match fuel st:
    case 0n s:
      messages.give(s)
    case 1n+p Msgs.more{Each.short{}, rest, left, acc}:
      (List.reverse(&2, Msg, acc), rest)
    case 1n+p Msgs.more{Each.msg{msg, +after, +have}, rest, left, acc}:
      messages.go(p, Msgs.more{each.of(after, have), after, have, msg <> acc})

def messages.start(+buf: List<&2, U32>, +have: Nat) -> List<&2, Msg> & List<&2, U32>:
  messages.go(have, Msgs.more{each.of(buf, have), buf, have, Nil{}})

# the whole handshake messages at the front of buf (they may span records, so the caller
# concatenates record bodies), and the rest
def messages(+buf: List<&2, U32>) -> List<&2, Msg> & List<&2, U32>:
  messages.start(buf, U32.to_nat(Bytes.len(buf)))

# Extensions
# ----------

# the three extensions this client reads out of a server's handshake messages:
# supported_versions (43), key_share (51) and ALPN (16). An empty list is one the server
# didn't send.
type Seen is Data:
  Seen{versions: List<&2, U32>, share: List<&2, U32>, alpn: List<&2, U32>}

# data when tag is the extension wanted and nothing was there yet, else what was there
def seen.take(+tag: U32, +want: U32, +data: List<&2, U32>, +had: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, Bool.and(U32.is_eq(tag, want), List.is_empty(&2, U32, had)), data, had)

def seen.next(+tag: U32, +data: List<&2, U32>, +s: Seen) -> Seen:
  match s:
    case Seen{versions, share, alpn}:
      Seen{seen.take(tag, 43, data, versions), seen.take(tag, 51, data, share), seen.take(tag, 16, data, alpn)}

# the extension at the front of a block, when the block holds all of it
type Ext is Data:
  Ext.one{tag: U32, data: List<&2, U32>, after: List<&2, U32>, have: Nat}
  Ext.end{}
  Ext.bad{}

# the bytes the first extension takes: 2-byte tag, 2-byte length, the data
def ext.need(+buf: List<&2, U32>) -> Nat:
  Nat.add(4n, U32.to_nat(Bytes.get.be(Bytes.drop(buf, 2n), 2n)))

def ext.one(+buf: List<&2, U32>, +have: Nat) -> Ext:
  +need = ext.need(buf)
  +n = U32.to_nat(Bytes.get.be(Bytes.drop(buf, 2n), 2n))
  Ext.one{Bytes.get.be(buf, 2n), Bytes.take(Bytes.drop(buf, 4n), n), Bytes.drop(buf, need), Nat.sub(have, need)}

def ext.fits(+buf: List<&2, U32>, +have: Nat) -> Ext:
  Bool.pick(Ext, Nat.is_le(ext.need(buf), have), ext.one(buf, have), Ext.bad{})

def ext.of(+buf: List<&2, U32>, +have: Nat) -> Ext:
  Bool.pick(Ext, Nat.is_eq(have, 0n), Ext.end{}, Bool.pick(Ext, Nat.is_le(4n, have), ext.fits(buf, have), Ext.bad{}))

type Scan is Data:
  Scan.more{ext: Ext, buf: List<&2, U32>, left: Nat, seen: Seen}

def scan.give(st: Scan) -> Maybe<&2, Seen>:
  match st:
    case Scan.more{ext, buf, left, seen}:
      Some{seen}

def scan.go(fuel: Nat, st: Scan) -> Maybe<&2, Seen>:
  match fuel st:
    case 0n s:
      scan.give(s)
    case 1n+p Scan.more{Ext.end{}, buf, left, seen}:
      Some{seen}
    case 1n+p Scan.more{Ext.bad{}, buf, left, seen}:
      None{}
    case 1n+p Scan.more{Ext.one{tag, data, +after, +have}, buf, left, seen}:
      scan.go(p, Scan.more{ext.of(after, have), after, have, seen.next(tag, data, seen)})

def scan.start(+buf: List<&2, U32>, +have: Nat) -> Maybe<&2, Seen>:
  scan.go(have, Scan.more{ext.of(buf, have), buf, have, Seen{Nil{}, Nil{}, Nil{}}})

# the three extensions of a block, None when the block doesn't parse
# (the walk uses a byte count as fuel: every step eats an extension, so it ends)
def seen(+buf: List<&2, U32>) -> Maybe<&2, Seen>:
  scan.start(buf, U32.to_nat(Bytes.len(buf)))

# ClientHello
# -----------

def ext.pair(+tag: U32, +data: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(Bytes.cat(Bytes.be16(tag), Bytes.be16(Bytes.len(data))), data)

def hello.sni.entry(+names: List<&2, U32>) -> List<&2, U32>:
  0 <> Bytes.cat(Bytes.be16(Bytes.len(names)), names)

# server_name (0): a list of one host_name, a one-byte name type and the name (RFC 6066 3)
def hello.sni(+host: String) -> List<&2, U32>:
  +names = Bytes.of_ascii(host)
  ext.pair(0, Bytes.cat(Bytes.be16(U32.add(Bytes.len(names), 3)), hello.sni.entry(names)))

# no server_name for an IP literal: it has no name to send
def hello.sni.if(+host: String) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, String.is_empty(host), Nil{}, hello.sni(host))

# supported_groups (10): x25519 only
def hello.groups() -> List<&2, U32>:
  ext.pair(10, Bytes.cat(Bytes.be16(2), Bytes.be16(group.x25519())))

# signature_algorithms (13): rsa_pss_rsae_sha256, rsa_pss_rsae_sha384,
# ecdsa_secp256r1_sha256, ecdsa_secp384r1_sha384, rsa_pkcs1_sha256, rsa_pkcs1_sha384
def hello.schemes() -> List<&2, U32>:
  Bytes.cat(Bytes.be16(1027), Bytes.cat(Bytes.be16(1283), Bytes.cat(Bytes.be16(2052), Bytes.cat(Bytes.be16(2053), Bytes.cat(Bytes.be16(1025), Bytes.be16(1281))))))

def hello.sigs() -> List<&2, U32>:
  ext.pair(13, Bytes.cat(Bytes.be16(12), hello.schemes()))

# supported_versions (43): one version, 0x0304
def hello.versions() -> List<&2, U32>:
  ext.pair(43, [2, 3, 4])

# key_share (51): one entry, the x25519 group and the public key
def hello.share(+share: List<&2, U32>) -> List<&2, U32>:
  +entry = Bytes.cat(Bytes.be16(group.x25519()), Bytes.cat(Bytes.be16(Bytes.len(share)), share))
  ext.pair(51, Bytes.cat(Bytes.be16(Bytes.len(entry)), entry))

# application_layer_protocol_negotiation (16): "http/1.1" (RFC 7301 3.1)
def hello.alpn() -> List<&2, U32>:
  +p = Bytes.of_ascii("http/1.1")
  ext.pair(16, Bytes.cat(Bytes.be16(U32.add(Bytes.len(p), 1)), Bytes.len(p) <> p))

# legacy_version 0x0303
def hello.legacy() -> List<&2, U32>:
  [3, 3]

# the suites, chacha20-poly1305 first, and one null compression method (RFC 8446 4.1.2)
def hello.suites() -> List<&2, U32>:
  Bytes.cat(Bytes.be16(4), Bytes.cat(Bytes.be16(suite.chacha()), Bytes.be16(suite.aes128())))

def hello.comp() -> List<&2, U32>:
  [1, 0]

def hello.ids(+session: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(Bytes.len(session) <> session, Bytes.cat(hello.suites(), hello.comp()))

def hello.fixed(+random: List<&2, U32>, +session: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(hello.legacy(), Bytes.cat(random, hello.ids(session)))

def hello.ext.tail(+share: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(hello.groups(), Bytes.cat(hello.sigs(), Bytes.cat(hello.versions(), Bytes.cat(hello.share(share), hello.alpn()))))

def hello.ext.list(+host: String, +share: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(hello.sni.if(host), hello.ext.tail(share))

def hello.exts(+host: String, +share: List<&2, U32>) -> List<&2, U32>:
  +xs = hello.ext.list(host, share)
  Bytes.cat(Bytes.be16(Bytes.len(xs)), xs)

def hello.body(+random: List<&2, U32>, +session: List<&2, U32>, +host: String, +share: List<&2, U32>) -> List<&2, U32>:
  Bytes.cat(hello.fixed(random, session), hello.exts(host, share))

# the full ClientHello handshake message. random is 32 bytes, session the 32-byte legacy
# session id a middlebox compatible client sends, share the 32-byte x25519 public key, and
# host the server name: "" (an IP literal) sends no SNI and no ALPN beyond "http/1.1".
def client_hello(random: List<&2, U32>, session: List<&2, U32>, host: String, share: List<&2, U32>) -> List<&2, U32>:
  handshake(1, hello.body(random, session, host, share))

# ServerHello
# ----------

# SHA-256("HelloRetryRequest"): a ServerHello whose random is this is a HelloRetryRequest
# (RFC 8446 4.1.3)
def hrr.random() -> List<&2, U32>:
  Bytes.of_hex("cf 21 ad 74 e5 9a 61 11 be 1d 8c 02 1e 65 b8 91 c2 a2 11 16 7a bb 8c 5e 07 9e 09 e2 c8 a8 33 9c")

def sh.retry(+body: List<&2, U32>) -> Bool:
  Bytes.eq(Bytes.take(Bytes.drop(body, 2n), 32n), hrr.random())

# where the cipher suite starts: legacy_version, random and the echoed session id
def sh.suite.at(+body: List<&2, U32>) -> Nat:
  Nat.add(35n, U32.to_nat(Bytes.get.be(Bytes.drop(body, 34n), 1n)))

def sh.suite(+body: List<&2, U32>) -> U32:
  Bytes.get.be(Bytes.drop(body, sh.suite.at(body)), 2n)

# where the extensions length starts: the suite and the compression method
def sh.ext.at(+body: List<&2, U32>) -> Nat:
  Nat.add(3n, sh.suite.at(body))

# the length of the extension block is exactly the rest of the body
def sh.ext.ok(+body: List<&2, U32>) -> Bool:
  +at = sh.ext.at(body)
  Bool.and(Nat.is_le(Nat.add(at, 2n), U32.to_nat(Bytes.len(body))), U32.is_eq(Bytes.get.be(Bytes.drop(body, at), 2n), Bytes.len(Bytes.drop(body, Nat.add(at, 2n)))))

def sh.ext(+body: List<&2, U32>, good: Bool) -> Maybe<&2, Seen>:
  match good:
    case False{}:
      None{}
    case True{}:
      seen(Bytes.drop(body, Nat.add(sh.ext.at(body), 2n)))

# supported_versions (43) in a ServerHello: the two bytes 0x0304, no length byte (RFC 8446
# 4.2.1)
def sh.ver.ok(+versions: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(Bytes.len(versions), 2), U32.is_eq(Bytes.get.be(versions, 2n), ver.tls13()))

def key.group(+data: List<&2, U32>) -> U32:
  Bytes.get.be(data, 2n)

# one whole key exchange: the x25519 group, a 32-byte length and the 32 bytes
def key.one.ok(+data: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(Bytes.len(data), 36), Bool.and(U32.is_eq(key.group(data), group.x25519()), U32.is_eq(Bytes.get.be(Bytes.drop(data, 2n), 2n), 32)))

# a HelloRetryRequest's key share: the group it picked, the key itself (RFC 8446 4.1.4)
def key.retry.ok(+data: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(Bytes.len(data), 2), U32.is_eq(key.group(data), group.x25519()))

def key.ok(+data: List<&2, U32>, +retry: Bool) -> Bool:
  Bool.pick(Bool, retry, key.retry.ok(data), key.one.ok(data))

# the server's key: [] for a HelloRetryRequest, and [] when the share isn't x25519
def key.pick(+data: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, key.one.ok(data), Bytes.take(Bytes.drop(data, 4n), 32n), Nil{})

# every check the client makes on a ServerHello, in the order sh.why reports them
def sh.good(+body: List<&2, U32>, +versions: List<&2, U32>, +share: List<&2, U32>, +retry: Bool) -> Bool:
  Bool.and(sh.ver.ok(versions), Bool.and(suite.ok(sh.suite(body)), key.ok(share, retry)))

def sh.why.key(+data: List<&2, U32>, +retry: Bool) -> String:
  Bool.pick(String, retry, "the HelloRetryRequest picked a group that isn't x25519", "the key share isn't a 32-byte x25519 key")

def sh.why(+body: List<&2, U32>, +versions: List<&2, U32>, +share: List<&2, U32>, +retry: Bool) -> String:
  Bool.pick(String, sh.ver.ok(versions), Bool.pick(String, suite.ok(sh.suite(body)), sh.why.key(share, retry), "the server picked a cipher suite we didn't offer"), "supported_versions isn't 0x0304")

def sh.verdict(+body: List<&2, U32>, +versions: List<&2, U32>, +share: List<&2, U32>, +retry: Bool, good: Bool) -> Result<&1, &1, String, Hello>:
  match good:
    case True{}:
      Done{Hello{sh.suite(body), key.pick(share), retry}}
    case False{}:
      Fail{sh.why(body, versions, share, retry)}

def sh.check(+body: List<&2, U32>, m: Maybe<&2, Seen>, +retry: Bool) -> Result<&1, &1, String, Hello>:
  match m:
    case None{}:
      Fail{"malformed ServerHello"}
    case Some{Seen{+versions, +share, alpn}}:
      sh.verdict(body, versions, share, retry, sh.good(body, versions, share, retry))

type Hello is Data:
  Hello{suite: U32, share: List<&2, U32>, retry: Bool}

# a ServerHello body: the suite, the server's x25519 key share, and whether it is really a
# HelloRetryRequest. Fails when the body runs out, when supported_versions isn't 0x0304,
# when the group isn't x25519, or when the suite isn't one the ClientHello offered.
def server_hello(+body: List<&2, U32>) -> Result<&1, &1, String, Hello>:
  sh.check(body, sh.ext(body, sh.ext.ok(body)), sh.retry(body))

# EncryptedExtensions
# -------------------

# the length of the extension block is exactly the body
def ee.ok(+body: List<&2, U32>) -> Bool:
  Bool.and(U32.is_le(2, Bytes.len(body)), U32.is_eq(Bytes.get.be(body, 2n), Bytes.len(Bytes.drop(body, 2n))))

def ee.seen(+body: List<&2, U32>, good: Bool) -> Maybe<&2, Seen>:
  match good:
    case False{}:
      None{}
    case True{}:
      seen(Bytes.drop(body, 2n))

# a server that sent no ALPN extension at all, or a list whose length is the data
def alpn.data.ok(+data: List<&2, U32>) -> Bool:
  Bool.or(U32.is_eq(Bytes.len(data), 0), Bool.and(U32.is_le(2, Bytes.len(data)), U32.is_eq(Bytes.get.be(data, 2n), U32.sub(Bytes.len(data), 2))))

# a name is its one-byte length and that many bytes, and the list may hold none
def alpn.name.ok(+entry: List<&2, U32>) -> Bool:
  Bool.or(U32.is_eq(Bytes.len(entry), 0), U32.is_le(U32.add(Bytes.get.be(entry, 1n), 1), Bytes.len(entry)))

def alpn.name(+entry: List<&2, U32>, good: Bool) -> Result<&1, &1, String, String>:
  match good:
    case False{}:
      Fail{"bad ALPN protocol name"}
    case True{}:
      Done{Bytes.to_ascii(Bytes.take(Bytes.drop(entry, 1n), U32.to_nat(Bytes.get.be(entry, 1n))))}

def alpn.entry(+entry: List<&2, U32>, good: Bool) -> Result<&1, &1, String, String>:
  match good:
    case False{}:
      Fail{"bad ALPN extension"}
    case True{}:
      alpn.name(entry, alpn.name.ok(entry))

# the first protocol name of an ALPNProtocolList (RFC 7301 3.1), "" when there is none
def alpn.first(+data: List<&2, U32>) -> Result<&1, &1, String, String>:
  alpn.entry(Bytes.drop(data, 2n), alpn.data.ok(data))

def ee.alpn(m: Maybe<&2, Seen>) -> Result<&1, &1, String, String>:
  match m:
    case None{}:
      Fail{"malformed EncryptedExtensions"}
    case Some{Seen{versions, share, alpn}}:
      alpn.first(alpn)

# the ALPN protocol the server picked, "" when it sent no ALPN extension. It fails when the
# extension block or the protocol list doesn't parse.
def encrypted_extensions(+body: List<&2, U32>) -> Result<&1, &1, String, String>:
  ee.alpn(ee.seen(body, ee.ok(body)))

# Certificate
# -----------

# the certificate entry at the front of a buffer, when the buffer holds all of it
type Cd is Data:
  Cd.one{der: List<&2, U32>, after: List<&2, U32>, have: Nat}
  Cd.end{}
  Cd.bad{}

# the bytes one entry takes: a 3-byte certificate length, the DER, a 2-byte extension
# length and the extensions (RFC 8446 4.4.2)
def cd.need(+buf: List<&2, U32>) -> Nat:
  Nat.add(5n, Nat.add(U32.to_nat(Bytes.get.be(buf, 3n)), U32.to_nat(Bytes.get.be(Bytes.drop(buf, Nat.add(3n, U32.to_nat(Bytes.get.be(buf, 3n)))), 2n))))

def cd.one(+buf: List<&2, U32>, +have: Nat) -> Cd:
  +need = cd.need(buf)
  +n = U32.to_nat(Bytes.get.be(buf, 3n))
  Cd.one{Bytes.take(Bytes.drop(buf, 3n), n), Bytes.drop(buf, need), Nat.sub(have, need)}

def cd.fits(+buf: List<&2, U32>, +have: Nat) -> Cd:
  Bool.pick(Cd, Nat.is_le(cd.need(buf), have), cd.one(buf, have), Cd.bad{})

def cert.of(+buf: List<&2, U32>, +have: Nat) -> Cd:
  Bool.pick(Cd, Nat.is_eq(have, 0n), Cd.end{}, cd.fits(buf, have))

type Certs is Data:
  Certs.more{cd: Cd, buf: List<&2, U32>, left: Nat, acc: List<&2, List<&2, U32>>}

def cert.give(st: Certs) -> Result<&1, &1, String, List<&2, List<&2, U32>>>:
  match st:
    case Certs.more{cd, buf, left, acc}:
      Done{List.reverse(&2, List<&2, U32>, acc)}

def cert.go(fuel: Nat, st: Certs) -> Result<&1, &1, String, List<&2, List<&2, U32>>>:
  match fuel st:
    case 0n s:
      cert.give(s)
    case 1n+p Certs.more{Cd.end{}, buf, left, acc}:
      Done{List.reverse(&2, List<&2, U32>, acc)}
    case 1n+p Certs.more{Cd.bad{}, buf, left, acc}:
      Fail{"malformed certificate entry"}
    case 1n+p Certs.more{Cd.one{der, +after, +have}, buf, left, acc}:
      cert.go(p, Certs.more{cert.of(after, have), after, have, der <> acc})

def cert.entries(+xs: List<&2, U32>) -> Result<&1, &1, String, List<&2, List<&2, U32>>>:
  +have = U32.to_nat(Bytes.len(xs))
  cert.go(have, Certs.more{cert.of(xs, have), xs, have, Nil{}})

# the certificate list of a Certificate body, when it accounts for the whole body
def cert.ok(+body: List<&2, U32>) -> Bool:
  +ctx = U32.to_nat(Bytes.get.be(body, 1n))
  +at = Nat.add(ctx, 4n)
  +n = U32.to_nat(Bytes.len(body))
  Bool.and(Nat.is_le(at, n), Nat.is_eq(Nat.add(U32.to_nat(Bytes.get.be(Bytes.drop(body, Nat.add(ctx, 1n)), 3n)), at), n))

def cert.list(+body: List<&2, U32>, good: Bool) -> Result<&1, &1, String, List<&2, List<&2, U32>>>:
  match good:
    case False{}:
      Fail{"malformed Certificate"}
    case True{}:
      cert.entries(Bytes.drop(body, Nat.add(U32.to_nat(Bytes.get.be(body, 1n)), 4n)))

# the certificate DERs, leaf first (per-certificate extensions skipped)
def certificate(+body: List<&2, U32>) -> Result<&1, &1, String, List<&2, List<&2, U32>>>:
  cert.list(body, cert.ok(body))

# CertificateVerify
# -----------------

type Verify is Data:
  Verify{scheme: U32, sig: List<&2, U32>}

# the signature is a 2-byte length and that many bytes, and it is the rest of the body
def cv.ok(+body: List<&2, U32>) -> Bool:
  Bool.and(U32.is_le(4, Bytes.len(body)), U32.is_eq(U32.add(Bytes.get.be(Bytes.drop(body, 2n), 2n), 4), Bytes.len(body)))

def cv.of(+body: List<&2, U32>, good: Bool) -> Result<&1, &1, String, Verify>:
  match good:
    case False{}:
      Fail{"malformed CertificateVerify"}
    case True{}:
      Done{Verify{Bytes.get.be(body, 2n), Bytes.take(Bytes.drop(body, 4n), U32.to_nat(Bytes.get.be(Bytes.drop(body, 2n), 2n)))}}

# the scheme and the signature of a CertificateVerify (RFC 8446 4.4.3)
def certificate_verify(+body: List<&2, U32>) -> Result<&1, &1, String, Verify>:
  cv.of(body, cv.ok(body))

# Alerts
# ------

# the descriptions of RFC 8446 6.2, "" for a code it doesn't name
def alert.name.of(c: Nat) -> String:
  match c:
    case 0n:
      "close_notify"
    case 10n:
      "unexpected_message"
    case 20n:
      "bad_record_mac"
    case 22n:
      "record_overflow"
    case 40n:
      "handshake_failure"
    case 42n:
      "bad_certificate"
    case 43n:
      "unsupported_certificate"
    case 44n:
      "certificate_revoked"
    case 45n:
      "certificate_expired"
    case 46n:
      "certificate_unknown"
    case 47n:
      "illegal_parameter"
    case 48n:
      "unknown_ca"
    case 49n:
      "access_denied"
    case 50n:
      "decode_error"
    case 51n:
      "decrypt_error"
    case 70n:
      "protocol_version"
    case 71n:
      "insufficient_security"
    case 80n:
      "internal_error"
    case 86n:
      "inappropriate_fallback"
    case 90n:
      "user_canceled"
    case 109n:
      "missing_extension"
    case 110n:
      "unsupported_extension"
    case 112n:
      "unrecognized_name"
    case 113n:
      "bad_certificate_status_response"
    case 115n:
      "unknown_psk_identity"
    case 116n:
      "certificate_required"
    case 120n:
      "no_application_protocol"
    case _:
      ""

def alert.name(+code: U32) -> String:
  alert.name.of(U32.to_nat(code))

# the name, with the code after it for anything but a warning and for a code the RFC
# doesn't name, whose number is the only thing we know
def alert.line.if(+level: U32, +code: U32, +name: String, empty: Bool) -> String:
  match empty:
    case True{}:
      "unknown (" ++ U32.show(code) ++ ")"
    case False{}:
      Bool.pick(String, U32.is_eq(level, 1), name, name ++ " (" ++ U32.show(code) ++ ")")

def alert.line(+level: U32, +code: U32) -> String:
  +name = alert.name(code)
  alert.line.if(level, code, name, String.is_empty(name))

def alert.text(+body: List<&2, U32>, good: Bool) -> String:
  match good:
    case False{}:
      "malformed alert"
    case True{}:
      alert.line(Bytes.get.be(body, 1n), Bytes.get.be(Bytes.drop(body, 1n), 1n))

# an alert's two bytes as text: "close_notify", "handshake_failure (40)", ..
def alert(+body: List<&2, U32>) -> String:
  alert.text(body, U32.is_eq(Bytes.len(body), 2))

# TLSInnerPlaintext
# -----------------

# the last non-zero byte of a reversed plaintext: nothing, padding, or the content type
type Last is Data:
  Last.none{}
  Last.zero{rest: List<&2, U32>}
  Last.ctype{ctype: U32, rest: List<&2, U32>}

def inner.last(+r: List<&2, U32>) -> Last:
  Bool.pick(Last, U32.is_eq(Bytes.len(r), 0), Last.none{}, Bool.pick(Last, U32.is_eq(Bytes.get.be(r, 1n), 0), Last.zero{Bytes.drop(r, 1n)}, Last.ctype{Bytes.get.be(r, 1n), Bytes.drop(r, 1n)}))

def inner.give(st: Last) -> Maybe<&2, Rec>:
  match st:
    case Last.none{}:
      None{}
    case Last.zero{rest}:
      None{}
    case Last.ctype{ctype, rest}:
      Some{Rec{ctype, Bytes.rev(rest)}}

def inner.go(fuel: Nat, st: Last) -> Maybe<&2, Rec>:
  match fuel st:
    case 0n s:
      inner.give(s)
    case 1n+p Last.none{}:
      None{}
    case 1n+p Last.zero{rest}:
      inner.go(p, inner.last(rest))
    case 1n+p Last.ctype{ctype, rest}:
      Some{Rec{ctype, Bytes.rev(rest)}}

# the content type and content of a TLSInnerPlaintext, with its zero padding stripped: the
# last non-zero byte is the real content type and everything before it is the content
# (RFC 8446 5.4). None when it is all zeros, which is padding with no content at all.
def inner(+plain: List<&2, U32>) -> Maybe<&2, Rec>:
  inner.go(U32.to_nat(Bytes.len(plain)), inner.last(Bytes.rev(plain)))
