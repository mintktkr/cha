# chaki worker brief

You are building one module of chaki, cha's own Bend library (`lib/chaki/README.md` has the
whole map). Your lane file (`docs/chaki/lanes/<lane>.md`) says exactly what to build. This
file is what every lane shares. Read both fully before writing code.

## Where you are

- Your cwd is your own git worktree, `~/dev/cha-wt/chaki-<lane>`, on branch
  `memu/chaki-<lane>`. Nobody else writes here. Only touch the files your lane owns.
- `lib/chaki/bytes.bend` and `lib/chaki/check.bend` already exist. Use them, don't edit them.
  If you need a byte helper they lack, write it in your own module.
- Don't modify anything under `src/`, `main.bend`, `LAWS.bend`, `PROOF.bend` or `scripts/`.

## Running bend

bend is memory-hungry (2-3 GB a run on the JS lane), so the build ran on one shared machine,
with a few slots at a time:

```bash
bend test/chaki_<module>_check.bend          # check, then run main on the JS lane
bend lib/chaki/<module>.bend --check-only    # type-check only
bend test/chaki_<module>_check.bend -o out/t && ./out/t   # native build, then run it
```

- A JS-lane run of a small module takes 10-30 s. A native build takes 1-4 min.
- Put native binaries under `out/` (it's in `.gitignore`).
- Never run `scripts/check.sh` or `bend main.bend` from a lane: the integrator runs the full
  gate when a lane lands. Run only your own checks.
- `bun scripts/order.ts lib/chaki/<module>.bend` checks def order without bend.

## The language

Read `~/.bend/guide/GUIDE.md` (the whole language, ~700 lines) before you write code. For
custom effects (only the `sys` and `ossl` lanes), also read `~/.bend/guide/EFFECTS.md` and the
reference effects in `~/.bend/bend2/effs/`. Base is `~/.bend/bend2/base.bend`: grep it for
the exact signature of anything you call.

The walls everyone hits, with the fix:

- **`match` only on a parameter or a pattern-bound variable.** Not on a call result. A `let`
  may not come before a `match` on a parameter. To branch on a computed value, pass it to a
  helper that matches on its own parameter: `def x.if(.., ok: Bool)`. `src/` is full of these.
- **A def only sees defs above it.** Helpers go first.
- **No mutual recursion.** Use classify-then-match (map items to a small Data type, then
  recurse over the classified list with nested patterns) or one fuel-counted state machine
  (first argument a `Nat` fuel, second a state constructor, one fuel per step).
- **Termination:** a recursive call must pass a smaller piece of a pattern-matched argument,
  and arguments are read left to right, so put the one that shrinks first.
- **Affine by default.** A variable is used at most once. Write `+x` on a parameter, pattern
  field or let to reuse a Data value. Lists of U32 are `List<&2, U32>`, which is Data.
- **Operators need a type and spaces**: `(a + b : U32)`, `(x .^. y : U32)`. Use `U32.is_eq`
  for equality; `==` is only the type of a proof.
- **`U32.shl` / `U32.shr` shift by ONE bit.** Use `U32.shln(x, 8n)` / `U32.shrn(x, 8n)` (a Nat
  count) or `(x << 8n : U32)`. Rotations: `U32.or(U32.shln(x, k), U32.shrn(x, 32 - k))`.
- **U32.mul keeps only the low 32 bits.** For wide products use 16-bit limbs, so every
  product fits, and carry by hand.
- **`Bool.pick(T, c, a, b)` evaluates both `a` and `b`.** Fine for cheap values. Never put a
  recursive call or expensive work in it; use a match helper instead.
- **Keywords you can't use as names:** `is`, `where`, `match`, `case`, `def`, `type`, `law`,
  `import`, `as`, `do`, `return`. Base already has types such as `Word`; check
  `bend base --types`.
- **Tail calls for anything body-sized.** Non-tail recursion over a long list (≈30k deep)
  overflows the JS lane. Accumulate and reverse (`Bytes.rev`, `Bytes.cat`).
- **Keep defs small.** A native build refuses a def that keeps more than 247 words alive across
  a call ("an arity over 247"), and a build just under the limit has produced a wrong binary.
  Long straight-line code (a hash round, a field multiply) goes in several small defs, with
  state packed into a constructor of a few fields. Run a native build of your check before
  you call the lane done. The JS lane doesn't catch this.
- **A tuple `A & B` is affine** (Kind &1), even when A and B are Data, so `List<&2, A & B>`
  and `Maybe<&2, A & B>` don't typecheck. Name a Data pair instead:
  `def Field() -> Data: Sigma<&2, &2, String, _ => String>`, then `List<&2, Field()>`. Tuples
  `(a, b)` still build and destructure it.
- **Arrays** (`Array<U32>`) are mutable in place but affine: every read hands the array back.
  Prefer lists and constructors unless a table lookup is on the hot path.
- `bend PROOF.bend` is the project's proof gate and has nothing to do with your lane. Don't
  add laws unless your lane says to.

## Tests

- Your check is `test/chaki_<module>_check.bend`. It imports your module and
  `../lib/chaki/check.bend as T`, and its `main` prints one line per case with `T.eq`,
  `T.ok` or `T.hex`. It must print no `FAIL` line, and must pass on the JS lane **and**
  natively.
- Vectors come from the primary document (the RFC or FIPS text), copied verbatim. Fetch it:
  `curl -s https://www.rfc-editor.org/rfc/rfc8439.txt`. Name each case after its section
  ("RFC 8439 2.8.2 seal").
- Where your lane asks for a fixture you have to generate (certificates, signatures, big
  numbers), generate it with a tool on this machine (`openssl`, `bun`) and paste the result
  into the check as hex. Fixtures must be synthetic or public test vectors, never real
  private data. The repo is public.
- Also test the edges: empty input, one byte, block boundaries (55/56/63/64/65 bytes for a
  hash), maximum values, malformed input.

## Code style

- Match the style of `lib/chaki/bytes.bend`: a header comment saying what the module is, short
  comments above the public defs saying what they answer, and plain names (`seal`, `open`,
  `parse`). Private helpers are named after their public def with a dot suffix (`seal.go`).
- No dead code, no speculative options, no TODOs left in.
- Bytes are `List<&2, U32>`. Return `Maybe` or `Result` for anything that can fail on input.
  Never print or return secret material in an error.

## Committing

- Commit in your worktree as you reach green milestones. Stage your files by name (never
  `git add -A` or `git add .`). Author as memu, no trailers:
  `git -c user.name=memu -c user.email=memu@muu.space commit -m "chaki: <what>"`
- Don't push, don't merge, don't rebase, don't touch other branches.

## When you're done, or stuck

Finish with a report in this shape:

```
lane: <lane>
status: done | partial | blocked
files: <the files you own, with line counts>
api: <the public defs, with exact signatures>
checks: <the JS-lane and native results: how many ok, any FAIL>
commits: <hashes>
notes: <anything the integrator must know: limits, performance, open edges>
```

If you're blocked by something outside your lane (a Base bug, a contradiction in your spec),
say so in the report with the exact error. Don't work around it by editing files you don't
own. A truthful `partial` beats a fake `done`. Never weaken or skip a vector to get green.
