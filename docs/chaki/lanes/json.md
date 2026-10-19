# lane: json

JSON for cha: a flat reader and a small writer. jsmn is the model. One pass over the bytes,
no tree, and the output is exactly what cha's commands already consume: rows of
`Map<&2, String>` keyed by dotted paths.

## Files you own

`lib/chaki/json.bend`, `test/chaki_json_check.bend`.

## API (exact)

```python
# a value to write. Text is a String (decoded); Num holds its digits as written.
type Val is Data:
  Null{}
  Flag{on: Bool}
  Num{text: String}
  Str{text: String}
  Arr{xs: List<&2, Val>}
  Obj{kvs: List<&2, String & Val>}

# compact RFC 8259 text, keys in the order given
def encode(v: Val) -> String

# a whole JSON document flattened (rules below); None when it isn't valid JSON
def flat(b: List<&2, U32>) -> Maybe<&2, Map<&2, String>>

# the elements of a top-level array, each flattened from its own root; [] when the
# document isn't an array or isn't valid
def rows(b: List<&2, U32>) -> List<&2, Map<&2, String>>

# the elements of the array at member key of a top-level object ({"workflow_runs": [..]})
def rows.at(b: List<&2, U32>, key: String) -> List<&2, Map<&2, String>>

# a top-level document flattened; an empty map when it isn't valid
def obj(b: List<&2, U32>) -> Map<&2, String>
```

## Flattening rules (cha depends on every one)

These are the rules of `flat` in `src/api.bend`, which this replaces. Read it.

- An object member's key is `prefix.member`, or just `member` at the root.
- An array element's key is `prefix.i` (0-based), and the array also sets `prefix.#` to its
  length as text. `{"labels": [{"name": "x"}]}` gives `labels.0.name = x`, `labels.# = 1`.
  An empty array gives only `labels.# = 0`. An empty object gives nothing.
- A string is its decoded text. A number is its text as written. true and false are `true`
  and `false`, and null is `""`.
- A scalar at the root (or a scalar element of `rows`) is stored under the key `""`.
- Keys aren't escaped: a member named `a.b` just makes the key `prefix.a.b`.
- On a duplicate member, the last one wins.

## Reader rules

- Strict RFC 8259. Any syntax error makes the whole document invalid. Whitespace is space,
  tab, CR and LF.
- Escapes: `\" \\ \/ \b \f \n \r \t \uXXXX`. A surrogate pair joins into one character; a
  lone surrogate becomes U+FFFD. Raw bytes in strings are UTF-8 decoded, with U+FFFD for
  invalid input. Control characters below 0x20 must be escaped (raw ones are invalid).
- One left-to-right pass with an explicit stack of open containers (key prefix, next
  index). No recursion on nesting depth, and tail calls only. A page of 100 GitHub issues is
  ~500 KB, and a 2 MB document must parse in a few seconds on the JS lane.
- Bend won't match on byte values, so classify each byte first, then run one state machine
  over the classes. Count fuel from the byte length.

## Writer rules

Escape `"` and `\`. Write control characters below 0x20 as `\n \r \t \b \f`, or `\u00XX` for
the rest. Everything else (non-ASCII included) is written as is, and the caller UTF-8-encodes
the result.

## Checks

`test/chaki_json_check.bend`:

- Every flattening rule above, one case each.
- The shapes cha reads: a GitHub issue with `user.login`, `labels.0.name`, `labels.#` and
  `pull_request.url`; an `actions/runs` object read with `rows.at(b, "workflow_runs")`.
- Escapes, surrogate pairs (`"\ud83d\ude00"` is 😀), a lone surrogate, and raw UTF-8.
- About 30 invalid documents, each must come back None: trailing commas, single quotes,
  leading zeros (`01`), `+1`, `.5`, `1.`, `NaN`, unterminated strings, raw control
  characters, `{"a" 1}`, `[1 2]`, garbage after the value, an empty input.
- `encode` of a nested value with every escape, decoded back through `flat`.
- A generated array of 3000 objects parses, and `rows` has length 3000.
