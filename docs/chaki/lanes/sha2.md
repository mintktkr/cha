# lane: sha2

SHA-2 and the constructions TLS 1.3 builds on it: HMAC, HKDF, and HKDF-Expand-Label.
Monocypher's readable SHA-512 is the model.

## Files you own

`lib/chaki/sha2.bend`, `test/chaki_sha2_check.bend`.

## API (exact)

```python
type Alg is Data:
  S256{}
  S384{}
  S512{}

# digest size in bytes: 32, 48, 64
def size(a: Alg) -> U32
def hash(a: Alg, b: List<&2, U32>) -> List<&2, U32>
def hmac(a: Alg, key: List<&2, U32>, msg: List<&2, U32>) -> List<&2, U32>
# RFC 5869
def extract(a: Alg, salt: List<&2, U32>, ikm: List<&2, U32>) -> List<&2, U32>
def expand(a: Alg, prk: List<&2, U32>, info: List<&2, U32>, len: U32) -> List<&2, U32>
# RFC 8446 §7.1: HkdfLabel with "tls13 " + label
def expand_label(a: Alg, secret: List<&2, U32>, label: String, context: List<&2, U32>, len: U32) -> List<&2, U32>
# expand_label(secret, label, hash(messages), size)
def derive_secret(a: Alg, secret: List<&2, U32>, label: String, messages: List<&2, U32>) -> List<&2, U32>
```

## How

- SHA-384 and SHA-512 need 64-bit words: carry them as pairs of U32 (hi, lo), with add, rotate
  and shift done on pairs. Keep each round a small def. The native build's 247-word limit
  bites wide straight-line code; pack the eight working variables into one constructor.
- Pad with the message length in bits, as the standard says (128-bit length for 384/512).
- Tail calls over 64- or 128-byte blocks.

## Checks

`test/chaki_sha2_check.bend`, every value from the primary text:

- RFC 6234 §8.5 test vectors TEST1 ("abc"), TEST2 (the 448-bit one), and TEST4 for SHA-256,
  -384 and -512. Also the empty message, and lengths 55, 56, 63, 64 and 65 (expected values
  from `openssl dgst`). Hashing 1,000,000 bytes of 'a' (TEST3) must finish in under a
  minute natively, and run on the JS lane too if it takes under three minutes there.
- RFC 4231 test cases 1-7 for HMAC with SHA-256, -384 and -512 (case 5 truncated as the RFC
  shows).
- RFC 5869 test cases 1-3 (HKDF-SHA256).
- RFC 8448 §3 (Simple 1-RTT handshake) key schedule: from the shared x25519 secret and the
  transcript hashes the RFC gives, reproduce the early secret, the handshake secret, both
  handshake traffic secrets, and their key and iv expansions (`expand_label(.., "key", "",
  16)` / `"iv", "", 12`), byte for byte.
