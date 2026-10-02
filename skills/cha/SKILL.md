---
name: cha
description: Use cha for Gitea, Forgejo and GitHub work from the terminal - issues, pull requests, Actions runs and logs, releases, repo files, and "what moved since yesterday" sweeps. Prefer it over gh, tea or raw API calls for those. One binary, plain output when piped, --json for scripting.
---

# cha

`cha` is a forge CLI for Gitea, Forgejo and GitHub, with the same commands on every forge. Inside a checkout it reads the host and repo from the `origin` remote, worktrees included.

## Picking the repo and the identity

- Inside a checkout, nothing is needed.
- Elsewhere, or for another repo: `-R owner/repo` (same host as the checkout) or `-R host/owner/repo`, for example `-R github.com/bendlang/bend` or `-R codeberg.org/forgejo/forgejo`.
- Token order: `CHA_TOKEN`, then `GITHUB_TOKEN`/`GH_TOKEN` on github.com, then `~/.git-credentials`. When a host has several users in the credential store, `CHA_USER=<name>` picks one. Public repos work without a token.
- cha never prints a token.

## Output

- Piped output is plain text: no colour, no animation, one line per item in lists.
- `--json` gives an array of objects with flat string fields (`"user.login"`, `"labels"`), booleans as `"true"`/`"false"`.
- Bare `--json` prints every field. `--json a,b` or `--json=a,b` prints only those fields, in that order. Spaces after commas are trimmed when the list is quoted.
- The word after a bare `--json` is the field list unless it starts with `-` or a digit, or is a command name. So `cha issue view --json 7` is issue 7, and `cha issue view --json title 7` selects the title. In scripts, use `--json=a,b`.
- An unknown field exits 1 with `unknown JSON field X; valid fields: a, b, c`, so `--json nope` is a cheap way to list a command's fields.
- `issue view --comments`, `runs view` and `moved` print nested records. They take no field list and exit 1 if given one; bare `--json` still works.
- Write commands print the URL of what they created or changed on stdout.
- Errors go to stderr with exit code 1. `pr checks` and `runs watch` also exit 1 when something failed.
- Bodies come from `--body TEXT` or `--body-file PATH`. `--body-file -` reads stdin. cha never opens an editor or prompts.

## Commands

```bash
cha issue list [--state open|closed|all] [--label L] [--all] [--json]
cha issue view N [--comments]
cha issue create --title T [--body B | --body-file F] [--label a,b] [--assignee u]
cha issue comment N --body B          # or --body-file -
cha issue edit N [--title T] [--body B]
cha issue close N [--comment C]  /  cha issue reopen N
cha issue labels N add a,b | remove a,b | set a,b

cha pr list [--state open|closed|all] [--json]
cha pr view N [--comments]            # state, head -> base, mergeable, review summary, body
cha pr diff N                         # raw unified diff
cha pr create --head H [--base main] --title T [--body B | --body-file F]
cha pr merge N [--squash|--merge|--rebase] [--delete-branch]
cha pr edit N [--title T] [--body B]
cha pr comment N --body B
cha pr checks N                       # statuses and check runs of the head commit

cha runs list [--branch B] [--status S] [--workflow FILE|NAME] [--limit N] [--json]
cha runs view ID                      # run, jobs, runners and step timings
cha runs logs ID [--job ID|NAME] [--failed] [--step NAME]
cha runs watch ID                     # polls until done
cha runs dispatch WORKFLOW_FILE [--ref main] [--input k=v]
cha runs rerun ID [--failed | --job ID]  /  cha runs cancel ID

cha repo [view] [--json]
cha repo labels  /  cha repo label-create NAME [--color HEX] [--description D]
cha repo branches
cha repo file PATH [--ref R]          # raw file content, no clone needed
cha repo tree [--ref R]

cha release list  /  cha release latest  /  cha release view TAG|latest
cha release create TAG [--title T] [--notes N | --notes-file F] [--draft] [--prerelease] [--target BRANCH]

cha moved [--since 1d|6h|30m|ISO8601] [--json]   # issues/PRs, comments, commits, runs since then
cha auth status [--json]               # host, forge, login, token source; exit 1 without a working token

cha help [command]
cha completions fish
```

## Runs output and filters

- `runs view --json` is one array: a `kind: "run"` row followed by `kind: "job"` rows. Job rows include `runner_name`, timestamps, `duration` in seconds, and `steps.#` / `steps.N.*` flat string fields. Missing timestamps and durations are empty strings.
- Run rows include `updated_at`, `completed_at` and `duration`. A forge that supplies only `updated_at` leaves completion and duration empty; an update is not necessarily a completion.
- `runs list --workflow` matches an exact filename, path or display name. Filtering follows pages until `--limit` matches (default 20, range 1–1000), with a 100-page safety cap. On Gitea, names resolve through current workflow metadata; use the filename for renamed or removed workflows.
- When `head_branch` is absent, the branch column falls back to the workflow ref. Tags and pull-request refs retain their `refs/tags/` or `refs/pull/` prefix.
- Logs accept a job id or case-insensitive exact job name. `--failed` selects failed jobs; it still prints each selected job's full log unless `--step` is also given.
- On GitHub, unfinished jobs print a watch hint on stderr while completed jobs still print their logs; partial retrieval exits 1. `--step` uses the step log endpoint. On Gitea it needs step timestamps; its whole-second boundaries can overlap adjacent steps, and missing metadata produces an actionable error.
- `runs rerun --job` requires a job id belonging to the supplied run. It cannot be combined with `--failed`.

## Recipes

- Before a write, or when a request 401s: `cha auth status` shows which login and token source cha will use. It never prints the token.
- Why did CI fail: `cha runs list --limit 5`, then `cha runs logs ID --failed`.
- Failing run ids for a script: `cha runs list --status failure --json=id,workflow`.
- Catch up on a repo: `cha moved --since 1d`.
- Long comment or body from a heredoc: `cha issue comment 12 --body-file - <<'EOF' ... EOF`.
- Check the latest upstream version: `cha -R github.com/owner/repo release latest`.
- Read a file without cloning: `cha -R host/owner/repo repo file README.md --ref main`.

## Forge differences cha already handles

- Gitea's 405 on merge means a conflict or a moved base. cha says so.
- Label names are checked before any write, because Gitea silently ignores unknown names, or wipes the set on replace.
- Gitea 1.25 has no API to rerun or cancel an Actions run. `cha runs rerun|cancel` exit 1 with a hint: push a commit, or use the web UI.
- GitHub's issue list includes pull requests. `cha issue list` drops them.

## When cha isn't enough

cha doesn't cover secrets, runners, packages, webhooks, mirrors, branch protection or tokens yet. Call the forge's REST API directly for those (Gitea: `https://<host>/api/v1/`, GitHub: `https://api.github.com/`). If a missing command keeps coming up, that's worth an issue on cha.
