# cha 茶

A forge CLI for Gitea, Forgejo and GitHub. One binary, no runtime dependencies. You don't need `gh`, `tea` or even `git` installed.

```
cha issue list
cha pr view 42 --comments
cha runs logs 1337 --failed
cha moved --since 1d
```

> **Status: early.** The commands above are the plan, not the present. Follow the issues to see where it's at.

## Why

- **One tool for every forge.** The same commands work against a self-hosted Gitea and against github.com. cha reads the host and repo from the current checkout's remote.
- **Built for agents as much as for people.** Much of the time, the one typing `cha` is a coding agent:
  - It never opens an editor. Bodies come from stdin or a file.
  - When stdout isn't a terminal, output is plain text with no colour codes.
  - `--json` gives stable fields.
  - Exit codes mean something.
- **Covers Gitea Actions.** It lists runs, reads job logs and dispatches workflows. Today's cross-forge tools leave this out.
- **Nothing to install.** It talks HTTPS and JSON directly. Credentials come from git's credential store or an environment variable.

## Written in Bend

cha is written in [Bend](https://bend-lang.com). The rules that must never break live in `LAWS.bend`, and every commit has to prove them. Examples:

- a token never reaches the output
- with colour off, no escape byte is printed
- pagination always terminates

## Contributing

Humans and agents are both welcome, and both follow the same rules. Start with [AGENTS.md](AGENTS.md).

## License

[MIT](LICENSE)
