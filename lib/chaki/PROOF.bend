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

# end time

# sha2, chacha [hash]
# -------------------

# end hash

# aes, x25519 [block]
# -------------------

# end block

# big, rsa, ecdsa [pk]
# --------------------

# end pk

# asn1, x509, x509v [x509]
# ------------------------

# end x509

# tlsmsg, tls [tls]
# -----------------

# end tls

# http (its pure decisions) [http]
# --------------------------------

# end http
