# cha roadmap

The September 2026 usage survey makes agent workflows the priority: predictable
non-interactive commands, useful filters, compact output and fewer parsing steps.
Its original implementation suggestions are superseded by cha's Bend toolchain
and no-runtime-dependencies rule. Private survey examples are not fixtures.

## Current pass: Actions runs and logs

Address the open runs issues before adding command groups:

- [#3](https://github.com/mintktkr/cha/issues/3): display the ref when a run has no branch.
- [#5–#7](https://github.com/mintktkr/cha/issues/5): select logs by job name, explain unfinished jobs, remove leading BOMs.
- [#8–#9](https://github.com/mintktkr/cha/issues/8): one JSON array, runner details and step timings.
- [#10](https://github.com/mintktkr/cha/issues/10): select a named step's logs.
- [#11](https://github.com/mintktkr/cha/issues/11): workflow filtering and honest run timestamps.
- [#12](https://github.com/mintktkr/cha/issues/12): rerun failed jobs or one job on GitHub.

## Next priorities

1. **JSON field selection.** The survey found about 43% of forge calls needed an
   external parser. Start with validated `--json fields`, retaining bare `--json`.
   A general `--jq` evaluator needs a separate design compatible with one binary.
2. **Daily filters and identity.** Issue assignee/since filters and explicit PR
   inclusion; run SHA filtering; read-only `auth status` / `whoami` showing the
   chosen host and identity without exposing credentials.
3. **Release assets and runner health.** Implement asset upload/listing
   ([#2](https://github.com/mintktkr/cha/issues/2)) and read-only repo/org runners
   ([#13](https://github.com/mintktkr/cha/issues/13)). Runner health then fits `moved`.
4. **Complete inspection workflows.** PR file summaries, structured comments and
   reviews in JSON, and a distinct failed-step-only log mode. Current `--failed`
   selects jobs rather than individual failed steps.
5. **Weekly operations.** Packages, secrets, mirrors and search, ordered by the
   next concrete usage need rather than adding every forge endpoint at once.

GitHub write-path live coverage
([#4](https://github.com/mintktkr/cha/issues/4)) needs a repository explicitly
assigned for testing. Offline tests and anonymous reads of public repositories
can run without changing remote state.
