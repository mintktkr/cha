<p align="center">
  <img src="docs/banner.svg" alt="cha 茶" width="760">
</p>

<p align="center">
  <img alt="written in bend" src="https://img.shields.io/badge/written%20in-Bend%20%E2%9C%A8-ff6eb4?style=for-the-badge&labelColor=1a1b26">
  <img alt="zero dependencies" src="https://img.shields.io/badge/dependencies-zero-6ef2b8?style=for-the-badge&labelColor=1a1b26">
  <img alt="laws proven" src="https://img.shields.io/badge/laws-proven%20%E2%99%A1-d67fe8?style=for-the-badge&labelColor=1a1b26">
  <img alt="status" src="https://img.shields.io/badge/status-steeping%20%E2%98%95-ffe14d?style=for-the-badge&labelColor=1a1b26">
</p>

<p align="center"><b>A forge CLI for Gitea, Forgejo and GitHub.</b><br>
One binary. No <code>gh</code>, no <code>tea</code>, not even <code>git</code>.</p>

---

## ☕ Usage

```console
$ cha issue list
$ cha pr view 42 --comments
$ cha runs logs 1337 --failed
$ cha runs watch 1337
$ cha moved --since 1d
```

> 🫖 **Early days.** The commands above work today. See the [agent skill](skills/cha/SKILL.md) for supported flags, [how a command flows](docs/how.md) for the path from shell to forge, and the [roadmap](docs/roadmap.md) for the next priorities.

## 📦 Install

**Arch Linux**: `packaging/arch/PKGBUILD` builds cha from source with a pinned Bend toolchain, or grab the package from the [latest release](https://github.com/mintktkr/cha/releases/latest):

```console
$ cd packaging/arch && makepkg -si
```

**From source**: install [Bend](https://bend-lang.com) 2.0.34 and clang, then:

```console
$ bend main.bend -o cha && install -m755 cha ~/.local/bin/
$ cha completions fish > ~/.config/fish/completions/cha.fish
```

**For your agents**: `skills/cha/SKILL.md` teaches coding agents how to use cha. Link it where they look for skills, for example `ln -s $PWD/skills/cha ~/.agents/skills/cha`. The Arch package installs it to `/usr/share/cha/skills/cha`.

## 🌸 Why

- **One tool for every forge.** The same commands work against a self-hosted Gitea and against github.com. cha reads the host and repo from the current checkout's remote.
- **Made for agents too.** Much of the time a coding agent runs `cha`, so:
  - it never opens an editor. Bodies come from stdin or a file
  - piped output is plain text, with no escape codes
  - `--json` gives stable fields, `--json a,b` only those
  - exit codes mean something
- **Gitea Actions included.** List runs, read job logs, dispatch workflows.
- **Nothing to install.** cha speaks HTTPS and JSON itself. Credentials come from git's credential store or an environment variable.

## 🌈 Colours

In a terminal, cha uses a pink → lavender → mint palette where every colour means something:

| | colour | meaning |
|---|---|---|
| 🩷 | pink `#ff6eb4` | failed |
| 🍋 | lemon `#ffe14d` | running |
| 🩵 | aqua `#6ef3ff` | commands, links |
| 🌿 | mint `#6ef2b8` | success, open |
| 💜 | lavender `#d67fe8` | merged |

`cha help` goes all out with glow, animation and kaomoji ✧･ﾟ: ･ﾟ✧. Piped, it prints plain text.

## ✨ Written in Bend

cha is written in [Bend](https://bend-lang.com). The rules that must never break live in `LAWS.bend`, and a commit only lands if they still prove:

- 🔐 a token never reaches the output
- 🎨 with colour off, no escape byte is printed
- 🔁 pagination always terminates

## 💌 Contributing

Humans and agents are both welcome, under the same rules. Start with [AGENTS.md](AGENTS.md).

## 📜 License

[MIT](LICENSE) · made with ☕ at the bottom of the world 🐧
