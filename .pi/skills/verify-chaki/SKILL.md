---
name: verify-chaki
description: "Use whenever a change touches lib/chaki/tls.bend, lib/chaki/tlsmsg.bend, lib/chaki/tlsio.bend, lib/chaki/http.bend or lib/chaki/hop.bend, or a review needs the TLS 1.3 client handshake or the redirect chain checked beyond the tests: two TLA+ models of chaki's handshake and its redirect hops, each rule break as a shortest path in plain words."
---

# Verify chaki's TLS handshake and its redirect chain

chaki's TLS 1.3 client and its redirect chain are the two places where the order of events is
the security property, and where the offline tests reach some orders but not all of them.
These two models check every order of the events, over a small state space:

- `verify/tls/` — the client handshake of `lib/chaki/tls.bend`, the ServerHello refusals of
  `lib/chaki/tlsmsg.bend` and the trust decision of `lib/chaki/tlsio.bend`, with the server as
  an adversary that sends any message at any time.
- `verify/redirect/` — the redirect chain of `lib/chaki/http.bend` and the rules it asks
  `lib/chaki/hop.bend` for, over two origins, an https start, and a hop budget of four.

Each folder holds the model (`.tla`), its TLC config (`.cfg`, where the constants and the
checked rules are listed) and the view module (`view.ts`, the words the chart uses). Each rule
is one `INVARIANT` with a one-line comment; each action names, in a comment, the def it models.

## Read every result with /skill:statechart

Run `/skill:statechart` on each model folder and read what it prints and writes, by name. It
checks the rules with TLC, draws the chart of how the system moves between states, and gives
the shortest path to each rule it finds broken, in the words of the view. Never read `tlc.out`
by hand and never treat a chart as a pass: the report's "Rules that hold" list is the verdict.

## Run it

For each of `verify/tls` and `verify/redirect`: delete its `out/`, then run

    /skill:statechart <folder>/<Model>.tla --view <folder>/view.ts --out <folder>/out

The command needs the model, the config beside it and the view; the out folder is new or empty
each run (the command refuses to write into one that is not). Pass `--view` every time: without
it the chart draws the raw variable values instead of the reader's words, and nothing says so.
Both `--view` and `--out` are relative to where you run the command, not to the model. A run
takes seconds and needs no network on a machine where TLC is already installed.

`verify/*/out/` is in `.gitignore`: `tlc.out` and `report.md` hold TLC's local paths, pids and
timestamps, so they are never committed. The chart that is readable on GitHub is
`verify/README.md`, which holds each model's `chart.mmd` as a mermaid block beside its rules and
state count; when a model or a view changes, rerun and paste the new `chart.mmd` there (without
the `---` title frontmatter) and move its state count.

`test/verify_redirect_check.bend` is the redirect model's replay against the code and is part
of `scripts/check.sh`, not of a model run: `rr bend test/verify_redirect_check.bend` prints its
five `ok` lines.

Two rules to keep the runs honest:

- Never move a model's constant in the `.cfg` alone. The view states the budget too (the
  redirect view names the hop budget), so change both, or the chart lies.
- Never weaken a rule, a guard or a view label to make a run pass. A rule that breaks is a
  finding, not noise.

## The rules, in plain words

Each model's chart is in `verify/README.md`, one mermaid block per model.

TLS 1.3 client (`verify/tls/Tls13Client.tla`):

1. `NoApplicationDataBeforeAllChecks` — no application data is handed to the caller, and none
   is sent, before the server's Finished, the certificate chain and the CertificateVerify
   signature have all been verified.
2. `ConnectedOnlyAfterAllChecks` — the client says Connected only after those three hold.
3. `ChecksInOrder` — the order the code uses: the server's Finished is checked first (it is
   what asks the shell), then the chain, then the leaf's signature.
4. `FailedIsAbsorbing` — once the connection has failed, every later state is Failed.
5. `AtMostOneHelloRetryRequest` — at most one HelloRetryRequest, because the first one ends the
   connection.

Redirect (`verify/redirect/Redirect.tla`):

1. `NoCredentialsToAnotherOrigin` — `authorization` and `cookie` are never sent to an origin
   other than the one the chain started at.
2. `DroppedStaysDropped` — once dropped, they never come back, not even at the first origin.
3. `NoHttpAfterHttps` — no request goes over http after an https start.
4. `WithinHopBudget` — the chain does not outlive the hop budget; `walk`'s fuel refuses the
   next hop.

## The laws, and the rule each one backs

`lib/chaki/LAWS.bend` states the same promises a second way: a law fixes one case on the real
code, where a rule here holds over every order of events. A law that breaks is a code bug in
one case; a rule that breaks is the design itself. The two sections are `[tls]`
(`tls.bend`, `tlsmsg.bend`) and `[http]` (`hop.bend`, the redirect decisions).

"none" is worth reading: it means the model leaves that part out, so the law is the only check
on it. If you change one of those, add the action or the rule here first.

TLS 1.3 client:

| law | backs |
|---|---|
| `tlsmsg_serverhello_taken` | `SrvServerHello`, the accepted ServerHello |
| `tlsmsg_serverhello_downgrade` | `SrvDowngradeSentinel` |
| `tlsmsg_serverhello_suite`, `tlsmsg_serverhello_group` | none: every refused ServerHello is one step to Failed here, and neither reason has its own action |
| `tls_app_needs_ready` | R1, through `SrvApplicationDataEarly` |
| `tls_app_when_ready` | `SrvApplicationData` |
| `tls_finished_refused` | `SrvBadFinished`, the step that leaves R1's `finVerified` false |
| `tls_finished_asks` | `SrvFinished`, the step R3's `chainTrusted => finVerified` rests on |
| `tls_trusted_refused` | `ShellRefuses` |
| `tls_trusted_early` | the `phase = "asked"` guard on `ShellTrusts` and `ShellRefuses` |
| `tls_retry_refused`, `tls_retry_wire_refused` | R5, through `SrvHelloRetryRequest` and `SrvLateHelloRetryRequest` |
| `tls_cert_empty_refused` | `SrvNoCertificate` |
| `tls_send_needs_ready` | R1's `appSent` side, and `ShellSendsData`'s `phase = "ready"` guard |
| `tls_dead_absorbs` | R4, `FailedIsAbsorbing` |
| `tlsmsg_record_max`, `tlsmsg_record_overflow`, `tlsmsg_record_overflow_refused`, `tlsmsg_clienthello_roundtrip`, `tlsmsg_clienthello_one`, `tlsmsg_clienthello_short`, `tls_record_refused`, `tls_ccs_after_ready`, `tls_ccs_bad_refused`, `tls_traffic_next`, `tls_update_fresh_seq`, `tls_update_refused`, `tls_transcript_grows`, `tls_close_needs_ready` | none: the record and byte layer, ChangeCipherSpec, KeyUpdate, the transcript and the client's own close_notify are outside the model |

Redirect:

| law | backs |
|---|---|
| `hop_cross_origin_drops_credentials` | R1, through `RedirectElsewhere` |
| `hop_same_origin_keeps_request`, `hop_308_keeps_request` | `RedirectHere` |
| `hop_credentials_stay_dropped` | R2; it is the chain a.example -> b.example -> a.example -> b.example, which is why the budget is four |
| `hop_drop_named` | R1 and R2's mechanism: the drop both go through |
| `hop_downgrade_refused` | R3, through `RedirectToHttp` |
| `hop_no_redirect_no_hop`, `hop_empty_location_no_hop` | `Answer` |
| `hop_keeps_status`, `hop_see_other_get`, `hop_see_other_head` | none: the method and body rules are outside the model |
| `hop_bad_location_refused` | none: a Location that isn't a url is outside the model |

## Coverage record

| model | covers | defs, at cf7905c |
|---|---|---|
| `verify/tls` | the handshake and the trust decision | `lib/chaki/tls.bend`: `hs.die`, `hs.next`, `hs.gate`, `hs.server`, `hs.server.keys`, `hs.server.zero`, `hs.server.retry`, `hs.server.res`, `hs.ee`, `hs.ee.alpn`, `hs.cert`, `hs.cert.by`, `hs.verify.sig`, `hs.fin`, `hs.fin.mac`, `hs.fin.by`, `hs.finish.sent`, `hs.trusted`, `hs.app`, `hs.alert`, `hs.alert.ready`, `hs.msg.at`, `hs.one.at`, `want.of`, `hs.park`, `hs.send`; `lib/chaki/tlsmsg.bend`: `server_hello`, `sh.check`, `sh.retry`, `sh.ver.ok`, `sh.downgrade.ok`, `suite.ok`, `key.ok`; `lib/chaki/tlsio.bend`: `trust`, `trust.chain`, `trust.leaf`, `sh.verdict` |
| `verify/redirect` | the hop rules of the redirect walk | `lib/chaki/hop.bend`: `judge.resp`, `judge.follows`, `judge.next`, `judge.hop`, `judge.down`, `judge.go`, `move.method`, `move.headers`, `move.body`, `move.creds`, `drop`, `drop.has`, `drop.keep`, `drop.go`, `redirect.code`, `redirect.keeps`, `scheme.of`; `lib/chaki/http.bend`: `judge`, `judge.state`, `judge.answer`, `fetch`, `walk`'s fuel; `lib/chaki/url.bend`: `Url.origin`, `Url.resolve` |

Sync commit: **cf7905c**. Both models were confirmed against the code at that commit.

`test/verify_redirect_check.bend` replays the redirect model's hops through `judge` itself: the
credentials dropped on a hop to the other origin, dropped ones still absent when the chain
comes back to the first origin, and the https -> http refusal. It reads `hop.bend` through
`http.bend`'s `judge`, so it is the code's own answer for the model's steps, and it passes at
cf7905c. It is an offline check in the `test/*_check.bend` style, so `scripts/check.sh` runs it
on every change; run it alone with `rr bend test/verify_redirect_check.bend`.

## A model error, or a bug

A break is one or the other. Work in this order:

1. Open the def the action names in its comment, and read the path the report gives, step by
   step, against it.
2. **Model error** when the def has a guard the model left out: a `hs.gate`/`hs.die` branch, a
   `by` False branch, `want.of`'s `Want.refuse` (a record that arrives in `Phase.asked` is
   parked, not refused), or, on the redirect side, `judge.follows` versus the status alone and
   `move.creds`' `cross` in `judge.go`. Fix the model, and say in the change what the model had
   wrong.
3. **Code bug** when the code really takes the step the path names. Report it with the path in
   the code's words, and do not change the code on your own authority.
4. Where it can run, `test/chaki_tls_check.bend` settles the step for the client: its lines
   `app first`, `early trusted event`, `retry fails`, `garbage hello`, `alert first`,
   `send early` and `close early` are the code's own answer for exactly these actions.

Before trusting a rule you have just added, break a copy of the model in scratch (under
`~/.cache/agent-tmp/`, never `/tmp`) and show that the run's shortest path names the step you
broke. A rule that has never been seen to fail proves nothing. Do not keep the broken copy in
the repo.

## When the code changes

The models do not read the code: they check the design you say the code implements, so a code
change that the model was not told about passes silently. So:

- Change the model in the same change as the code, then rerun both and read the result.
- Move the sync commit above forward only after you have confirmed, def by def, that the model
  still describes the code at the new commit.
- If a covered def disappears or its name changes, the model's comments name a def that is
  gone: fix them in the same change.
- If a new rule is needed, add an `INVARIANT` with its one-line comment, add a broken variant in
  scratch that breaks it, and say in the hand-off which state the chart now marks.

## What the models leave out

TLS: the record and byte layer (fragmentation, the AEADs, sequence numbers, the transcript
hashes), TLS 1.2 itself and the alert a client is expected to send when it refuses a
handshake (only two ServerHello refusals are modelled: a `supported_versions` that isn't 0x0304, and the TLS 1.2 downgrade sentinel in the
random; both end in the one Failed state, and a bad suite, a bad key share or a malformed
ServerHello share that step without an action of their own), PSK, 0-RTT, client certificates,
`KeyUpdate` and `NewSessionTicket` after Connected, the legacy `ChangeCipherSpec`, the client's
own `close_notify`, and the shell's event loop, where `Reply.ready` reaches the caller before a
record parked in `Phase.asked` is replayed.

Redirect: the headers other than `authorization` and `cookie`, the method and body rules
(301/302/303 to GET, 307/308 keep both), a `Location` that is not a url, a request that fails,
ports, TLS, and the code's real fuel of 23, which allows 12 requests. The model's budget of 4
is a small bound for model checking, not the code's number: it is as long as the chain the
credentials law walks, and no longer.
