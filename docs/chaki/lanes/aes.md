# lane: aes

AES-128/256 and GCM. TLS_AES_128_GCM_SHA256 is the one cipher suite every TLS 1.3 server
must speak, so chaki needs it even though it prefers ChaCha20. BearSSL is the model.

## Files you own

`lib/chaki/aes.bend`, `test/chaki_aes_check.bend`.

## API (exact)

```python
# one block under a 16- or 32-byte key (the forward cipher, all GCM needs)
def encrypt(key: List<&2, U32>, block: List<&2, U32>) -> List<&2, U32>
# ciphertext followed by the 16-byte tag; nonce 12 bytes
def seal(key: List<&2, U32>, nonce: List<&2, U32>, aad: List<&2, U32>, plain: List<&2, U32>) -> List<&2, U32>
# None when the tag doesn't match (constant-time compare) or sealed is shorter than a tag
def open(key: List<&2, U32>, nonce: List<&2, U32>, aad: List<&2, U32>, sealed: List<&2, U32>) -> Maybe<&2, List<&2, U32>>
```

## How

- Expand the key once per call into a round-key constructor, then run blocks against it.
- The S-box: a lookup is the hot path. Either thread a 256-entry `Array<U32>` (arrays are
  affine, so every read hands it back), or generate a balanced comparison tree of small defs.
  Note in your report which you chose, and that table lookups aren't constant-time.
- GHASH: multiplication in GF(2^128), bit by bit on four U32 words, as GCM's spec describes
  (Algorithm 1). Simple and correct beats fast here.
- Keep defs narrow: native builds reject wide defs.

## Checks

`test/chaki_aes_check.bend`:

- FIPS-197 Appendix C.1 (AES-128) and C.3 (AES-256).
- GCM test cases 1-4 (AES-128) and 13-16 (AES-256) from McGrew and Viega, "The
  Galois/Counter Mode of Operation (GCM)", 96-bit IVs only. Fetch them from the published
  spec or NIST's GCM documents, and name the source in a comment.
- Tampering with one bit of the ciphertext, the tag or the AAD makes `open` answer None.
- A 256 KB round trip finishes.
