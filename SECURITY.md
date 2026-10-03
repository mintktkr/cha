# Security

cha handles forge tokens, so a leak is a security bug. These count:

- a token, or part of one, in any output: stdout, stderr, errors, `--json` or debug dumps
- a token sent to a host other than the one it belongs to
- a remote URL's user or password reaching output or the parsed repo
- escape sequences from forge content (issue titles, logs) reaching a terminal unescaped

## Reporting a vulnerability

Report it privately through [GitHub's vulnerability reporting](https://github.com/mintktkr/cha/security/advisories/new), or email mint@muu.space. Please don't open a public issue.

Include the cha version (`cha version`), the forge, and the steps to reproduce. Redact real tokens.

## What happens next

- You get a reply within 7 days.
- A fix ships in a release within 30 days. A token leak takes priority over everything else.
- Disclosure is coordinated with you. The advisory is published when the fix is out, or after 90 days, whichever comes first, and you're credited unless you'd rather not be.

## Supported versions

Only the latest release gets fixes.
