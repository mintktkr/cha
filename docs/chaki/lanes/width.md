# lane: width

How many terminal columns a piece of text takes, for aligned tables. Markus Kuhn's
`mk_wcwidth` is the model, with the table regenerated from Unicode 17.0.0.

## Files you own

`scripts/chaki-width.ts` (the generator, run with bun), `lib/chaki/width.bend` (generated:
don't hand-edit), `test/chaki_width_check.bend`.

## API (exact)

```python
# columns one character takes: 0, 1 or 2
def char(c: U32) -> U32

# columns a whole String takes (the sum)
def text(s: String) -> U32
```

## Rules

- 0: C0 and C1 controls, DEL, ZWJ U+200D and ZWNJ U+200C, and the general categories Mn,
  Me and Cf (except U+00AD SOFT HYPHEN, which is 1). Also variation selectors (FE00..FE0F,
  E0100..E01EF) and Hangul Jamo medial vowels and final consonants (U+1160..U+11FF).
- 2: East_Asian_Width W or F, and characters with Emoji_Presentation=Yes.
- 1: everything else, including unassigned code points.

## How

- The generator downloads `EastAsianWidth.txt`, `extracted/DerivedGeneralCategory.txt` and
  `emoji/emoji-data.txt` from `https://www.unicode.org/Public/17.0.0/ucd/`, merges adjacent
  ranges of equal width, and emits `width.bend` with a header naming the source and version.
- Lookup must be fast and stateless: emit the ranges as a balanced binary search, as a tree of
  small defs where each node compares once and picks a child. Since a def only sees defs
  above it, emit leaves first. Printable ASCII (0x20..0x7E) is 1 before any search.
- `text` is a tail call over the String.

## Checks

`test/chaki_width_check.bend`: `a` 1, `é` precomposed 1, U+0301 combining acute 0, `あ` 2,
`中` 2, `한` 2, `😀` 2, U+FE0F 0, ZWJ 0, U+00AD 1, U+1F1E6 (regional indicator A) 2, tab 0,
U+0007 0, `cha 茶` 6, `日本語` 6, and the edge code points of a few ranges both sides
(U+10FF 1, U+1100 2, U+115F 2, U+1160 0). Add 20 spot checks the generator prints as it
runs, from its own data.
