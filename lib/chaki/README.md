# chaki 茶器

cha's own library: everything cha needs below its commands, written in Bend, with no hub
dependencies. It replaces bend-kit (hairpin, http, http2, hpack, wire, dns, zlib, json,
bytes, encoding, url, time, int, tty, concurrency).

The model is the small C libraries that run on edge devices: each does one job, holds no
hidden state, and has a surface you can read in one sitting.

| module | job | after |
|---|---|---|
| `bytes.bend` | byte strings as `List<&2, U32>`, hex, big-endian ints | lwIP pbufs, flattened |
| `check.bend` | the `ok` / `FAIL` line format of the offline checks | |
| `sys.bend` + `effs/sys.{c,js}` | the only foreign code: dial (getaddrinfo + connect with a deadline), recv with a deadline, wall clock, isatty, terminal columns | Mongoose's OS layer |
| `utf8.bend` | UTF-8 encode, decode (U+FFFD for bad input), validate | Björn Höhrmann's DFA |
| `b64.bend` | base64 and PEM blocks | RFC 4648 |
| `json.bend` | a flat reader (JSON straight to dotted-key rows, no tree) and a small writer | jsmn |
| `time.bend` | Unix seconds as U32, RFC 3339 parse and print | Howard Hinnant's date algorithms |
| `width.bend` | terminal display width of text (generated table) | mk_wcwidth |
| `url.bend` | http(s) URL parse, resolve (RFC 3986 §5.2), origin, percent-encoding | |
| `http1.bend` | HTTP/1.1 request writer and incremental response parser | picohttpparser |
| `asn1.bend`, `x509.bend` | DER reader and X.509 certificate parser | BearSSL's x509 minimal engine |
| `sha2.bend` | SHA-256/384/512, HMAC, HKDF, TLS 1.3 HKDF-Expand-Label | Monocypher |
| `chacha.bend` | ChaCha20, Poly1305, the RFC 8439 AEAD | Monocypher, TweetNaCl |
| `aes.bend` | AES-128/256 and GCM | BearSSL |
| `x25519.bend` | X25519 key exchange | TweetNaCl |
| `big.bend` | big naturals for RSA and ECDSA | BearSSL's i31 |
| `rsa.bend` | RSA PKCS#1 v1.5 and PSS signature verification | |
| `ecdsa.bend` | ECDSA P-256 and P-384 verification | |
| `x509v.bend` | chain building, trust anchors, hostname and time checks | BearSSL |
| `tlsmsg.bend` | TLS 1.3 records and handshake messages, as bytes | |
| `tls.bend` | the TLS 1.3 client | RFC 8446 |
| `ossl.bend` + `effs/ossl.{c,js}` | TLS through the system's OpenSSL 3 (dlopen), the fallback transport | |
| `http.bend` | the HTTP client: transport, redirects, the one request cha makes | |

## Conventions

- Bytes are `List<&2, U32>`, each 0..255. Text is `String`. Converting between them is
  always explicit (`Utf8.encode`, `Bytes.of_ascii`).
- Anything that walks a body is a tail call. Bodies are megabytes, and non-tail recursion
  that deep overflows the JS lane.
- Every module has `test/chaki_<module>_check.bend`, which runs offline and prints `ok` or
  `FAIL` lines through `check.bend`. Modules that talk to the network also have
  `test/chaki_<module>_live.bend`, run by hand.
- Crypto is checked against the published vectors of its RFC or FIPS document, verbatim.
- Secrets (keys, tokens, traffic secrets) never reach output, errors included.
- Import modules by relative path (`import ../lib/chaki/bytes.bend as Bytes`), never from
  the hub.
