# x509v: certificate path validation, the trust decision of chaki's TLS. Is this chain, as a
# server sent it, trusted for this host right now? BearSSL's minimal X.509 engine is the
# model: small and strict, failing closed on anything it doesn't understand.
import Base
import ./bytes.bend as Bytes
import ./sha2.bend as Sha2
import ./b64.bend as B64
import ./x509.bend as X509
import ./rsa.bend as Rsa
import ./ecdsa.bend as Ecdsa

# Trust anchors
# -------------

def anchors.keep(m: Maybe<&2, X509.Cert>, acc: List<&2, X509.Cert>) -> List<&2, X509.Cert>:
  match m:
    case Some{c}:
      c <> acc
    case None{}:
      acc

def anchors.go(ders: List<&2, List<&2, U32>>, acc: List<&2, X509.Cert>) -> List<&2, X509.Cert>:
  match ders:
    case Nil{}:
      List.reverse(&2, X509.Cert, acc)
    case Con{d, t}:
      anchors.go(t, anchors.keep(X509.parse(d), acc))

# every CERTIFICATE block of a PEM bundle that parses
def anchors(pem: String) -> List<&2, X509.Cert>:
  anchors.go(B64.pem(pem, "CERTIFICATE"), Nil{})

def file.text(got: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match got:
    case Done{s}:
      Some{s}
    case Fail{e}:
      None{}

def file.done(r: File & Result<&1, &1, U32 & String, String>) -> IO(Maybe<&2, String>):
  (f, got) = r
  do IO<Maybe<&2, String>>:
    File.close(f)
    return file.text(got)

def file.open(r: Result<&1, &1, U32 & String, File>) -> IO(Maybe<&2, String>):
  match r:
    case Done{f}:
      do IO<Maybe<&2, String>>:
        got : File & Result<&1, &1, U32 & String, String> <- File.read(f, 16777216)
        file.done(got)
    case Fail{e}:
      IO.pure(Maybe<&2, String>, None{})

# a file's whole text, or None
def file(path: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    file.open(r)

def known() -> List<&2, String>:
  ["/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/cert.pem", "/etc/ssl/ca-bundle.pem"]

def load.paths(env: Result<&1, &1, U32 & String, String>) -> List<&2, String>:
  match env:
    case Done{p}:
      p <> known()
    case Fail{e}:
      known()

# the first of ps that reads
def load.go(ps: List<&2, String>, got: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match ps got:
    case Nil{} Some{s}:
      IO.pure(Maybe<&2, String>, Some{s})
    case Con{p, t} Some{s}:
      IO.pure(Maybe<&2, String>, Some{s})
    case Nil{} None{}:
      IO.pure(Maybe<&2, String>, None{})
    case Con{p, t} None{}:
      IO.bind(Maybe<&2, String>, Maybe<&2, String>, file(p), m => load.go(t, m))

def load.some(+xs: List<&2, X509.Cert>) -> Result<&1, &1, U32 & String, List<&2, X509.Cert>>:
  Bool.pick(Result<&1, &1, U32 & String, List<&2, X509.Cert>>, List.is_empty(&2, X509.Cert, xs), Fail{(2, "the trust store holds no certificates")}, Done{xs})

def load.anchors(m: Maybe<&2, String>) -> Result<&1, &1, U32 & String, List<&2, X509.Cert>>:
  match m:
    case None{}:
      Fail{(2, "no trust store found (set SSL_CERT_FILE)")}
    case Some{text}:
      load.some(anchors(text))

# the system's trust anchors: $SSL_CERT_FILE, else the first of the usual bundle paths that
# reads
def load() -> IO(Result<&1, &1, U32 & String, List<&2, X509.Cert>>):
  do IO<Result<&1, &1, U32 & String, List<&2, X509.Cert>>>:
    env : Result<&1, &1, U32 & String, String> <- IO.get_env("SSL_CERT_FILE")
    m : Maybe<&2, String> <- load.go(load.paths(env), None{})
    return load.anchors(m)

# Signatures
# ----------

def RSA() -> String:
  "1.2.840.113549.1.1.1"

def EC() -> String:
  "1.2.840.10045.2.1"

# the certificate signature algorithms the engine checks (RFC 4055, RFC 5758)
type Sig is Data:
  Pkcs{a: Sha2.Alg}
  Ecd{a: Sha2.Alg}
  Unknown{}

def sig.of(+oid: String) -> Sig:
  Bool.pick(Sig, String.eq(oid, "1.2.840.113549.1.1.11"), Pkcs{Sha2.S256{}},
  Bool.pick(Sig, String.eq(oid, "1.2.840.113549.1.1.12"), Pkcs{Sha2.S384{}},
  Bool.pick(Sig, String.eq(oid, "1.2.840.113549.1.1.13"), Pkcs{Sha2.S512{}},
  Bool.pick(Sig, String.eq(oid, "1.2.840.10045.4.3.2"), Ecd{Sha2.S256{}},
  Bool.pick(Sig, String.eq(oid, "1.2.840.10045.4.3.3"), Ecd{Sha2.S384{}},
  Bool.pick(Sig, String.eq(oid, "1.2.840.10045.4.3.4"), Ecd{Sha2.S512{}}, Unknown{}))))))

def rsa.key(a: Sha2.Alg, m: Maybe<&2, X509.Two()>, tbs: List<&2, U32>, sig: List<&2, U32>) -> Bool:
  match m:
    case Some{(n, e)}:
      Rsa.pkcs1(a, n, e, tbs, sig)
    case None{}:
      False{}

def rsa.if(a: Sha2.Alg, key: List<&2, U32>, tbs: List<&2, U32>, sig: List<&2, U32>, ok: Bool) -> Bool:
  match ok:
    case True{}:
      rsa.key(a, X509.rsa_key(key), tbs, sig)
    case False{}:
      False{}

def ec.key(a: Sha2.Alg, m: Maybe<&2, Ecdsa.Curve>, key: List<&2, U32>, tbs: List<&2, U32>, sig: List<&2, U32>) -> Bool:
  match m:
    case Some{c}:
      Ecdsa.verify.der(c, a, key, tbs, sig)
    case None{}:
      False{}

def ec.if(a: Sha2.Alg, +curve: String, key: List<&2, U32>, tbs: List<&2, U32>, sig: List<&2, U32>, ok: Bool) -> Bool:
  match ok:
    case True{}:
      ec.key(a, Ecdsa.curve(curve), key, tbs, sig)
    case False{}:
      False{}

def signed.with(s: Sig, +alg: String, +curve: String, key: List<&2, U32>, tbs: List<&2, U32>, sig: List<&2, U32>) -> Bool:
  match s:
    case Pkcs{a}:
      rsa.if(a, key, tbs, sig, String.eq(alg, RSA()))
    case Ecd{a}:
      ec.if(a, curve, key, tbs, sig, String.eq(alg, EC()))
    case Unknown{}:
      False{}

# whether cert's signature verifies under issuer's public key
def signed_by(cert: X509.Cert, issuer: X509.Cert) -> Bool:
  match cert issuer:
    case X509.Cert{d, tbs, +sa, sig, i, su, nb, na, ka, kc, k, dns, ca, pl, ku, uc, st} X509.Cert{d2, t2, sa2, s2, i2, su2, nb2, na2, +alg, +curve, key, dns2, ca2, pl2, ku2, uc2, st2}:
      signed.with(sig.of(sa), alg, curve, key, tbs, sig)

# Hosts
# -----

def ip.chars(cs: List<&2, Char>) -> Bool:
  match cs:
    case Nil{}:
      True{}
    case Con{+c, t}:
      Bool.and(Bool.or(Char.is_digit(c), Char.is_eq(c, '.')), ip.chars(t))

# an IPv6 literal (it has a colon) or an IPv4 one (digits and dots)
def host.ip(+h: String) -> Bool:
  Bool.or(String.contains(h, ":"), ip.chars(String.to_list(h)))

def host.norm.if(+h: String, dot: Bool) -> String:
  match dot:
    case True{}:
      String.take(h, Nat.sub(String.length(h), 1n))
    case False{}:
      h

# lowercase, and one trailing dot dropped ("cha.test." is "cha.test")
def host.norm(+h: String) -> String:
  host.norm.if(String.to_lower(h), String.ends_with(h, "."))

def nth(xs: List<&2, String>, n: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, n), "")

# "*.cha.test" matches exactly one more non-empty label: x.cha.test, not cha.test or a.b.cha.test.
# The rest must still be two labels or more, so "*.test" matches nothing.
def wild.ok(+pat: String, +host: String) -> Bool:
  +parts = String.split(host, '.')
  +base = String.drop(pat, 2n)
  Bool.and(Bool.not(String.is_empty(nth(parts, 0n))),
    Bool.and(String.eq(String.join(List.drop(&2, String, parts, 1n), "."), base), String.contains(base, ".")))

def name.ok(+pat: String, +host: String) -> Bool:
  Bool.or(String.eq(pat, host), Bool.and(String.starts_with(pat, "*."), wild.ok(pat, host)))

def names.ok(ps: List<&2, String>, +host: String) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{+p, t}:
      Bool.or(name.ok(p, host), names.ok(t, host))

def host_ok.if(ip: Bool, c: X509.Cert, +host: String) -> Bool:
  match ip:
    case True{}:
      False{}
    case False{}:
      match c:
        case X509.Cert{d, t, sa, s, i, su, nb, na, ka, kc, k, dns, ca, pl, ku, uc, st}:
          names.ok(dns, host)

# whether host matches the certificate: SAN dNSName entries only, case-insensitive, a "*."
# leftmost label matching exactly one non-empty label, no other wildcards; an IP literal
# never matches
def host_ok(cert: X509.Cert, +host: String) -> Bool:
  +h = host.norm(host)
  host_ok.if(host.ip(h), cert, h)

# Paths
# -----

def subject.of(c: X509.Cert) -> List<&2, U32>:
  match c:
    case X509.Cert{d, t, sa, s, i, su, nb, na, ka, kc, k, dns, ca, pl, ku, uc, st}:
      su

def issuer.of(c: X509.Cert) -> List<&2, U32>:
  match c:
    case X509.Cert{d, t, sa, s, i, su, nb, na, ka, kc, k, dns, ca, pl, ku, uc, st}:
      i

# the signature is only checked once the names match: most candidates fail on bytes
def issues.if(+cur: X509.Cert, +c: X509.Cert, same: Bool) -> Bool:
  match same:
    case True{}:
      signed_by(cur, c)
    case False{}:
      False{}

def issues(+cur: X509.Cert, +c: X509.Cert) -> Bool:
  issues.if(cur, c, Bytes.eq(subject.of(c), issuer.of(cur)))

def find.keep(+c: X509.Cert, ok: Bool) -> Maybe<&2, X509.Cert>:
  match ok:
    case True{}:
      Some{c}
    case False{}:
      None{}

# the first candidate that issued cur
def find.go(cs: List<&2, X509.Cert>, +cur: X509.Cert, got: Maybe<&2, X509.Cert>) -> Maybe<&2, X509.Cert>:
  match cs got:
    case Nil{} g:
      g
    case Con{c, t} Some{x}:
      Some{x}
    case Con{+c, t} None{}:
      find.go(t, cur, find.keep(c, issues(cur, c)))

def find(cs: List<&2, X509.Cert>, +cur: X509.Cert) -> Maybe<&2, X509.Cert>:
  find.go(cs, cur, None{})

def KEY_CERT_SIGN() -> U32:
  32

# why an issuer that isn't an anchor can't sit at this place in the path ("" when it can):
# below is how many issuers sit between it and the leaf
def inter.why(c: X509.Cert, +below: U32, +now: U32) -> String:
  match c:
    case X509.Cert{d, t, sa, s, i, su, +nb, +na, ka, kc, k, dns, ca, +pl, +ku, uc, st}:
      Bool.pick(String, Bool.not(ca), "an issuer in the chain isn't a CA",
      Bool.pick(String, Bool.and(U32.is_ne(ku, 4294967295), U32.is_eq(U32.and(ku, KEY_CERT_SIGN()), 0)), "an issuer in the chain may not sign certificates",
      Bool.pick(String, U32.is_lt(now, nb), "an issuer in the chain isn't valid yet",
      Bool.pick(String, U32.is_gt(now, na), "an issuer in the chain has expired",
      Bool.pick(String, uc, "an issuer in the chain has a critical extension chaki doesn't know",
      Bool.pick(String, U32.is_lt(pl, below), "the chain is longer than an issuer allows", ""))))))

def leaf.why(c: X509.Cert, +host: String, +now: U32, ok: Bool) -> String:
  match c:
    case X509.Cert{d, t, sa, s, i, su, +nb, +na, ka, kc, k, dns, ca, pl, ku, uc, st}:
      Bool.pick(String, U32.is_lt(now, nb), "the server's certificate isn't valid yet",
      Bool.pick(String, U32.is_gt(now, na), "the server's certificate has expired",
      Bool.pick(String, uc, "the server's certificate has a critical extension chaki doesn't know",
      Bool.pick(String, Bool.not(ok), "the server's certificate isn't for " ++ host, ""))))

type Path is Data:
  At{cur: X509.Cert, below: U32}
  Trusted{}
  Refused{why: String}

def path.inter(+p: X509.Cert, +below: U32, +why: String) -> Path:
  Bool.pick(Path, String.is_empty(why), At{p, (below + 1 : U32)}, Refused{why})

def path.pool(m: Maybe<&2, X509.Cert>, +below: U32, +now: U32) -> Path:
  match m:
    case None{}:
      Refused{"the chain doesn't lead to a trusted root"}
    case Some{+p}:
      path.inter(p, below, inter.why(p, below, now))

def path.anchor(m: Maybe<&2, X509.Cert>, +cur: X509.Cert, +below: U32, +pool: List<&2, X509.Cert>, +now: U32) -> Path:
  match m:
    case Some{a}:
      Trusted{}
    case None{}:
      path.pool(find(pool, cur), below, now)

# one step up: an anchor that issued cur ends the walk; otherwise one of the sent
# certificates must have, and be fit to
def path.step(+cur: X509.Cert, +below: U32, +pool: List<&2, X509.Cert>, +anchors: List<&2, X509.Cert>, +now: U32) -> Path:
  path.anchor(find(anchors, cur), cur, below, pool, now)

# at most 8 certificates from the leaf to an anchor
def path.go(fuel: Nat, +pool: List<&2, X509.Cert>, +anchors: List<&2, X509.Cert>, +now: U32, st: Path) -> Result<&1, &1, String, Unit>:
  match fuel st:
    case 0n Trusted{}:
      Done{Unit{}}
    case 0n Refused{w}:
      Fail{w}
    case 0n At{c, b}:
      Fail{"the chain is too long"}
    case 1n+k Trusted{}:
      Done{Unit{}}
    case 1n+k Refused{w}:
      Fail{w}
    case 1n+k At{+c, +b}:
      path.go(k, pool, anchors, now, path.step(c, b, pool, anchors, now))

def leaf.walk(ok: Bool, +leaf: X509.Cert, +pool: List<&2, X509.Cert>, +anchors: List<&2, X509.Cert>, +now: U32, +why: String) -> Result<&1, &1, String, Unit>:
  match ok:
    case True{}:
      path.go(8n, pool, anchors, now, At{leaf, 0})
    case False{}:
      Fail{why}

def leaf.walk.of(+leaf: X509.Cert, +pool: List<&2, X509.Cert>, +anchors: List<&2, X509.Cert>, +now: U32, +why: String) -> Result<&1, &1, String, Unit>:
  leaf.walk(String.is_empty(why), leaf, pool, anchors, now, why)

def verify.leaf(m: Maybe<&2, X509.Cert>, +rest: List<&2, List<&2, U32>>, +anchors: List<&2, X509.Cert>, +host: String, +now: U32) -> Result<&1, &1, String, Unit>:
  match m:
    case None{}:
      Fail{"the server's certificate doesn't parse"}
    case Some{+leaf}:
      leaf.walk.of(leaf, anchors.go(rest, Nil{}), anchors, now, leaf.why(leaf, host, now, host_ok(leaf, host)))

# chain: DER certificates as the server sent them, leaf first. Done when the leaf is for
# host at now and a path of valid issuers leads from it to one of anchors; otherwise one
# short line naming what failed.
def verify(chain: List<&2, List<&2, U32>>, anchors: List<&2, X509.Cert>, host: String, now: U32) -> Result<&1, &1, String, Unit>:
  match chain:
    case Nil{}:
      Fail{"the server sent no certificate"}
    case Con{d, rest}:
      verify.leaf(X509.parse(d), rest, anchors, host, now)
