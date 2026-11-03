---
name: verify-chaki
description: "Use whenever a change touches lib/chaki/tls.bend, lib/chaki/tlsio.bend, lib/chaki/http.bend or lib/chaki/hop.bend, or a review needs the TLS 1.3 client handshake or the redirect chain checked beyond the tests: two TLA+ models of chaki's handshake and its redirect hops, each rule break as a shortest path in plain words."
---

# Verify chaki's TLS handshake and its redirect chain

chaki's TLS 1.3 client and its redirect chain are the two places where the order of events is
the security property, and where the offline tests reach some orders but not all of them.
These two models check every order of the events, over a small state space:

- `verify/tls/` — the client handshake of `lib/chaki/tls.bend` and the trust decision of
  `lib/chaki/tlsio.bend`, with the server as an adversary that sends any message at any time.
- `verify/redirect/` — the redirect chain of `lib/chaki/http.bend`, over two origins, an https
  start, and a hop budget of three.

Each folder holds the model (`.tla`), its TLC config (`.cfg`, where the constants and the
checked rules are listed) and the view module (`view.ts`, the words the chart uses). Each rule
is one `INVARIANT` with a one-line comment; each action names, in a comment, the def it models.

## Read every result with /skill:statechart

Run `/skill:statechart` on each model folder and read what it prints and writes, by name. It
checks the rules with TLC, draws the chart of how the system moves between states, and gives
the shortest path to each rule it finds broken, in the words of the view. Never read `tlc.out`
by hand and never treat a chart as a pass: the report's "Rules that hold" list is the verdict.

## Run it

For each of `verify/tls` and `verify/redirect`: open `out/`, delete it, and run
`/skill:statechart` on the model in the folder. It needs the model, the config beside it, and
the view; the out folder is new or empty each run (the command refuses to write into one that
is not). A run takes seconds and needs no network on a machine where TLC is already installed.

Two rules to keep the runs honest:

- Never move a model's constant in the `.cfg` alone. The view states the budget too (the
  redirect view names the hop budget), so change both, or the chart lies.
- Never weaken a rule, a guard or a view label to make a run pass. A rule that breaks is a
  finding, not noise.

## The rules, in plain words

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

## Coverage record

| model | covers | defs, at 51c3231 |
|---|---|---|
| `verify/tls` | the handshake and the trust decision | `lib/chaki/tls.bend`: `hs.die`, `hs.next`, `hs.gate`, `hs.server`, `hs.server.keys`, `hs.server.zero`, `hs.server.retry`, `hs.ee`, `hs.ee.alpn`, `hs.cert`, `hs.cert.by`, `hs.verify.sig`, `hs.fin`, `hs.fin.mac`, `hs.fin.by`, `hs.finish.sent`, `hs.trusted`, `hs.app`, `hs.alert`, `hs.alert.ready`, `hs.msg.at`, `hs.one.at`, `want.of`, `hs.park`, `hs.send`; `lib/chaki/tlsmsg.bend`: `server_hello`, `sh.retry`, `sh.ver.ok`, `suite.ok`; `lib/chaki/tlsio.bend`: `trust`, `trust.chain`, `trust.leaf`, `sh.verdict` |
| `verify/redirect` | the hop rules of the redirect walk | `lib/chaki/http.bend`: `judge`, `judge.resp`, `judge.next`, `judge.hop`, `judge.go`, `judge.answer`, `drop`, `drop.go`, `redirect.code`, `fetch`, `walk`'s fuel; `lib/chaki/url.bend`: `Url.origin` |

Sync commit: **51c3231**. The models were last confirmed against the code at that commit.

`verify/replay_redirect_check.bend` replays the redirect rules through `judge` itself: the
credentials dropped on a hop to the other origin, dropped ones still absent when the chain
comes back to the first origin, and the https -> http refusal. At 51c3231 it cannot run:
`lib/chaki/tlsio.bend` does not typecheck (its `Sh` constructors `Wait` and `Ready` collide
with `Base`'s `Poll` constructors) and `http.bend` imports it. Run it once that is fixed, with
`rr bend verify/replay_redirect_check.bend` on a machine with the pinned bend.

## A model error, or a bug

A break is one or the other. Work in this order:

1. Open the def the action names in its comment, and read the path the report gives, step by
   step, against it.
2. **Model error** when the def has a guard the model left out: a `hs.gate`/`hs.die` branch, a
   `by` False branch, `want.of`'s `Want.refuse` (a record that arrives in `Phase.asked` is
   parked, not refused), `judge.hop`'s `down`, or `drop` in `judge.go`. Fix the model, and say
   in the change what the model had wrong.
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
hashes), TLS 1.2 and the downgrade alert itself (only the accepted-ServerHello route is
modelled), PSK, 0-RTT, client certificates, `KeyUpdate` and `NewSessionTicket` after Connected,
the legacy `ChangeCipherSpec`, the client's own `close_notify`, and the shell's event loop,
where `Reply.ready` reaches the caller before a record parked in `Phase.asked` is replayed.

Redirect: the headers other than `authorization` and `cookie`, the method and body rules
(301/302/303 to GET, 307/308 keep both), a `Location` that is not a url, a request that fails,
ports, TLS, and the code's real fuel of 23, which allows 12 requests. The model's budget of 3
is a small bound for model checking, not the code's number.
