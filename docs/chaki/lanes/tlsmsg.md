# lane: tlsmsg

TLS 1.3 records and handshake messages as bytes: build the ClientHello, split records and
messages, and parse what a server sends. No crypto and no IO. The client that uses this
comes in a later lane.

## Files you own

`lib/chaki/tlsmsg.bend`, `test/chaki_tlsmsg_check.bend`.

## API (exact)

```python
# one record: content type, legacy version 0x0303, 16-bit length, payload
def record(ctype: U32, payload: List<&2, U32>) -> List<&2, U32>

type Rec is Data:
  Rec{ctype: U32, body: List<&2, U32>}

# the whole records at the front of buf, and the rest. None when a header is malformed: a
# bad type, a bad version, or a length past 2^14 + 256.
def records(buf: List<&2, U32>) -> Maybe<&2, List<&2, Rec> & List<&2, U32>>

# a handshake message: type, 24-bit length, body
def handshake(htype: U32, body: List<&2, U32>) -> List<&2, U32>

# raw is header plus body, which is what goes into the transcript hash
type Msg is Data:
  Msg{htype: U32, body: List<&2, U32>, raw: List<&2, U32>}

# the whole handshake messages at the front of buf (they may span records, so the caller
# concatenates record bodies), and the rest
def messages(buf: List<&2, U32>) -> List<&2, Msg> & List<&2, U32>

# the full ClientHello handshake message. random 32 bytes, session 32 bytes (middlebox
# compatibility), share the 32-byte x25519 public key. host "" (an IP literal) omits SNI.
def client_hello(random: List<&2, U32>, session: List<&2, U32>, host: String, share: List<&2, U32>) -> List<&2, U32>

type Hello is Data:
  Hello{suite: U32, share: List<&2, U32>, retry: Bool}

# a ServerHello body: the suite, the server's x25519 share, and whether it's really a
# HelloRetryRequest (its random is the RFC 8446 §4.1.3 constant). Fail when
# supported_versions isn't 0x0304, the group isn't x25519, or the suite isn't one offered.
def server_hello(body: List<&2, U32>) -> Result<&1, &1, String, Hello>

# the ALPN protocol the server picked, "" when none
def encrypted_extensions(body: List<&2, U32>) -> Result<&1, &1, String, String>

# the certificate DERs, leaf first (per-certificate extensions skipped)
def certificate(body: List<&2, U32>) -> Result<&1, &1, String, List<&2, List<&2, U32>>>

type Verify is Data:
  Verify{scheme: U32, sig: List<&2, U32>}

def certificate_verify(body: List<&2, U32>) -> Result<&1, &1, String, Verify>

# an alert's two bytes as text: "close_notify", "handshake_failure (40)", ..
def alert(body: List<&2, U32>) -> String

# TLSInnerPlaintext: strip the zero padding; the last non-zero byte is the real content
# type. None when it's all zeros.
def inner(plain: List<&2, U32>) -> Maybe<&2, Rec>
```

## The ClientHello, exactly

Legacy version 0x0303, the random, a 32-byte legacy session id, cipher suites
`[0x1303 TLS_CHACHA20_POLY1305_SHA256, 0x1301 TLS_AES_128_GCM_SHA256]`, and compression
`[0]`. Then these extensions, in this order:

- server_name (0), when host isn't empty;
- supported_groups (10): `[0x001d x25519]`;
- signature_algorithms (13): `[0x0403, 0x0503, 0x0804, 0x0805, 0x0401, 0x0501]`;
- supported_versions (43): `[0x0304]`;
- key_share (51): one x25519 entry;
- application_layer_protocol_negotiation (16): `["http/1.1"]`.

No PSK, no early data, no padding extension.

## Checks

`test/chaki_tlsmsg_check.bend`:

- Parse the server's flight from RFC 8448 §3 (Simple 1-RTT): ServerHello (suite 0x1301 and
  its share), EncryptedExtensions, Certificate (one cert, and its length), CertificateVerify
  (the scheme and signature length), and Finished. These are the decrypted handshake bytes
  the RFC prints.
- `records` and `messages` on that flight split byte-exactly, including a message spanning
  two records and a buffer cut mid-record (the rest comes back).
- `client_hello` with fixed inputs: walk the bytes back (every length field consistent, the
  extensions in order with their exact contents) and compare against hex you derive by hand
  from the layout above.
- A HelloRetryRequest is recognized. The wrong version, the wrong group, and an unoffered
  suite all fail.
- `inner` with padding, without, and all zeros. Alerts by name.
