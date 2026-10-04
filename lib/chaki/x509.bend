# x509: X.509 certificates, parsed. The structure a TLS client checks, in BearSSL's
# minimal shape: read one DER certificate, keep the bytes the signature covers, the two
# names, the validity, the key and the extensions that matter, and mark a critical
# extension the engine doesn't know. Signature checks, chain building and hostname
# matching are a later lane's job.
import Base
import ./bytes.bend as Bytes
import ./asn1.bend as Asn1

# der: the whole certificate. tbs: the TBSCertificate, header included, which the
# signature covers. sig_alg: the outer signatureAlgorithm OID. sig: the signature BIT
# STRING's bytes. issuer, subject: the raw DER of each Name, compared as bytes.
# key_alg: the SubjectPublicKeyInfo algorithm OID. key_curve: the namedCurve OID for
# id-ecPublicKey, else "". key: the subjectPublicKey BIT STRING's bytes. dns: the
# subjectAltName dNSName entries, lowercased. path_len and key_usage are 4294967295 when
# their extension is absent. unknown_critical: a critical extension outside the four the
# engine reads.
type Cert is Data:
  Cert{der: List<&2, U32>, tbs: List<&2, U32>, sig_alg: String, sig: List<&2, U32>,
       issuer: List<&2, U32>, subject: List<&2, U32>, not_before: U32, not_after: U32,
       key_alg: String, key_curve: String, key: List<&2, U32>, dns: List<&2, String>,
       ca: Bool, path_len: U32, key_usage: U32, unknown_critical: Bool}

# the extensions the engine reads, or the defaults when there are none
type Exts is Data:
  Exts{ca: Bool, path_len: U32, key_usage: U32, dns: List<&2, String>, unknown: Bool}

# a TBSCertificate's fields
type Tbs is Data:
  Tbs{issuer: List<&2, U32>, subject: List<&2, U32>, not_before: U32, not_after: U32,
      key_alg: String, key_curve: String, key: List<&2, U32>, ca: Bool, path_len: U32,
      key_usage: U32, dns: List<&2, String>, unknown: Bool}

# a SubjectPublicKeyInfo
type Spki is Data:
  Spki{key_alg: String, key_curve: String, key: List<&2, U32>}

# a Validity
type Validity is Data:
  Validity{not_before: U32, not_after: U32}

# Pieces of an element
# --------------------

def x509.tag.of(t: Asn1.Tlv) -> U32:
  match t:
    case Asn1.Tlv{tag, value, rest}:
      tag

def x509.value.of(t: Asn1.Tlv) -> List<&2, U32>:
  match t:
    case Asn1.Tlv{tag, value, rest}:
      value

def x509.rest.of(t: Asn1.Tlv) -> List<&2, U32>:
  match t:
    case Asn1.Tlv{tag, value, rest}:
      rest

# the DER of the first element of b, which ends where rest begins
def x509.raw(+b: List<&2, U32>, +rest: List<&2, U32>) -> List<&2, U32>:
  Bytes.take(b, Nat.sub(U32.to_nat(Bytes.len(b)), U32.to_nat(Bytes.len(rest))))

# a constructed value's elements; None for another tag or contents that don't parse
def x509.seq.if(ok: Bool, t: Asn1.Tlv) -> Maybe<&2, List<&2, Asn1.Tlv>>:
  match ok:
    case True{}:
      Asn1.items(x509.value.of(t))
    case False{}:
      None{}

def x509.seq(+t: Asn1.Tlv) -> Maybe<&2, List<&2, Asn1.Tlv>>:
  x509.seq.if(U32.is_eq(x509.tag.of(t), 48), t)

# OIDs
# ----

# an OID's dotted text; None for another tag
def x509.oid.of.if(ok: Bool, t: Asn1.Tlv) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{Asn1.oid(x509.value.of(t))}
    case False{}:
      None{}

def x509.oid.of(+t: Asn1.Tlv) -> Maybe<&2, String>:
  x509.oid.of.if(U32.is_eq(x509.tag.of(t), 6), t)

# an OID's dotted text, "" for another tag
def x509.oid.text.if(ok: Bool, t: Asn1.Tlv) -> String:
  match ok:
    case True{}:
      Asn1.oid(x509.value.of(t))
    case False{}:
      ""

def x509.oid.text(+t: Asn1.Tlv) -> String:
  x509.oid.text.if(U32.is_eq(x509.tag.of(t), 6), t)

# the algorithm OID at the front of an AlgorithmIdentifier's contents
def x509.alg.oid.tlv(m: Maybe<&2, Asn1.Tlv>) -> Maybe<&2, String>:
  match m:
    case Some{t}:
      x509.oid.of(t)
    case None{}:
      None{}

def x509.alg.oid(v: List<&2, U32>) -> Maybe<&2, String>:
  x509.alg.oid.tlv(Asn1.read(v))

# the second OID of an AlgorithmIdentifier, "" when there is none
def x509.curve.items(m: Maybe<&2, List<&2, Asn1.Tlv>>) -> String:
  match m:
    case Some{Con{first, Con{second, rest}}}:
      x509.oid.text(second)
    case _:
      ""

def x509.curve(v: List<&2, U32>) -> String:
  x509.curve.items(Asn1.items(v))

# the namedCurve of an id-ecPublicKey AlgorithmIdentifier, "" for another algorithm
def x509.curve.ec.if(ec: Bool, v: List<&2, U32>) -> String:
  match ec:
    case True{}:
      x509.curve(v)
    case False{}:
      ""

def x509.curve.of(+a: String, v: List<&2, U32>) -> String:
  x509.curve.ec.if(String.eq(a, "1.2.840.10045.2.1"), v)

# a BIT STRING's bytes; None for another tag, an empty string, or unused bits
def x509.bits.go(t: Asn1.Tlv) -> Bool:
  match t:
    case Asn1.Tlv{tag, +value, rest}:
      Bool.and(U32.is_eq(tag, 3), Bool.and(U32.is_ge(Bytes.len(value), 1), U32.is_zero(Bytes.get.be(value, 1n))))

def x509.bits.if(ok: Bool, t: Asn1.Tlv) -> Maybe<&2, List<&2, U32>>:
  match ok:
    case True{}:
      Some{Bytes.drop(x509.value.of(t), 1n)}
    case False{}:
      None{}

def x509.bits(+t: Asn1.Tlv) -> Maybe<&2, List<&2, U32>>:
  x509.bits.if(x509.bits.go(t), t)

def x509.time.of(t: Asn1.Tlv) -> Maybe<&2, U32>:
  match t:
    case Asn1.Tlv{tag, value, rest}:
      Asn1.time(tag, value)

# Validity
# --------

def x509.validity.times(nb: Asn1.Tlv, na: Asn1.Tlv) -> Maybe<&2, Validity>:
  do Maybe<&2, Validity>:
    a : U32 <- x509.time.of(nb)
    b : U32 <- x509.time.of(na)
    return Validity{a, b}

def x509.validity.m(m: Maybe<&2, List<&2, Asn1.Tlv>>) -> Maybe<&2, Validity>:
  match m:
    case Some{Con{nb, Con{na, Nil{}}}}:
      x509.validity.times(nb, na)
    case _:
      None{}

# the validity SEQUENCE's two times
def x509.validity(t: Asn1.Tlv) -> Maybe<&2, Validity>:
  x509.validity.m(x509.seq(t))

# SubjectPublicKeyInfo
# --------------------

def x509.spki.make(+alg: Asn1.Tlv, bits: Asn1.Tlv) -> Maybe<&2, Spki>:
  do Maybe<&2, Spki>:
    +a : String <- x509.alg.oid(x509.value.of(alg))
    k : List<&2, U32> <- x509.bits(bits)
    return Spki{a, x509.curve.of(a, x509.value.of(alg)), k}

def x509.spki.m(m: Maybe<&2, List<&2, Asn1.Tlv>>) -> Maybe<&2, Spki>:
  match m:
    case Some{Con{alg, Con{bits, Nil{}}}}:
      x509.spki.make(alg, bits)
    case _:
      None{}

# the algorithm, its namedCurve and the key of a SubjectPublicKeyInfo
def x509.spki(t: Asn1.Tlv) -> Maybe<&2, Spki>:
  x509.spki.m(x509.seq(t))

# Small values
# ------------

# an OCTET STRING's single DER value
def x509.oct.if(ok: Bool, t: Asn1.Tlv) -> Maybe<&2, Asn1.Tlv>:
  match ok:
    case True{}:
      Asn1.read(x509.value.of(t))
    case False{}:
      None{}

def x509.oct(+t: Asn1.Tlv) -> Maybe<&2, Asn1.Tlv>:
  x509.oct.if(U32.is_eq(x509.tag.of(t), 4), t)

def x509.oct.seq.m(m: Maybe<&2, Asn1.Tlv>) -> Maybe<&2, List<&2, Asn1.Tlv>>:
  match m:
    case Some{inner}:
      x509.seq(inner)
    case None{}:
      None{}

# the SEQUENCE an extension's OCTET STRING holds, as its elements
def x509.oct.seq(t: Asn1.Tlv) -> Maybe<&2, List<&2, Asn1.Tlv>>:
  x509.oct.seq.m(x509.oct(t))

# a BOOLEAN
def x509.bool.of.if(ok: Bool, t: Asn1.Tlv) -> Maybe<&2, Bool>:
  match ok:
    case True{}:
      Some{U32.is_ne(Bytes.get.be(x509.value.of(t), 1n), 0)}
    case False{}:
      None{}

def x509.bool.of(+t: Asn1.Tlv) -> Maybe<&2, Bool>:
  x509.bool.of.if(U32.is_eq(x509.tag.of(t), 1), t)

# an INTEGER's value, at most four bytes
def x509.uint.of.bytes.if(+v: List<&2, U32>, small: Bool) -> Maybe<&2, U32>:
  match small:
    case True{}:
      Some{Bytes.get.be(v, 4n)}
    case False{}:
      None{}

def x509.uint.of.bytes(+v: List<&2, U32>) -> Maybe<&2, U32>:
  x509.uint.of.bytes.if(v, U32.is_le(Bytes.len(v), 4))

def x509.uint.if(ok: Bool, t: Asn1.Tlv) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      x509.uint.of.bytes(Asn1.uint(x509.value.of(t)))
    case False{}:
      None{}

def x509.uint.of(+t: Asn1.Tlv) -> Maybe<&2, U32>:
  x509.uint.if(U32.is_eq(x509.tag.of(t), 2), t)

# Extensions
# ----------

def x509.exts.none() -> Exts:
  Exts{False{}, 4294967295, 4294967295, Nil{}, False{}}

def x509.exts.ca(+acc: Exts, ca: Bool, +path_len: U32) -> Exts:
  match acc:
    case Exts{old_ca, old_path, usage, dns, unknown}:
      Exts{ca, path_len, usage, dns, unknown}

def x509.exts.usage(+acc: Exts, +key_usage: U32) -> Exts:
  match acc:
    case Exts{ca, path_len, old_usage, dns, unknown}:
      Exts{ca, path_len, key_usage, dns, unknown}

def x509.exts.dns(+acc: Exts, dns: List<&2, String>) -> Exts:
  match acc:
    case Exts{ca, path_len, key_usage, old_dns, unknown}:
      Exts{ca, path_len, key_usage, dns, unknown}

def x509.exts.unknown(+acc: Exts) -> Exts:
  match acc:
    case Exts{ca, path_len, key_usage, dns, unknown}:
      Exts{ca, path_len, key_usage, dns, True{}}

# basicConstraints: cA, then pathLenConstraint
def x509.ext.basic.path(rest: List<&2, Asn1.Tlv>, +acc: Exts, ca: Bool) -> Maybe<&2, Exts>:
  match rest:
    case Nil{}:
      Some{x509.exts.ca(acc, ca, 4294967295)}
    case Con{len, Nil{}}:
      do Maybe<&2, Exts>:
        n : U32 <- x509.uint.of(len)
        return x509.exts.ca(acc, ca, n)
    case Con{len, others}:
      None{}

def x509.ext.basic.ca(first: Asn1.Tlv, rest: List<&2, Asn1.Tlv>, +acc: Exts) -> Maybe<&2, Exts>:
  do Maybe<&2, Exts>:
    ca : Bool <- x509.bool.of(first)
    out : Exts <- x509.ext.basic.path(rest, acc, ca)
    return out

def x509.ext.basic.parts(parts: List<&2, Asn1.Tlv>, +acc: Exts) -> Maybe<&2, Exts>:
  match parts:
    case Nil{}:
      Some{x509.exts.ca(acc, False{}, 4294967295)}
    case Con{first, rest}:
      x509.ext.basic.ca(first, rest, acc)

def x509.ext.basic.m(m: Maybe<&2, List<&2, Asn1.Tlv>>, +acc: Exts) -> Maybe<&2, Exts>:
  match m:
    case Some{parts}:
      x509.ext.basic.parts(parts, acc)
    case None{}:
      None{}

def x509.ext.basic(t: Asn1.Tlv, +acc: Exts) -> Maybe<&2, Exts>:
  x509.ext.basic.m(x509.oct.seq(t), acc)

# the low 8 bits with their bit order reversed
def x509.rev8(+b: U32) -> U32:
  +r = U32.or(U32.shln(U32.and(b, 85), 1n), U32.shrn(U32.and(b, 170), 1n))
  +s = U32.or(U32.shln(U32.and(r, 51), 2n), U32.shrn(U32.and(r, 204), 2n))
  U32.or(U32.shln(U32.and(s, 15), 4n), U32.shrn(U32.and(s, 240), 4n))

# byte n of a BIT STRING, as the eight bits it carries (0 past the end)
def x509.key.byte(+xs: List<&2, U32>, n: Nat) -> U32:
  x509.rev8(Bytes.get.be(Bytes.drop(xs, n), 1n))

def x509.key.bits(+xs: List<&2, U32>) -> U32:
  U32.or(U32.or(x509.key.byte(xs, 0n), U32.shln(x509.key.byte(xs, 1n), 8n)), U32.or(U32.shln(x509.key.byte(xs, 2n), 16n), U32.shln(x509.key.byte(xs, 3n), 24n)))

# keyUsage: bit n of the BIT STRING is bit n of the U32, RFC 5280 numbering.
#
# (the extension's OCTET STRING holds a BIT STRING, and its last byte may have unused bits,
# so this reads the bits directly rather than through x509.bits, which asks for none)
def x509.ext.usage.m(m: Maybe<&2, Asn1.Tlv>, +acc: Exts) -> Maybe<&2, Exts>:
  match m:
    case Some{Asn1.Tlv{3, value, rest}}:
      Some{x509.exts.usage(acc, x509.key.bits(Bytes.drop(value, 1n)))}
    case _:
      None{}

def x509.ext.usage(t: Asn1.Tlv, +acc: Exts) -> Maybe<&2, Exts>:
  x509.ext.usage.m(x509.oct(t), acc)

# subjectAltName: the dNSName entries, lowercased
def x509.lower.byte(+c: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_le(65, c), U32.is_le(c, 90)), (c + 32 : U32), c)

def x509.lower.go(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Bytes.rev(acc)
    case Con{+h, t}:
      x509.lower.go(t, x509.lower.byte(h) <> acc)

def x509.lower(+xs: List<&2, U32>) -> String:
  Bytes.to_ascii(x509.lower.go(xs, Nil{}))

def x509.san.rev.go(xs: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      x509.san.rev.go(t, h <> acc)

def x509.san.rev(xs: List<&2, String>) -> List<&2, String>:
  x509.san.rev.go(xs, Nil{})

def x509.san.names.go(parts: List<&2, Asn1.Tlv>, acc: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match parts:
    case Nil{}:
      Some{x509.san.rev(acc)}
    case Con{Asn1.Tlv{130, value, rest2}, rest}:
      x509.san.names.go(rest, x509.lower(value) <> acc)
    case Con{Asn1.Tlv{tag, value, rest2}, rest}:
      x509.san.names.go(rest, acc)

def x509.san.names(parts: List<&2, Asn1.Tlv>) -> Maybe<&2, List<&2, String>>:
  x509.san.names.go(parts, Nil{})

def x509.ext.san.m(m: Maybe<&2, List<&2, Asn1.Tlv>>, +acc: Exts) -> Maybe<&2, Exts>:
  match m:
    case Some{parts}:
      do Maybe<&2, Exts>:
        names : List<&2, String> <- x509.san.names(parts)
        return x509.exts.dns(acc, names)
    case None{}:
      None{}

def x509.ext.san(t: Asn1.Tlv, +acc: Exts) -> Maybe<&2, Exts>:
  x509.ext.san.m(x509.oct.seq(t), acc)

# the extensions the engine reads: basicConstraints, keyUsage, subjectAltName,
# extKeyUsage. Another OID is fine unless it is marked critical.
type Ext is Data:
  Basic{}
  Usage{}
  San{}
  Eku{}
  Unknown{}

def x509.kind(+s: String) -> Ext:
  Bool.pick(Ext, String.eq(s, "2.5.29.19"), Basic{},
    Bool.pick(Ext, String.eq(s, "2.5.29.15"), Usage{},
      Bool.pick(Ext, String.eq(s, "2.5.29.17"), San{},
        Bool.pick(Ext, String.eq(s, "2.5.29.37"), Eku{}, Unknown{}))))

def x509.ext.unknown(crit: Bool, +acc: Exts) -> Maybe<&2, Exts>:
  match crit:
    case True{}:
      Some{x509.exts.unknown(acc)}
    case False{}:
      Some{acc}

def x509.ext.by(k: Ext, t: Asn1.Tlv, crit: Bool, +acc: Exts) -> Maybe<&2, Exts>:
  match k:
    case Basic{}:
      x509.ext.basic(t, acc)
    case Usage{}:
      x509.ext.usage(t, acc)
    case San{}:
      x509.ext.san(t, acc)
    case Eku{}:
      Some{acc}
    case Unknown{}:
      x509.ext.unknown(crit, acc)

def x509.ext.body.m(m: Maybe<&2, String>, +crit: Bool, t: Asn1.Tlv, +acc: Exts) -> Maybe<&2, Exts>:
  match m:
    case Some{s}:
      x509.ext.by(x509.kind(s), t, crit, acc)
    case None{}:
      None{}

# an extension's OID, its critical flag and its value
def x509.ext.body(oid: Asn1.Tlv, crit: Bool, t: Asn1.Tlv, +acc: Exts) -> Maybe<&2, Exts>:
  x509.ext.body.m(x509.oid.of(oid), crit, t, acc)

def x509.ext.one.crit(oid: Asn1.Tlv, crit: Asn1.Tlv, t: Asn1.Tlv, +acc: Exts) -> Maybe<&2, Exts>:
  do Maybe<&2, Exts>:
    on : Bool <- x509.bool.of(crit)
    out : Exts <- x509.ext.body(oid, on, t, acc)
    return out

def x509.ext.one.m(m: Maybe<&2, List<&2, Asn1.Tlv>>, +acc: Exts) -> Maybe<&2, Exts>:
  match m:
    case Some{Con{oid, Con{crit, Con{value, Nil{}}}}}:
      x509.ext.one.crit(oid, crit, value, acc)
    case Some{Con{oid, Con{value, Nil{}}}}:
      x509.ext.body(oid, False{}, value, acc)
    case _:
      None{}

def x509.ext.one(t: Asn1.Tlv, +acc: Exts) -> Maybe<&2, Exts>:
  x509.ext.one.m(x509.seq(t), acc)

def x509.extlist.go(parts: List<&2, Asn1.Tlv>, acc: Exts) -> Maybe<&2, Exts>:
  match parts:
    case Nil{}:
      Some{acc}
    case Con{ext, rest}:
      do Maybe<&2, Exts>:
        next : Exts <- x509.ext.one(ext, acc)
        out : Exts <- x509.extlist.go(rest, next)
        return out

def x509.extlist.m(m: Maybe<&2, List<&2, Asn1.Tlv>>, +acc: Exts) -> Maybe<&2, Exts>:
  match m:
    case Some{parts}:
      x509.extlist.go(parts, acc)
    case None{}:
      None{}

def x509.exts.seq.m(m: Maybe<&2, List<&2, Asn1.Tlv>>, +acc: Exts) -> Maybe<&2, Exts>:
  match m:
    case Some{Con{seq, rest}}:
      x509.extlist.m(x509.seq(seq), acc)
    case _:
      None{}

# a [3] EXPLICIT extensions element: its single SEQUENCE of Extension
def x509.exts.seq(v: List<&2, U32>, +acc: Exts) -> Maybe<&2, Exts>:
  x509.exts.seq.m(Asn1.items(v), acc)

# the elements after subjectPublicKeyInfo: [1] and [2] are ignored, [3] is extensions
def x509.exts.go(parts: List<&2, Asn1.Tlv>, acc: Exts) -> Maybe<&2, Exts>:
  match parts:
    case Nil{}:
      Some{acc}
    case Con{Asn1.Tlv{163, value, rest2}, rest}:
      do Maybe<&2, Exts>:
        next : Exts <- x509.exts.seq(value, acc)
        out : Exts <- x509.exts.go(rest, next)
        return out
    case Con{Asn1.Tlv{161, value, rest2}, rest}:
      x509.exts.go(rest, acc)
    case Con{Asn1.Tlv{162, value, rest2}, rest}:
      x509.exts.go(rest, acc)
    case Con{Asn1.Tlv{tag, value, rest2}, rest}:
      None{}

def x509.exts(parts: List<&2, Asn1.Tlv>) -> Maybe<&2, Exts>:
  x509.exts.go(parts, x509.exts.none())

# TBSCertificate
# --------------

def x509.tbs.make(issuer: List<&2, U32>, subject: List<&2, U32>, v: Validity, k: Spki, e: Exts) -> Tbs:
  match v k e:
    case Validity{nb, na} Spki{alg, curve, key} Exts{ca, path_len, key_usage, dns, unknown}:
      Tbs{issuer, subject, nb, na, alg, curve, key, ca, path_len, key_usage, dns, unknown}

# sign: the DER start of the issuer's Name. issuer's rest is that Name's end, validity's
# rest the start of the subject's Name.
def x509.tbs.go(sign: List<&2, U32>, +issuer: Asn1.Tlv, +validity: Asn1.Tlv, subject: Asn1.Tlv, spki: Asn1.Tlv, extras: List<&2, Asn1.Tlv>) -> Maybe<&2, Tbs>:
  do Maybe<&2, Tbs>:
    v : Validity <- x509.validity(validity)
    k : Spki <- x509.spki(spki)
    e : Exts <- x509.exts(extras)
    return x509.tbs.make(x509.raw(sign, x509.rest.of(issuer)), x509.raw(x509.rest.of(validity), x509.rest.of(subject)), v, k, e)

# the fields after the version: serialNumber, signature, issuer, validity, subject,
# subjectPublicKeyInfo and the optional trailing elements
def x509.tbs.fields(parts: List<&2, Asn1.Tlv>) -> Maybe<&2, Tbs>:
  match parts:
    case Con{serial, Con{sigalg, Con{issuer, Con{validity, Con{subject, Con{spki, extras}}}}}}:
      x509.tbs.go(x509.rest.of(sigalg), issuer, validity, subject, spki, extras)
    case _:
      None{}

# the version element holds the INTEGER 0, 1 or 2, that is v1 to v3
def x509.tbs.ver.ok(+v: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(Bytes.len(v), 3), Bool.and(U32.is_eq(Bytes.get.be(v, 2n), 513), U32.is_le(Bytes.get.be(Bytes.drop(v, 2n), 1n), 2)))

def x509.tbs.ver.if(ok: Bool, parts: List<&2, Asn1.Tlv>) -> Maybe<&2, Tbs>:
  match ok:
    case True{}:
      x509.tbs.fields(parts)
    case False{}:
      None{}

def x509.tbs.m(m: Maybe<&2, List<&2, Asn1.Tlv>>) -> Maybe<&2, Tbs>:
  match m:
    case Some{Con{Asn1.Tlv{160, version, vrest}, rest}}:
      x509.tbs.ver.if(x509.tbs.ver.ok(version), rest)
    case Some{parts}:
      x509.tbs.fields(parts)
    case None{}:
      None{}

# a TBSCertificate: the version when present, then the fields
def x509.tbs(t: Asn1.Tlv) -> Maybe<&2, Tbs>:
  x509.tbs.m(x509.seq(t))

# The certificate
# ---------------

def x509.cert.make(der: List<&2, U32>, tbs: List<&2, U32>, sig_alg: String, sig: List<&2, U32>, b: Tbs) -> Cert:
  match b:
    case Tbs{issuer, subject, not_before, not_after, key_alg, key_curve, key, ca, path_len, key_usage, dns, unknown}:
      Cert{der, tbs, sig_alg, sig, issuer, subject, not_before, not_after, key_alg, key_curve, key, dns, ca, path_len, key_usage, unknown}

def x509.cert.go(der: List<&2, U32>, raw: List<&2, U32>, tbs: Asn1.Tlv, sigalg: Asn1.Tlv, sig: Asn1.Tlv) -> Maybe<&2, Cert>:
  do Maybe<&2, Cert>:
    sa : String <- x509.alg.oid(x509.value.of(sigalg))
    s : List<&2, U32> <- x509.bits(sig)
    b : Tbs <- x509.tbs(tbs)
    return x509.cert.make(der, raw, sa, s, b)

# the outer SEQUENCE's three elements: tbsCertificate, signatureAlgorithm, signatureValue
def x509.cert.parts(der: List<&2, U32>, body: List<&2, U32>, parts: List<&2, Asn1.Tlv>) -> Maybe<&2, Cert>:
  match parts:
    case Con{+tbs, Con{+sigalg, Con{sig, Nil{}}}}:
      x509.cert.go(der, x509.raw(body, x509.rest.of(tbs)), tbs, sigalg, sig)
    case _:
      None{}

def x509.cert.m(m: Maybe<&2, List<&2, Asn1.Tlv>>, der: List<&2, U32>, body: List<&2, U32>) -> Maybe<&2, Cert>:
  match m:
    case Some{parts}:
      x509.cert.parts(der, body, parts)
    case None{}:
      None{}

def x509.cert.if(ok: Bool, +outer: Asn1.Tlv, der: List<&2, U32>) -> Maybe<&2, Cert>:
  match ok:
    case True{}:
      x509.cert.m(Asn1.items(x509.value.of(outer)), der, x509.value.of(outer))
    case False{}:
      None{}

def x509.cert.check(+outer: Asn1.Tlv, der: List<&2, U32>) -> Maybe<&2, Cert>:
  x509.cert.if(U32.is_eq(x509.tag.of(outer), 48), outer, der)

# a certificate ends where its bytes end: nothing may follow
def x509.cert.empty.if(ok: Bool, +outer: Asn1.Tlv, der: List<&2, U32>) -> Maybe<&2, Cert>:
  match ok:
    case True{}:
      x509.cert.check(outer, der)
    case False{}:
      None{}

def x509.cert.empty(m: Maybe<&2, Asn1.Tlv>, der: List<&2, U32>) -> Maybe<&2, Cert>:
  match m:
    case Some{+outer}:
      x509.cert.empty.if(U32.is_zero(Bytes.len(x509.rest.of(outer))), outer, der)
    case None{}:
      None{}

# a DER certificate
def parse(+der: List<&2, U32>) -> Maybe<&2, Cert>:
  x509.cert.empty(Asn1.read(der), der)

# Keys and signatures
# -------------------

# two byte strings as one Data value: a tuple A & B is affine (Kind &1), and a Maybe<&2, ..>
# can only hold Data. (a, b) builds it and destructures it, as a tuple does.
def Two() -> Data:
  Sigma<&2, &2, List<&2, U32>, _ => List<&2, U32>>

# the modulus and exponent of a DER RSAPublicKey
def x509.rsa.exp(modulus: List<&2, U32>, m: Maybe<&2, Asn1.Tlv>) -> Maybe<&2, Two()>:
  match m:
    case Some{Asn1.Tlv{2, evalue, erest}}:
      Some{(Asn1.uint(modulus), Asn1.uint(evalue))}
    case _:
      None{}

def x509.rsa.ints(m: Maybe<&2, Asn1.Tlv>) -> Maybe<&2, Two()>:
  match m:
    case Some{Asn1.Tlv{2, mvalue, mrest}}:
      x509.rsa.exp(Asn1.uint(mvalue), Asn1.read(mrest))
    case _:
      None{}

def x509.rsa.seq(m: Maybe<&2, Asn1.Tlv>) -> Maybe<&2, Two()>:
  match m:
    case Some{Asn1.Tlv{48, value, rest}}:
      x509.rsa.ints(Asn1.read(value))
    case _:
      None{}

def rsa_key(key: List<&2, U32>) -> Maybe<&2, Two()>:
  x509.rsa.seq(Asn1.read(key))

# r and s of a DER ECDSA-Sig-Value
def x509.ecdsa.s(r: List<&2, U32>, m: Maybe<&2, Asn1.Tlv>) -> Maybe<&2, Two()>:
  match m:
    case Some{Asn1.Tlv{2, svalue, srest}}:
      Some{(r, Asn1.uint(svalue))}
    case _:
      None{}

def x509.ecdsa.ints(m: Maybe<&2, Asn1.Tlv>) -> Maybe<&2, Two()>:
  match m:
    case Some{Asn1.Tlv{2, rvalue, rrest}}:
      x509.ecdsa.s(Asn1.uint(rvalue), Asn1.read(rrest))
    case _:
      None{}

def x509.ecdsa.seq(m: Maybe<&2, Asn1.Tlv>) -> Maybe<&2, Two()>:
  match m:
    case Some{Asn1.Tlv{48, value, rest}}:
      x509.ecdsa.ints(Asn1.read(value))
    case _:
      None{}

def ecdsa_sig(sig: List<&2, U32>) -> Maybe<&2, Two()>:
  x509.ecdsa.seq(Asn1.read(sig))
