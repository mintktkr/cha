\* Tls13Client: chaki's TLS 1.3 client handshake, as lib/chaki/tls.bend runs it at 51c3231,
\* with the server as an adversary that sends any message at any time.
\*
\* The client is the pure state machine of tls.bend: Phase is the message that is due next
\* (Phase.hello, ee, cert, verify, fin), asked is the phase where the shell owes a verdict on
\* the chain and the CertificateVerify (tlsio.bend's trust), ready is Reply.ready, closed is
\* the server's close_notify, and dead is hs.die. Each action names the def it models. The
\* shell's trust verdict is one step, because tlsio.bend's trust makes it in one call: x509v
\* for the chain, then the leaf's signature.
\*
\* This model checks five rules (see the INVARIANTs at the end):
\*   R1 no application data is delivered to, or sent by, the client before the server's
\*      Finished is verified and the chain and the CertificateVerify verified;
\*   R2 Connected only after the chain was trusted, the CertificateVerify verified and the
\*      server's Finished verified;
\*   R3 those three checks happen in the order the code makes them: the Finished first (it is
\*      what asks the shell), then the chain, then the signature;
\*   R4 Failed is absorbing: once the connection fails, every later state is Failed;
\*   R5 at most one HelloRetryRequest.
\*
\* It leaves out the record and byte layer (fragmentation, the AEAD, sequence numbers, the
\* transcript hashes), TLS 1.2 itself (only the refusal of a ServerHello without 0x0304 is
\* modelled), PSK and 0-RTT, KeyUpdate and NewSessionTicket after Connected, the legacy
\* ChangeCipherSpec, the client's own close_notify, and the shell's event loop, which answers
\* Reply.ready before a record parked in Phase.asked is replayed.
---- MODULE Tls13Client ----
EXTENDS Naturals

VARIABLES
  phase,          \* how far the handshake is: the message that is due, or the end
  hrr,            \* how many HelloRetryRequests the server has sent
  parked,         \* what hs.one kept in buf in Phase.asked instead of acting on it
  finVerified,    \* hs.fin.mac held for the server's Finished
  chainTrusted,   \* x509v.verify held for the chain (tlsio.bend's trust.chain)
  sigVerified,    \* the CertificateVerify signature held (tlsio.bend's trust.leaf)
  delivered,      \* hs.app handed application data to the shell (Reply.data)
  appSent,        \* hs.send put application data records on the wire
  everFailed      \* a state at or after passing through Phase.dead

vars == <<phase, hrr, parked, finVerified, chainTrusted, sigVerified, delivered, appSent, everFailed>>

\* the phases whose records the client acts on in the same step. In Phase.asked,
\* Phase.closed and Phase.dead, want.of is Want.refuse and hs.one parks the bytes instead.
Before == {"hello", "ee", "cert", "verify", "fin"}

Init ==
  /\ phase = "hello"
  /\ hrr = 0
  /\ parked = "none"
  /\ finVerified = FALSE
  /\ chainTrusted = FALSE
  /\ sigVerified = FALSE
  /\ delivered = FALSE
  /\ appSent = FALSE
  /\ everFailed = FALSE

\* hs.die: the phase is dead from here on, and Reply.failed is the last event
Failed ==
  /\ phase' = "failed"
  /\ everFailed' = TRUE
  /\ UNCHANGED <<hrr, parked, finVerified, chainTrusted, sigVerified, delivered, appSent>>

\* the same for a HelloRetryRequest, which tlsmsg.bend's sh.retry sees by its random
FailedOnRetry ==
  /\ phase' = "failed"
  /\ everFailed' = TRUE
  /\ hrr' = hrr + 1
  /\ UNCHANGED <<parked, finVerified, chainTrusted, sigVerified, delivered, appSent>>

\* hs.next, hs.ee, hs.cert, hs.verify.sig: the phase moves on and nothing else changes
Forward(p) ==
  /\ phase' = p
  /\ UNCHANGED <<hrr, parked, finVerified, chainTrusted, sigVerified, delivered, appSent, everFailed>>

\* hs.park: a record that arrived in Phase.asked waits in buf. hs.resume replays it after the
\* shell's verdict, so park names what is waiting: application data, a close_notify, or
\* anything that ends the connection.
Park(what) ==
  /\ phase' = phase
  /\ parked' = what
  /\ UNCHANGED <<hrr, finVerified, chainTrusted, sigVerified, delivered, appSent, everFailed>>

\* --- the server's messages, in the order the client expects them ---

\* hs.server, hs.server.keys: a ServerHello with 0x0304, an offered suite and a non-zero
\* x25519 share; the handshake keys are derived and Phase.ee is due
SrvServerHello ==
  phase = "hello" /\ Forward("ee")

\* hs.server.retry: a HelloRetryRequest, and x25519 is all the ClientHello offers, so the
\* connection dies. A second one can never arrive.
SrvHelloRetryRequest ==
  phase = "hello" /\ FailedOnRetry

\* hs.msg.at's last case: a ServerHello the phase doesn't expect, which is a second
\* HelloRetryRequest when it carries sh.retry's random
SrvLateHelloRetryRequest ==
  \/ /\ phase \in Before \ {"hello"}
     /\ FailedOnRetry
  \/ /\ phase = "asked"
     /\ Park("fatal")

\* tlsmsg.bend's sh.ver.ok: no 0x0304 in supported_versions, which is what a TLS 1.2 server
\* answers with the RFC 8446 4.1.3 downgrade sentinel. hs.server.res -> hs.die
SrvDowngrade ==
  phase = "hello" /\ Failed

\* hs.server.zero: the server's share is all zeros, so it has small order (RFC 7748 6.1)
SrvSmallOrderShare ==
  phase = "hello" /\ Failed

\* hs.ee, hs.ee.alpn: EncryptedExtensions with http/1.1 or no ALPN at all
SrvEncryptedExtensions ==
  phase = "ee" /\ Forward("cert")

\* hs.ee.alpn's False branch: an ALPN the ClientHello didn't offer
SrvBadAlpn ==
  phase = "ee" /\ Failed

\* hs.cert, hs.cert.by: a non-empty certificate chain, leaf first
SrvCertificate ==
  phase = "cert" /\ Forward("verify")

\* hs.cert.by's True branch: an empty chain
SrvNoCertificate ==
  phase = "cert" /\ Failed

\* hs.verify.sig: a CertificateVerify with one of the four schemes; the signed content (64
\* spaces, the context string, a 0 byte, the transcript hash) goes to the shell
SrvCertificateVerify ==
  phase = "verify" /\ Forward("fin")

\* hs.verify.sig's hs.gate: a pkcs1 or unknown signature scheme, refused before the shell
\* ever sees the signature
SrvPkcs1CertificateVerify ==
  phase = "verify" /\ Failed

\* hs.fin, hs.fin.mac: the server's Finished checks, so the phase is asked and Reply.check
\* asks the shell for its verdict
SrvFinished ==
  /\ phase = "fin"
  /\ phase' = "asked"
  /\ finVerified' = TRUE
  /\ UNCHANGED <<hrr, parked, chainTrusted, sigVerified, delivered, appSent, everFailed>>

\* hs.fin.by's False branch: the Finished MAC doesn't check
SrvBadFinished ==
  phase = "fin" /\ Failed

\* hs.app: application data before the handshake ended is hs.die, and in Phase.asked the
\* record is parked first
SrvApplicationDataEarly ==
  \/ /\ phase \in Before
     /\ Failed
  \/ /\ phase = "asked"
     /\ Park("data")

\* hs.app in Phase.ready: Reply.data, the only way bytes reach the shell's buffer
SrvApplicationData ==
  /\ phase = "ready"
  /\ phase' = phase
  /\ delivered' = TRUE
  /\ UNCHANGED <<hrr, parked, finVerified, chainTrusted, sigVerified, appSent, everFailed>>

\* hs.alert: a fatal alert names itself and the connection dies
SrvAlert ==
  \/ /\ phase \in Before
     /\ Failed
  \/ /\ phase = "asked"
     /\ Park("fatal")

\* hs.alert.ready: close_notify after the handshake is Reply.closed; before it, hs.die
SrvCloseNotify ==
  \/ /\ phase = "ready"
     /\ Forward("closed")
  \/ /\ phase \in Before
     /\ Failed
  \/ /\ phase = "asked"
     /\ Park("closed")

\* hs.msg.at's last case: any other handshake message the phase doesn't expect is
\* "an unexpected handshake message"
SrvUnexpectedMessage ==
  \/ /\ phase \in Before
     /\ Failed
  \/ /\ phase = "asked"
     /\ Park("fatal")

\* --- the shell, holding the core's Check ---

\* hs.trusted with True, after tlsio.bend's trust: x509v.verify for the chain, then the leaf's
\* CertificateVerify signature. hs.finish.sent sends the client's Finished and answers
\* Reply.ready, and hs.resume then replays whatever hs.park kept.
ShellTrusts ==
  /\ phase = "asked"
  /\ chainTrusted' = TRUE
  /\ sigVerified' = TRUE
  /\ UNCHANGED <<hrr, parked, finVerified, appSent>>
  /\ \/ /\ parked = "none"
        /\ phase' = "ready"
        /\ UNCHANGED <<delivered, everFailed>>
     \/ /\ parked = "data"
        /\ phase' = "ready"
        /\ delivered' = TRUE
        /\ UNCHANGED everFailed
     \/ /\ parked = "closed"
        /\ phase' = "closed"
        /\ UNCHANGED <<delivered, everFailed>>
     \/ /\ parked = "fatal"
        /\ phase' = "failed"
        /\ everFailed' = TRUE
        /\ UNCHANGED delivered

\* hs.trusted with False: the chain or the signature was refused, and hs.resume never runs
ShellRefuses ==
  phase = "asked" /\ Failed

\* hs.send: application data records, only in Phase.ready
ShellSendsData ==
  /\ phase = "ready"
  /\ phase' = phase
  /\ appSent' = TRUE
  /\ UNCHANGED <<hrr, parked, finVerified, chainTrusted, sigVerified, delivered, everFailed>>

\* every end state: nothing else can happen, and the state stays
Done ==
  phase \in {"failed", "closed"} /\ UNCHANGED vars

Next ==
  \/ SrvServerHello
  \/ SrvHelloRetryRequest
  \/ SrvLateHelloRetryRequest
  \/ SrvDowngrade
  \/ SrvSmallOrderShare
  \/ SrvEncryptedExtensions
  \/ SrvBadAlpn
  \/ SrvCertificate
  \/ SrvNoCertificate
  \/ SrvCertificateVerify
  \/ SrvPkcs1CertificateVerify
  \/ SrvFinished
  \/ SrvBadFinished
  \/ SrvApplicationDataEarly
  \/ SrvApplicationData
  \/ SrvAlert
  \/ SrvCloseNotify
  \/ SrvUnexpectedMessage
  \/ ShellTrusts
  \/ ShellRefuses
  \/ ShellSendsData
  \/ Done

Spec == Init /\ [][Next]_vars

\* R1: no application data is delivered to the client, and none is sent by it, before the
\* server's Finished is verified and the shell trusted the chain and the signature
NoApplicationDataBeforeAllChecks ==
  (delivered \/ appSent) => (finVerified /\ chainTrusted /\ sigVerified)

\* R2: Connected only after the chain was trusted, the CertificateVerify verified, and the
\* server's Finished verified
ConnectedOnlyAfterAllChecks ==
  phase = "ready" => (chainTrusted /\ sigVerified /\ finVerified)

\* R3: the three checks happen in the code's order: the Finished asks the shell, the shell
\* trusts the chain first, and only a trusted chain's leaf is asked for its signature
ChecksInOrder ==
  /\ chainTrusted => finVerified
  /\ sigVerified => chainTrusted

\* R4: Failed is absorbing; once the phase is dead, every later state is failed
FailedIsAbsorbing ==
  everFailed => phase = "failed"

\* R5: at most one HelloRetryRequest, because the first one ends the connection
AtMostOneHelloRetryRequest ==
  hrr <= 1

====
