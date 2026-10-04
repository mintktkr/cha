# offline checks for lib/chaki/tls.bend. The vectors are RFC 8448 3 (Simple
# 1-RTT), copied verbatim: the client's key, the ClientHello and ServerHello, the
# server's encrypted flight, the key schedule's secrets, the client Finished record,
# one ticket, one application record each way and the server's close_notify. The
# trace is replayed through hs.over (the ClientHello as recorded, since ours would
# offer different extensions) and hs.input, exactly as printed. Tampered records and
# refused trust must fail, and the edges (empty input, wrong order, alerts, a
# HelloRetryRequest, KeyUpdate, close_notify, chunked sends) are covered too.
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T
import ../lib/chaki/sha2.bend as Sha2
import ../lib/chaki/aes.bend as Aes
import ../lib/chaki/tlsmsg.bend as Tls
import ../lib/chaki/x25519.bend as X
import ../lib/chaki/tls.bend as H

# The vectors
# -----------

# [0] the client's x25519 private key, [1] its public key, [15] the shared secret
def v.priv() -> List<&2, U32>:
  Bytes.of_hex("49af42ba7f7994852d713ef2784bcbcaa7911de26adc5642cb634540e7ea5005")

def v.client.pub() -> List<&2, U32>:
  Bytes.of_hex("99381de560e4bd43d23d8e435a7dbafeb3c06e51c13cae4d5413691e529aaf2c")

def v.shared() -> List<&2, U32>:
  Bytes.of_hex("8bd4054fb55b9d63fdfbacf9f04b9f0d35e6d63f537563efd46272900f89492d")

# [2] the ClientHello handshake message, [9] the ServerHello one, [33] its record
def v.hello() -> List<&2, U32>:
  Bytes.of_hex("010000c00303cb34ecb1e78163ba1c38c6dacb196a6dffa21a8d9912ec18a2ef6283024dece7000006130113031302010000910000000b0009000006736572766572ff01000100000a00140012001d0017001800190100010101020103010400230000003300260024001d002099381de560e4bd43d23d8e435a7dbafeb3c06e51c13cae4d5413691e529aaf2c002b0003020304000d0020001e040305030603020308040805080604010501060102010402050206020202002d00020101001c00024001")

def v.sh.msg() -> List<&2, U32>:
  Bytes.of_hex("020000560303a6af06a4121860dc5e6e60249cd34c95930c8ac5cb1434dac155772ed3e2692800130100002e00330024001d0020c9828876112095fe66762bdbf7c672e156d6cc253b833df1dd69b1b04e751f0f002b00020304")

def v.sh.rec() -> List<&2, U32>:
  Bytes.of_hex("160303005a020000560303a6af06a4121860dc5e6e60249cd34c95930c8ac5cb1434dac155772ed3e2692800130100002e00330024001d0020c9828876112095fe66762bdbf7c672e156d6cc253b833df1dd69b1b04e751f0f002b00020304")

# the client's random as sent in [2]
def v.rand() -> List<&2, U32>:
  Bytes.of_hex("cb34ecb1e78163ba1c38c6dacb196a6dffa21a8d9912ec18a2ef6283024dece70")

# [20] and [24]: the client and server handshake traffic secrets
def v.chs() -> List<&2, U32>:
  Bytes.of_hex("b3eddb126e067f35a780b3abf45e2d8f3b1a950738f52e9600746a0e27a55a21")

def v.shs() -> List<&2, U32>:
  Bytes.of_hex("b67b7d690cc16c4e75e54213cb2d37b4e9c912bcded9105d42befd59d391ad38")

# [36] and [38]: the server handshake key and IV; [69] and [71]: the client's
def v.sh.key() -> List<&2, U32>:
  Bytes.of_hex("3fce516009c21727d0f2e4e86ee403bc")

def v.sh.iv() -> List<&2, U32>:
  Bytes.of_hex("5d313eb2671276ee13000b30")

def v.chs.key() -> List<&2, U32>:
  Bytes.of_hex("dbfaa693d1762c5b666af5d950258d01")

def v.chs.iv() -> List<&2, U32>:
  Bytes.of_hex("5bd3c71b836e0b76bb73265f")

# [18]: SHA-256(ClientHello .. ServerHello)
def v.hash.sh() -> List<&2, U32>:
  Bytes.of_hex("860c06edc07858ee8e78f0e7428c58edd6b43f2ca3e6e95f02ed063cf0e1cad8")

# [39] EncryptedExtensions, [40] Certificate and [41] CertificateVerify
def v.ee() -> List<&2, U32>:
  Bytes.of_hex("080000240022000a00140012001d00170018001901000101010201030104001c0002400100000000")

def v.cert() -> List<&2, U32>:
  Bytes.of_hex("0b0001b9000001b50001b0308201ac30820115a003020102020102300d06092a864886f70d01010b0500300e310c300a06035504031303727361301e170d3136303733303031323335395a170d3236303733303031323335395a300e310c300a0603550403130372736130819f300d06092a864886f70d010101050003818d0030818902818100b4bb498f8279303d980836399b36c6988c0c68de55e1bdb826d3901a2461eafd2de49a91d015abbc9a95137ace6c1af19eaa6af98c7ced43120998e187a80ee0ccb0524b1b018c3e0b63264d449a6d38e22a5fda430846748030530ef0461c8ca9d9efbfae8ea6d1d03e2bd193eff0ab9a8002c47428a6d35a8d88d79f7f1e3f0203010001a31a301830090603551d1304023000300b0603551d0f0404030205a0300d06092a864886f70d01010b05000381810085aad2a0e5b9276b908c65f73a7267170618a54c5f8a7b337d2df7a594365417f2eae8f8a58c8f8172f9319cf36b7fd6c55b80f21a03015156726096fd335e5e67f2dbf102702e608ccae6bec1fc63a42a99be5c3eb7107c3c54e9b9eb2bd5203b1c3b84e0a8b2f759409ba3eac9d91d402dcc0cc8f8961229ac9187b42b4de10000")

def v.cv() -> List<&2, U32>:
  Bytes.of_hex("0f000084080400805a747c5d88fa9bd2e55ab085a61015b7211f824cd484145ab3ff52f1fda8477b0b7abc90db78e2d33a5c141a078653fa6bef780c5ea248eeaaa785c4f394cab6d30bbe8d4859ee511f602957b15411ac027671459e46445c9ea58c181e818e95b8c3fb0bf3278409d3be152a3da5043e063dda65cdf5aea20d53dfacd42f74f3")

# the certificate DER inside [40], and the signature inside [41]
def v.der() -> List<&2, U32>:
  Bytes.of_hex("308201ac30820115a003020102020102300d06092a864886f70d01010b0500300e310c300a06035504031303727361301e170d3136303733303031323335395a170d3236303733303031323335395a300e310c300a0603550403130372736130819f300d06092a864886f70d010101050003818d0030818902818100b4bb498f8279303d980836399b36c6988c0c68de55e1bdb826d3901a2461eafd2de49a91d015abbc9a95137ace6c1af19eaa6af98c7ced43120998e187a80ee0ccb0524b1b018c3e0b63264d449a6d38e22a5fda430846748030530ef0461c8ca9d9efbfae8ea6d1d03e2bd193eff0ab9a8002c47428a6d35a8d88d79f7f1e3f0203010001a31a301830090603551d1304023000300b0603551d0f0404030205a0300d06092a864886f70d01010b05000381810085aad2a0e5b9276b908c65f73a7267170618a54c5f8a7b337d2df7a594365417f2eae8f8a58c8f8172f9319cf36b7fd6c55b80f21a03015156726096fd335e5e67f2dbf102702e608ccae6bec1fc63a42a99be5c3eb7107c3c54e9b9eb2bd5203b1c3b84e0a8b2f759409ba3eac9d91d402dcc0cc8f8961229ac9187b42b4de1")

def v.sig() -> List<&2, U32>:
  Bytes.of_hex("5a747c5d88fa9bd2e55ab085a61015b7211f824cd484145ab3ff52f1fda8477b0b7abc90db78e2d33a5c141a078653fa6bef780c5ea248eeaaa785c4f394cab6d30bbe8d4859ee511f602957b15411ac027671459e46445c9ea58c181e818e95b8c3fb0bf3278409d3be152a3da5043e063dda65cdf5aea20d53dfacd42f74f3")

# [49] the server's whole encrypted flight in one record
def v.flight() -> List<&2, U32>:
  Bytes.of_hex("17030302a2d1ff334a56f5bff6594a07cc87b580233f500f45e489e7f33af35edf7869fcf40aa40aa2b8ea73f848a7ca07612ef9f945cb960b4068905123ea78b111b429ba9191cd05d2a389280f526134aadc7fc78c4b729df828b5ecf7b13bd9aefb0e57f271585b8ea9bb355c7c79020716cfb9b1183ef3ab20e37d57a6b9d7477609aee6e122a4cf51427325250c7d0e509289444c9b3a648f1d71035d2ed65b0e3cdd0cbae8bf2d0b227812cbb360987255cc744110c453baa4fcd610928d809810e4b7ed1a8fd991f06aa6248204797e36a6a73b70a2559c09ead686945ba246ab66e5edd8044b4c6de3fcf2a89441ac66272fd8fb330ef8190579b3684596c960bd596eea520a56a8d650f563aad27409960dca63d3e688611ea5e22f4415cf9538d51a200c27034272968a264ed6540c84838d89f72c24461aad6d26f59ecaba9acbbb317b66d902f4f292a36ac1b639c637ce343117b659622245317b49eeda0c6258f100d7d961ffb138647e92ea330faeea6dfa31c7a84dc3bd7e1b7a6c7178af36879018e3f252107f243d243dc7339d5684c8b0378bf30244da8c87c843f5e56eb4c5e8280a2b48052cf93b16499a66db7cca71e4599426f7d461e66f99882bd89fc50800becca62d6c74116dbd2972fda1fa80f85df881edbe5a37668936b335583b599186dc5c6918a396fa48a181d6b6fa4f9d62d513afbb992f2b992f67f8afe67f76913fa388cb5630c8ca01e0c65d11c66a1e2ac4c85977b7c7a6999bbf10dc35ae69f5515614636c0b9b68c19ed2e31c0b3b66763038ebba42f3b38edc0399f3a9f23faa63978c317fc9fa66a73f60f0504de93b5b845e275592c12335ee340bbc4fddd502784016e4b3be7ef04dda49f4b440a30cb5d2af939828fd4ae3794e44f94df5a631ede42c1719bfdabf0253fe5175be898e750edc53370d2b")

# [53] and [57]: the client and server application traffic secrets
def v.cap() -> List<&2, U32>:
  Bytes.of_hex("9e40646ce79a7f9dc05af8889bce6552875afa0b06df0087f792ebb7c17504a5")

def v.sap() -> List<&2, U32>:
  Bytes.of_hex("a11af9f05531f856ad47116b45a950328204b4f44bfb6b3a4b4f1f3fcb631643")

# [64] and [66]: the server application key and IV; [86] and [88]: the client's
def v.sap.key() -> List<&2, U32>:
  Bytes.of_hex("9f02283b6c9c07efc26bb9f2ac92e356")

def v.sap.iv() -> List<&2, U32>:
  Bytes.of_hex("cf782b88dd83549aadf1e984")

def v.cap.key() -> List<&2, U32>:
  Bytes.of_hex("17422dda596ed5d9acd890e3c63f5051")

def v.cap.iv() -> List<&2, U32>:
  Bytes.of_hex("5b78923dee08579033e523d9")

# [83] the client's Finished record, [99] a ticket, [100]-[103] application
# data with its records (the client sends first), [104]-[107] the close_notifies
def v.cfin.rec() -> List<&2, U32>:
  Bytes.of_hex("170303003575ec4dc238cce60b298044a71e219c56cc77b0517fe9b93c7a4bfc44d87f38f80338ac98fc46deb384bd1caeacab6867d726c40546")

def v.ticket() -> List<&2, U32>:
  Bytes.of_hex("17030300de3a6b8f90414a97d6959c3487680de5134a2b240e6cffac116e95d41d6af8f6b580dcf3d11d63c758db289a015940252f55713e061dc13e078891a38efbcf5753ad8ef170ad3c7353d16d9da773b9ca7f2b9fa1b6c0d4a3d03f75e09c30ba1e62972ac46f75f7b981be63439b2999ce13064615139891d5e4c5b406f16e3fc181a77ca475840025db2f0a77f81b5ab05b94c01346755f69232c86519d86cbeeac87aac347d143f9605d64f650db4d023e70e952ca49fe5137121c74bc2697687e248746d6df353005f3bce18696129c8153556b3b6c6779b37bf15985684f")

def v.app() -> List<&2, U32>:
  Bytes.of_hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f3031")

def v.app.rec() -> List<&2, U32>:
  Bytes.of_hex("17030300432e937e11ef4ac740e538ad36005fc4a46932fc3225d05f82aa1b36e30efaf97d90e6dffc602dcb501a59a8fcc49c4bf2e5f0a21c0047c2abf332540dd032e167c2955d")

def v.close.rec() -> List<&2, U32>:
  Bytes.of_hex("1703030013b58fd67166ebf599d24720cfbe7efa7a8864a9")

# [101] the client's application_data record, [105] its close_notify: what
# hs.send and hs.close must byte-match once the transcript does
def v.cli.rec() -> List<&2, U32>:
  Bytes.of_hex("1703030043a23f7054b62c94d0affafe8228ba55cbefacea42f914aa66bcab3f2b9819a8a5b46b395bd54a9a20441e2b62974e1f5a6292a2977014bd1e3deae63aeebb21694915e4")

def v.cli.close() -> List<&2, U32>:
  Bytes.of_hex("1703030013c9872760655666b74d7ff1153efd6db6d0b0e3")

def v.spaces() -> List<&2, U32>:
  Sha2.fill(32, 64n)

def v.tx.cv.hash() -> List<&2, U32>:
  Sha2.hash(Sha2.S256{}, Bytes.cat(v.hello(), Bytes.cat(v.sh.msg(), Bytes.cat(v.ee(), v.cert()))))

# the CertificateVerify's signed content: 64 spaces, the context string, a zero
# byte and the transcript hash up to the Certificate
def v.signed() -> List<&2, U32>:
  Bytes.cat(v.spaces(), Bytes.cat(Bytes.of_ascii("TLS 1.3, server CertificateVerify"), Bytes.cat([0], v.tx.cv.hash())))

# Reading the core
# ----------------

# the first event's name, and how many events there are
def ev.name(e: H.Reply) -> String:
  match e:
    case H.Reply.need{}:
      "need"
    case H.Reply.check{certs, scheme, signed, sig}:
      "check"
    case H.Reply.ready{}:
      "ready"
    case H.Reply.data{bytes}:
      "data"
    case H.Reply.closed{}:
      "closed"
    case H.Reply.failed{why}:
      "failed"

def evs.first(evs: List<&2, H.Reply>) -> String:
  match evs:
    case Nil{}:
      "none"
    case e <> t:
      ev.name(e)

def evs.len.go(evs: List<&2, H.Reply>, n: U32) -> U32:
  match evs:
    case Nil{}:
      n
    case e <> t:
      evs.len.go(t, (n + 1 : U32))

def evs.len(evs: List<&2, H.Reply>) -> U32:
  evs.len.go(evs, 0)

# the bytes of a single Data event, and nothing otherwise
def ev.data.of(e: H.Reply) -> List<&2, U32>:
  match e:
    case H.Reply.data{bytes}:
      bytes
    case _:
      Nil{}

def evs.data(evs: List<&2, H.Reply>) -> List<&2, U32>:
  match evs:
    case Nil{}:
      Nil{}
    case e <> t:
      ev.data.of(e)

# the transcript, the handshake and application traffic keys, and the proof
def st.tx(+st: H.Hs) -> List<&2, U32>:
  H.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
  tx

def st.rd(+st: H.Hs) -> H.Traffic:
  H.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
  H.Keys{aead, master, rd, wr, ard, awr} = keys
  rd

def st.wr(+st: H.Hs) -> H.Traffic:
  H.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
  H.Keys{aead, master, rd, wr, ard, awr} = keys
  wr

def tr.secret(t: H.Traffic) -> List<&2, U32>:
  H.Traffic{secret, k, iv, n} = t
  secret

def tr.key(t: H.Traffic) -> List<&2, U32>:
  H.Traffic{secret, k, iv, n} = t
  k

def tr.iv(t: H.Traffic) -> List<&2, U32>:
  H.Traffic{secret, k, iv, n} = t
  iv

def st.proof(+st: H.Hs) -> H.Proof:
  H.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
  proof

def pr.certs(p: H.Proof) -> List<&2, List<&2, U32>>:
  H.Proof{certs, scheme, signed, sig} = p
  certs

def pr.scheme(p: H.Proof) -> U32:
  H.Proof{certs, scheme, signed, sig} = p
  scheme

def pr.signed(p: H.Proof) -> List<&2, U32>:
  H.Proof{certs, scheme, signed, sig} = p
  signed

def pr.sig(p: H.Proof) -> List<&2, U32>:
  H.Proof{certs, scheme, signed, sig} = p
  sig

def certs.len.go(certs: List<&2, List<&2, U32>>, n: U32) -> U32:
  match certs:
    case Nil{}:
      n
    case c <> t:
      certs.len.go(t, (n + 1 : U32))

def certs.first(certs: List<&2, List<&2, U32>>) -> List<&2, U32>:
  match certs:
    case Nil{}:
      Nil{}
    case c <> t:
      c

# secrets are compared with eq, so only ok or FAIL reaches the output, never the
# bytes themselves
def is.eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  Bytes.eq(a, b)

# flipping the last byte: any authenticated record must then fail
def tamper(+xs: List<&2, U32>) -> List<&2, U32>:
  +n = Nat.sub(U32.to_nat(Bytes.len(xs)), 1n)
  Bytes.cat(Bytes.take(xs, n), [(Bytes.get.be(xs, n) .^. 1 : U32)])

# a KeyUpdate record under a key: update_requested when byte is 1 (RFC 8446 4.6.3)
def ku.nonce(+iv: List<&2, U32>, n: U32) -> List<&2, U32>:
  Bytes.cat(Bytes.take(iv, 4n), Bytes.xor(Bytes.drop(iv, 4n), Bytes.cat(Bytes.be32(0), Bytes.be32(n))))

def ku.rec(+key: List<&2, U32>, +iv: List<&2, U32>, seq: U32, byte: U32) -> List<&2, U32>:
  +inner = Bytes.cat(Tls.handshake(24, [byte]), [22])
  +aad = Tls.record.head(23, (Bytes.len(inner) + 16 : U32))
  Tls.record(23, Aes.seal(key, ku.nonce(iv, seq), aad, inner))

# application bytes under a key at a sequence number
def app.rec(+key: List<&2, U32>, +iv: List<&2, U32>, seq: U32, +data: List<&2, U32>) -> List<&2, U32>:
  +inner = Bytes.cat(data, [23])
  +aad = Tls.record.head(23, (Bytes.len(inner) + 16 : U32))
  Tls.record(23, Aes.seal(key, ku.nonce(iv, seq), aad, inner))

# the next application traffic secret of a KeyUpdate (RFC 8446 7.2)
def updated(+secret: List<&2, U32>) -> List<&2, U32>:
  Sha2.expand_label(Sha2.S256{}, secret, "traffic upd", Nil{}, 32)

def next.key(+secret: List<&2, U32>) -> List<&2, U32>:
  Sha2.expand_label(Sha2.S256{}, updated(secret), "key", Nil{}, 16)

def next.iv(+secret: List<&2, U32>) -> List<&2, U32>:
  Sha2.expand_label(Sha2.S256{}, updated(secret), "iv", Nil{}, 12)

# one outer record opened with a key: the inner plaintext and its content type, or
# nothing and type 999 when the tag doesn't check
def cut.at(f: Tls.First) -> Tls.Rec:
  match f:
    case Tls.First.rec{rec, after, have}:
      rec
    case Tls.First.short{}:
      Tls.Rec{0, Nil{}}
    case Tls.First.bad{}:
      Tls.Rec{0, Nil{}}

def cut.one(+buf: List<&2, U32>) -> Tls.Rec:
  cut.at(Tls.first.of(buf, U32.to_nat(Bytes.len(buf))))

def open.m(m: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  match m:
    case None{}:
      Nil{}
    case Some{v}:
      v

def open.r(m: Maybe<&2, Tls.Rec>) -> List<&2, U32> & U32:
  match m:
    case None{}:
      (Nil{}, 999)
    case Some{Tls.Rec{ctype, body}}:
      (body, ctype)

def probe.rec(+key: List<&2, U32>, +iv: List<&2, U32>, seq: U32, r: Tls.Rec) -> List<&2, U32> & U32:
  Tls.Rec{+ctype, +body} = r
  open.r(Tls.inner(open.m(Aes.open(key, ku.nonce(iv, seq), Tls.record.head(ctype, Bytes.len(body)), body))))

def probe.open(+key: List<&2, U32>, +iv: List<&2, U32>, seq: U32, +bytes: List<&2, U32>) -> List<&2, U32> & U32:
  probe.rec(key, iv, seq, cut.one(bytes))

# SHA-256("HelloRetryRequest"): a ServerHello with this random is one (RFC 8446 4.1.3)
def hrr.random() -> List<&2, U32>:
  Bytes.of_hex("cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c")

def hrr.msg() -> List<&2, U32>:
  +body = Bytes.cat(Bytes.take(Bytes.drop(v.sh.msg(), 4n), 2n), Bytes.cat(hrr.random(), Bytes.drop(Bytes.drop(v.sh.msg(), 4n), 34n)))
  Tls.handshake(2, body)

# Answer triples
# --------------

# an answer is used once, so each component has its own def: a match only
# scrutinizes a parameter
def two.fst(p: H.Hs & List<&2, U32>) -> H.Hs:
  match p:
    case (fst, snd):
      fst

def two.snd(p: H.Hs & List<&2, U32>) -> List<&2, U32>:
  match p:
    case (fst, snd):
      snd

def got.plain(p: List<&2, U32> & U32) -> List<&2, U32>:
  match p:
    case (plain, ctype):
      plain

def got.type(p: List<&2, U32> & U32) -> U32:
  match p:
    case (plain, ctype):
      ctype

def cat.go(+r: List<&2, String>, b: List<&2, String>) -> List<&2, String>:
  match r:
    case Nil{}:
      b
    case l <> t:
      cat.go(t, l <> b)

# lines in print order
def cat.lines(+a: List<&2, String>, b: List<&2, String>) -> List<&2, String>:
  cat.go(List.reverse(&2, String, a), b)

# The stages
# ----------

# each step matches the last answer and feeds the next bytes, with the report
# lines accumulating after what came before
def start.lines() -> List<&2, String>:
  +ch = two.snd(H.hs.start(v.rand(), Bytes.zeros(32n), v.priv(), ""))
  [T.ok("RFC 8448 3 public", is.eq(X.public(v.priv()), v.client.pub())),
    T.eq("start record type", U32.show(Bytes.get.be(ch, 1n)), "22"),
    T.eq("start hello type", U32.show(Bytes.get.be(Bytes.drop(ch, 5n), 1n)), "1"),
    T.ok("start random", is.eq(Bytes.take(Bytes.drop(ch, 11n), 32n), v.rand()))]

def data.lines(p: List<&2, U32> & List<&2, H.Reply>, +first: String, +second: String) -> List<&2, String>:
  match p:
    case (out, +evs):
      [T.eq(first, evs.first(evs), "data"),
        T.ok(second, is.eq(evs.data(evs), v.app()))]

def ticket.lines(p: List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (out, evs):
      [T.eq("ticket event", evs.first(evs), "need"),
        T.eq("ticket out", U32.show(Bytes.len(out)), "0")]

def quiet.lines(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (st, (out, evs)):
      [T.eq("keyupdate quiet", evs.first(evs), "need"),
        T.eq("keyupdate quiet out", U32.show(Bytes.len(out)), "0")]

def ku.here.lines(p: List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (+out, evs):
      [T.eq("keyupdate event", evs.first(evs), "need"),
        T.eq("keyupdate answer len", U32.show(Bytes.len(out)), "27"),
        T.hex("keyupdate answer", got.plain(probe.open(v.cap.key(), v.cap.iv(), 0, out)), "1800000100"),
        T.eq("keyupdate answer type", U32.show(got.type(probe.open(v.cap.key(), v.cap.iv(), 0, out))), "22")]

def bad.ku() -> List<&2, U32>:
  +inner = Bytes.cat(Tls.handshake(24, [0, 0]), [22])
  Tls.record(23, Aes.seal(next.key(v.sap()), ku.nonce(next.iv(v.sap()), 0), Tls.record.head(23, (Bytes.len(inner) + 16 : U32)), inner))

def s.ku.bad(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (st, (out, evs)):
      [T.eq("keyupdate bad", evs.first(evs), "failed")]

def s.ku.rot(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (st, rest):
      data.lines(rest, "rotated event", "rotated bytes")

def s.ku(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (+st, rest):
      cat.lines(ku.here.lines(rest),
        cat.lines(s.ku.rot(H.hs.input(st, app.rec(next.key(v.sap()), next.iv(v.sap()), 0, v.app()))),
          s.ku.bad(H.hs.input(st, bad.ku()))))

def s.close(p: H.Hs & List<&2, U32> & List<&2, H.Reply>, acc: List<&2, String>) -> List<&2, String>:
  match p:
    case (st, (out, evs)):
      cat.lines(acc, [T.eq("close event", evs.first(evs), "closed")])

def s.app(p: H.Hs & List<&2, U32> & List<&2, H.Reply>, acc: List<&2, String>) -> List<&2, String>:
  match p:
    case (+st, rest):
      s.close(H.hs.input(st, v.close.rec()),
        cat.lines(acc, cat.lines(data.lines(rest, "app event", "app bytes"),
          cat.lines(s.ku(H.hs.input(st, ku.rec(v.sap.key(), v.sap.iv(), 2, 1))),
            quiet.lines(H.hs.input(st, ku.rec(v.sap.key(), v.sap.iv(), 2, 0)))))))

def s.tampered.app(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (st, (out, evs)):
      [T.eq("tampered app", evs.first(evs), "failed")]

def s.ticket(p: H.Hs & List<&2, U32> & List<&2, H.Reply>, acc: List<&2, String>) -> List<&2, String>:
  match p:
    case (+st, rest):
      s.app(H.hs.input(st, v.app.rec()),
        cat.lines(acc, cat.lines(ticket.lines(rest), s.tampered.app(H.hs.input(st, tamper(v.app.rec()))))))

def ping.lines(+st: H.Hs) -> List<&2, String>:
  [T.hex("send round-trips", got.plain(probe.open(v.cap.key(), v.cap.iv(), 0, two.snd(H.hs.send(st, Bytes.of_ascii("ping"))))), "70696e67"),
    T.eq("send type", U32.show(got.type(probe.open(v.cap.key(), v.cap.iv(), 0, two.snd(H.hs.send(st, Bytes.of_ascii("ping")))))), "23")]

def big.lines(st: H.Hs) -> List<&2, String>:
  +big = Sha2.fill(97, 16385n)
  +out = two.snd(H.hs.send(st, big))
  [T.eq("big len", U32.show(Bytes.len(out)), "16429"),
    T.ok("big round-trips", is.eq(Bytes.cat(got.plain(probe.open(v.cap.key(), v.cap.iv(), 0, Bytes.take(out, 16406n))), got.plain(probe.open(v.cap.key(), v.cap.iv(), 1, Bytes.drop(out, 16406n)))), big))]

def send.lines(+st: H.Hs) -> List<&2, String>:
  +sout = two.snd(H.hs.send(st, v.app()))
  +sst = two.fst(H.hs.send(st, v.app()))
  cat.lines([T.ok("send matches", is.eq(sout, v.cli.rec())),
    T.ok("close matches", is.eq(H.hs.close(sst), v.cli.close()))],
    cat.lines(ping.lines(st), big.lines(st)))

def ready.lines(p: List<&2, U32> & List<&2, H.Reply>, +st: H.Hs) -> List<&2, String>:
  match p:
    case (out, evs):
      [T.eq("trusted event", evs.first(evs), "ready"),
        T.ok("client finished", is.eq(out, Bytes.cat(Tls.record(20, [1]), v.cfin.rec()))),
        T.ok("trusted c ap", is.eq(tr.secret(st.wr(st)), v.cap())),
        T.ok("trusted s ap", is.eq(tr.secret(st.rd(st)), v.sap())),
        T.ok("trusted s key", is.eq(tr.key(st.rd(st)), v.sap.key())),
        T.ok("trusted s iv", is.eq(tr.iv(st.rd(st)), v.sap.iv())),
        T.ok("trusted c key", is.eq(tr.key(st.wr(st)), v.cap.key())),
        T.ok("trusted c iv", is.eq(tr.iv(st.wr(st)), v.cap.iv()))]

def s.late.ccs(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (st, (out, evs)):
      [T.eq("ccs late", evs.first(evs), "failed")]

def s.tampered.ticket(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (st, (out, evs)):
      [T.eq("tampered ticket", evs.first(evs), "failed")]

def s.ready(p: H.Hs & List<&2, U32> & List<&2, H.Reply>, acc: List<&2, String>) -> List<&2, String>:
  match p:
    case (+st, rest):
      s.ticket(H.hs.input(st, v.ticket()),
        cat.lines(acc, cat.lines(ready.lines(rest, st),
          cat.lines(s.tampered.ticket(H.hs.input(st, tamper(v.ticket()))),
            cat.lines(s.late.ccs(H.hs.input(st, Tls.record(20, [1]))),
              send.lines(st))))))

def flight.lines(p: List<&2, U32> & List<&2, H.Reply>, +st: H.Hs) -> List<&2, String>:
  match p:
    case (out, +evs):
      [T.eq("flight event", evs.first(evs), "check"),
        T.eq("flight events", U32.show(evs.len(evs)), "1"),
        T.eq("flight out", U32.show(Bytes.len(out)), "0"),
        T.eq("check certs", U32.show(certs.len.go(pr.certs(st.proof(st)), 0)), "1"),
        T.ok("check cert", is.eq(certs.first(pr.certs(st.proof(st))), v.der())),
        T.eq("check scheme", U32.show(pr.scheme(st.proof(st))), "2052"),
        T.ok("check signed", is.eq(pr.signed(st.proof(st)), v.signed())),
        T.ok("check sig", is.eq(pr.sig(st.proof(st)), v.sig()))]

def s.refused(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (st, (out, evs)):
      [T.eq("refused event", evs.first(evs), "failed")]

def s.flight(p: H.Hs & List<&2, U32> & List<&2, H.Reply>, acc: List<&2, String>) -> List<&2, String>:
  match p:
    case (+st, rest):
      s.ready(H.hs.trusted(st, True{}),
        cat.lines(acc, cat.lines(flight.lines(rest, st), s.refused(H.hs.trusted(st, False{})))))

def sh.lines(p: List<&2, U32> & List<&2, H.Reply>, +st: H.Hs) -> List<&2, String>:
  match p:
    case (out, +evs):
      [T.eq("serverhello event", evs.first(evs), "need"),
        T.eq("serverhello events", U32.show(evs.len(evs)), "1"),
        T.eq("serverhello out", U32.show(Bytes.len(out)), "0"),
        T.ok("serverhello transcript", is.eq(Sha2.hash(Sha2.S256{}, st.tx(st)), v.hash.sh())),
        T.ok("serverhello c hs", is.eq(tr.secret(st.wr(st)), v.chs())),
        T.ok("serverhello s hs", is.eq(tr.secret(st.rd(st)), v.shs())),
        T.ok("serverhello s key", is.eq(tr.key(st.rd(st)), v.sh.key())),
        T.ok("serverhello s iv", is.eq(tr.iv(st.rd(st)), v.sh.iv())),
        T.ok("serverhello c key", is.eq(tr.key(st.wr(st)), v.chs.key())),
        T.ok("serverhello c iv", is.eq(tr.iv(st.wr(st)), v.chs.iv()))]

def s.tampered(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (st, (out, evs)):
      [T.eq("tampered flight", evs.first(evs), "failed")]

def s.early(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (st, (out, evs)):
      [T.eq("early trusted event", evs.first(evs), "failed")]

def s.sh(p: H.Hs & List<&2, U32> & List<&2, H.Reply>, acc: List<&2, String>) -> List<&2, String>:
  match p:
    case (+st, rest):
      s.flight(H.hs.input(st, v.flight()),
        cat.lines(acc, cat.lines(sh.lines(rest, st),
          cat.lines(s.tampered(H.hs.input(st, tamper(v.flight()))),
            s.early(H.hs.trusted(st, True{}))))))

def edge.ev(p: H.Hs & List<&2, U32> & List<&2, H.Reply>, name: String, want: String) -> String:
  match p:
    case (st, (out, evs)):
      T.eq(name, evs.first(evs), want)

def edge.ccs3(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (st, (out, evs)):
      [T.eq("ccs then hello", evs.first(evs), "need")]

def edge.ccs2(p: H.Hs & List<&2, U32> & List<&2, H.Reply>) -> List<&2, String>:
  match p:
    case (st, rest):
      edge.ccs3(H.hs.input(st, v.sh.rec()))

def edge.lines(+st: H.Hs) -> List<&2, String>:
  cat.lines([edge.ev(H.hs.input(st, Nil{}), "empty event", "need"),
    edge.ev(H.hs.input(st, v.app.rec()), "app first", "failed"),
    edge.ev(H.hs.input(st, Tls.record(22, Tls.handshake(2, Nil{}))), "garbage hello", "failed"),
    edge.ev(H.hs.input(st, Tls.record(21, [2, 20])), "alert first", "failed"),
    edge.ev(H.hs.input(st, Tls.record(22, hrr.msg())), "retry fails", "failed"),
    edge.ev(H.hs.input(st, Tls.record(20, [1])), "ccs event", "need"),
    T.eq("send early", U32.show(Bytes.len(two.snd(H.hs.send(st, Bytes.of_ascii("x"))))), "0"),
    T.eq("close early", U32.show(Bytes.len(H.hs.close(st))), "0")],
    edge.ccs2(H.hs.input(st, Tls.record(20, [1]))))

def run() -> List<&2, String>:
  cat.lines(start.lines(),
    cat.lines(s.sh(H.hs.input(H.hs.over(v.hello(), v.priv()), v.sh.rec()), Nil{}),
      edge.lines(H.hs.over(v.hello(), v.priv()))))

def print.all(xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Nil{}:
      do IO<Unit>:
        return Unit{}
    case l <> t:
      do IO<Unit>:
        IO.print(l)
        print.all(t)

def main() -> IO(Unit):
  do IO<Unit>:
    print.all(run())
