# lane: ecdsa

ECDSA verification on P-256 and P-384, as certificate chains and TLS 1.3 CertificateVerify
need it. Verification only.

## Builds on

`big.bend` (modular arithmetic, and its Montgomery form if it exports one), `sha2.bend`,
`asn1.bend` / `x509.bend` (`X509.ecdsa_sig` for DER signatures).

## Files you own

`lib/chaki/ecdsa.bend`, `test/chaki_ecdsa_check.bend`.

## API (exact)

```python
type Curve is Data:
  P256{}
  P384{}

# pub: the uncompressed point 04 || X || Y. digest: the message hash, any length (its
# leftmost bits are used, as SEC 1 §4.1.4 says). r, s: big-endian.
def verify(c: Curve, pub: List<&2, U32>, digest: List<&2, U32>, r: List<&2, U32>, s: List<&2, U32>) -> Bool

# hash msg with a, take r and s from a DER ECDSA-Sig-Value, and verify
def verify.der(c: Curve, a: Sha2.Alg, pub: List<&2, U32>, msg: List<&2, U32>, sig: List<&2, U32>) -> Bool

# the curve for a namedCurve OID: prime256v1 1.2.840.10045.3.1.7, secp384r1 1.3.132.0.34
def curve(oid: String) -> Maybe<&2, Curve>
```

## Rules

- Reject a public key that isn't on the curve, isn't uncompressed, or has coordinates
  ≥ p; r or s outside [1, n-1]; and a result at infinity.
- u1·G + u2·Q in Jacobian coordinates, with Shamir's trick (one joint double-and-add).
  This is verification of public data, so constant time isn't required, but correctness at
  the edges is: a doubling inside an addition (P + P), and P + (−P).
- Curve constants come from SEC 2 / FIPS 186-4 D.1.2. Cite the source in a comment.

## Checks

`test/chaki_ecdsa_check.bend`:

- RFC 6979 A.2.5 (P-256) and A.2.6 (P-384): the given public keys, and the signatures over
  "sample" and "test" with SHA-256, SHA-384 and SHA-512, all verified. With P-256, SHA-384
  and SHA-512 exercise the truncation.
- False for: a flipped bit in r, s or the message; r = 0; s = n; a public key off the curve;
  and a P-256 key used as P-384.
- `verify.der` on a signature made by `openssl dgst` (synthetic key, commands in a comment).

Report the time of one verify per curve on both lanes. The targets are under 3 s on JS and
under 100 ms natively.
