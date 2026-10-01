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
