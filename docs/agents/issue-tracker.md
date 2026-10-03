# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use `cha` for every operation it covers. The wayfinding operations below still need `gh api`, because cha has no sub-issue or dependency commands yet.

## Conventions

- **Create an issue**: `cha issue create --title "..." --body-file - <<'EOF' ... EOF`, or `--body "..."` for one line. Add `--label a,b`.
- **Read an issue**: `cha issue view <number> --comments`. Bare `--json` gives the nested record.
- **List issues**: `cha issue list --state open --json`, with `--label`, `--assignee` and `--since` filters. `--json nope` lists the valid fields.
- **Comment on an issue**: `cha issue comment <number> --body "..."`, or `--body-file -` for multi-line.
- **Apply / remove labels**: `cha issue labels <number> add a,b` / `remove a,b`. cha checks label names before writing.
- **Close**: `cha issue close <number> --comment "..."`

Inside a clone, cha reads the repo from the `origin` remote. Elsewhere, pass `-R github.com/mintktkr/cha`.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the PR equivalents:

- **Read a PR**: `cha pr view <number> --comments` and `cha pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `cha pr comment`; `gh pr edit --add-label`/`--remove-label` and `gh pr close` until cha has them.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with `cha pr view 42` and fall back to `cha issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `cha issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `cha issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write. (cha can't add an assignee to an existing issue yet.)
- **Resolve**: `cha issue comment <n> --body "<answer>"`, then `cha issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.

## Dogfooding

As soon as `cha` covers an operation above, use `cha` for it instead of `gh`. Wherever `cha` falls short, that's a bug worth filing.
