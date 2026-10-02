# cha 茶

A forge CLI for Gitea, Forgejo and GitHub, written in Bend, with no runtime dependencies. See `README.md` for the pitch. This file covers how to work here.

## Who works here

Humans and agents, under the same rules. A coding agent named **memu** is a regular contributor. Its commits are authored `memu <memu@muu.space>`.

## Bend

- Run `bend guide` before writing Bend. The guide is the whole language.
- Toolchain: bend **2.0.34**. Don't bump it as a side effect. A bump is its own commit.
- Rules that must never break go in `LAWS.bend`. Run `bend PROOF.bend` before every commit. A red proof means the change doesn't land.
- Parallelize where it's natural, for example the independent requests in a sweep.
- Hub imports are pinned by hash. Never float a version. Hub packages churn daily, so a bump is deliberate and gets its own commit.

## Layout

| file | what |
|---|---|
| `main.bend` | entry: global flags (`-R`, `--json`), repo + token resolution, dispatch |
| `src/ctx.bend` | forge, host, repo from the checkout (worktrees too), tokens |
| `src/api.bend` | requests, `Reply`, pagination (`Api.all`), flat rows (`Api.rows`, `Api.obj`, `Api.f`, `Api.join`) |
| `src/cli.bend` | `Env` (what every command gets), `Cli.flag`, `Cli.has`, `Cli.arg`, `Cli.json.rows`, `Cli.fail` |
| `src/ui.bend` | palette, colour decision, `Ui.state`, `Ui.glow`, `Ui.info`/`error`/`done` |
| `src/help.bend` | `cha help` |
| `src/cmd/*.bend` | one file per command group, each exposing `run(env)` |
| `test/*_check.bend` | offline checks: `scripts/check.sh` runs them and they must exit 0 |
| `test/*_live.bend` | checks against real forges, run by hand |
| `LAWS.bend`, `PROOF.bend` | the laws and their proofs |
| `skills/cha/SKILL.md` | the agent skill. Keep it in step with the commands and flags |
| `docs/how.md` | how a command flows, with a diagram |
| `packaging/arch/` | PKGBUILD. Bump `pkgver` with `version()` in `main.bend` and tag `v<version>` |

`scripts/check.sh` checks definition order, type-checks every file, proves the laws and runs the offline checks. Run it before every commit. `bend PROOF.bend` on its own always ends with "SOME PROOFS FAIL" plus a list of defs relying on foreign code (the tty and http effects pulled in by `ui` and `api`). That's cha's green state. `check.sh` fails only on a law error, a TODO, or a law that itself relies on foreign code.

## Bend patterns used here

These are the walls every newcomer hits. `src/` has a working example of each.

- **`match` only on a parameter or a pattern-bound variable.** Not on a call result, not on a destructured call result, not on a lambda parameter. A `let` may not come before a `match` on a parameter. To branch on a computed value, pass it to a helper: `def x.if(.., cond: Bool)` that matches `cond`.
- **A def only sees defs above it.** Put helpers first. `bun scripts/order.ts <files>` lists violations.
- **No mutual recursion.** Two shapes replace it:
  - **classify, then match**: map each item to a small Data type with a non-recursive helper, then recurse over the classified list with nested patterns. See `Cli.flag` (`mark`, `flag.find`).
  - **a fuel-counted state machine**: one def whose first argument is a `Nat` fuel and whose second is a state constructor. Every step costs one fuel. See `Api.all.go`.
- **Affine by default.** `+x` makes a Data parameter or pattern field reusable. `Json.Val` is affine: reading one field consumes it. So never walk JSON in commands. Use `Api.rows(body)` / `Api.obj(body)` to get flat `Map<&2, String>` rows, then read them with `Api.f(row, "user.login")` and `Api.join(row, "labels", "name", ",")`.
- **Operators need a type**: `(a + b : U32)`. For `Nat`, prefer `Nat.sub`, `Nat.is_gt`, and so on.
- **Hub versions must match.** Import hairpin, http, json, bytes and encoding at exactly the hashes in `src/api.bend`. Each version is a distinct type.
- **JSON bodies** are `Json.Obj{[(Json.utf8(k), Api.utf8(v)), ..]}` passed to `Api.send(repo, tok, "POST", url, Some{body})`.
- **Name clashes**: Base already has types such as `Word`, and `where` is a keyword. Check `bend base --types`.
- **Running**:
  - `bend main.bend -- <args>` runs on the JS lane in seconds.
  - `bend main.bend --check-only` type-checks. For `main.bend` it always ends with a list of "defs that rely on unsafe or foreign code": that's the network and tty effects, and it's expected. A real error prints `Error:` with a `Location:`.
  - A native build, `bend main.bend -o out/cha`, takes minutes. Do it once at the end, not in the edit loop.
- **The JS lane is heavy.** Every `bend main.bend -- ...` recompiles the whole program and takes 2-3 GB of memory. Run one bend process at a time, wrapped in `timeout`. Several agents in parallel will exhaust a 16 GB machine.
- **A known JS-lane hang**: calling a helper that takes a `+Map` and returns a String from inside a recursive row-mapping def can loop forever with runaway memory (likely upstream bendlang/bend#1206). If a run hangs, inline the call.
- **Wall-clock time**: `IO.now()` is monotonic, not wall time. Use `Time.now()` from `0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend` (bend-kit-time@0.1.0.0, already a hairpin dependency).
- **Live tests**: read anonymously from public forges, for example `-R codeberg.org/forgejo/forgejo` or `-R github.com/bendlang/bend`. Only write to repos you were explicitly given for testing.

## Forge quirks cha handles

- Gitea 1.25 ignores `limit` unless `page` is also sent.
- Gitea creates issues with label IDs, ignores unknown label names on add, and replaces the whole set on `PUT .../labels`, wiping it for an unknown name. Resolve names before any write.
- Gitea answers a blocked merge with HTTP 405 "Please try again later". It means a conflict or a moved base, not a rate limit.
- Gitea 1.25 has no API to rerun or cancel an Actions run.
- Gitea timestamps carry a local offset (`-03:00`), so compare parsed instants, never strings.
- GitHub lists pull requests among issues (they carry `pull_request.url`) and 404s on a trailing slash after `repos/o/r`.
- `actions/runs` answers an object (`workflow_runs`), not an array.

## Hard rules

- **No runtime dependencies.** Don't shell out to `gh`, `tea`, `git`, `curl` or `jq`. cha speaks HTTPS and JSON itself.
- **Agent-first output.**
  - Colour and animation only when the stream is a terminal, `NO_COLOR` is unset and `TERM` isn't `dumb`. Decide per stream.
  - Spinners go to stderr only.
  - Never prompt or open an editor unless stdin is a terminal.
- **Secrets never reach output**: not in errors, not in `--json`, not in debug dumps. This is a law, not a guideline.
- **Public repo.** Never commit:
  - private hostnames, private org or repo names, tokens, or real issue content from private forges
  - test fixtures that aren't synthetic or taken from public repositories

## Look and feel

The palette is pink `ff6eb4`, lemon `ffe14d`, aqua `6ef3ff`, mint `6ef2b8`, plus a pink → lavender → mint glow gradient.

Every colour carries meaning:

| colour | meaning |
|---|---|
| mint | success, open |
| pink | failure |
| lemon | running |
| dim | queued, closed |
| lavender `d67fe8` | merged |

Glyphs: `✓` for ok, `✗` for errors.

- **Working output** (lists, views, logs) stays calm. No kaomoji, and nothing moves except the spinner and `runs watch`.
- **`help`, `about` and the banner** are where cha gets to play: glow, animation, kaomoji. They're terminal-only, of course. Piped, they're plain text.

## Commits and PRs

- Small commits with plain messages. No attribution trailers or `Co-Authored-By` lines.
- Stage specific files, never `git add -A`.
- Maintainers, memu included, commit straight to `main` for now. Keep `main` green: `bend PROOF.bend` and the checks pass before every push.
- Outside contributors work on a branch and open a PR. The maintainer merges.
- Parallel agent work happens in separate worktrees on `<agent>/<topic>` branches, for example `memu/pagination`, so the agents never share a checkout.

## Agent skills

### Issue tracker

GitHub Issues on `mintktkr/cha`. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default roles (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root, created lazily. See `docs/agents/domain.md`.
