\* Redirect: the redirect chain of lib/chaki/http.bend's Redirects section and the rules it
\* asks lib/chaki/hop.bend for, at cf7905c, over two origins and a hop budget of four, with
\* the server choosing each answer. The budget is four because that is the chain
\* lib/chaki/LAWS.bend's hop_credentials_stay_dropped states: a.example -> b.example ->
\* a.example -> b.example. With three, the request that comes back to the first origin has no
\* hop left, and R2 cannot be exercised in its own words.
\*
\* http.bend follows a redirect with judge: judge reads the response, asks hop.bend's
\* judge.follows whether the status and the Location ask for another request, and puts the
\* Next that judge.resp hands back into the walk's state with judge.state. hop.bend decides
\* the rest: another origin drops authorization and cookie (judge.go, move.creds), 301, 302
\* and 303 drop the body and the headers that framed it and turn anything but a HEAD into a
\* GET (move.method, move.headers, move.body), an https -> http hop is refused (judge.down,
\* judge.hop), and walk's fuel bounds how many hops a chain can take.
\*
\* The model takes one hop as one step, because the request and the judgement are two steps
\* in the code (walk's step and judge) with only the nondeterministic answer between them,
\* and no rule here looks at a request before its answer.
\*
\* This model checks four rules (see the INVARIANTs at the end):
\*   R1 credentials are never sent to an origin other than the first;
\*   R2 once dropped they are never sent again, even back at the first origin;
\*   R3 no request goes over http after an https start;
\*   R4 the chain ends within the hop budget.
\*
\* It leaves out the headers other than authorization and cookie, the method and body rules
\* (301/302/303 -> GET, 307/308 keep both; see lib/chaki/LAWS.bend's hop laws), a Location
\* that isn't a url, a request that fails, ports, TLS, and the code's real fuel of 23, which
\* allows 12 requests: the model's budget of four is a small bound for model checking, not
\* the code's number.
---- MODULE Redirect ----
EXTENDS Naturals

CONSTANT MaxHops    \* the budget: how many requests one chain may make

VARIABLES
  pc,       \* "go": a request is in flight; "done": the answer; "stopped": a Fail
  hop,      \* how many requests the chain has made
  at,       \* the origin of the request in flight
  secure,   \* whether that request goes over https
  creds,    \* whether that request carries authorization and cookie
  dropped   \* whether the chain has dropped them at some point

vars == <<pc, hop, at, secure, creds, dropped>>

First == "a.example"
Second == "b.example"

\* fetch sends the first hop: the caller's url, headers and body, so https to the first origin
\* with authorization and cookie (http.bend's fetch, walk, step)
Init ==
  /\ pc = "go"
  /\ hop = 1
  /\ at = First
  /\ secure = TRUE
  /\ creds = TRUE
  /\ dropped = FALSE

\* hop.bend's judge.resp with follow FALSE, so judge.follows found no redirect or no Location,
\* and http.bend's judge.answer makes the response the answer: the chain ends
Answer ==
  /\ pc = "go"
  /\ pc' = "done"
  /\ UNCHANGED <<hop, at, secure, creds, dropped>>

\* judge.go with cross FALSE: a redirect to the same origin, so move.creds keeps the headers
RedirectHere ==
  /\ pc = "go"
  /\ hop < MaxHops
  /\ pc' = "go"
  /\ hop' = hop + 1
  /\ at' = at
  /\ UNCHANGED <<secure, creds, dropped>>

\* judge.go with cross TRUE: Url.origin differs, so move.creds drops authorization and cookie
\* (hop.bend's drop of the two names)
RedirectElsewhere ==
  /\ pc = "go"
  /\ hop < MaxHops
  /\ pc' = "go"
  /\ hop' = hop + 1
  /\ at' = IF at = First THEN Second ELSE First
  /\ creds' = FALSE
  /\ dropped' = TRUE
  /\ secure' = secure

\* judge.hop with down TRUE (judge.down): https -> http is refused before any header is built
RedirectToHttp ==
  /\ pc = "go"
  /\ pc' = "stopped"
  /\ UNCHANGED <<hop, at, secure, creds, dropped>>

\* walk's fuel is gone and the answer was a redirect: Fail{"too many redirects"} (the walk
\* is http.bend's; the fuel is its own step, not a decision hop.bend makes)
TooManyRedirects ==
  /\ pc = "go"
  /\ hop = MaxHops
  /\ pc' = "stopped"
  /\ UNCHANGED <<hop, at, secure, creds, dropped>>

\* an end state: nothing else can happen, and the state stays
Done ==
  pc \in {"done", "stopped"} /\ UNCHANGED vars

Next ==
  \/ Answer
  \/ RedirectHere
  \/ RedirectElsewhere
  \/ RedirectToHttp
  \/ TooManyRedirects
  \/ Done

Spec == Init /\ [][Next]_vars

\* R1: credentials are never sent to an origin other than the first
NoCredentialsToAnotherOrigin ==
  creds => at = First

\* R2: once dropped they are never sent again, even back at the first origin
DroppedStaysDropped ==
  dropped => ~creds

\* R3: no request goes over http after an https start
NoHttpAfterHttps ==
  secure

\* R4: the chain ends within the hop budget
WithinHopBudget ==
  hop <= MaxHops

====
