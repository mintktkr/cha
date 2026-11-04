# Exercising the write paths

cha's offline checks cover how requests are built, not whether a forge accepts them. So the write paths get a live run against a throwaway repo before any release that touches them. This page is that procedure; with `repo create` and `repo delete`, cha makes and removes the sandbox itself.

`OWNER/cha-sandbox` stands for that repo, and `C` for `cha -R github.com/OWNER/cha-sandbox`. Keep the repo private and delete it when you're done.

Test with a **native build** of the commit you mean to release (`bend main.bend -o out/cha`), not just the JS lane. The two lanes can differ: on 2026-10-03, `runs logs --step` built natively and returned a 404 that the JS lane never showed.

## Setup

The repo needs two workflows and two branches:

- `ci`: runs on push and on `workflow_dispatch` (input `note`), with one job that passes (`ok`) and one that fails (`flaky`, a step `fail on purpose`), so `rerun --failed` and `logs --failed` have something to work on.
- `slow`: `workflow_dispatch` only, one job that sleeps 15 minutes, for `cancel`.
- branches `feat-merge` and `feat-delete`, each one commit ahead of `main`, for two pull requests.

The token needs the `repo` scope (`cha auth status` names its source). `repo` covers dispatch, rerun and cancel. On GitHub, deleting the sandbox also needs the `delete_repo` scope. Workflow files are pushed with git, so the token never needs the `workflow` scope. For the hooks rows, `printf 's3cr3t' > /tmp/cha-hook-secret`, outside the repo.

cha makes and removes the sandbox itself. `-R` names the host and the token; its `OWNER/NAME` need not exist yet, since only the host is read from it.

```console
$ cha -R github.com/OWNER/cha-sandbox repo create cha-sandbox --private --description 'cha write-path sandbox'
$ cha -R github.com/OWNER/cha-sandbox repo delete OWNER/cha-sandbox --yes
```

`repo create` makes the repo in the token's own account, or in `--org ORG`'s, and prints its URL. `repo delete` never defaults to the checkout's repo: it deletes the `OWNER/NAME` it is given, on the host `-R` names (or the checkout's origin). It requires `--yes`, because cha never prompts; without it, it exits 1 naming the repo and sends no request. A 403 names the scope the token is missing (`delete_repo` on GitHub, `write:repository` on Gitea).

Never trace these commands with `set -x` in a shell that also reads the token: the trace prints it.

## Checklist

On GitHub, an issue and a pull request share one number sequence: the first PR in a fresh repo after one issue is #2.

| area | command | expect |
|---|---|---|
| auth | `C auth status` | host, login, token source |
| labels | `C repo label-create cha-test --color ff6eb4 --description D`, `C repo labels` | the label is listed |
| issue | `C issue create --title T --body B --label cha-test` | URL of #1 |
| | `C issue comment 1 --body B` | comment URL |
| | `C issue view 1 --comments` then `C issue comment-edit ID --body B2` | `issue view 1 --comments` shows the new body |
| | `C issue comment-delete ID --yes`; first without `--yes` | the second deletes; the first fails, exit 1, nothing sent |
| | `C issue edit 1 --title T2 --body B2` | `issue view 1` shows both |
| | `C issue labels 1 add X`, `remove X`, `set a,b` | `issue view 1` shows the set |
| | `C issue labels 1 add no-such-label` | fails (#19) |
| | `C issue close 1 --comment C`, `reopen 1`, `close 1` | state follows |
| pr | `C pr create --head feat-merge --base main --title T --body B` | URL of #2 |
| | `C pr edit 2 --title T2 --body B2`, `C pr comment 2 --body B` | `pr view 2 --comments` shows both |
| | `C pr close 2 --comment C`, `C pr reopen 2`, `C pr close 2` | state follows; the comment lands on the pull request |
| | `C pr comment-edit ID --body B3`, `C pr comment-delete ID --yes` | a PR's conversation comment, edited then gone (same ids as `issue`) |
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
| | `C runs watch RUN` on a succeeded run | exit 0 |
| release | `C release create v0.0.1-test --title T --notes N --target main` | URL |
| | `C release upload v0.0.1-test FILE out/cha` | one download URL per file (#18) |
| | `C release view v0.0.1-test` | lists both assets; the binary downloads byte-identical |
| hooks | `C hooks create https://example.com/hook --events push --secret-file /tmp/cha-hook-secret` | `#ID  https://example.com/hook`; `C hooks` lists it |
| | `C hooks --json` | the hook's fields, and no secret field at all |
| | `C hooks test ID` | exit 0 (the forge queues a test delivery) |
| | `C hooks delete ID` | exit 1, names the hook, sends nothing; `C hooks` still lists it |
| | `C hooks delete ID --yes` | `C hooks` no longer lists it |

## Results

**2026-10-03, github.com, cha main at 20fe816 + b372bf9, native build.** Everything in the table passed except:

- #17: `runs dispatch` names the wrong run (the dispatch itself works).
- #18: `release upload` fails with `HTTP 400: Bad Content-Length`. bend-kit's HTTP/2 client sends no `content-length`, so this needs an upstream fix. (2026-11-03: chaki's HTTP/1.1 writer always sends it, so #24 removes the cause; the row needs a re-run.)
- #19: `issue labels add` creates an unknown label.
- #20: `pr comment` accepts an issue number; merging a merged PR says nothing.
- #21: `runs view` doesn't show the attempt, so a rerun has to be checked through the API.

**2026-11-03, a self-hosted Gitea 1.25.3, cha main at f939798, native build.** Every row in the table passed except:

- `runs logs RUN --job ok --step "say hi"`: `runs logs: no step named say hi; steps:` + `ok:` and exit 1. Gitea 1.25.3 sends `steps: null` for a job, from both the job list and the single-job endpoint, so a step has no name or timestamps to cut on. The forge's limit, not cha's. The message read oddly (an empty step list), and #63 makes it say to drop `--step`.
- `runs cancel RUN`: clean refusal, `runs cancel: this forge has no cancel API (HTTP 404, needs Gitea >= 28); cancel it from the web UI`, exit 1. Needs Gitea 28.
- `runs rerun RUN` (no flag, `--failed`, `--job ID`): clean refusal on all three, `runs rerun: this forge has no rerun API (HTTP 404, needs Gitea >= 1.26)`, exit 1. Needs Gitea 1.26.

Gitea numbers issues and pull requests in one sequence, so the sandbox's first pull request was #2. Rows that were bugs on GitHub on 2026-10-03 now pass here:

- #17 is gone: `runs dispatch` printed the run it created (`actions/runs/6` for Gitea run id 4888, `run_number` 6), twice, on both forges.
- #18 is gone: `release upload` of a 17-byte text file and the 6.1 MB binary answered with an attachment URL each, and both downloaded byte-identical (sha256 of each asset matched the local file).
- #19 is gone: `issue labels 1 add no-such-label` exits 1 with `issue labels: unknown label: no-such-label` and changes nothing.
- #20 is gone: `pr comment 1 --body B` on an issue exits 1 with `#1 is not a pull request (an issue, or no such number)`, and `pr merge 3` on a merged pull request exits 1 with `#3 is already merged (commit abd011a)`.
- #21 is gone on Gitea 28: `runs view` prints `attempt 3` after two reruns.

Two rows the table lacks, both added and both passing: `pr reopen 2` after a close (state follows, and the `--comment` of the close landed on the pull request), and `runs watch RUN` on a succeeded run (exit 0, `success`).

Not observed on 1.25.3: `runs view` step timings and `runs logs --step`, for the reason above.

**2026-11-03, a self-hosted Gitea 28.2, cha main at f939798, native build.** Every row in the table passed except:

- The five rows that need a run to execute were skipped: this user-owned repo had no runner, so its runs stayed `queued` for the whole session and `runners --user` listed nothing. Skipped: `runs logs --step`, `runs logs --failed`, `runs watch` on a failed run, and the `pr checks` row (both checks read `pending`, exit 0, never `flaky failed`). The dispatch, cancel and rerun rows still ran, against runs that never started.
- `runs rerun RUN --failed` reached the forge and relayed its own refusal, `HTTP 400: this workflow run has no failed jobs to re-run`, on the cancelled run it was given. With no runner there was no failed job to rerun.

New on 28.2, both fixed in #63 before v0.2.0:

- A run cancelled before a runner picked it up renders `sleep  cancelled  #13611    1793753021s`: Gitea sends `started_at: 1970-01-01T00:00:00Z` for a job that never started, and `runs view` subtracts it from `completed_at`. `--json` also prints that epoch as `started_at` instead of the empty string the docs promise for a missing timestamp.
- `runs rerun RUN --job ID` with an id that the run no longer holds (a rerun renumbers its jobs) answers the forge's 404 with `this forge has no rerun API (HTTP 404, needs Gitea >= 1.26)`, which is false on 28.2. The right reading is a stale job id.

`runs rerun` works on 28.2 with no flag and with `--job ID` (attempt 2 and 3 both appeared as `queued`), `runs cancel` cancels a queued run, and `runs rerun RUN --job <job of another run>` exits 1 with `job does not belong to run 7690` before any rerun request, on both forges.

Gitea has no API that serves a release asset's bytes: `/repos/O/R/releases/assets/{id}` is a 404 on 1.25.3, so both assets were downloaded from the release's `releases/download/...` URL with the same `Authorization: token` header and hashed there.

