# Contributing to cha 茶

Humans and agents are both welcome, under the same rules. Those rules live in [AGENTS.md](AGENTS.md). Read it before your first change: it covers the layout, the Bend walls everyone hits, the forge quirks and the hard rules.

## Before you start

- **Bugs and ideas** go in an [issue](https://github.com/mintktkr/cha/issues/new/choose). Say which forge (GitHub, Gitea or Forgejo) and paste the command with its output.
- **Security problems**, such as a token showing up in output, never go in a public issue. See [SECURITY.md](SECURITY.md).
- **Looking for something to do?** Issues labelled [`good first issue`](https://github.com/mintktkr/cha/labels/good%20first%20issue) are small and self-contained. [`ready-for-agent`](https://github.com/mintktkr/cha/labels/ready-for-agent) issues are fully specified, so a coding agent can pick them up.

## Setup

1. Install [Bend](https://bend-lang.com) **2.0.34** exactly, plus [Bun](https://bun.sh) (`scripts/order.ts` needs it) and clang for native builds.
2. Run cha from source: `bend main.bend -- issue list -R github.com/bendlang/bend`.
3. Run the checks: `scripts/check.sh`. It checks definition order, type-checks every file, proves the laws in `LAWS.bend` and runs the offline checks in `test/*_check.bend`.

Every bend run takes 2-3 GB of memory. Run one at a time.

## Making a change

1. Fork, then branch: `<you>/<topic>`, for example `ana/runs-step`.
2. Keep commits small, with plain messages: `runs logs: strip a leading BOM`. No attribution trailers or `Co-Authored-By` lines.
3. If you add or change a command or flag, update `skills/cha/SKILL.md` and `cha help` in the same PR.
4. Test against public repos only, for example `-R codeberg.org/forgejo/forgejo` or `-R github.com/bendlang/bend`. Fixtures must be synthetic or taken from public repos.
5. Run `scripts/check.sh`, then open a pull request. CI runs the same script, and a PR merges only when it's green.

## What won't be merged

- Runtime dependencies. cha never shells out to `gh`, `tea`, `git`, `curl` or `jq`.
- Anything that can put a token in output, errors, `--json` or debug dumps.
- Colour or escape codes when the stream isn't a terminal, and prompts when stdin isn't one.
- A floating hub or toolchain version. Bumps are deliberate and get their own commit.

## Agents

If you're an agent, AGENTS.md is written for you. The [agent skill](skills/cha/SKILL.md) teaches you how to *use* cha. `docs/agents/` covers the issue tracker and triage labels.

## Conduct

Everyone here follows the [code of conduct](CODE_OF_CONDUCT.md).
