# Porting cha's commands from bend-kit to chaki

The shared layer is already ported on `memu/chaki-port`: `src/api.bend`, `src/cli.bend`,
`src/ui.bend`, `src/help.bend`, `src/url.bend`, `src/since.bend`, `src/runlogs.bend`, and
`test/since_check.bend`. Read them first; they're the pattern. Your lane ports the command
files and tests it owns, so that no file under `src/` or `test/` imports a hub package
(`0x...` or `bend-kit-...`) any more.

`lib/chaki/http.bend` on this branch is a temporary stub with the real module's
signatures. Requests answer `Broke{"stub"}`. That's fine, because your checks are offline.
Don't edit it.

## The mapping

| bend-kit | chaki |
|---|---|
| `import 0x...json.bend as Json` | `import ../../lib/chaki/json.bend as Json` (from `src/cmd/`; `../lib/chaki/..` from `test/`) |
| `import 0x...bytes.bend as Bytes` | `import ../../lib/chaki/bytes.bend as Bytes`, only if you still need a helper |
| `import 0x...encoding.bend as Enc` | `import ../../lib/chaki/utf8.bend as Utf8` |
| `import 0x...time.bend as Time` | `import ../../lib/chaki/time.bend as Time` (and `sys.bend as Sys` for the clock) |
| `import 0x...int.bend as Int` | gone: use U32 |
| `import bend-kit-hairpin..` / `bend-kit-http..` | gone: requests go through `Api` |
| `Bytes.Bytes` (the type) | `List<&2, U32>` |
| `Bytes.to_string(b)` | `Bytes.to_ascii(b)` (one Char per byte), or `Utf8.decode(b)` for text |
| `Bytes.from_string(s)` | `Utf8.encode(s)` for text, `Bytes.of_ascii(s)` for protocol ASCII |
| `Bytes.length(b)` (answered `(b, n)`) | `Bytes.len(b)` (answers just the U32; the list is Data, so keep it with `+b`) |
| `Bytes.concat`, `Bytes.new`, `Bytes.set` | `Bytes.cat`, list literals, rebuilding a list |
| `Enc.utf8.encode(s)` / `Enc.utf8.decode(b)` | `Utf8.encode(s)` / `Utf8.decode(b)` |
| `Time.Instant` | `U32`: Unix seconds |
| `Time.now()` | `Sys.now()` (wall clock, U32) |
| `Time.rfc3339.parse(s)` | `Time.parse(s)`: `Maybe<&2, U32>`, fraction dropped |
| `Time.rfc3339(i)` | `Time.show(t)` (always succeeds, no Maybe) |
| `Time.Instant.cmp(a, b)` | `U32.cmp(a, b)`, or `U32.is_lt` and friends |
| `Time.Instant.since(a, b)`, Durations, `Int.I64` | plain U32 seconds: `(a - b : U32)` guarded by `U32.is_ge(a, b)` |
| `Time.Instant.epoch()` | `0` |
| `Json.Val` built for a request body | chaki's `Json.Val` (`Str{text: String}`, `Num{text: String}`, `Flag{on}`, `Null{}`, `Arr{xs}`, `Obj{kvs}`) |
| `(Json.utf8(k), v)` an object member | `(k, v)`, a `Json.Member()` |
| `List<&1, Bytes.Bytes & Json.Val>` | `List<&2, Json.Member()>` |
| `List<&1, Json.Val>` | `List<&2, Json.Val>` |
| `Api.utf8(s)` | still works (it's `Json.Str{s}`) |
| `Json.Num{Bytes.from_string(s)}` | `Json.Num{s}` |
| `Map<&2, List<&2, String>>` request headers | `List<&2, Http1.Field()>` (`import ../../lib/chaki/http1.bend as Http1`), built as `[("content-type", "..")]`; `Api.header.one(k, v)` still works |
| a Hairpin client with its own `accept` | `Api.get.accept(repo, tok, url, accept)` |
| `Http.Res`, `Http.Err`, `Hairpin.*` | gone: everything answers `Api.Reply` |

`Api` keeps every name the commands use: `Reply`, `Broke`, `path`, `send`, `send.raw`, `get`,
`ok`, `raw.text`, `text`, `utf8`, `json.bool`, `rows`, `obj`, `raw.f`, `f`, `f.lines`,
`raw.join`, `join`, `count`, `message`, `all`, `base`. A reply's `body` is now
`List<&2, U32>` (Data), so you can pass it on with `+body`.

## Rules

- Keep behavior identical: the same output, the same errors, the same flags. Change only
  what the mapping forces. Where a type change makes code simpler (Instants becoming U32s
  often does), take it, but no unrelated refactors.
- Keep `AGENTS.md`'s laws: no secrets in output, plain output when piped, and the Bend
  patterns.
- A check that compared Instants or durations compares U32 seconds now. Keep every case it
  had; keep the expected text the same unless the old value was an artifact of the old
  type (say so in your report).
- Type-check with `bend src/cmd/<file>.bend --check-only`. A run that ends in "N defs
  rely on unsafe or foreign code" plus that list is green (the network and tty effects).
  Run your tests with `bend test/<file>_check.bend`, natively too.
- Never run `scripts/check.sh` or `bend main.bend`; the integrator does.
- Commit as memu, your files only.
