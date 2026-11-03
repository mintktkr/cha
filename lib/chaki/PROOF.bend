# proof: every claim in LAWS.bend beside it. `bend lib/chaki/PROOF.bend` prints ALL PROOFS CHECK
# once each holds.
import Base
import ./bytes.bend as Bytes
import ./utf8.bend as Utf8
import ./b64.bend as B64
import ./time.bend as Time
import ./width.bend as Width
import ./url.bend as Url
import ./http1.bend as Http1
import ./sha2.bend as Sha2
import ./chacha.bend as Chacha
import ./aes.bend as Aes
import ./x25519.bend as X25519
import ./big.bend as Big
import ./rsa.bend as Rsa
import ./ecdsa.bend as Ecdsa
import ./asn1.bend as Asn1
import ./x509.bend as X509
import ./x509v.bend as X509v
import ./tlsmsg.bend as Tlsmsg
import ./tls.bend as Tls
import ./hop.bend as Hop
import ./LAWS.bend as Laws

# bytes, utf8, b64 [enc]
# ----------------------

# end enc

# json [json]
# -----------

# end json

# url [url]
# ---------

# Most of these laws name one closed input, so {==} proves them: the checker evaluates both sides
# to the same term. The two that quantify over the text after a space or a control character need
# the lemma below, since the plain check carries its answer along the whole text.

# a space or a control character drives the plain check's accumulator to False, and it stays there
# however the text goes on
def url.plain_off(s: String) -> {False{} == Url.url.plain.go(s, False{}) : Bool}:
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{c}, t}:
      url.plain_off(t)

def Laws.url_parse_https_port():
  {==}

def Laws.url_parse_http_port():
  {==}

def Laws.url_parse_folds_case():
  {==}

def Laws.url_parse_case_insensitive():
  {==}

def Laws.url_parse_default_port_equal():
  {==}

def Laws.url_parse_port():
  {==}

def Laws.url_parse_empty_port():
  {==}

def Laws.url_parse_ipv6():
  {==}

def Laws.url_parse_drops_fragment():
  {==}

def Laws.url_parse_empty_query():
  {==}

def Laws.url_parse_query_no_path():
  {==}

def Laws.url_parse_userinfo_refused():
  {==}

def Laws.url_parse_user_only_refused():
  {==}

def Laws.url_parse_scheme_refused():
  {==}

def Laws.url_parse_no_authority_refused():
  {==}

def Laws.url_parse_port_refused():
  {==}

def Laws.url_parse_bad_port_refused():
  {==}

def Laws.url_parse_empty_host_refused():
  {==}

def Laws.url_parse_no_host_refused():
  {==}

def Laws.url_parse_no_scheme_refused():
  {==}

# the goal only meets the lemma once the text is peeled as far as the stuck accumulator, so the
# rewrite names the peeled text: this is the "http://a/ " prefix, then the first character, then
# the rest as the list unfolds
def Laws.url_parse_space_refused(cs):
  match cs:
    case Nil{}:
      {==}
    case Con{Chr{c}, t}:
      %url.plain_off(String.from_list(t)) : {Url.parse.plain(SCon{'h', SCon{'t', SCon{'t', SCon{'p', SCon{':', SCon{'/', SCon{'/', SCon{'a', SCon{'/', SCon{' ', SCon{Chr{c}, String.from_list(t)}}}}}}}}}}}, _) == None{} : Maybe<&2, Url.Url>}
      {==}

# as above, with the control character's own character in place of the space
def Laws.url_parse_control_refused(cs):
  match cs:
    case Nil{}:
      {==}
    case Con{Chr{c}, t}:
      %url.plain_off(String.from_list(t)) : {Url.parse.plain(SCon{'h', SCon{'t', SCon{'t', SCon{'p', SCon{':', SCon{'/', SCon{'/', SCon{'a', SCon{'/', SCon{Chr{9}, SCon{Chr{c}, String.from_list(t)}}}}}}}}}}}, _) == None{} : Maybe<&2, Url.Url>}
      {==}

def Laws.url_show_default_port():
  {==}

def Laws.url_show_port():
  {==}

def Laws.url_show_ipv6():
  {==}

def Laws.url_parse_show_https():
  {==}

def Laws.url_parse_show_port():
  {==}

def Laws.url_parse_show_ipv6():
  {==}

def Laws.url_host_header_default():
  {==}

def Laws.url_host_header_port():
  {==}

def Laws.url_host_header_ipv6():
  {==}

def Laws.url_origin_default_port_spelled():
  {==}

def Laws.url_origin_differs_port():
  {==}

def Laws.url_origin_differs_host():
  {==}

def Laws.url_origin_differs_scheme():
  {==}

def Laws.url_resolve_absolute_wins():
  {==}

def Laws.url_resolve_net_port():
  {==}

def Laws.url_resolve_absolute_dots():
  {==}

def Laws.url_resolve_net_dots():
  {==}

def Laws.url_resolve_query_only():
  {==}

def Laws.url_resolve_api_path():
  {==}

def Laws.url_show_target(t):
  {==}

def Laws.url_origin_ignores_target(t):
  {==}

def Laws.url_dots_rooted(p):
  {==}

def Laws.url_resolve_empty(u):
  match u:
    case Url.Url{+scheme, +host, +port, +target}:
      {==}

def Laws.url_resolve_fragment(u):
  match u:
    case Url.Url{+scheme, +host, +port, +target}:
      {==}

def Laws.url_parse_rfc_base():
  {==}

def Laws.url_rfc_5_4_1_g_h():
  {==}

def Laws.url_rfc_5_4_1_g():
  {==}

def Laws.url_rfc_5_4_1_dot_slash_g():
  {==}

def Laws.url_rfc_5_4_1_g_slash():
  {==}

def Laws.url_rfc_5_4_1_slash_g():
  {==}

def Laws.url_rfc_5_4_1_scheme_relative_g():
  {==}

def Laws.url_rfc_5_4_1_query():
  {==}

def Laws.url_rfc_5_4_1_query_fragment():
  {==}

def Laws.url_rfc_5_4_1_g_query():
  {==}

def Laws.url_rfc_5_4_1_fragment():
  {==}

def Laws.url_rfc_5_4_1_g_fragment():
  {==}

def Laws.url_rfc_5_4_1_g_query_fragment():
  {==}

def Laws.url_rfc_5_4_1_semicolon_x():
  {==}

def Laws.url_rfc_5_4_1_g_semicolon_x():
  {==}

def Laws.url_rfc_5_4_1_g_semicolon_x_query_fragment():
  {==}

def Laws.url_rfc_5_4_1_empty():
  {==}

def Laws.url_rfc_5_4_1_dot():
  {==}

def Laws.url_rfc_5_4_1_dot_slash():
  {==}

def Laws.url_rfc_5_4_1_dotdot():
  {==}

def Laws.url_rfc_5_4_1_dotdot_slash():
  {==}

def Laws.url_rfc_5_4_1_dotdot_g():
  {==}

def Laws.url_rfc_5_4_1_dotdot_dotdot():
  {==}

def Laws.url_rfc_5_4_1_dotdot_dotdot_slash():
  {==}

def Laws.url_rfc_5_4_1_dotdot_dotdot_g():
  {==}

def Laws.url_rfc_5_4_2_dotdot_x3_g():
  {==}

def Laws.url_rfc_5_4_2_dotdot_x4_g():
  {==}

def Laws.url_rfc_5_4_2_slash_dot_g():
  {==}

def Laws.url_rfc_5_4_2_slash_dotdot_g():
  {==}

def Laws.url_rfc_5_4_2_g_dot():
  {==}

def Laws.url_rfc_5_4_2_dot_g():
  {==}

def Laws.url_rfc_5_4_2_g_dotdot():
  {==}

def Laws.url_rfc_5_4_2_dotdot_g_():
  {==}

def Laws.url_rfc_5_4_2_dot_dotdot_g():
  {==}

def Laws.url_rfc_5_4_2_dot_g_dot():
  {==}

def Laws.url_rfc_5_4_2_g_dot_h():
  {==}

def Laws.url_rfc_5_4_2_g_dotdot_h():
  {==}

def Laws.url_rfc_5_4_2_g_semicolon_x_1_dot_y():
  {==}

def Laws.url_rfc_5_4_2_g_semicolon_x_1_dotdot_y():
  {==}

def Laws.url_rfc_5_4_2_g_query_dot_x():
  {==}

def Laws.url_rfc_5_4_2_g_query_dotdot_x():
  {==}

def Laws.url_rfc_5_4_2_g_fragment_dot_x():
  {==}

def Laws.url_rfc_5_4_2_g_fragment_dotdot_x():
  {==}

def Laws.url_rfc_5_4_2_http_g():
  {==}

def Laws.url_pct_keeps_unreserved():
  {==}

def Laws.url_pct_separators():
  {==}

def Laws.url_pct_percent():
  {==}

def Laws.url_pct_space():
  {==}

def Laws.url_pct_utf8():
  {==}

def Laws.url_pct_empty():
  {==}

# end url

# http1 [http1]
# -------------

# end http1

# time, width [time]
# ------------------
# Every claim names a closed input, so both sides of it reduce to the same term and
# reflexivity is the whole proof; a law that is a conjunction proves as a tuple of those.
# There is nothing to induct on: the calendar and the width table reach their answers through
# U32 division, multiplication and comparison, and those are opaque on anything but a
# constructor.

def Laws.time_show_epoch():
  {==}

def Laws.time_civil_days_epoch():
  ({==}, {==})

def Laws.time_civil_days_leap():
  ({==}, {==})

def Laws.time_civil_days_century():
  ({==}, {==})

def Laws.time_show_known():
  ({==}, {==}, {==}, {==})

def Laws.time_parse_show_roundtrip():
  ({==}, {==}, {==}, {==}, {==})

def Laws.time_parse_refuses():
  ({==}, {==}, {==}, {==})

def Laws.time_parse_offset():
  ({==}, {==})

def Laws.time_february_len():
  ({==}, {==}, {==}, {==})

def Laws.width_ascii_printable():
  ({==}, {==}, {==})

def Laws.width_ascii_controls():
  {==}

def Laws.width_combining_mark():
  ({==}, {==})

def Laws.width_wide():
  ({==}, {==}, {==})

def Laws.width_text_concat():
  ({==}, {==})

# end time

# sha2, chacha [hash]
# -------------------

# end hash

# aes, x25519 [block]
# -------------------
# Each claim is closed on both sides or reduces to the same term with the law's variables
# left in place, so reflexivity is the whole proof and the checker computes the vectors.

def Laws.aes_encrypt_fips_197_c1():
  {==}

def Laws.aes_encrypt_fips_197_c3():
  {==}

def Laws.aes_encrypt_refuses_short_key():
  {==}

def Laws.aes_open_refuses_short_message():
  {==}

def Laws.aes_open_refuses_short_nonce():
  {==}

# clamp only reads the ends of the scalar and masks them, so both sides reduce to the same
# list with the bytes the law names still standing as themselves

def Laws.x25519_clamp_bytes(b0, mid, last):
  {==}

# end block

# big, rsa, ecdsa [pk]
# --------------------

# end pk

# asn1, x509, x509v [x509]
# ------------------------

# end x509

# tlsmsg, tls [tls]
# -----------------
# Everything here is closed or decided by the shape of the state, so reflexivity does the
# work: the checker runs the parse and the gate itself when it checks the law. The state
# machine's laws are about a field of the state, so their proofs take the state apart with a
# match and the goal then reduces on its own.

# tlsmsg_record_max, tlsmsg_record_overflow, tlsmsg_record_overflow_refused
# The length bound of RFC 8446 5.2, at the bound and one byte past it.
def Laws.tlsmsg_record_max():
  {==}

def Laws.tlsmsg_record_overflow():
  {==}

def Laws.tlsmsg_record_overflow_refused():
  {==}

# tlsmsg_serverhello_taken, tlsmsg_serverhello_suite, tlsmsg_serverhello_group,
# tlsmsg_serverhello_downgrade
# The recorded ServerHello of RFC 8448 3, then the same body with its cipher suite, its group
# and its random changed.
def Laws.tlsmsg_serverhello_taken():
  {==}

def Laws.tlsmsg_serverhello_suite():
  {==}

def Laws.tlsmsg_serverhello_group():
  {==}

def Laws.tlsmsg_serverhello_downgrade():
  {==}

# tlsmsg_clienthello_roundtrip, tlsmsg_clienthello_one, tlsmsg_clienthello_short
# Splitting the recorded ClientHello, glueing it back, and the same recording cut short.
def Laws.tlsmsg_clienthello_roundtrip():
  {==}

def Laws.tlsmsg_clienthello_one():
  {==}

def Laws.tlsmsg_clienthello_short():
  {==}

# tls_app_needs_ready
# hs.app dies with keys(st, k) in hand, so the state is taken apart first: the phase field
# of a state built by hs.die is the dead one whatever the state was.
def tls_app_die(st: Tls.Hs, k: Tls.Keys) ->
  {Tls.Phase.dead{"application data before the handshake ended"} == Tls.phase.of(Tls.hs.die(Tls.hs.keys(st, k), "application data before the handshake ended")) : Tls.Phase}:
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

# The phase is the scrutinee: hs.app reads nothing else, so its cases are the whole law.
def Laws.tls_app_needs_ready(p, k, st, body):
  match p:
    case Tls.Phase.hello{}:
      %tls_app_die(st, k) : {Laws.tls_dead(_) == True{} : Bool}
      {==}
    case Tls.Phase.ee{}:
      %tls_app_die(st, k) : {Laws.tls_dead(_) == True{} : Bool}
      {==}
    case Tls.Phase.cert{}:
      %tls_app_die(st, k) : {Laws.tls_dead(_) == True{} : Bool}
      {==}
    case Tls.Phase.verify{}:
      %tls_app_die(st, k) : {Laws.tls_dead(_) == True{} : Bool}
      {==}
    case Tls.Phase.fin{}:
      %tls_app_die(st, k) : {Laws.tls_dead(_) == True{} : Bool}
      {==}
    case Tls.Phase.asked{}:
      %tls_app_die(st, k) : {Laws.tls_dead(_) == True{} : Bool}
      {==}
    case Tls.Phase.closed{}:
      %tls_app_die(st, k) : {Laws.tls_dead(_) == True{} : Bool}
      {==}
    case Tls.Phase.dead{why}:
      %tls_app_die(st, k) : {Laws.tls_dead(_) == True{} : Bool}
      {==}
    case Tls.Phase.ready{}:
      {==}

# tls_app_when_ready
# The events are a field of the state, so the state is taken apart to read them.
def Laws.tls_app_when_ready(k, st, body):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

# tls_finished_refused, tls_finished_asks
def Laws.tls_finished_refused(st, m):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

def Laws.tls_finished_asks(st, m):
  match st:
    case Tls.Hs{phase, tx, Tls.Keys{+aead, +master, +rd, +wr, +ard, +awr}, priv, Tls.Proof{+certs, +scheme, +signed, +sig}, buf, msgs, out, evs}:
      {==}

# tls_trusted_refused, tls_trusted_early
def Laws.tls_trusted_refused(st):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

def Laws.tls_trusted_early(st, ok):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

# tls_retry_refused, tls_retry_wire_refused, tls_record_refused, tls_ccs_after_ready
# The HelloRetryRequest's random is the one RFC 8446 4.1.3 names, so the parser recognizes it
# and the retry check refuses it.
def Laws.tls_retry_refused(st, m, suite, share):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

def Laws.tls_retry_wire_refused(st):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

def Laws.tls_record_refused(st, k):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

def Laws.tls_ccs_after_ready(st, one):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

# tls_traffic_next
# One traffic key: the sequence number is its own plus one.
def Laws.tls_traffic_next(t):
  match t:
    case Tls.Traffic{+secret, +k, +iv, +n}:
      {==}

# tls_send_needs_ready, tls_close_needs_ready
def Laws.tls_send_needs_ready(st, data):
  {==}

def Laws.tls_close_needs_ready(st):
  {==}

# tls_transcript_grows
# The transcript is a field of the state, so the state is taken apart to read it.
def Laws.tls_transcript_grows(st, m, p):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

# tls_dead_absorbs
# The walk is a loop over the buffer with the buffer's length as fuel, and a failed connection
# refuses every record it reads: the state it hands on is the same state with the record's
# bytes parked, still failed. The lemma carries the fields one by one, because the walk hands
# each step a state built from them.
def tls_dead_walk(fuel: Nat, +why: String, +tx: List<&2, U32>, +keys: Tls.Keys, +priv: List<&2, U32>, +proof: Tls.Proof, +bufs: List<&2, U32>, +msgs: List<&2, U32>, +out: List<&2, U32>, +evs: List<&2, Tls.Reply>, +buf: List<&2, U32>, h: Tls.Head) ->
  {Laws.tls_dead(Tls.phase.of(Tls.hs.walk(fuel, Tls.Hs{Tls.Phase.dead{why}, tx, keys, priv, proof, bufs, msgs, out, evs}, buf, h))) == True{} : Bool}:
  match fuel h:
    case 0n head:
      {==}
    case 1n+p Tls.Head.short{}:
      {==}
    case 1n+p Tls.Head.bad{}:
      {==}
    case 1n+p Tls.Head.one{r, +raw, +rest}:
      tls_dead_walk(p, why, tx, keys, priv, proof, Bytes.cat(bufs, raw), msgs, out, evs, rest, Tls.head.of(rest))

# The phase of the state an answer carries is the phase of the state it answers: both are
# read off the same field. The state is taken apart to read it.
def tls_answer_phase(st: Tls.Hs) ->
  {Tls.phase.of(st) == Tls.phase.of(Laws.tls_state(Tls.hs.answer(st))) : Tls.Phase}:
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

# A state that has died is a state whose phase is the dead one, and hs.input empties its
# buffer and walks the bytes it was handed: the lemma covers that walk.
def Laws.tls_dead_absorbs(st, why, bytes):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      +w = Tls.hs.walk(U32.to_nat(Bytes.len(Bytes.cat(buf, bytes))), Tls.Hs{Tls.Phase.dead{why}, tx, keys, priv, proof, Nil{}, msgs, out, List.append(&2, Tls.Reply, evs, [Tls.Reply.failed{why}])}, Bytes.cat(buf, bytes), Tls.head.of(Bytes.cat(buf, bytes)))
      %tls_answer_phase(w) : {Laws.tls_dead(_) == True{} : Bool}
      tls_dead_walk(U32.to_nat(Bytes.len(Bytes.cat(buf, bytes))), why, tx, keys, priv, proof, Nil{}, msgs, out, List.append(&2, Tls.Reply, evs, [Tls.Reply.failed{why}]), Bytes.cat(buf, bytes), Tls.head.of(Bytes.cat(buf, bytes)))

# end tls

# hop (http's pure decisions) [http]
# --------------------------------

def Laws.hop_cross_origin_drops_credentials(hs, b):
  {==}

def Laws.hop_same_origin_keeps_request(m, hs, b):
  {==}

def Laws.hop_308_keeps_request(m, hs, b):
  {==}

def Laws.hop_keeps_status():
  {==}

def Laws.hop_downgrade_refused(h, status):
  {==}

def Laws.hop_see_other_get(hs, b):
  {==}

def Laws.hop_see_other_head(hs, b):
  {==}

def Laws.hop_no_redirect_no_hop(h):
  {==}

def Laws.hop_empty_location_no_hop(h):
  {==}

def Laws.hop_bad_location_refused(h, status):
  {==}

def Laws.hop_drop_named(v):
  {==}

def Laws.hop_credentials_stay_dropped(hs, b):
  {==}

# end http
