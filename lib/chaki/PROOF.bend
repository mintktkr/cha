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
import ./json.bend as Json
import ./LAWS.bend as Laws

# bytes, utf8, b64 [enc]
# ----------------------

# bytes: as lists
# ---------------
# bytes.bend reverses onto an accumulator and builds cat out of rev, so its proofs need a
# plain append and its order laws.

def enc.app(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      ys
    case Con{h, t}:
      h <> enc.app(t, ys)

# app(xs, Nil) is xs

def enc.app_nil(xs: List<&2, U32>) -> {enc.app(xs, Nil{}) == xs : List<&2, U32>}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, t}:
      Equal.cong(List<&2, U32>, List<&2, U32>, x => Con{h, x}, enc.app(t, Nil{}), t, enc.app_nil(t))

# app regroups: app(app(a, b), c) is app(a, app(b, c))

def enc.app_assoc(a: List<&2, U32>, b: List<&2, U32>, c: List<&2, U32>) -> {enc.app(enc.app(a, b), c) == enc.app(a, enc.app(b, c)) : List<&2, U32>}:
  match a:
    case Nil{}:
      {==}
    case Con{+h, t}:
      Equal.cong(List<&2, U32>, List<&2, U32>, x => Con{h, x}, enc.app(enc.app(t, b), c), enc.app(t, enc.app(b, c)), enc.app_assoc(t, b, c))

# reversing onto an accumulator is appending a reversed string in front

def enc.rev_onto_app(xs: List<&2, U32>, +ys: List<&2, U32>) -> {Bytes.rev.onto(xs, ys) == enc.app(Bytes.rev(xs), ys) : List<&2, U32>}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      +s1 = Equal.sym(List<&2, U32>, Bytes.rev.onto(t, Con{h, Nil{}}), enc.app(Bytes.rev(t), Con{h, Nil{}}), enc.rev_onto_app(t, Con{h, Nil{}}))
      %s1 : {Bytes.rev.onto(t, h <> ys) == enc.app(_, ys) : List<&2, U32>}
      +s2 = Equal.sym(List<&2, U32>, enc.app(enc.app(Bytes.rev(t), Con{h, Nil{}}), ys), enc.app(Bytes.rev(t), enc.app(Con{h, Nil{}}, ys)), enc.app_assoc(Bytes.rev(t), Con{h, Nil{}}, ys))
      %s2 : {Bytes.rev.onto(t, h <> ys) == _ : List<&2, U32>}
      +s3 = Equal.sym(List<&2, U32>, Bytes.rev.onto(t, h <> ys), enc.app(Bytes.rev(t), h <> ys), enc.rev_onto_app(t, h <> ys))
      %s3 : {_ == enc.app(Bytes.rev(t), h <> ys) : List<&2, U32>}
      {==}

# reversing twice is the identity: rev(rev.onto(xs, acc)) is app(rev(acc), xs), and the
# accumulator is empty for the law itself

def enc.rev_rev_go(xs: List<&2, U32>, +acc: List<&2, U32>) -> {Bytes.rev(Bytes.rev.onto(xs, acc)) == enc.app(Bytes.rev(acc), xs) : List<&2, U32>}:
  match xs:
    case Nil{}:
      Equal.sym(List<&2, U32>, enc.app(Bytes.rev(acc), Nil{}), Bytes.rev(acc), enc.app_nil(Bytes.rev(acc)))
    case Con{+h, +t}:
      +r = Equal.sym(List<&2, U32>, Bytes.rev(Bytes.rev.onto(t, h <> acc)), enc.app(Bytes.rev(h <> acc), t), enc.rev_rev_go(t, h <> acc))
      %r : {_ == enc.app(Bytes.rev(acc), h <> t) : List<&2, U32>}
      +e = Equal.sym(List<&2, U32>, Bytes.rev.onto(acc, Con{h, Nil{}}), enc.app(Bytes.rev(acc), Con{h, Nil{}}), enc.rev_onto_app(acc, Con{h, Nil{}}))
      %e : {enc.app(_, t) == enc.app(Bytes.rev(acc), h <> t) : List<&2, U32>}
      +a = Equal.sym(List<&2, U32>, enc.app(enc.app(Bytes.rev(acc), Con{h, Nil{}}), t), enc.app(Bytes.rev(acc), enc.app(Con{h, Nil{}}, t)), enc.app_assoc(Bytes.rev(acc), Con{h, Nil{}}, t))
      %a : {_ == enc.app(Bytes.rev(acc), h <> t) : List<&2, U32>}
      {==}

def Laws.bytes_rev_rev(b):
  enc.rev_rev_go(b, Nil{})

# cat is rev.onto with a reversed head, so rev_rev_go already says what reversing it gives

def enc.rev_cat(a: List<&2, U32>, +b: List<&2, U32>) -> {Bytes.rev(Bytes.cat(a, b)) == enc.app(Bytes.rev(b), Bytes.rev(a)) : List<&2, U32>}:
  enc.rev_rev_go(Bytes.rev(a), b)

# cat of a reversed string is that string appended: the head's own reversal is undone first

def enc.app_cat_rev(+x: List<&2, U32>, +y: List<&2, U32>) -> {enc.app(Bytes.rev(x), y) == Bytes.cat(Bytes.rev(x), y) : List<&2, U32>}:
  %Equal.sym(List<&2, U32>, Bytes.rev(Bytes.rev(x)), x, Laws.bytes_rev_rev(x)) : {enc.app(Bytes.rev(x), y) == Bytes.rev.onto(_, y) : List<&2, U32>}
  Equal.sym(List<&2, U32>, Bytes.rev.onto(x, y), enc.app(Bytes.rev(x), y), enc.rev_onto_app(x, y))

def Laws.bytes_rev_cat(a, b):
  Equal.trans(List<&2, U32>, Bytes.rev(Bytes.cat(a, b)), enc.app(Bytes.rev(b), Bytes.rev(a)), Bytes.cat(Bytes.rev(b), Bytes.rev(a)), enc.rev_cat(a, b), enc.app_cat_rev(b, Bytes.rev(a)))

# counting one late is counting one early: the length of a list, added on after the count,
# is the length counted from one more

def enc.len_shift(xs: List<&2, U32>, n: U32) -> {U32.add(Bytes.len.go(xs, n), 1) == Bytes.len.go(xs, U32.add(n, 1)) : U32}:
  match xs:
    case Nil{}:
      {==}
    case Con{h, t}:
      enc.len_shift(t, U32.add(n, 1))

# reversing onto an accumulator keeps the count: the count of the reversed string starting
# at n is the count of acc starting at the count of xs

def enc.len_rev_acc(xs: List<&2, U32>, +acc: List<&2, U32>, +n: U32) -> {Bytes.len.go(Bytes.rev.onto(xs, acc), n) == Bytes.len.go(acc, Bytes.len.go(xs, n)) : U32}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      +r = Equal.sym(U32, Bytes.len.go(Bytes.rev.onto(t, h <> acc), n), Bytes.len.go(h <> acc, Bytes.len.go(t, n)), enc.len_rev_acc(t, h <> acc, n))
      %r : {_ == Bytes.len.go(acc, Bytes.len.go(t, U32.add(n, 1))) : U32}
      %enc.len_shift(t, n) : {Bytes.len.go(acc, U32.add(Bytes.len.go(t, n), 1)) == Bytes.len.go(acc, _) : U32}
      {==}

def Laws.bytes_len_rev(b):
  enc.len_rev_acc(b, Nil{}, 0)

def Laws.bytes_hex_round_trip():
  {==}

def Laws.bytes_eq_self():
  {==}

def Laws.bytes_ct_eq_agrees():
  {==}

def Laws.bytes_ct_eq_agrees_differs():
  {==}

# utf8 and b64: known answers
# ---------------------------
# Each of these laws names one closed text or byte string, so both sides reduce to the same
# term and reflexivity is the whole proof: the DFA and the decoder run at check time.

def Laws.utf8_decode_encode():
  {==}

def Laws.utf8_encode_boundaries():
  {==}

def Laws.utf8_encode_length():
  {==}

def Laws.utf8_valid_encode():
  {==}

def Laws.utf8_decode_valid():
  {==}

def Laws.utf8_reject_overlong():
  {==}

def Laws.utf8_reject_overlong_nul():
  {==}

def Laws.utf8_reject_surrogate():
  {==}

def Laws.utf8_reject_past_limit():
  {==}

def Laws.utf8_reject_truncated():
  {==}

def Laws.utf8_decode_truncated():
  {==}

def Laws.utf8_decode_nul():
  {==}

def Laws.utf8_decode_subparts():
  {==}

def Laws.b64_rfc4648_empty():
  {==}

def Laws.b64_rfc4648_f():
  {==}

def Laws.b64_rfc4648_fo():
  {==}

def Laws.b64_rfc4648_foo():
  {==}

def Laws.b64_rfc4648_foob():
  {==}

def Laws.b64_rfc4648_fooba():
  {==}

def Laws.b64_rfc4648_foobar():
  {==}

def Laws.b64_decode_one():
  {==}

def Laws.b64_decode_two():
  {==}

def Laws.b64_decode_three():
  {==}

def Laws.b64_decode_encode():
  {==}

def Laws.b64_length():
  {==}

def Laws.b64_reject_char():
  {==}

def Laws.b64_reject_non_ascii():
  {==}

def Laws.b64_reject_pad_bits():
  {==}

# a newline ends whatever line was open, and finishing a splitter whose line just ended is
# finishing it as it was, so the last line lands in the same place

def enc.lines_newline_go(s: String, +st: B64.Split) -> {B64.lines.rev(B64.split.walk(String.append(s, "\n"), st)) == B64.lines.rev(B64.split.walk(s, st)) : List<&2, String>}:
  match s:
    case SNil{}:
      match st:
        case B64.Split{cur, spare, acc}:
          {==}
    case SCon{Chr{+c}, +t}:
      enc.lines_newline_go(t, B64.split.step(st, B64.cls(c), c))

def Laws.b64_lines_newline(s):
  enc.lines_newline_go(s, B64.Split{SNil{}, SNil{}, Nil{}})

def Laws.b64_pem_block():
  {==}

def Laws.b64_pem_no_end():
  {==}

def Laws.b64_pem_two_blocks():
  {==}

def Laws.b64_pem_other_label():
  {==}

def Laws.b64_pem_empty_body():
  {==}

# base64 text with a trailing newline
# -----------------------------------
# Whitespace is skipped wherever it sits, so a newline after the last character leaves the
# decoder in the state the walk over the text alone reached. The proof is that induction,
# and the state it holds for is any state at all. b64.bend names its own types with the B64
# prefix, so the state's full name here is B64.B64.State.

def enc.newline_go(s: String, +st: B64.B64.State) -> {B64.decode.go(String.append(s, "\n"), st) == B64.decode.go(s, st) : B64.B64.State}:
  match s:
    case SNil{}:
      match st:
        case B64.B64.State{v, n, pad, out, ok}:
          {==}
    case SCon{Chr{+c}, +t}:
      enc.newline_go(t, B64.feed(st, B64.sym(c)))

def Laws.b64_decode_wrapped():
  {==}

# a skip is the identity on the state, so a newline before the text leaves the walk where it
# was and the rest of the string is read from the same state

def enc.feed_skip(st: B64.B64.State) -> {B64.feed(st, B64.B64.Skip{}) == st : B64.B64.State}:
  match st:
    case B64.B64.State{v, n, pad, out, ok}:
      {==}

def enc.newline_front(s: String, +st: B64.B64.State) -> {B64.decode.go(String.append("\n", s), st) == B64.decode.go(s, st) : B64.B64.State}:
  Equal.cong(B64.B64.State, B64.B64.State, x => B64.decode.go(s, x), B64.feed(st, B64.B64.Skip{}), st, enc.feed_skip(st))

def Laws.b64_decode_leading_newline(s):
  +r = enc.newline_front(s, B64.B64.State{0, 0n, 0n, Nil{}, True{}})
  %r : {B64.decode.end(B64.decode.go(String.append("\n", s), B64.B64.State{0, 0n, 0n, Nil{}, True{}})) == B64.decode.end(_) : Maybe<&2, List<&2, U32>>}
  {==}

def Laws.b64_decode_newline(s):
  +r = enc.newline_go(s, B64.B64.State{0, 0n, 0n, Nil{}, True{}})
  %r : {B64.decode.end(B64.decode.go(String.append(s, "\n"), B64.B64.State{0, 0n, 0n, Nil{}, True{}})) == B64.decode.end(_) : Maybe<&2, List<&2, U32>>}
  {==}

# end enc

# json [json]
# -----------
# Each json law is a worked case whose two sides are closed, so {==} settles it, bar the
# dotted-key one, which holds for the prefix it is given.

def Laws.json_encode_escapes():
  {==}

def Laws.json_encode_str_read_back():
  {==}

def Laws.json_encode_obj_read_back():
  {==}

def Laws.json_read_number_text():
  {==}

def Laws.json_read_surrogate_pair():
  {==}

def Laws.json_read_lone_surrogate():
  {==}

def Laws.json_read_unterminated_string():
  {==}

def Laws.json_read_trailing_comma():
  {==}

def Laws.json_read_trailing_comma_array():
  {==}

def Laws.json_read_raw_control():
  {==}

def Laws.json_read_leading_zero():
  {==}

def Laws.json_read_deep():
  {==}

def Laws.json_read_deep_unclosed():
  {==}

def Laws.json_rows_at():
  {==}

def Laws.json_child_under_prefix(c, t, k):
  {==}

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

# The request writer: a target, a host or a header value holding CR, LF or NUL
# ----------------------------------------------------------------------------

# the bytes half of a (bytes, bad) pair: a header value's line is built from that pair, so
# the proof has to be able to name the pair's bytes
def http1.fst(r: List<&2, U32> & Bool) -> List<&2, U32>:
  (a, b) = r
  a

# a bad flag that is already True never clears: req.bytes answers None, whatever follows
def http1.msticky(s: String, acc: List<&2, U32>) -> {Http1.req.bytes.m(Http1.req.bytes.go(s, acc, True{})) == None{} : Maybe<&2, List<&2, U32>>}:
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{+h}, t}:
      http1.msticky(t, U32.and(h, 255) <> acc)

# one control byte at the head of the string, whatever came before it and whatever follows:
# the flag it leaves is True, so the rest is never read
def http1.refuse.head(b: Bool, c: U32, q: String, acc: List<&2, U32>, e: {True{} == Http1.ctl.ch(c) : Bool}) -> {Http1.req.bytes.m(Http1.req.bytes.go(SCon{Chr{c}, q}, acc, b)) == None{} : Maybe<&2, List<&2, U32>>}:
  match b:
    case True{}:
      http1.msticky(q, U32.and(c, 255) <> acc)
    case False{}:
      %e : {Http1.req.bytes.m(Http1.req.bytes.go(q, U32.and(c, 255) <> acc, _)) == None{} : Maybe<&2, List<&2, U32>>}
      http1.msticky(q, U32.and(c, 255) <> acc)

# a control byte after p: the induction is on p, and the flag it leaves is True
def http1.refuse.at(p: String, c: U32, q: String, acc: List<&2, U32>, b: Bool, e: {True{} == Http1.ctl.ch(c) : Bool}) -> {Http1.req.bytes.m(Http1.req.bytes.go(String.append(p, SCon{Chr{c}, q}), acc, b)) == None{} : Maybe<&2, List<&2, U32>>}:
  match p:
    case SNil{}:
      http1.refuse.head(b, c, q, acc, e)
    case SCon{Chr{+h}, t}:
      http1.refuse.at(t, c, q, U32.and(h, 255) <> acc, Bool.or(b, Http1.ctl.ch(h)), e)

# a string holding a control byte is not a target, a host or a header value
def http1.refuse(p: String, c: U32, q: String, e: {True{} == Http1.ctl.ch(c) : Bool}) -> {Http1.req.bytes(String.append(p, SCon{Chr{c}, q})) == None{} : Maybe<&2, List<&2, U32>>}:
  http1.refuse.at(p, c, q, Nil{}, False{}, e)

# the target is the bind of the request's do block, so the goal is that bind with the target
# bytes as its hole
def http1.target(p: String, c: U32, q: String, e: {True{} == Http1.ctl.ch(c) : Bool}) -> {Http1.request("GET", "example.com", String.append(p, SCon{Chr{c}, q}), Nil{}, Nil{}) == None{} : Maybe<&2, List<&2, U32>>}:
  %Equal.sym(Maybe<&2, List<&2, U32>>, Http1.req.bytes.m(Http1.req.bytes.go(String.append(p, SCon{Chr{c}, q}), Nil{}, False{})), None{}, http1.refuse(p, c, q, e)) : {Maybe.bind(&2, List<&2, U32>, List<&2, U32>, _, t => Some{Http1.req.pack(Bytes.of_ascii("GET"), Bytes.of_ascii("example.com"), t, Nil{}, (Nil{}, 0n))}) == None{} : Maybe<&2, List<&2, U32>>}
  {==}

# the host is a bind of the request's do block too, and the writer's own Host line comes
# from it: refused, like the target, as soon as it holds a control byte
def http1.host(p: String, c: U32, q: String, e: {True{} == Http1.ctl.ch(c) : Bool}) -> {Http1.request("GET", String.append(p, SCon{Chr{c}, q}), "/x", Nil{}, Nil{}) == None{} : Maybe<&2, List<&2, U32>>}:
  %Equal.sym(Maybe<&2, List<&2, U32>>, Http1.req.bytes.m(Http1.req.bytes.go(String.append(p, SCon{Chr{c}, q}), Nil{}, False{})), None{}, http1.refuse(p, c, q, e)) : {Maybe.bind(&2, List<&2, U32>, List<&2, U32>, _, h => Some{Http1.req.pack(Bytes.of_ascii("GET"), h, Bytes.of_ascii("/x"), Nil{}, (Nil{}, 0n))}) == None{} : Maybe<&2, List<&2, U32>>}
  {==}

# a bad flag that is already True never clears, as the flag of the (bytes, bad) pair
def http1.pair.sticky(s: String, acc: List<&2, U32>) -> {Http1.req.bytes.go(s, acc, True{}) == (http1.fst(Http1.req.bytes.go(s, acc, True{})), True{}) : List<&2, U32> & Bool}:
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{+h}, t}:
      http1.pair.sticky(t, U32.and(h, 255) <> acc)

# the pair, for a CR at the head of a value: whatever came before it, the flag is True after
def http1.pair.cr(b: Bool, q: String, acc: List<&2, U32>) -> {Http1.req.bytes.go(SCon{Chr{13}, q}, acc, b) == (http1.fst(Http1.req.bytes.go(SCon{Chr{13}, q}, acc, b)), True{}) : List<&2, U32> & Bool}:
  match b:
    case True{}:
      http1.pair.sticky(q, 13 <> acc)
    case False{}:
      http1.pair.sticky(q, 13 <> acc)

# the same, for a LF
def http1.pair.lf(b: Bool, q: String, acc: List<&2, U32>) -> {Http1.req.bytes.go(SCon{Chr{10}, q}, acc, b) == (http1.fst(Http1.req.bytes.go(SCon{Chr{10}, q}, acc, b)), True{}) : List<&2, U32> & Bool}:
  match b:
    case True{}:
      http1.pair.sticky(q, 10 <> acc)
    case False{}:
      http1.pair.sticky(q, 10 <> acc)

# a CR after p, as the pair
def http1.pair.cr.at(p: String, q: String, acc: List<&2, U32>, b: Bool) -> {Http1.req.bytes.go(String.append(p, SCon{Chr{13}, q}), acc, b) == (http1.fst(Http1.req.bytes.go(String.append(p, SCon{Chr{13}, q}), acc, b)), True{}) : List<&2, U32> & Bool}:
  match p:
    case SNil{}:
      http1.pair.cr(b, q, acc)
    case SCon{Chr{+h}, t}:
      http1.pair.cr.at(t, q, U32.and(h, 255) <> acc, Bool.or(b, Http1.ctl.ch(h)))

# the same, for a LF
def http1.pair.lf.at(p: String, q: String, acc: List<&2, U32>, b: Bool) -> {Http1.req.bytes.go(String.append(p, SCon{Chr{10}, q}), acc, b) == (http1.fst(Http1.req.bytes.go(String.append(p, SCon{Chr{10}, q}), acc, b)), True{}) : List<&2, U32> & Bool}:
  match p:
    case SNil{}:
      http1.pair.lf(b, q, acc)
    case SCon{Chr{+h}, t}:
      http1.pair.lf.at(t, q, U32.and(h, 255) <> acc, Bool.or(b, Http1.ctl.ch(h)))

# a value holding a CR: req.field reads the pair, and the flag there is what refuses the line
def http1.value.cr(p: String, q: String) -> {Http1.request("GET", "example.com", "/x", [("x", String.append(p, SCon{Chr{13}, q}))], Nil{}) == None{} : Maybe<&2, List<&2, U32>>}:
  %Equal.sym(List<&2, U32> & Bool, Http1.req.bytes.go(String.append(p, SCon{Chr{13}, q}), Nil{}, False{}), (http1.fst(Http1.req.bytes.go(String.append(p, SCon{Chr{13}, q}), Nil{}, False{})), True{}), http1.pair.cr.at(p, q, Nil{}, False{})) : {Maybe.bind(&2, List<&2, List<&2, U32>>, List<&2, U32>, Http1.req.hdrs.end([Http1.req.sent.bytes(Http1.req.field.go(Http1.req.bytes.go(String.append(p, SCon{Chr{13}, q}), Nil{}, False{}), [120], False{}))], Http1.req.sent.bad(Http1.req.field.go(_, [120], False{}))), hs => Some{Http1.req.pack(Bytes.of_ascii("GET"), Bytes.of_ascii("example.com"), Bytes.of_ascii("/x"), hs, (Nil{}, 0n))}) == None{} : Maybe<&2, List<&2, U32>>}
  {==}

# the same, for a LF
def http1.value.lf(p: String, q: String) -> {Http1.request("GET", "example.com", "/x", [("x", String.append(p, SCon{Chr{10}, q}))], Nil{}) == None{} : Maybe<&2, List<&2, U32>>}:
  %Equal.sym(List<&2, U32> & Bool, Http1.req.bytes.go(String.append(p, SCon{Chr{10}, q}), Nil{}, False{}), (http1.fst(Http1.req.bytes.go(String.append(p, SCon{Chr{10}, q}), Nil{}, False{})), True{}), http1.pair.lf.at(p, q, Nil{}, False{})) : {Maybe.bind(&2, List<&2, List<&2, U32>>, List<&2, U32>, Http1.req.hdrs.end([Http1.req.sent.bytes(Http1.req.field.go(Http1.req.bytes.go(String.append(p, SCon{Chr{10}, q}), Nil{}, False{}), [120], False{}))], Http1.req.sent.bad(Http1.req.field.go(_, [120], False{}))), hs => Some{Http1.req.pack(Bytes.of_ascii("GET"), Bytes.of_ascii("example.com"), Bytes.of_ascii("/x"), hs, (Nil{}, 0n))}) == None{} : Maybe<&2, List<&2, U32>>}
  {==}

# A header name: an RFC 9110 token, nothing else
# ----------------------------------------------

# a flag that is already bad stays bad, from a seen name with no good byte in it
def http1.name.sticky(s: String, acc: List<&2, U32>) -> {Http1.req.name.go(s, True{}, False{}, acc) == (http1.fst(Http1.req.name.go(s, True{}, False{}, acc)), True{}) : List<&2, U32> & Bool}:
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{+h}, t}:
      http1.name.sticky(t, U32.and(h, 255) <> acc)

# a byte that is not a token character ends the name and makes it bad, whatever preceded it
# and whatever follows
def http1.name.head(seen: Bool, ok: Bool, c: U32, q: String, acc: List<&2, U32>, e: {False{} == Http1.is.tchar(c) : Bool}) -> {Http1.req.name.go(SCon{Chr{c}, q}, seen, ok, acc) == (http1.fst(Http1.req.name.go(SCon{Chr{c}, q}, seen, ok, acc)), True{}) : List<&2, U32> & Bool}:
  match seen ok:
    case True{} True{}:
      %e : {Http1.req.name.go(q, True{}, _, U32.and(c, 255) <> acc) == (http1.fst(Http1.req.name.go(q, True{}, _, U32.and(c, 255) <> acc)), True{}) : List<&2, U32> & Bool}
      http1.name.sticky(q, U32.and(c, 255) <> acc)
    case True{} False{}:
      http1.name.sticky(q, U32.and(c, 255) <> acc)
    case False{} True{}:
      %e : {Http1.req.name.go(q, True{}, _, U32.and(c, 255) <> acc) == (http1.fst(Http1.req.name.go(q, True{}, _, U32.and(c, 255) <> acc)), True{}) : List<&2, U32> & Bool}
      http1.name.sticky(q, U32.and(c, 255) <> acc)
    case False{} False{}:
      http1.name.sticky(q, U32.and(c, 255) <> acc)

# the bad byte after p: the induction is on p
def http1.name.at(p: String, c: U32, q: String, acc: List<&2, U32>, seen: Bool, ok: Bool, e: {False{} == Http1.is.tchar(c) : Bool}) -> {Http1.req.name.go(String.append(p, SCon{Chr{c}, q}), seen, ok, acc) == (http1.fst(Http1.req.name.go(String.append(p, SCon{Chr{c}, q}), seen, ok, acc)), True{}) : List<&2, U32> & Bool}:
  match p:
    case SNil{}:
      http1.name.head(seen, ok, c, q, acc, e)
    case SCon{Chr{+h}, t}:
      http1.name.at(t, c, q, U32.and(h, 255) <> acc, True{}, Bool.and(ok, Http1.is.tchar(h)), e)

# a name holding a byte outside the token set: req.field reads the pair, and the flag there
# is what refuses the line
def http1.name(p: String, c: U32, q: String, e: {False{} == Http1.is.tchar(c) : Bool}) -> {Http1.request("GET", "example.com", "/x", [(String.append(p, SCon{Chr{c}, q}), "v")], Nil{}) == None{} : Maybe<&2, List<&2, U32>>}:
  %Equal.sym(List<&2, U32> & Bool, Http1.req.name.go(String.append(p, SCon{Chr{c}, q}), False{}, True{}, Nil{}), (http1.fst(Http1.req.name.go(String.append(p, SCon{Chr{c}, q}), False{}, True{}, Nil{})), True{}), http1.name.at(p, c, q, Nil{}, False{}, True{}, e)) : {Maybe.bind(&2, List<&2, List<&2, U32>>, List<&2, U32>, Http1.req.hdrs.end([Http1.req.sent.bytes(Http1.req.field.m(Http1.req.name.go(String.append(p, SCon{Chr{c}, q}), False{}, True{}, Nil{}), "v"))], Http1.req.sent.bad(Http1.req.field.m(_, "v"))), hs => Some{Http1.req.pack(Bytes.of_ascii("GET"), Bytes.of_ascii("example.com"), Bytes.of_ascii("/x"), hs, (Nil{}, 0n))}) == None{} : Maybe<&2, List<&2, U32>>}
  {==}

# The laws
# --------

def Laws.http1_request_bytes():
  {==}

def Laws.http1_method_not_token():
  ({==}, {==})

def Laws.http1_target_ctl(p, q):
  (http1.target(p, 13, q, {==}), http1.target(p, 10, q, {==}))

def Laws.http1_host_ctl(p, q):
  (http1.host(p, 13, q, {==}), http1.host(p, 10, q, {==}))

def Laws.http1_value_ctl(p, q):
  (http1.value.cr(p, q), http1.value.lf(p, q))

def Laws.http1_name_not_token(p, q):
  (http1.name(p, 32, q, {==}), http1.name(p, 13, q, {==}))

def Laws.http1_bad_header_name():
  {==}

def Laws.http1_value_nul():
  {==}

def Laws.http1_trailing_bytes():
  {==}

def Laws.http1_status_not_http():
  ({==}, {==}, {==})

def Laws.http1_te_and_cl():
  {==}

def Laws.http1_cl_differs():
  {==}

def Laws.http1_cl_agree():
  {==}

def Laws.http1_folded_header():
  {==}

def Laws.http1_cl_not_digits():
  ({==}, {==})

def Laws.http1_chunked_body():
  {==}

def Laws.http1_chunk_not_hex():
  {==}

def Laws.http1_header_case():
  ({==}, {==})

def Laws.http1_feed_split():
  ({==}, {==}, {==})

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

def Laws.sha2_sha256_empty():
  {==}

def Laws.sha2_sha256_abc():
  {==}

# the 56-byte message pads to two blocks: pad.to, words32 and sha256.blocks all run twice
def Laws.sha2_sha256_two_block():
  {==}

# SHA-384 and SHA-512 take the 64-bit path, where W64's halves are added and rotated by hand
def Laws.sha2_sha384_abc():
  {==}

def Laws.sha2_sha512_empty():
  {==}

def Laws.sha2_sha512_abc():
  {==}

# pad.to counts the bytes it has to fill from the message length alone: 55 bytes leave room for
# the 0x80 and the 8-byte length in one 64-byte block, and one more byte does not
def Laws.sha2_pad_55_one_block():
  {==}

def Laws.sha2_pad_56_two_blocks():
  {==}

# the pads are a whole block wide, so one MAC is four compressions
def Laws.sha2_hmac_sha256_rfc4231_1():
  {==}

# expand counts its blocks from the length asked for, and zero blocks is no work at all, so the
# prk and the info are never read
def Laws.sha2_expand_zero(prk, info):
  {==}

def Laws.chacha20_block_rfc8439_2_3_2():
  {==}

def Laws.chacha_poly1305_rfc8439_2_5_2():
  {==}

def Laws.chacha_aead_open_refuses_tag_flip():
  {==}

# Bytes.len of the empty list is 0 and of fifteen zeros is 15, both below a tag, so open's guard
# answers None before the key, the nonce or the aad are touched
def Laws.chacha_aead_open_refuses_empty(key, nonce, aad):
  {==}

def Laws.chacha_aead_open_refuses_short(key, nonce, aad):
  {==}

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
# Every law here is a closed known answer, so each proof is reflexivity: the checker
# computes both sides at check time and they are the same term. Nothing is case analysed
# or inducted on, and no proof leans on a def that is not pure.

def Laws.big_of_bytes_to_bytes():
  {==}

def Laws.big_add_word_31():
  {==}

def Laws.big_sub_word_62():
  {==}

def Laws.big_mul_word_31():
  {==}

def Laws.big_mod_word_31():
  {==}

def Laws.big_sub_word_31():
  {==}

def Laws.big_sub_below_zero():
  {==}

def Laws.big_mod_by_zero():
  {==}

def Laws.big_cmp_word_31():
  {==}

def Laws.rsa_mod_bits_2048():
  {==}

def Laws.rsa_refuses_even_exponent():
  {==}

def Laws.rsa_refuses_exponent_one():
  {==}

def Laws.rsa_accepts_exponent_65537():
  {==}

def Laws.rsa_pkcs1_refuses_short_signature():
  {==}

def Laws.rsa_pkcs1_refuses_signature_at_modulus():
  {==}

def Laws.rsa_verify_accepts_exact_encoding():
  {==}

def Laws.rsa_verify_refuses_changed_encoding():
  {==}

def Laws.rsa_pkcs1_encoding_is_rfc8017():
  {==}

def Laws.rsa_mgf1_sha256():
  {==}

def Laws.rsa_pss_refuses_short_signature():
  {==}

def Laws.rsa_pss_emlen_2047():
  {==}

def Laws.ecdsa_refuses_zero_r():
  {==}

def Laws.ecdsa_refuses_value_at_order():
  {==}

def Laws.ecdsa_accepts_rfc6979_r():
  {==}

def Laws.ecdsa_refuses_coordinate_at_p():
  {==}

def Laws.ecdsa_refuses_key_missing_y():
  {==}

def Laws.ecdsa_refuses_compressed_key():
  {==}

# end pk

# asn1, x509, x509v [x509]
# ------------------------
# Each DER refusal is decided before the bytes that follow are looked at, so the claim holds
# with the tail left symbolic: reflexivity alone proves it. The positive claims reduce the
# read over a literal tag and length, a value and a tail left symbolic.

def Laws.asn1_read_high_tag(t):
  {==}

def Laws.asn1_read_indefinite(t):
  {==}

def Laws.asn1_read_long_zero(t):
  {==}

def Laws.asn1_read_long_short(t):
  {==}

def Laws.asn1_read_long_count(t):
  {==}

def Laws.asn1_read_past_end():
  {==}

def Laws.asn1_read_short_max():
  {==}

def Laws.asn1_read_exact(v, t):
  {==}

def Laws.asn1_read_zero_len(t):
  {==}

def Laws.asn1_time_pivot():
  {==}

# dNSNames
# --------
# Both claims are over closed elements, so the parse of the entries reduces to the name list.

def Laws.x509_san_lower():
  {==}

def Laws.x509_san_skips_ip():
  {==}

# Hosts
# -----
# The wildcard laws are closed pairs of names and the exact-name law is one closed name
# against a symbolic host, so each reduces to a Bool. A name comparison stays stuck until the
# host is known, so the exact-name law joins the two sides first: or with a False is the Bool
# itself.

def x509v_or_false(+b: Bool) -> {Bool.or(b, False{}) == b : Bool}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.x509v_name_wild_one_label():
  {==}

def Laws.x509v_name_wild_not_apex():
  {==}

def Laws.x509v_name_wild_not_two_labels():
  {==}

def Laws.x509v_name_wild_not_suffix():
  {==}

def Laws.x509v_name_wild_leftmost():
  {==}

def Laws.x509v_name_wild_two_labels():
  {==}

def Laws.x509v_name_wild_no_empty_label():
  {==}

def Laws.x509v_names_empty(h):
  {==}

def Laws.x509v_host_norm():
  {==}

def Laws.x509v_name_exact_only_itself(h):
  %Equal.sym(Bool, Bool.or(String.eq("cha.test", h), False{}), String.eq("cha.test", h), x509v_or_false(String.eq("cha.test", h))) : {_ == String.eq("cha.test", h) : Bool}
  {==}

# host_ok.if decides on the host's kind before it reads the certificate, so an IP literal's
# proof rewrites the hypothesis into the goal and the certificate stays symbolic.
def Laws.x509v_host_trailing_dot():
  {==}

def Laws.x509v_ip_is_address():
  {==}

def Laws.x509v_ip_never_matches(c, n, ok):
  %Equal.sym(Bool, X509v.host.ip(n), True{}, ok) : {X509v.host_ok.if(_, c, n) == False{} : Bool}
  {==}

# Time and issuers
# ----------------
# Each claim is a closed certificate and a closed instant, so the decision reduces to its
# text. The two anchor laws read the found anchor's presence, not its bytes.

def Laws.x509v_leaf_expired():
  {==}

def Laws.x509v_leaf_not_yet():
  {==}

def Laws.x509v_leaf_ok():
  {==}

def Laws.x509v_leaf_unknown_critical():
  {==}

def Laws.x509v_leaf_not_server_auth():
  {==}

def Laws.x509v_inter_not_ca():
  {==}

def Laws.x509v_inter_pathlen():
  {==}

def Laws.x509v_inter_pathlen_room():
  {==}

def Laws.x509v_inter_expired():
  {==}

def Laws.x509v_chain_anchor_trusted(a, c):
  {==}

def Laws.x509v_chain_no_anchor(c):
  {==}

def Laws.x509v_chain_too_long(c):
  {==}

# Signature algorithms
# --------------------
# The signature check compares the named algorithm with the issuer's key kind before it
# touches any key material, so a mismatch and an algorithm it doesn't know both answer False
# with the key, the signed bytes and the signature left symbolic.

def Laws.x509v_signed_rsa_under_ec():
  {==}

def Laws.x509v_signed_ec_under_rsa():
  {==}

def Laws.x509v_signed_unknown_alg():
  {==}

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

# tls_update_refused, tls_ccs_bad_refused, tls_cert_empty_refused, tls_update_fresh_seq
# The four gates read the message or the byte, and the state only to die in it.
def Laws.tls_update_refused(st, m):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

def Laws.tls_ccs_bad_refused(st):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

def Laws.tls_cert_empty_refused(st, m, certs):
  match st:
    case Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs}:
      {==}

def Laws.tls_update_fresh_seq(t, a):
  match t:
    case Tls.Traffic{+secret, +k, +iv, +n}:
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
