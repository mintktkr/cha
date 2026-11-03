# lane: rsa

RSA signature verification, as certificate chains and TLS 1.3 CertificateVerify need it.
Verification only: no keys are generated and nothing is signed.

## Builds on

`big.bend` (modexp), `sha2.bend` (hash, and the MGF1 hash), `bytes.bend`.

## Files you own

`lib/chaki/rsa.bend`, `test/chaki_rsa_check.bend`.

## API (exact)

```python
# RSASSA-PKCS1-v1_5 (RFC 8017 §8.2.2): EMSA-PKCS1-v1_5 with the DigestInfo for a.
# n and e are big-endian bytes (as X509.rsa_key gives them).
def pkcs1(a: Sha2.Alg, n: List<&2, U32>, e: List<&2, U32>, msg: List<&2, U32>, sig: List<&2, U32>) -> Bool

# RSASSA-PSS (RFC 8017 §8.1.2): MGF1 with the same hash, salt length = hash length, which is
# what TLS 1.3's rsa_pss_rsae_* schemes and the web PKI use
def pss(a: Sha2.Alg, n: List<&2, U32>, e: List<&2, U32>, msg: List<&2, U32>, sig: List<&2, U32>) -> Bool
```

## Rules

- A signature whose length isn't the modulus length, or whose value isn't below n, is
  false. So is a modulus under 2048 bits, or an exponent that is even or 1.
- PKCS#1 v1.5: rebuild the expected encoded message and compare all of it in constant time.
  Never parse the decrypted block (that's how Bleichenbacher's forgeries work).
- PSS: follow EMSA-PSS-VERIFY step by step, including the leftmost-bits mask and the 0x01
  separator check.

## Checks

`test/chaki_rsa_check.bend`. Generate the fixtures with `openssl` (keep the commands in a
comment): RSA-2048 and RSA-4096 keys, and a fixed message signed with PKCS#1 v1.5 and with
PSS (`-sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:digest`) for SHA-256, SHA-384
and SHA-512. Every one verifies. Each of these is false: a flipped bit in the signature or
the message, the wrong hash, a PKCS#1 signature checked as PSS and the reverse, a signature
one byte short, and a 1024-bit key. Report the time of one 4096-bit verify on both lanes.
