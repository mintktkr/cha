# verify

Two TLA+ models of the places where chaki's order of events is the security property: the TLS
1.3 client handshake and the redirect chain. Each folder holds the model (`.tla`), its TLC
config (`.cfg`) and the view module (`view.ts`, the words the chart uses). Each rule is one
`INVARIANT`; each action names, in a comment, the def it models.

Run them, and read the result, as `.pi/skills/verify-chaki/SKILL.md` says. The `out/` folders
are not committed: `tlc.out` and `report.md` carry TLC's local paths, pids and timestamps, so
they are regenerated per run and are in `.gitignore`. The charts below are the last run's.

Sync commit: **cf7905c**. Both models were confirmed against the code at that commit.

## TLS 1.3 client — 29 states, 97 steps

`verify/tls/Tls13Client.tla` covers the handshake of `lib/chaki/tls.bend`, the ServerHello
refusals of `lib/chaki/tlsmsg.bend` and the trust decision of `lib/chaki/tlsio.bend`, with the
server as an adversary that sends any message at any time. TLC reached 29 distinct states and
97 steps; every rule holds.

- `NoApplicationDataBeforeAllChecks` — no application data is handed to the caller, and none is
  sent, before the server's Finished, the certificate chain and the CertificateVerify have all
  been verified.
- `ConnectedOnlyAfterAllChecks` — the client says Connected only after those three hold.
- `ChecksInOrder` — the Finished first (it is what asks the shell), then the chain, then the
  leaf's signature.
- `FailedIsAbsorbing` — once the connection has failed, every later state is Failed.
- `AtMostOneHelloRetryRequest` — at most one HelloRetryRequest, because the first one ends the
  connection.

```mermaid
stateDiagram-v2
  state "Legend" as legend {
    lg0: handshake
    lg1: checking
    lg2: connected
    lg3: over
  }
  class lg0 blue
  class lg1 yellow
  class lg2 teal
  class lg3 pink
  s0: Waiting for the ServerHello
  s1: Waiting for the EncryptedExtensions
  s2: Failed
  s3: Waiting for the certificate
  s4: Waiting for the CertificateVerify
  s5: Waiting for the server's Finished
  s6: Server's flight in, checking the certificate
  s7: Connected
  s8: Closed by the server
  [*] --> s0
  s0 --> s1: the ServerHello arrives
  s0 --> s2: an alert arrives or application data arrives early or the server answers for TLS 1.2 or the server is done sending [before the handshake ends] or the ServerHello carries the TLS 1.2 downgrade sentinel or the key share is all zeros or an unexpected message arrives or the server asks for another key exchange
  s1 --> s2: an alert arrives or application data arrives early or the server picks a protocol you didn't offer or the server is done sending [before the handshake ends] or an unexpected message arrives or a second key-exchange request arrives
  s1 --> s3: the EncryptedExtensions arrive
  s3 --> s2: an alert arrives or application data arrives early or the server is done sending [before the handshake ends] or the chain is empty or an unexpected message arrives or a second key-exchange request arrives
  s3 --> s4: the chain arrives
  s4 --> s2: an alert arrives or application data arrives early or the server is done sending [before the handshake ends] or the CertificateVerify uses a pkcs1 scheme or an unexpected message arrives or a second key-exchange request arrives
  s4 --> s5: the CertificateVerify arrives
  s5 --> s2: an alert arrives or application data arrives early or the server's Finished is wrong or the server is done sending [before the handshake ends] or an unexpected message arrives or a second key-exchange request arrives
  s5 --> s6: the server's Finished checks out
  s6 --> s2: the chain or the signature is refused or the chain and the signature check out, and a record that ends the connection was waiting
  s6 --> s7: the chain and the signature check out or the chain and the signature check out, and data was waiting
  s6 --> s8: the chain and the signature check out, and close_notify was waiting
  s7 --> s8: the server is done sending
  class s0 blue
  class s1 blue
  class s2 pink
  class s3 blue
  class s4 blue
  class s5 blue
  class s6 yellow
  class s7 teal
  class s8 pink
```

## Redirect chain — 27 states, 51 steps

`verify/redirect/Redirect.tla` covers the walk of `lib/chaki/http.bend` and the decisions it
asks `lib/chaki/hop.bend` for, over two origins, an https start and a hop budget of four. TLC
reached 27 distinct states and 51 steps; every rule holds. `test/verify_redirect_check.bend`
replays these hops through `judge` itself and runs in `scripts/check.sh`.

- `NoCredentialsToAnotherOrigin` — `authorization` and `cookie` are never sent to an origin
  other than the one the chain started at.
- `DroppedStaysDropped` — once dropped, they never come back, not even at the first origin.
- `NoHttpAfterHttps` — no request goes over http after an https start.
- `WithinHopBudget` — the chain does not outlive the hop budget; `walk`'s fuel refuses the next
  hop.

```mermaid
stateDiagram-v2
  state "Legend" as legend {
    lg0: asking
    lg1: answered
    lg2: stopped
  }
  class lg0 blue
  class lg1 teal
  class lg2 pink
  s0: Hop 1 of 4: a.example over https, with your credentials
  s1: Answer from a.example over https, with your credentials
  s2: Hop 2 of 4: a.example over https, with your credentials
  s3: Chain stopped
  s4: Hop 2 of 4: b.example over https, without your credentials
  s5: Hop 3 of 4: a.example over https, with your credentials
  s6: Hop 3 of 4: a.example over https, without your credentials
  s7: Answer from b.example over https, without your credentials
  s8: Hop 3 of 4: b.example over https, without your credentials
  s9: Hop 4 of 4: a.example over https, with your credentials
  s10: Answer from a.example over https, without your credentials
  s11: Hop 4 of 4: a.example over https, without your credentials
  s12: Hop 4 of 4: b.example over https, without your credentials
  [*] --> s0
  s0 --> s1: the server answers with no redirect
  s0 --> s2: the server redirects to the same origin
  s0 --> s3: the server redirects to http [refused]
  s0 --> s4: the server redirects to the other origin
  s2 --> s1: the server answers with no redirect
  s2 --> s5: the server redirects to the same origin
  s2 --> s3: the server redirects to http [refused]
  s2 --> s8: the server redirects to the other origin
  s4 --> s6: the server redirects to the other origin
  s4 --> s7: the server answers with no redirect
  s4 --> s8: the server redirects to the same origin
  s4 --> s3: the server redirects to http [refused]
  s5 --> s1: the server answers with no redirect
  s5 --> s9: the server redirects to the same origin
  s5 --> s3: the server redirects to http [refused]
  s5 --> s12: the server redirects to the other origin
  s6 --> s10: the server answers with no redirect
  s6 --> s11: the server redirects to the same origin
  s6 --> s3: the server redirects to http [refused]
  s6 --> s12: the server redirects to the other origin
  s8 --> s11: the server redirects to the other origin
  s8 --> s7: the server answers with no redirect
  s8 --> s12: the server redirects to the same origin
  s8 --> s3: the server redirects to http [refused]
  s9 --> s1: the server answers with no redirect
  s9 --> s3: the server redirects to http [refused] or the server redirects again [no hops left]
  s11 --> s10: the server answers with no redirect
  s11 --> s3: the server redirects to http [refused] or the server redirects again [no hops left]
  s12 --> s7: the server answers with no redirect
  s12 --> s3: the server redirects to http [refused] or the server redirects again [no hops left]
  class s0 blue
  class s1 teal
  class s2 blue
  class s3 pink
  class s4 blue
  class s5 blue
  class s6 blue
  class s7 teal
  class s8 blue
  class s9 blue
  class s10 teal
  class s11 blue
  class s12 blue
```
