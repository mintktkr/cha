# laws: what the pure core must keep. Each law is a claim; PROOF.bend proves it.
# They cover what a wrong turn would break quietly: colour off must leave text unchanged,
# the string and flag helpers must behave at their edges, a remote URL must parse to the
# repo it names, a runner id must not reach a path with anything but digits, and a name
# that goes into a path must not carry a segment that walks out of it.
import Base
import ./src/clean.bend as Clean
import ./src/ui.bend as Ui
import ./src/ctx.bend as Ctx
import ./src/cli.bend as Cli
import ./src/api.bend as Api
import ./src/url.bend as Url
import ./src/cmd/repo.bend as Repo
import ./src/cmd/runners.bend as Runners
import ./src/cmd/runs.bend as Runs
import ./src/cmd/packages.bend as Packages
import ./src/cmd/pr.bend as Pr
import ./src/hooks.bend as Hooks
import ./src/cmd/secrets.bend as Secrets
import ./src/cmd/mirror.bend as Mirror

# Colour off
# ----------
# With colour off every style is the identity, so piped output stays plain and no escape
# sequence can leak.

# LAW: styled text with colour off is the text.
law styled_off:
  for o: String
  for c: String
  for s: String
  {Ui.styled(False{}, o, c, s) == s : String}

# LAW: fg with colour off is the text.
law fg_off:
  for c: Ui.Rgb
  for s: String
  {Ui.fg(False{}, c, s) == s : String}

# LAW: bold with colour off is the text.
law bold_off:
  for s: String
  {Ui.bold(False{}, s) == s : String}

# LAW: dim with colour off is the text.
law dim_off:
  for s: String
  {Ui.dim(False{}, s) == s : String}

# LAW: a forge state with colour off is its label.
law state_off:
  for +s: String
  {Ui.state(False{}, s) == s : String}

# LAW: the glow gradient with colour off is the text.
law glow_off:
  for +s: String
  {Ui.glow(False{}, s) == s : String}

# or
# --
# or picks a unless it is empty.

# LAW: a non-empty a wins.
law or_left:
  for c: Char
  for t: String
  for b: String
  {Ctx.or(SCon{c, t}, b) == SCon{c, t} : String}

# LAW: an empty a falls through to b.
law or_empty:
  for b: String
  {Ctx.or("", b) == b : String}

# Flags
# -----
# An absent argument list means the flag is missing and takes its default.

# LAW: has is False when there is nothing to search.
law has_nil:
  for name: String
  {Cli.has(Nil{}, name) == False{} : Bool}

# LAW: flag gives the default when there is nothing to search.
law flag_empty:
  for name: String
  for dflt: String
  {Cli.flag(Nil{}, name, dflt) == dflt : String}

# LAW: a flag the command doesn't read is named, so it can fail loud instead of vanishing
# with its value.
law unknown_flag:
  {Cli.unknown(["--state"], ["--state", "open", "--limit", "3"]) == ["--limit"] : List<&2, String>}

# LAW: a flag is judged by its name before any =, so --limit=3 can't slip past as one word.
law unknown_flag_eq:
  {Cli.unknown(["--state"], ["--state=open", "--limit=3"]) == ["--limit"] : List<&2, String>}

# LAW: -h and --help are never unknown, even to a command that reads no flags.
law unknown_flag_help:
  {Cli.unknown(Nil{}, ["-h", "--help"]) == Nil{} : List<&2, String>}

# LAW: a flag that takes a value and is given none is named, so it can fail loud instead of
# vanishing. At the end of the line:
law missing_flag_end:
  {Cli.missing(["--limit"], ["list", "--limit"]) == "--limit" : String}

# LAW: ...or before a flag the command reads:
law missing_flag_next:
  {Cli.missing(["--limit", "--json"], ["list", "--limit", "--json"]) == "--limit" : String}

# LAW: ...or with nothing after its =:
law missing_flag_blank:
  {Cli.missing(["--limit"], ["list", "--limit="]) == "--limit" : String}

# LAW: a value that starts with a dash is a value, not a flag without one.
law missing_flag_dash:
  {Cli.missing(["--body"], ["--body", "-1 from me"]) == "" : String}

# LAW: a word that is not a flag the command reads is a value, so --title "--limit" keeps
# its title.
law missing_flag_other:
  {Cli.missing(["--title"], ["--title", "--limit"]) == "" : String}

# Concrete examples
# -----------------

# LAW: a scp-shaped remote parses to its forge, host, owner and name.
law parse_remote_scp:
  {Ctx.parse_remote("git@github.com:mintktkr/cha.git") == Some{Ctx.Repo{Ctx.GitHub{}, "github.com", "mintktkr", "cha"}} : Maybe<&2, Ctx.Repo>}

# Secrets
# -------
# A token can sit in a remote URL (https://user:token@host/...). The repo parsed from it
# must not carry it, since the host reaches URLs and error messages.

# LAW: an https remote's user and token are dropped.
law parse_remote_drops_credentials:
  {Ctx.parse_remote("https://x:SECRET@github.com/o/r.git") == Some{Ctx.Repo{Ctx.GitHub{}, "github.com", "o", "r"}} : Maybe<&2, Ctx.Repo>}

# LAW: a bare token before the host is dropped too.
law parse_remote_drops_token:
  {Ctx.parse_remote("https://SECRET@example.org/o/r") == Some{Ctx.Repo{Ctx.Gitea{}, "example.org", "o", "r"}} : Maybe<&2, Ctx.Repo>}

# LAW: a mirror URL's user and password are dropped before it is printed.
law no_credentials_user_pass:
  {Ctx.no_credentials("https://x:SECRET@example.org/o/r.git") == "https://example.org/o/r.git" : String}

# LAW: a bare token before a mirror URL's host is dropped too.
law no_credentials_token:
  {Ctx.no_credentials("https://SECRET@example.org/o/r") == "https://example.org/o/r" : String}

# LAW: a URL that carries no credentials is printed as it is, its path untouched.
law no_credentials_plain:
  {Ctx.no_credentials("https://example.org/a@b/c.git") == "https://example.org/a@b/c.git" : String}

# LAW: the forge stores a mirror's password raw, so a / in it doesn't end the userinfo.
law no_credentials_pass_slash:
  {Ctx.no_credentials("https://u:p/ss@host/o/r") == "https://host/o/r" : String}

# LAW: an @ in the password doesn't end the userinfo either.
law no_credentials_pass_at:
  {Ctx.no_credentials("https://u:p@ss@host/o/r") == "https://host/o/r" : String}

# LAW: a query and a fragment can carry a token, so neither is printed.
law no_credentials_query:
  {Ctx.no_credentials("https://example.org/o/r?token=SECRET#top") == "https://example.org/o/r" : String}

# A push mirror's last error is git's own text, and git quotes the remote URL it failed on.

# LAW: a mirror's error text loses the credentials of the URL it quotes.
law mirror_error_url:
  {Mirror.error.text("Push to https://x:tok@github.com/o/r.git failed") == "Push to https://github.com/o/r.git failed" : String}

# LAW: a Link header without rel="next" has no next page.
law link_no_next:
  {Api.link.next("</issues?page=2>; rel=\"last\"") == "" : String}

# LAW: a Link header with rel="next" yields that URL.
law link_next_url:
  {Api.link.next("</issues?page=2>; rel=\"next\", </issues?page=5>; rel=\"last\"") == "/issues?page=2" : String}

# Failed secrets set
# ------------------
# A secret's value goes out in one request and never comes back. A failed reply's body can
# echo it whole, in part, re-cased or escaped, and a control byte in it would only be
# dropped after a check, so the message a failed `secrets set` prints is built from the
# status alone: no word of the forge's body, and so no value.

# LAW: a 422's message is the fixed text, whatever the forge's body echoed.
law secrets_set_422_text:
  {Secrets.set.why(422) == "the forge refused the name or the value (HTTP 422)" : String}

# LAW: a 404's message is the fixed text too.
law secrets_set_404_text:
  {Secrets.set.why(404) == "no such repo or org (HTTP 404)" : String}

# LAW: a 401 names the token, with its own status.
law secrets_set_401_text:
  {Secrets.set.why(401) == "the token can't write secrets here (HTTP 401)" : String}

# LAW: a 403 names the token, with its own status.
law secrets_set_403_text:
  {Secrets.set.why(403) == "the token can't write secrets here (HTTP 403)" : String}

# LAW: any other status is the status alone, with nothing quoted from the body.
law secrets_set_other_text:
  {Secrets.set.why(500) == "HTTP 500" : String}

# LAW: the message holds no value, for a status whose body repeated one.
law secrets_set_hides_value:
  {String.contains(Secrets.set.why(422), "hunter2") == False{} : Bool}

# Value files
# -----------
# A value, a body, notes or a secret come from a file or stdin, and the shared reader reads
# octets until the source ends. The cap is a byte count: a count of characters would let a
# multi-byte file through, and a read split inside a character would lose it.

# LAW: a source of exactly the cap fits whole.
law value_file_at_cap:
  {Cli.text.over(1048576, Cli.file.cap()) == False{} : Bool}

# LAW: one octet more is over it.
law value_file_over_cap:
  {Cli.text.over(1048577, Cli.file.cap()) == True{} : Bool}

# LAW: the octets of a read are counted as they came, not as characters.
law value_file_chunk_octets:
  {Cli.chunk.size([228, 138, 182]) == 3 : U32}

# Terminal escape
# ---------------
# Forge text reaches a terminal through Clean.text, which drops escape sequences and
# control bytes, so a title, a body, a label or a CI log line cannot move the cursor,
# clear the screen, retitle the window or open a hyperlink, and cannot redraw a line.

# LAW: a CSI (an SGR colour, a screen clear) is dropped whole.
law clean_csi:
  {Clean.text("a\u{1b}[1;31mred\u{1b}[2Jb") == "aredb" : String}

# LAW: an OSC is dropped whole, up to its BEL.
law clean_osc_bel:
  {Clean.text("\u{1b}]8;;https://example.com\u{7}link") == "link" : String}

# LAW: an OSC ends at ESC backslash too.
law clean_osc_st:
  {Clean.text("\u{1b}]0;title\u{1b}\\ok") == "ok" : String}

# LAW: an escape inside an escape sequence opens another one, so a doubled ESC cannot
# hide the sequence after it.
law clean_esc_esc:
  {Clean.text("a\u{1b}\u{1b}[2Jb") == "ab" : String}

# LAW: a carriage return is dropped, and one before a newline is that newline.
law clean_cr:
  {Clean.text("a\rb\r\nc\rd") == "ab\ncd" : String}

# LAW: control bytes, DEL and a C1 control are dropped; tab and newline are kept.
law clean_controls:
  {Clean.text("a\u{0}b\tc\nd\u{7f}e\u{85}f") == "ab\tc\ndef" : String}

# LAW: a character that is neither a control nor an escape is kept.
law clean_plain:
  {Clean.text("茶 (´∀｀)♡ 🍵") == "茶 (´∀｀)♡ 🍵" : String}

# LAW: a field printed on one line keeps to it: a newline or a tab becomes a space, after
# the escapes are gone, so a title can't start a row of its own.
law clean_line:
  {Clean.line("a\nb\tc\r\nd\u{1b}[2J") == "a b c d" : String}

# Runner ids
# ----------
# A runner id reaches a URL path, so it must be digits only: "1/registration-token"
# would otherwise name one of the scope's other endpoints.

# LAW: a digit string is a runner id.
law runner_id_digits:
  {Runners.digits("1234") == True{} : Bool}

# LAW: a path, a letter or a space in a runner id is refused.
law runner_id_not_digits:
  {Runners.digits("1/registration-token") == False{} : Bool}

# Run ids
# --------
# A run id reaches a URL path, and rerun and cancel act on it, so it is digits only: U32
# read takes some punctuation as a zero, and ".." would name another endpoint.

# LAW: a number is a run id.
law runs_id_digits:
  {Cli.digits("1337") == True{} : Bool}

# LAW: ".." reads as a number under U32.read but is not one, so it is refused.
law runs_id_dots:
  {Cli.digits("..") == False{} : Bool}

# LAW: ...and neither is a path in a run id.
law runs_id_path:
  {Cli.digits("1/cancel") == False{} : Bool}

# LAW: ...and neither is an empty id.
law runs_id_empty:
  {Cli.digits("") == False{} : Bool}

# Watching and rerunning runs
# ----------------------------
# A watch follows a run for as long as it takes, so a poll that never reached the forge says
# nothing about the run: it is retried on the next tick, and only five failed polls in a row
# end the watch. Giving up exits with a code of its own, so a script that gates on a watch
# can tell "couldn't see the run" from "the run failed". A run ends where its status says
# so, on every forge. A rerun builds one endpoint per forge and mode, and a job id reaches
# it only as digits.

# LAW: a poll that never reached the forge is retried.
law watch_poll_broke:
  {Runs.poll.of(None{}) == Runs.Retry{} : Runs.Polled}

# LAW: a 5xx is the forge being unreachable, so it is retried too.
law watch_poll_5xx:
  {Runs.poll.of(Some{503}) == Runs.Retry{} : Runs.Polled}

# LAW: a 4xx is the forge answering, so it ends the watch.
law watch_poll_4xx:
  {Runs.poll.of(Some{404}) == Runs.Fatal{} : Runs.Polled}

# LAW: a 2xx is the run to read.
law watch_poll_2xx:
  {Runs.poll.of(Some{200}) == Runs.Good{} : Runs.Polled}

# LAW: a poll that got an answer resets the count of failed polls.
law watch_count_reset:
  {Runs.poll.count(4n, Runs.Good{}) == 0n : Nat}

# LAW: a retried poll adds one to the count.
law watch_count_retry:
  {Runs.poll.count(4n, Runs.Retry{}) == 5n : Nat}

# LAW: the watch gives up exactly when five polls in a row have failed.
law watch_gives_up:
  {Runs.poll.gave.up(5n) == True{} : Bool}

# LAW: ...and not before.
law watch_not_yet:
  {Runs.poll.gave.up(4n) == False{} : Bool}

# A run ends where its status says so. GitHub and Gitea say "completed" and send the
# conclusion beside it; Forgejo names the conclusion in the status field itself
# (success, failure, cancelled, skipped), so a watch that waited for "completed" never
# finished on Codeberg. A terminal status ends a watch on every forge, a state the run is
# still in does not, and the ending decides the exit code.

# LAW: a completed status ends a run, as it always has on GitHub and Gitea.
law watch_done_completed:
  {Runs.status.terminal("completed") == True{} : Bool}

# LAW: ...and so does a status Forgejo names a conclusion in.
law watch_done_success:
  {Runs.status.terminal("success") == True{} : Bool}

# LAW: ...a failed one.
law watch_done_failure:
  {Runs.status.terminal("failure") == True{} : Bool}

# LAW: ...a cancelled one.
law watch_done_cancelled:
  {Runs.status.terminal("cancelled") == True{} : Bool}

# LAW: ...a skipped one.
law watch_done_skipped:
  {Runs.status.terminal("skipped") == True{} : Bool}

# LAW: a run that is running is not done.
law watch_live_running:
  {Runs.status.terminal("running") == False{} : Bool}

# LAW: ...nor is a queued one.
law watch_live_queued:
  {Runs.status.terminal("queued") == False{} : Bool}

# LAW: ...nor one the forge sent no status for, so a body without one cannot end a watch.
law watch_live_empty:
  {Runs.status.terminal("") == False{} : Bool}

# LAW: Forgejo's ending is its status, since it sends no conclusion.
law watch_end_forgejo:
  {Runs.state.of("failure", "", True{}) == "failure" : String}

# LAW: a run that concluded in failure exits 1.
law watch_exit_failed:
  {Runs.watch.code(False{}) == 1 : U32}

# LAW: a watch that gave up on the forge exits 2, so the two never read alike.
law watch_exit_gaveup:
  {Runs.watch.code(True{}) == 2 : U32}

# LAW: a run whose ending is failure exits 1.
law watch_exit_status_failure:
  {Runs.watch.end.code("failure") == 1 : U32}

# LAW: ...and so does one that was cancelled.
law watch_exit_status_cancelled:
  {Runs.watch.end.code("cancelled") == 1 : U32}

# LAW: a run that succeeded exits 0.
law watch_exit_status_success:
  {Runs.watch.end.code("success") == 0 : U32}

# LAW: ...and so does one that was skipped, which is not a failure.
law watch_exit_status_skipped:
  {Runs.watch.end.code("skipped") == 0 : U32}

# LAW: a GitHub run ends the way it always did: completed with a failed conclusion exits 1.
law watch_exit_github_failure:
  {Runs.watch.end.code(Runs.state.of("completed", "failure", True{})) == 1 : U32}

# LAW: ...and completed with a good one exits 0.
law watch_exit_github_success:
  {Runs.watch.end.code(Runs.state.of("completed", "success", True{})) == 0 : U32}

# LAW: giving up names the count and the last state the watch saw.
law watch_gave_up_text:
  {Runs.watch.gave.up.text(5n, "in_progress") == "gave up after 5 failed polls; the run is still in_progress" : String}

# LAW: a Gitea rerun of a run is actions/runs/<run>/rerun.
law rerun_path_gitea:
  {Runs.rerun.path(Ctx.Gitea{}, "5056", "", False{}, False{}) == "actions/runs/5056/rerun" : String}

# LAW: ...its failed jobs are at the same path with -failed-jobs.
law rerun_path_gitea_failed:
  {Runs.rerun.path(Ctx.Gitea{}, "5056", "", True{}, False{}) == "actions/runs/5056/rerun-failed-jobs" : String}

# LAW: a Gitea job rerun nests under its run.
law rerun_path_gitea_job:
  {Runs.rerun.path(Ctx.Gitea{}, "5056", "42", False{}, True{}) == "actions/runs/5056/jobs/42/rerun" : String}

# LAW: a GitHub rerun of a run is the same path.
law rerun_path_github:
  {Runs.rerun.path(Ctx.GitHub{}, "5056", "", False{}, False{}) == "actions/runs/5056/rerun" : String}

# LAW: ...and so are its failed jobs.
law rerun_path_github_failed:
  {Runs.rerun.path(Ctx.GitHub{}, "5056", "", True{}, False{}) == "actions/runs/5056/rerun-failed-jobs" : String}

# LAW: a GitHub job rerun names the job alone, not its run.
law rerun_path_github_job:
  {Runs.rerun.path(Ctx.GitHub{}, "5056", "42", False{}, True{}) == "actions/jobs/42/rerun" : String}

# LAW: a job id that is not digits only never reaches a rerun path.
law rerun_job_id_digits:
  {Cli.digits("42/cancel") == False{} : Bool}

# runs view --json
# ---------------
# A command that addresses one run prints one object, as issue view --comments does.

# LAW: the document starts with the run.
law view_json_run_first:
  {String.starts_with(Runs.view.json.doc("{}", "[]"), "{\"run\":") == True{} : Bool}

# LAW: ...and carries the jobs as an array beside it, not as more run objects.
law view_json_jobs_array:
  {String.contains(Runs.view.json.doc("{}", "[]"), ",\"jobs\":[") == True{} : Bool}

# Path segments
# -------------
# A name that keeps its slashes goes into a URL path as it is, so no segment of it may be
# empty or a dot: "../x" would leave the path for another endpoint. A command refuses such
# a name before it sends anything.

# LAW: a .. segment is refused.
law path_dotdot:
  {Url.encode.path.ok("../x") == False{} : Bool}

# LAW: a .. segment in the middle is refused.
law path_dotdot_mid:
  {Url.encode.path.ok("a/../b") == False{} : Bool}

# LAW: a . segment is refused.
law path_dot:
  {Url.encode.path.ok("a/./b") == False{} : Bool}

# LAW: a leading slash, so an empty first segment, is refused.
law path_leading:
  {Url.encode.path.ok("/a") == False{} : Bool}

# LAW: a doubled slash, so an empty middle segment, is refused.
law path_double:
  {Url.encode.path.ok("a//b") == False{} : Bool}

# LAW: a branch name whose segments are plain is safe.
law path_ok_branch:
  {Url.encode.path.ok("memu/foo") == True{} : Bool}

# LAW: a dotted version is safe, since only a whole . or .. segment is refused.
law path_ok_version:
  {Url.encode.path.ok("v1.0.2") == True{} : Bool}

# LAW: a release branch with a dotted segment is safe.
law path_ok_release:
  {Url.encode.path.ok("release/1.0") == True{} : Bool}

# LAW: a value with a slash of its own is two segments, which one segment may not be.
law path_one_seg_slash:
  {Url.encode.seg.ok("ci.yml/ci.yml") == False{} : Bool}

# LAW: a . or .. is not one segment either.
law path_one_seg_dots:
  {Url.encode.seg.ok("..") == False{} : Bool}

# LAW: a workflow file name is one segment, and goes in the path.
law path_one_seg_plain:
  {Url.encode.seg.ok("ci.yml") == True{} : Bool}

# LAW: a repo delete of . as the owner names no repo, so it can't reach a path.
law repo_delete_dot_owner:
  {Repo.target(Ctx.Gitea{}, "codeberg.org", "./x") == None{} : Maybe<&2, Ctx.Repo>}

# LAW: ...and neither does .. as the name.
law repo_delete_dot_name:
  {Repo.target(Ctx.GitHub{}, "github.com", "x/..") == None{} : Maybe<&2, Ctx.Repo>}

# LAW: ...and neither does an empty half.
law repo_delete_empty_half:
  {Repo.target(Ctx.Gitea{}, "codeberg.org", "x/") == None{} : Maybe<&2, Ctx.Repo>}

# A merged GitHub pull request's head branch is deleted at git/refs/heads/<ref>, and the
# ref keeps its slashes in that path. The name is encoded, and one that would walk out of
# the path is left alone.

# LAW: main#x goes into the delete path encoded, so the # cannot cut it.
law pr_ref_path_hash:
  {Pr.gh.ref.path("main#x") == "git/refs/heads/main%23x" : String}

# LAW: ...and a percent in the name cannot smuggle another octet in.
law pr_ref_path_percent:
  {Pr.gh.ref.path("a%b") == "git/refs/heads/a%25b" : String}

# LAW: a branch under a slash keeps it, so memu/x stays memu/x.
law pr_ref_path_slash:
  {Pr.gh.ref.path("memu/x") == "git/refs/heads/memu/x" : String}

# LAW: a head ref with a .. segment is refused before the delete.
law pr_ref_dotdot:
  {Pr.gh.ref.path.ok("feature/../main") == False{} : Bool}

# Pull requests
# -------------
# A pull request's number reaches a URL path, so it is digits only, the way a run id is.
# close and reopen differ in one word, the state both forges read on the same PATCH, and a
# listed pull request carries the merge as merged_at, which a forge sends as null when it
# did not merge.

# LAW: a number is a pull request number.
law pr_number_digits:
  {Pr.number.ok("41") == True{} : Bool}

# LAW: ".." reads as a number under U32.read but is not one, so it is refused before it
# can reach pulls/<n>.
law pr_number_dots:
  {Pr.number.ok("..") == False{} : Bool}

# LAW: close sets the state closed, the one field a pull request's PATCH needs.
law pr_close_state:
  {Pr.state.word(True{}) == "closed" : String}

# LAW: reopen sets the state open.
law pr_reopen_state:
  {Pr.state.word(False{}) == "open" : String}

# LAW: that state goes to pulls/<number>, the path view reads.
law pr_state_path:
  {Pr.state.path("41") == "pulls/41" : String}

# LAW: merged is "true" exactly when merged_at names a merge.
law pr_merged_at:
  {Pr.merged.text("2026-11-03T12:00:00Z") == "true" : String}

# LAW: ...and "false" when merged_at is empty, the way a forge that sends null sends it.
law pr_merged_unset:
  {Pr.merged.text("") == "false" : String}

# LAW: a listed pull request's --json carries both refs and the merge, so one list maps
# every branch to its pull request without a view each.
law pr_list_fields:
  {Pr.list.fields() == ["number", "title", "state", "merged", "merged_at", "head.ref", "base.ref", "user.login", "html_url"] : List<&2, String>}

# LAW: a command that addresses one object prints the object itself, so its --json opens
# with { and closes with }, not the one-element array it printed before.
law pr_json_view:
  {Cli.json.doc("7", True{}) == "{7}" : String}

# LAW: a list prints an array, so its --json opens with [ and closes with ].
law pr_json_list:
  {Cli.json.doc("7", False{}) == "[7]" : String}

# Packages
# --------
# A package delete is destructive and cha never prompts, so a pipeline can only delete when
# it says --yes.

# LAW: a package delete without --yes is refused, and names the version it would remove.
law packages_refuses_without_yes:
  {Packages.refusal("cha", "0.1.0", False{}) == "packages delete: would remove cha 0.1.0 for good; rerun with --yes" : String}

# LAW: --yes lets the delete through.
law packages_allows_with_yes:
  {Packages.refusal("cha", "0.1.0", True{}) == "" : String}

# Hooks
# -----
# A webhook's config carries its secret: GitHub masks it, Gitea can hand it back. A hook
# row drops every field named secret, password or token, so neither the text line nor
# --json can print one.

# LAW: config.secret is dropped, and the fields around it stay.
law hooks_row_fields:
  {Hooks.row.fields(["id", "config.url", "config.content_type", "config.secret"]) == ["id", "config.url", "config.content_type"] : List<&2, String>}

# LAW: a field is judged by its last path segment, so a url that mentions a token is kept.
law hooks_row_fields_url:
  {Hooks.row.fields(["config.url?token=x", "config.password", "metadata.token"]) == ["config.url?token=x"] : List<&2, String>}

# LAW: the last segment is read in any case.
law hooks_row_fields_case:
  {Hooks.row.fields(["config.Secret", "Config.Password", "TOKEN"]) == Nil{} : List<&2, String>}

# LAW: a webhook URL is shown as its scheme and host and /… for its path: a Slack URL
# carries its token in the path.
law hooks_url_path:
  {Hooks.url.redact("https://hooks.slack.com/services/T000/B000/XXXX") == "https://hooks.slack.com/…" : String}

# LAW: a / in a raw password doesn't put any of it in the shown url.
law hooks_url_pass_slash:
  {Hooks.url.redact("https://u:p/ss@hooks.slack.com/services/T000/B000/XXXX") == "https://hooks.slack.com/…" : String}

# LAW: user:pass@ in a webhook URL is dropped.
law hooks_url_userinfo:
  {Hooks.url.redact("https://user:pass@hooks.example/hook") == "https://hooks.example/…" : String}

# LAW: a query is dropped, so a ?token= can't reach the output.
law hooks_url_query:
  {Hooks.url.redact("https://hooks.example/hook?token=s3cr3t") == "https://hooks.example/…" : String}

# LAW: a URL with no path, query or userinfo is shown as it is.
law hooks_url_plain:
  {Hooks.url.redact("https://hooks.example") == "https://hooks.example" : String}

# LAW: a hook id may go into a path only as digits: ".." reads as a number but is not one.
law hooks_id_dots:
  {Hooks.id.ok("..") == False{} : Bool}

# LAW: ...and neither is a number with anything but digits in it.
law hooks_id_letters:
  {Hooks.id.ok("12a") == False{} : Bool}

# LAW: ...and neither is an empty id.
law hooks_id_empty:
  {Hooks.id.ok("") == False{} : Bool}
