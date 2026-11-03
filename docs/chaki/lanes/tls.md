# lane: tls

A TLS 1.3 client in Bend (RFC 8446), small and strict:
- one key exchange (x25519) and two suites (TLS_CHACHA20_POLY1305_SHA256 preferred,
  TLS_AES_128_GCM_SHA256);
- no PSK, no 0-RTT, no client certificates, no TLS 1.2.

A server that can't do that gets a clear error, and cha falls back to the `ossl` transport.

## Builds on

`tlsmsg.bend` (all the wire formats), `x25519.bend`, `sha2.bend` (transcript hash, HKDF,
expand_label), `chacha.bend`, `aes.bend`, `rsa.bend` and `ecdsa.bend` (CertificateVerify),
`x509.bend` and `x509v.bend` (the chain), and `sys.bend` (sockets, clock). Randomness comes
from Base's `IO.random_u32`, which is getrandom.

## Files you own

`lib/chaki/tls.bend`, `test/chaki_tls_check.bend`, `test/chaki_tls_live.bend`.

## Shape: a pure core and a thin IO shell

The handshake and record layer are a pure state machine over bytes, so the RFC 8448 trace
can drive it offline. The shell does the socket reads and writes, the randomness and the
clock.

```python
# --- pure core ---
# Hs is your Data type: transcript, keys, sequence numbers, buffers, the phase.
# random 32, session 32, priv the 32-byte x25519 private key. Answers the state and the
# bytes to send (the ClientHello record).
def hs.start(random: List<&2, U32>, session: List<&2, U32>, priv: List<&2, U32>, host: String) -> Hs & List<&2, U32>

type Event is Data:
  Need{}                                     # feed more bytes
  # the whole server flight is in and its Finished MAC checked: the shell must now verify the
  # chain AND that sig is the leaf key's signature (scheme) over signed, the
  # CertificateVerify content (64 spaces, the context string, 0x00, the transcript hash)
  Check{certs: List<&2, List<&2, U32>>, scheme: U32, signed: List<&2, U32>, sig: List<&2, U32>}
  Ready{}                                    # handshake done; app data may flow
  Data{bytes: List<&2, U32>}                 # application data
  Closed{}                                   # close_notify
  Failed{why: String}

# feed bytes from the wire. Answers the new state, bytes to send (client Finished, a
# KeyUpdate answer, ..), and what happened.
def hs.input(st: Hs, bytes: List<&2, U32>) -> Hs & List<&2, U32> & List<&2, Event>

# the shell's verdict on Check: True sends the client Finished and answers Ready,
# False answers Failed. Nothing but Need can come before this.
def hs.trusted(st: Hs, ok: Bool) -> Hs & List<&2, U32> & List<&2, Event>

# application data to send, as records (chunks of at most 2^14 bytes)
def hs.send(st: Hs, data: List<&2, U32>) -> Hs & List<&2, U32>
# a close_notify alert record
def hs.close(st: Hs) -> List<&2, U32>

# --- the shell ---
type Conn is Type:
  Conn{sock: Socket, st: Hs, buf: List<&2, U32>}

# handshake on a connected socket; verifies the chain with X509v.verify(chain, anchors,
# host, Sys.now()). On failure the socket is closed.
def connect(sock: Socket, host: String, anchors: List<&2, X509.Cert>, ms: U32) -> IO(Result<&1, &1, U32 & String, Conn>)
def send(c: Conn, data: List<&2, U32>) -> IO(Conn & Result<&1, &1, U32 & String, Unit>)
# up to max bytes, waiting at most ms; Done{[]} after close_notify
def recv(c: Conn, max: U32, ms: U32) -> IO(Conn & Result<&1, &1, U32 & String, List<&2, U32>>)
def close(c: Conn) -> IO(Unit)
```

You may reshape the core's internals and its Event type if it gets cleaner. Keep the
shell's four defs exactly as written, because the `http` lane is built against them.

## Protocol rules

- Key schedule as RFC 8446 §7.1. The transcript is the concatenated `raw` of every handshake
  message. Record nonce: iv xor the 64-bit sequence number (§5.3). AAD: the 5-byte record
  header.
- Accept the legacy ChangeCipherSpec record (one 0x01 byte) only during the handshake, and
  ignore it. Send one before the client Finished (middlebox compatibility, §D.4).
- Server flight order: ServerHello, then encrypted EncryptedExtensions, Certificate,
  CertificateVerify and Finished. Anything else, or anything out of order, is Failed. So is a
  HelloRetryRequest, since only x25519 is ever offered.
- CertificateVerify (the shell checks it, through Check): 64 spaces, "TLS 1.3, server CertificateVerify", a 0x00 byte, then
  the transcript hash. Allowed schemes: 0x0403 (P-256/SHA-256), 0x0503 (P-384/SHA-384),
  0x0804 (PSS/SHA-256) and 0x0805 (PSS/SHA-384), checked against the leaf's key type. The
  pkcs1 schemes are refused here (§4.4.3).
- Finished: HMAC(finished_key, transcript hash), compared in constant time.
- After the handshake: ignore NewSessionTicket. Answer a KeyUpdate (rotate the read key,
  and if update_requested, send your own and rotate the write key). close_notify becomes
  Closed. Any other alert is Failed with its name. A record that doesn't decrypt is
  Failed (bad_record_mac).
- Never put a key, a secret or plaintext in a `why`.

## Two stages

The core doesn't import rsa, ecdsa, x509 or x509v: signature and chain checks reach it only as
`hs.trusted`. So build it in two stages:

1. Now: the pure core and `test/chaki_tls_check.bend` (offline, RFC 8448). Everything it
   needs (tlsmsg, x25519, sha2, chacha, aes) is already in your worktree. Commit, and report
   stage 1 done.
2. When the integrator says rsa, ecdsa, x509, x509v and sys have landed (merge `memu/chaki`
   into your branch then): the shell. `connect` turns Check into one verdict: X509v.verify
   on the chain, then the leaf's key against the scheme: 0x0403/0x0503 via Ecdsa.verify.der
   with the curve the leaf names, and 0x0804/0x0805 via Rsa.pss with SHA-256/384. Then the
   live test.

If stage 2 hasn't been called when stage 1 is done, end your run with the stage 1 report.

## Checks

- `test/chaki_tls_check.bend` (offline): replay RFC 8448 §3 (Simple 1-RTT). Feed `hs.start`
  the RFC's client random, its legacy session id (the RFC's ClientHello has an empty one, so
  reproduce the RFC's ClientHello only where your format allows, and assert on the derived
  values instead) and its x25519 private key. Feed `hs.input` the server's records exactly
  as printed. Then:
  - the handshake secrets, the server Finished check, the client Finished bytes, and the
    application traffic keys all equal the RFC's values;
  - `Check` carries the RFC's certificate, scheme 0x0804, and the signed content and
    signature the RFC's CertificateVerify implies;
  - after `hs.trusted(True)` the state is Ready;
  - the server's encrypted application data decrypts to the RFC's plaintext.
  Also a tampered byte in each encrypted server record gives Failed, and so does
  `hs.trusted(False)`.
- `test/chaki_tls_live.bend` (by hand, run it and report). `GET /` over `connect` to
  example.com, api.github.com (`/zen`), codeberg.org and gitea.com. Refused:
  expired.badssl.com, wrong.host.badssl.com, self-signed.badssl.com and
  untrusted-root.badssl.com. Say which suite each server picked.
