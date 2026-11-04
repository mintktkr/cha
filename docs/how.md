# How cha works

One command, end to end. `cha issue list` is the example.

```
your shell
┌──────────────────────────────────────────────────────────────────┐
│ cha issue list                                                   │
└─────────────────────────────────┬────────────────────────────────┘
                                  │  main.bend: argv, colour on/off, --json
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│ ctx    repo from the checkout's git remote (worktrees too),      │
│        or -R owner/repo, or -R host/owner/repo                   │
│        forge: github.com is GitHub; anywhere else is Gitea       │
│        token: CHA_TOKEN, then GITHUB_TOKEN/GH_TOKEN, then        │
│        ~/.git-credentials (CHA_USER picks the user)              │
└─────────────────────────────────┬────────────────────────────────┘
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│ api    requests and pages; total_count when Gitea sends no Link  │
│ chaki  HTTP/1.1 over the system's OpenSSL 3, or with             │
│        CHA_TLS=bend its own TLS 1.3; JSON, URLs, redirects       │
└─────────────────────────────────┬────────────────────────────────┘
                                  ▼
                  ┌───────────────────────────────┐
                  │ the forge                     │
                  │ Gitea · Forgejo · GitHub      │
                  └───────────────┬───────────────┘
                                  │  JSON body
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│ rows   Map<&2, String>, flat: "number", "title",                 │
│        "user.login", "labels.0.name", ... Every field text       │
└─────────────────────────────────┬────────────────────────────────┘
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│ out    terminal: colour. piped: plain text.                      │
│        --json: every field. --json a,b: only those.              │
└──────────────────────────────────────────────────────────────────┘
```

- **No runtime dependencies.** cha speaks HTTPS and JSON itself: no `gh`, no
  `tea`, no `git`, no `curl`. Nothing else is needed at run time.
- **One `Env` per command.** `main.bend` resolves the repo and its token,
  decides colour, reads the `--json` selection, then hands the command a
  `Cli.Env{repo, tok, color, json, args}`. A command resolves nothing itself.
- **Flat rows.** `Api.rows` and `Api.obj` flatten a body once into a map keyed
  like `user.login`, `labels.0.name` and `labels.#`. `Json.Val` is affine in
  Bend, so reading a field consumes it; a command never walks JSON, it reads
  `Api.f(row, "user.login")` and `Api.join(row, "labels", "name", ",")`.
- **Colour per stream.** Colour is on only when stdout is a terminal,
  `NO_COLOR` is unset and `TERM` isn't `dumb` (`Ui.color`). Off, every style
  is the identity, so no escape byte reaches a pipe.
- **Secrets never reach output.** The token goes into the `authorization`
  header and nowhere else; a failed request reports why, never the token. That
  is a hard rule for every change. `LAWS.bend` holds the part a parser could break: a
  remote URL with `user:token@` in it parses to a repo without them.

## Forges differ

| quirk | what cha does |
|---|---|
| Gitea ignores `limit` without `page` | paged walks send `page=1` |
| Gitea needs label ids, drops unknown names | resolves names first |
| Gitea `PUT` labels replaces the whole set | sends the full set |
| Gitea 405 "Please try again later" | means a conflict, not a limit |
| Gitea 1.25 has no rerun or cancel API | cha tries the request, and maps a 404 to a message naming the Gitea version |
| Gitea timestamps carry a local offset | compares parsed instants |
| Gitea lists: `total_count`, no Link | asks until the rows reach it |
| GitHub lists PRs among issues | drops rows with `pull_request.url` |
| GitHub 404s on a trailing slash | never sends one |
| `actions/runs` answers an object | reads `workflow_runs` |

## The laws

`LAWS.bend` holds the claims cha must never break, one `law` each: colour off
leaves text unchanged, a remote URL parses to the repo it names without its
credentials, an id can't walk out of its path, a flag fails loud instead of
vanishing. `lib/chaki/LAWS.bend` holds what chaki promises, on its pure modules:
redirects, HTTP/1.1 framing, TLS, X.509, JSON, URLs and the crypto vectors.
`PROOF.bend` beside each discharges every one. `scripts/check.sh` runs both with
the type checks, the definition-order check and the offline `test/*_check.bend`,
and cha only ships when it's green. [laws.md](laws.md) explains them in full.
