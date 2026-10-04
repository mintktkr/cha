# lane: text

UTF-8 and base64: the two text encodings everything above them needs.

## Files you own

`lib/chaki/utf8.bend`, `lib/chaki/b64.bend`, `test/chaki_utf8_check.bend`,
`test/chaki_b64_check.bend`.

## API (exact)

```python
# utf8.bend
# a String's UTF-8 bytes. A Char that isn't a Unicode scalar value (a surrogate, or past
# U+10FFFF) becomes U+FFFD's bytes.
def encode(s: String) -> List<&2, U32>

# bytes as text. Each maximal ill-formed subpart becomes one U+FFFD, as the Unicode
# Standard (ch. 3, "U+FFFD Substitution of Maximal Subparts") and WHATWG's decoder do.
def decode(b: List<&2, U32>) -> String

# whether b is well-formed UTF-8 (no overlongs, surrogates or values past U+10FFFF)
def valid(b: List<&2, U32>) -> Bool

# b64.bend
# RFC 4648 base64, padded
def encode(b: List<&2, U32>) -> String

# strict: whitespace (space, tab, CR, LF) is skipped; anything else outside the alphabet,
# wrong padding, or non-zero padding bits answer None
def decode(s: String) -> Maybe<&2, List<&2, U32>>

# the payload of every "-----BEGIN <label>-----" .. "-----END <label>-----" block in text,
# in order. Text outside blocks is ignored; a block that doesn't decode is skipped.
def pem(text: String, label: String) -> List<&2, List<&2, U32>>
```

## How

- UTF-8 decoding branches on byte values, which Bend won't let you match on directly. The
  classify-then-match pattern fits: map each byte to a small class (ascii, continuation,
  lead2, lead3, lead4, the E0/ED/F0/F4 special leads, invalid), then run one recursive state
  machine over the classes with nested patterns. Björn Höhrmann's DFA decoder is the model.
- Everything is a tail call (accumulate, then reverse). A CA bundle is ~220 KB of PEM.

## Checks

- `test/chaki_utf8_check.bend`: ASCII, 2/3/4-byte characters (é, 茶, 😀) both ways.
  Overlongs (C0 AF, E0 80 AF, F0 80 80 AF), surrogates (ED A0 80), past U+10FFFF (F4 90 80 80),
  stray continuations, and truncated sequences at the end. The maximal-subpart cases from
  the Unicode Standard's Table 3-8 (`61 F1 80 80 E1 80 C2 62 80 63 80 BF 64` decodes to
  `a\uFFFD\uFFFD\uFFFDb\uFFFDc\uFFFD\uFFFDd`). `valid` on each. A 300 KB round trip finishes.
- `test/chaki_b64_check.bend`: the RFC 4648 §10 vectors both ways (empty, f, fo, foo, foob,
  fooba, foobar). Rejects: bad characters, bad padding (`Zg=`, `Zg===`), non-zero padding bits
  (`Zh==`). Whitespace inside is skipped. `pem` on a text with two CERTIFICATE blocks and junk
  around them gives two payloads; a different label gives none. A 150 KB round trip finishes.
