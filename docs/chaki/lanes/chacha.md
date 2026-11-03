# lane: chacha

ChaCha20-Poly1305 (RFC 8439), the AEAD chaki's TLS prefers. Pure ARX, so it's a natural
fit for software. Monocypher and TweetNaCl are the model.

## Files you own

`lib/chaki/chacha.bend`, `test/chaki_chacha_check.bend`.

## API (exact)

```python
# one 64-byte keystream block (key 32 bytes, nonce 12)
def block(key: List<&2, U32>, counter: U32, nonce: List<&2, U32>) -> List<&2, U32>
# data xor the keystream from counter on
def chacha20(key: List<&2, U32>, nonce: List<&2, U32>, counter: U32, data: List<&2, U32>) -> List<&2, U32>
# the 16-byte tag of msg under a one-time 32-byte key
def poly1305(key: List<&2, U32>, msg: List<&2, U32>) -> List<&2, U32>
# ciphertext followed by the 16-byte tag
def seal(key: List<&2, U32>, nonce: List<&2, U32>, aad: List<&2, U32>, plain: List<&2, U32>) -> List<&2, U32>
# the plaintext, or None when the tag doesn't match (compared in constant time) or sealed
# is shorter than a tag
def open(key: List<&2, U32>, nonce: List<&2, U32>, aad: List<&2, U32>, sealed: List<&2, U32>) -> Maybe<&2, List<&2, U32>>
```

## How

- Poly1305 needs 130-bit arithmetic and U32.mul keeps only 32 bits: use 16-bit limbs (or
  13-bit, as some small implementations do), so every product fits, and carry explicitly.
  Then do the final reduction and the add of s modulo 2^128 exactly.
- The quarter round and the 20 rounds go in small defs with the 16-word state in a
  constructor. Native builds reject wide defs.
- No secret-dependent branches in the tag comparison.

## Checks

`test/chaki_chacha_check.bend`, verbatim from RFC 8439: 2.1.1 (quarter round), 2.3.2
(block), 2.4.2 (encryption), 2.5.2 (Poly1305), 2.6.2 (key generation), 2.8.2 (AEAD), and
Appendix A.1 #1-#5, A.2 #1-#3, A.3 #1-#11 (the Poly1305 edge cases matter most), A.4 #1-#3,
and A.5. Tampering: flipping one bit of the ciphertext, the tag or the AAD makes `open`
answer None. A 1 MB seal and open round-trips.
