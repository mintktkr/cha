# Exercising the write paths

cha's offline checks cover how requests are built, not whether a forge accepts them. So the write paths get a live run against a throwaway repo before any release that touches them. This page is that procedure, and #22 turns it into a script that runs on cha alone.

`OWNER/cha-sandbox` stands for that repo, and `C` for `cha -R github.com/OWNER/cha-sandbox`. Keep the repo private and delete it when you're done.

Test with a **native build** of the commit you mean to release (`bend main.bend -o out/cha`), not just the JS lane. The two lanes can differ: on 2026-10-03, `runs logs --step` built natively and returned a 404 that the JS lane never showed.

## Setup

The repo needs two workflows and two branches:

- `ci`: runs on push and on `workflow_dispatch` (input `note`), with one job that passes (`ok`) and one that fails (`flaky`, a step `fail on purpose`), so `rerun --failed` and `logs --failed` have something to work on.
- `slow`: `workflow_dispatch` only, one job that sleeps 15 minutes, for `cancel`.
- branches `feat-merge` and `feat-delete`, each one commit ahead of `main`, for two pull requests.

The token needs the `repo` scope (`cha auth status` names its source). `repo` covers dispatch, rerun and cancel. Workflow files are pushed with git, so the token never needs the `workflow` scope.

cha can't create or delete a repo yet (#22). Until it can, create the repo with `gh repo create OWNER/cha-sandbox --private` and delete it in the web UI.

Never trace these commands with `set -x` in a shell that also reads the token: the trace prints it.

## Checklist

On GitHub, an issue and a pull request share one number sequence: the first PR in a fresh repo after one issue is #2.

| area | command | expect |
|---|---|---|
| auth | `C auth status` | host, login, token source |
| labels | `C repo label-create cha-test --color ff6eb4 --description D`, `C repo labels` | the label is listed |
| issue | `C issue create --title T --body B --label cha-test` | URL of #1 |
| | `C issue comment 1 --body B` | comment URL |
| | `C issue edit 1 --title T2 --body B2` | `issue view 1` shows both |
| | `C issue labels 1 add X`, `remove X`, `set a,b` | `issue view 1` shows the set |
| | `C issue labels 1 add no-such-label` | fails (#19) |
| | `C issue close 1 --comment C`, `reopen 1`, `close 1` | state follows |
| pr | `C pr create --head feat-merge --base main --title T --body B` | URL of #2 |
| | `C pr edit 2 --title T2 --body B2`, `C pr comment 2 --body B` | `pr view 2 --comments` shows both |
| | `C pr diff 2` | the unified diff |
| | `C pr checks 2` | `flaky` failed, exit 1 |
| | `C pr comment 1 --body B` (an issue) | fails (#20) |
| | `C pr merge 2 --squash` | merged |
| | `C pr create --head feat-delete ...`, `C pr merge 3 --merge --delete-branch` | merged, `repo branches` no longer lists `feat-delete` |
| | `C pr merge 3` again | says it's merged (#20) |
| runs | `C runs dispatch ci.yml --ref main --input note=x` | a new `ci` run, its URL (#17) |
| | `C runs logs RUN --job ok --step "say hi"` | the step's section, with `hi x` |
| | `C runs logs RUN --failed` | `flaky`'s log |
| | `C runs dispatch slow.yml`, then `C runs cancel RUN` | `runs view RUN` says `cancelled` within seconds |
| | `C runs rerun RUN --failed` / `--job JOB` / no flag | attempt 2 (#21: `runs view` should show it) |
| | `C runs rerun RUN --job JOB-OF-ANOTHER-RUN` | `job does not belong to run`, exit 1 |
| | `C runs watch RUN` on a failed run | exit 1 |
| release | `C release create v0.0.1-test --title T --notes N --target main` | URL |
| | `C release upload v0.0.1-test FILE out/cha` | one download URL per file (#18) |
| | `C release view v0.0.1-test` | lists both assets; the binary downloads byte-identical |

## Results

**2026-10-03, github.com, cha main at 20fe816 + b372bf9, native build.** Everything in the table passed except:

- #17: `runs dispatch` names the wrong run (the dispatch itself works).
- #18: `release upload` fails with `HTTP 400: Bad Content-Length`. bend-kit's HTTP/2 client sends no `content-length`, so this needs an upstream fix.
- #19: `issue labels add` creates an unknown label.
- #20: `pr comment` accepts an issue number; merging a merged PR says nothing.
- #21: `runs view` doesn't show the attempt, so a rerun has to be checked through the API.

Gitea's write paths are still to be run the same way, against a Gitea sandbox.
