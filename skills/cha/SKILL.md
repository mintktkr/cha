---
name: cha
description: Use cha for Gitea, Forgejo and GitHub work from the terminal - issues, pull requests, Actions runs and logs, releases, repo files, search across a forge, and "what moved since yesterday" sweeps. Prefer it over gh, tea or raw API calls for those. One binary, plain output when piped, --json for scripting.
---

# cha

`cha` is a forge CLI for Gitea, Forgejo and GitHub, with the same commands on every forge. Inside a checkout it reads the host and repo from the `origin` remote, worktrees included.

## Picking the repo and the identity

- Inside a checkout, nothing is needed.
- Elsewhere, or for another repo: `-R owner/repo` (same host as the checkout) or `-R host/owner/repo`, for example `-R github.com/bendlang/bend` or `-R codeberg.org/forgejo/forgejo`.
- `repo create` and `repo delete` act on the name they are given, never on the checkout's repo. They use the checkout's host; outside a checkout, `-R host/OWNER/NAME` picks the host, and its repo need not exist yet for `repo create`.
- Token order: `CHA_TOKEN`, then `GITHUB_TOKEN`/`GH_TOKEN` on github.com, then `~/.git-credentials`. When a host has several users in the credential store, `CHA_USER=<name>` picks one. Public repos work without a token.
- cha never prints a token.

## Output

- Piped output is plain text: no colour, no animation, one line per item in lists.
- `--json` gives an array of objects with flat string fields (`"user.login"`, `"labels"`), booleans as `"true"`/`"false"`.
- Bare `--json` prints every field. `--json a,b` or `--json=a,b` prints only those fields, in that order. Spaces after commas are trimmed when the list is quoted.
- The word after a bare `--json` is the field list unless it starts with `-` or a digit, or is a command name. So `cha issue view --json 7` is issue 7, and `cha issue view --json title 7` selects the title. In scripts, use `--json=a,b`.
- An unknown field exits 1 with `unknown JSON field X; valid fields: a, b, c`, so `--json nope` is a cheap way to list a command's fields.
- `issue view --comments`, `runs view` and `moved` print nested records. They take no field list and exit 1 if given one; bare `--json` still works.
- Write commands print the URL of what they created or changed on stdout; `release upload` prints one line per file, the asset's download URL. `repo delete` prints nothing on success, only a `✓ deleted OWNER/NAME` line on stderr, because the forge answers 204. `comment-edit` prints the edited comment's URL; `comment-delete` prints nothing, and exit 0 is the receipt.
- `issue labels` and `issue create --label` resolve the names against the repo's labels before they write, so a typo exits 1 instead of applying a label the repo doesn't have (on GitHub the error also names the labels the repo does have).
- Errors go to stderr with exit code 1. `pr checks` and `runs watch` also exit 1 when something failed.
- A flag the subcommand doesn't take exits 1 and names the flags it does, for example `unknown flag --bogus for issue list; flags: --state --label ...`. `-h`, `--help` and `-R` are taken everywhere; `-h` or `--help` after a command prints its usage page instead of running it (`cha issue list --help` prints `cha issue`).
- A flag that takes a value and is given none exits 1 with `--limit needs a value`: at the end of the line, before another flag the command reads, or with nothing after its `=`. A value may start with a dash, or be another command's flag name, so `--body "-1 from me"` and `--title "--limit"` keep their words.
- Forge text is printed with its control characters and escape sequences removed, on stderr too, so a title, a body, a label, a branch name or a CI log line cannot move the cursor or spoof output. One-line fields (titles, labels, branches, names) also turn a newline or tab into a space, so they can't add rows to a list; bodies, comments and release notes keep their lines. Raw content stays byte-exact when piped: `repo file` and `pr diff` print the bytes unchanged into a redirect, and `--json` keeps the data, escaping control characters as `\uXXXX`.
- Bodies come from `--body TEXT` or `--body-file PATH`. `--body-file -` reads stdin. cha never opens an editor or prompts. A destructive command therefore needs `--yes`: without it, it exits 1 naming what it would remove and makes no request.
- `view N --comments` prints each comment's `id` beside its author and date, and `--json` carries it: that id is what `comment-edit` and `comment-delete` take. A PR's conversation comments are issue comments, so an id works under both `issue` and `pr`.
- `comment-delete` always needs `--yes`: without it cha names the comment it would delete, sends no request and exits 1. cha never prompts.

## Commands

```bash
cha issue list [--state open|closed|all] [--label L] [--assignee U] [--since 1d|6h|ISO8601] [--with-prs] [--all] [--limit N] [--json]
cha issue view N [--comments]
cha issue create --title T [--body B | --body-file F] [--label a,b] [--assignee u]
cha issue comment N --body B          # or --body-file -
cha issue comment-edit ID --body B    # edit a comment in place; the id is in `view --comments`
cha issue comment-delete ID --yes     # --yes is always required
cha issue edit N [--title T] [--body B]
cha issue close N [--comment C]  /  cha issue reopen N
cha issue labels N add a,b | remove a,b | set a,b

cha pr list [--state open|closed|all] [--all] [--limit N] [--json]
cha pr view N [--comments]            # state, head -> base, mergeable, review summary, body
cha pr diff N                         # raw unified diff
cha pr create --head H [--base main] --title T [--body B | --body-file F]
cha pr merge N [--squash|--merge|--rebase] [--delete-branch]
cha pr edit N [--title T] [--body B]
cha pr comment N --body B
cha pr comment-edit ID --body B       # the same comments a PR's conversation holds
cha pr comment-delete ID --yes
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
cha repo create NAME [--org O] [--private] [--description D]   # make a repo, prints its URL
cha repo delete OWNER/NAME --yes      # destructive; --yes is required, cha never prompts

cha release list  /  cha release latest  /  cha release view TAG|latest
cha release create TAG [--title T] [--notes N | --notes-file F] [--draft] [--prerelease] [--target BRANCH]
cha release upload TAG FILE...        # attach files; the asset name is the file's basename

cha moved [--since 1d|6h|30m|ISO8601] [--json]   # issues/PRs, comments, commits, runs since then
cha search issues QUERY [--state open|closed|all] [--owner O] [--limit N] [--json]
cha search prs QUERY [--state open|closed|all] [--owner O] [--limit N] [--json]
cha search repos QUERY [--owner O] [--limit N] [--json]
cha search code QUERY [--owner O] [--limit N] [--json]   # GitHub only, needs a token
cha auth status [--json]               # host, forge, login, token source; exit 1 without a working token
cha runners [list] [--org O | --user | --admin] [--json]   # self-hosted runners of a scope
cha runners delete ID --yes [--org O | --user | --admin]   # deregister one; cha never prompts

cha help [command]
cha completions fish
```

## Runs output and filters

- `runs view --json` is one array: a `kind: "run"` row followed by `kind: "job"` rows. Job rows include `runner_name`, timestamps, `duration` in seconds, and `steps.#` / `steps.N.*` flat string fields. Missing timestamps and durations are empty strings.
- Run rows include `updated_at`, `completed_at`, `duration` and `attempt`. Only GitHub counts attempts and sends `run_attempt`, so `attempt` is empty on Gitea and Forgejo. `runs view` appends `attempt N` to its header when N is above 1.
- `runs list --workflow` matches an exact filename, path or display name. Filtering follows pages until `--limit` matches (default 20, range 1–1000), with a 100-page safety cap. A display name resolves first through the workflows the forge lists now, on Gitea and GitHub alike; a name that matches no workflow exits 1 with the names it found, and a filename is used as given, for renamed or removed workflows.
- When `head_branch` is absent, the branch column falls back to the workflow ref. Tags and pull-request refs retain their `refs/tags/` or `refs/pull/` prefix.
- Logs accept a job id or case-insensitive exact job name. `--failed` selects failed jobs; it still prints each selected job's full log unless `--step` is also given.
- On GitHub, unfinished jobs print a watch hint on stderr while completed jobs still print their logs; partial retrieval exits 1. `--step` cuts the job log between the runner's `##[group]Run ...` markers, matching the step by case-insensitive name; a step the runner gave no group (an image pull, a runner step) falls back to its step times. On Gitea it needs step timestamps; its whole-second boundaries can overlap adjacent steps, and missing metadata produces an actionable error.
- `runs rerun --job` requires a job id belonging to the supplied run. It cannot be combined with `--failed`.
- `runs dispatch` prints the URL of the run it created. GitHub names that run in its reply (`return_run_details`); Gitea and Forgejo answer 204, so cha notes the instant before the POST and polls the repo's `workflow_dispatch` runs a few times, taking the newest run of that workflow file, on that ref, that appeared at or after it. When no such run has shown up after ~8s, it says the dispatch was accepted and prints the workflow's runs page instead of naming an older run.

## Search

- `issues`, `prs` and `code` search the current repo (the checkout, or `-R host/owner/repo`) unless `--owner O` narrows them to one owner instead. `repos` ignores the repo scope: it searches the whole forge, or one owner with `--owner`.
- Outside a checkout and without `-R`, `search` talks to github.com.
- Rows print like `issue list` (`#12  open  title  [labels]  @user`) and `repo view` (`full_name  visibility  stars N  forks N  description`). A search wider than one repo puts the repo name in front of every issue, pr and code row.
- `--state` takes open, closed or all (default: every state). `--limit` takes 1-100 and defaults to 20; a forge's page size caps it (50 on Gitea, 100 on GitHub).
- `code` needs a token on GitHub: anonymous code search answers 401, so cha says `search code: GitHub code search needs a token` and exits 1. Gitea and Forgejo have no code search API at all, and cha says so and exits 1.
- Gitea can search issues and prs by owner but has no owner filter for repos, so `search repos --owner` is GitHub-only.
- `--json` fields: issues and prs `repo,number,title,state,user.login,labels,html_url`; repos `full_name,forge,description,default_branch,visibility,stars,forks,open_issues,html_url`; code `repo,name,path,html_url`.

## Recipes

- What changed for me this week: `cha issue list --assignee LOGIN --since 7d`. `--assignee none` (unassigned) works on GitHub only.
- Before a write, or when a request 401s: `cha auth status` shows which login and token source cha will use. It never prints the token.
- Why did CI fail: `cha runs list --limit 5`, then `cha runs logs ID --failed`.
- Failing run ids for a script: `cha runs list --status failure --json=id,workflow`.
- Catch up on a repo: `cha moved --since 1d`.
- Find a repo before cloning it: `cha search repos kettle --json full_name,html_url`.
- Long comment or body from a heredoc: `cha issue comment 12 --body-file - <<'EOF' ... EOF`.
- Update a bot's marker comment instead of posting another: `cha issue view 12 --comments`, then `cha issue comment-edit ID --body-file -`.
- Check the latest upstream version: `cha -R github.com/owner/repo release latest`.
- Attach a build to a release: `cha release upload v0.1.0 out/cha`. The asset name is the file's basename, each asset's URL is printed, and `cha release view v0.1.0` lists the assets afterwards.
- Read a file without cloning: `cha -R host/owner/repo repo file README.md --ref main`.

## Forge differences cha already handles

- Forgejo (Codeberg) answers Actions with its own schema: `workflow_id`, `prettyref`, `commit_sha`, `started`/`stopped` and one status field. `runs list` and `runs view` map it onto the same columns. Its job listing carries no runner, timings or steps, so those stay empty there.
- Gitea's 405 on merge means a conflict or a moved base. cha says so. `pr merge` reads the pull request first, so an already merged one exits 1 naming the merge commit (when the forge gives it) and a closed unmerged one exits 1 saying it is closed; a merge is never a silent no-op.
- `pr comment N` checks that N is a pull request first. Both forges share the comment endpoint between issues and pull requests, so a number that is an issue (or none at all) exits 1 with `#N is not a pull request (an issue, or no such number)` instead of commenting on the issue.
- Label names are checked before any write, because Gitea silently ignores unknown names, or wipes the set on replace.
- Gitea 1.25 has no API to rerun or cancel an Actions run. `cha runs rerun|cancel` exit 1 with a hint: push a commit, or use the web UI.
- GitHub's issue list includes pull requests. `cha issue list` drops them.
- GitHub scopes runners to a repo or an org: `cha runners --user` and `--admin` exit 1 there. On Gitea and Forgejo, `--admin` lists every runner on the site and needs a site-admin token; a 403 says so. A runner id must be digits only, and a delete without `--yes` names the runner and exits 1.

## When cha isn't enough

cha doesn't cover secrets, packages, webhooks, mirrors, branch protection or tokens yet. Call the forge's REST API directly for those (Gitea: `https://<host>/api/v1/`, GitHub: `https://api.github.com/`). If a missing command keeps coming up, that's worth an issue on cha.
