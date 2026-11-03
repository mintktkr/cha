# laws: what chaki promises, stated before it is proven. Each law is a claim about a pure
# module; PROOF.bend beside this file proves it. The gate is scripts/check.sh: this file's
# PROOF.bend must exit 0 with ALL PROOFS CHECK, so no law here may lean on @unsafe or foreign
# code, and `bend lib/chaki/PROOF.bend --verdict` rechecks every proof with the BendTT kernel.
# sys, ossl, tlsio and http's IO stay out: their decisions move into pure defs that are stated
# here. Law names start with their module (b64_, tls_, ...).
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

# bytes, utf8, b64 [enc]
# ----------------------

# end enc

# json [json]
# -----------

# end json

# url [url]
# ---------

# parse: an http or https URL out of text

# LAW: parsing an https URL fills in the port https answers on, 443.
law url_parse_https_port:
  {Url.parse("https://example.com/x") == Some{Url.Url{"https", "example.com", 443, "/x"}} : Maybe<&2, Url.Url>}

# LAW: parsing an http URL fills in port 80, and a URL with no path gets the root as its path.
law url_parse_http_port:
  {Url.parse("http://a") == Some{Url.Url{"http", "a", 80, "/"}} : Maybe<&2, Url.Url>}

# LAW: parsing folds a scheme and a host to lowercase, so a URL carries them in one spelling.
law url_parse_folds_case:
  {Url.parse("HTTPS://Example.COM/") == Some{Url.Url{"https", "example.com", 443, "/"}} : Maybe<&2, Url.Url>}

# LAW: case never decides what URL a text names: a scheme and a host compare lowercased.
law url_parse_case_insensitive:
  {Url.parse("HTTPS://Example.COM/x") == Url.parse("https://example.com/x") : Maybe<&2, Url.Url>}

# LAW: spelling out the port a scheme answers on gives the same URL as leaving it out.
law url_parse_default_port_equal:
  {Url.parse("https://a:443/x") == Url.parse("https://a/x") : Maybe<&2, Url.Url>}

# LAW: an explicit port is kept as it is written.
law url_parse_port:
  {Url.parse("http://a:8080/x") == Some{Url.Url{"http", "a", 8080, "/x"}} : Maybe<&2, Url.Url>}

# LAW: a port that is written but empty is the scheme's default port.
law url_parse_empty_port:
  {Url.parse("http://a:/x") == Some{Url.Url{"http", "a", 80, "/x"}} : Maybe<&2, Url.Url>}

# LAW: an IPv6 host keeps no brackets and is folded like any other host.
law url_parse_ipv6:
  {Url.parse("http://[2001:DB8::1]:8080/x") == Some{Url.Url{"http", "2001:db8::1", 8080, "/x"}} : Maybe<&2, Url.Url>}

# LAW: a query is kept and a fragment is dropped.
law url_parse_drops_fragment:
  {Url.parse("http://a/b?q=1#frag") == Some{Url.Url{"http", "a", 80, "/b?q=1"}} : Maybe<&2, Url.Url>}

# LAW: a query that is only a question mark is kept as an empty query.
law url_parse_empty_query:
  {Url.parse("http://a/b?") == Some{Url.Url{"http", "a", 80, "/b?"}} : Maybe<&2, Url.Url>}

# LAW: a query with no path before it hangs off the root.
law url_parse_query_no_path:
  {Url.parse("http://a?q") == Some{Url.Url{"http", "a", 80, "/?q"}} : Maybe<&2, Url.Url>}

# LAW: a URL carrying a name and a password is refused: userinfo is not understood.
law url_parse_userinfo_refused:
  {Url.parse("https://user:pass@h/x") == None{} : Maybe<&2, Url.Url>}

# LAW: a URL carrying only a name before the host is refused too.
law url_parse_user_only_refused:
  {Url.parse("https://u@h/") == None{} : Maybe<&2, Url.Url>}

# LAW: a scheme that is not http or https is refused.
law url_parse_scheme_refused:
  {Url.parse("ftp://h/x") == None{} : Maybe<&2, Url.Url>}

# LAW: a reference that names a scheme and nothing else is refused, since http and https need a host.
law url_parse_no_authority_refused:
  {Url.parse("javascript:alert(1)") == None{} : Maybe<&2, Url.Url>}

# LAW: a port past 65535 is refused.
law url_parse_port_refused:
  {Url.parse("https://h:99999/") == None{} : Maybe<&2, Url.Url>}

# LAW: a port that is not a number is refused.
law url_parse_bad_port_refused:
  {Url.parse("http://a:b/") == None{} : Maybe<&2, Url.Url>}

# LAW: a URL with an empty host is refused.
law url_parse_empty_host_refused:
  {Url.parse("https:///x") == None{} : Maybe<&2, Url.Url>}

# LAW: a URL with no authority at all is refused.
law url_parse_no_host_refused:
  {Url.parse("http://") == None{} : Maybe<&2, Url.Url>}

# LAW: a URL with no scheme is refused.
law url_parse_no_scheme_refused:
  {Url.parse("/a/b") == None{} : Maybe<&2, Url.Url>}

# LAW: a space refuses the whole URL, whatever the rest of the text holds.
law url_parse_space_refused:
  for +cs: List<&2, Char>
  {Url.parse("http://a/ " ++ String.from_list(cs)) == None{} : Maybe<&2, Url.Url>}

# LAW: a control character refuses the whole URL, whatever the rest of the text holds.
law url_parse_control_refused:
  for +cs: List<&2, Char>
  {Url.parse("http://a/" ++ SCon{Chr{9}, String.from_list(cs)}) == None{} : Maybe<&2, Url.Url>}

# show, the Host header, and reading a URL back from its text

# LAW: showing a URL leaves the port out when it is the one the scheme answers on.
law url_show_default_port:
  {Url.show(Url.Url{"http", "a", 80, "/x"}) == "http://a/x" : String}

# LAW: showing a URL keeps a port that is not the scheme's default.
law url_show_port:
  {Url.show(Url.Url{"https", "h", 8443, "/x"}) == "https://h:8443/x" : String}

# LAW: showing a URL puts an IPv6 host back in brackets.
law url_show_ipv6:
  {Url.show(Url.Url{"http", "::1", 8080, "/"}) == "http://[::1]:8080/" : String}

# LAW: showing a URL writes its path and query back unchanged, whatever they hold.
law url_show_target:
  for +t: String
  {Url.show(Url.Url{"http", "a", 80, t}) == "http://a" ++ t : String}

# LAW: showing a URL and parsing that text back gives the same URL.
law url_parse_show_https:
  {Url.parse(Url.show(Url.Url{"https", "example.com", 443, "/x?q=1"})) == Some{Url.Url{"https", "example.com", 443, "/x?q=1"}} : Maybe<&2, Url.Url>}

# LAW: showing a URL and parsing that text back gives the same URL when a port is written too.
law url_parse_show_port:
  {Url.parse(Url.show(Url.Url{"https", "h", 8443, "/x"})) == Some{Url.Url{"https", "h", 8443, "/x"}} : Maybe<&2, Url.Url>}

# LAW: showing a URL and parsing that text back gives the same URL for an IPv6 host.
law url_parse_show_ipv6:
  {Url.parse(Url.show(Url.Url{"http", "::1", 8080, "/x"})) == Some{Url.Url{"http", "::1", 8080, "/x"}} : Maybe<&2, Url.Url>}

# LAW: the Host header is the bare host when the port is the scheme's default.
law url_host_header_default:
  {Url.host_header(Url.Url{"https", "a", 443, "/x"}) == "a" : String}

# LAW: the Host header spells a port out when it is not the scheme's default.
law url_host_header_port:
  {Url.host_header(Url.Url{"https", "a", 8443, "/x"}) == "a:8443" : String}

# LAW: the Host header keeps an IPv6 host in brackets.
law url_host_header_ipv6:
  {Url.host_header(Url.Url{"http", "::1", 8080, "/x"}) == "[::1]:8080" : String}

# origin

# LAW: a URL's origin is its scheme, host and port, so no path or query changes it.
law url_origin_ignores_target:
  for +t: String
  {Url.origin(Url.Url{"https", "a", 443, t}) == "https://a:443" : String}

# LAW: an origin always spells its port out, the default one included.
law url_origin_default_port_spelled:
  {Url.origin(Url.Url{"http", "a", 80, "/x"}) == "http://a:80" : String}

# LAW: URLs on different ports have different origins.
law url_origin_differs_port:
  {Bool.not(String.eq(Url.origin(Url.Url{"https", "a", 443, "/"}), Url.origin(Url.Url{"https", "a", 8443, "/"}))) == True{} : Bool}

# LAW: URLs on different hosts have different origins.
law url_origin_differs_host:
  {Bool.not(String.eq(Url.origin(Url.Url{"https", "a", 443, "/"}), Url.origin(Url.Url{"https", "b", 443, "/"}))) == True{} : Bool}

# LAW: URLs on different schemes have different origins, even on one port.
law url_origin_differs_scheme:
  {Bool.not(String.eq(Url.origin(Url.Url{"https", "a", 443, "/"}), Url.origin(Url.Url{"http", "a", 443, "/"}))) == True{} : Bool}

# dots: RFC 3986 section 5.2.4

# LAW: removing dot segments never lifts a path above the root: the path always starts at the root.
law url_dots_rooted:
  for +p: String
  {String.starts_with(Url.url.dots(p), "/") == True{} : Bool}

# resolve: RFC 3986 section 5.2, and the examples of its section 5.4

# LAW: an empty reference resolves to the base URL itself.
law url_resolve_empty:
  for +u: Url.Url
  {Url.resolve(u, "") == Some{u} : Maybe<&2, Url.Url>}

# LAW: a reference that is only a fragment resolves to the base URL, with the fragment dropped.
law url_resolve_fragment:
  for +u: Url.Url
  {Url.resolve(u, "#s") == Some{u} : Maybe<&2, Url.Url>}

# LAW: a reference that is a whole URL wins over the base it was resolved against.
law url_resolve_absolute_wins:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "https://other.example/x") == Some{Url.Url{"https", "other.example", 443, "/x"}} : Maybe<&2, Url.Url>}

# LAW: a reference that names only a host and a port keeps the base's scheme.
law url_resolve_net_port:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "//g:8080/x") == Some{Url.Url{"http", "g", 8080, "/x"}} : Maybe<&2, Url.Url>}

# LAW: a reference that is a whole URL arrives with its dot segments removed, like any other reference.
law url_resolve_absolute_dots:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "http://a/b/../c") == Some{Url.Url{"http", "a", 80, "/c"}} : Maybe<&2, Url.Url>}

# LAW: a reference that names only a host arrives with its dot segments removed too.
law url_resolve_net_dots:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "//h/a/./b") == Some{Url.Url{"http", "h", 80, "/a/b"}} : Maybe<&2, Url.Url>}

# LAW: a query-only reference replaces the base's query.
law url_resolve_query_only:
  {Url.resolve(Url.Url{"https", "a", 443, "/b"}, "?q") == Some{Url.Url{"https", "a", 443, "/b?q"}} : Maybe<&2, Url.Url>}

# LAW: a path resolved against an API base lands under that base, which is what cha asks for.
law url_resolve_api_path:
  {Url.resolve(Url.Url{"https", "gitea.example", 443, "/api/v1/"}, "repos/o/n/issues?limit=50") == Some{Url.Url{"https", "gitea.example", 443, "/api/v1/repos/o/n/issues?limit=50"}} : Maybe<&2, Url.Url>}

# RFC 3986 section 5.4, against its base http://a/b/c/d;p?q. The examples are known answers:
# the module's own resolve decides each one, and its canonical text fills in port 80, keeps a
# query, and drops a fragment.

# LAW: parsing the base URL the RFC's resolution examples use gives the URL they resolve against.
law url_parse_rfc_base:
  {Url.parse("http://a/b/c/d;p?q") == Some{Url.Url{"http", "a", 80, "/b/c/d;p?q"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1: the reference "g:h" is refused, since g is not a scheme this module speaks.
law url_rfc_5_4_1_g_h:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g:h") == None{} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g" against http://a/b/c/d;p?q answers http://a/b/c/g.
law url_rfc_5_4_1_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g") == Some{Url.Url{"http", "a", 80, "/b/c/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "./g" against http://a/b/c/d;p?q answers http://a/b/c/g.
law url_rfc_5_4_1_dot_slash_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "./g") == Some{Url.Url{"http", "a", 80, "/b/c/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g/" against http://a/b/c/d;p?q answers http://a/b/c/g/.
law url_rfc_5_4_1_g_slash:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g/") == Some{Url.Url{"http", "a", 80, "/b/c/g/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "/g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_1_slash_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "/g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "//g" against http://a/b/c/d;p?q answers http://g/.
law url_rfc_5_4_1_scheme_relative_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "//g") == Some{Url.Url{"http", "g", 80, "/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "?y" against http://a/b/c/d;p?q answers http://a/b/c/d;p?y.
law url_rfc_5_4_1_query:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "?y") == Some{Url.Url{"http", "a", 80, "/b/c/d;p?y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "?y#s" against http://a/b/c/d;p?q answers http://a/b/c/d;p?y: the fragment is dropped.
law url_rfc_5_4_1_query_fragment:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "?y#s") == Some{Url.Url{"http", "a", 80, "/b/c/d;p?y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g?y" against http://a/b/c/d;p?q answers http://a/b/c/g?y.
law url_rfc_5_4_1_g_query:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g?y") == Some{Url.Url{"http", "a", 80, "/b/c/g?y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "#s" against http://a/b/c/d;p?q answers http://a/b/c/d;p?q: the fragment is dropped.
law url_rfc_5_4_1_fragment:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "#s") == Some{Url.Url{"http", "a", 80, "/b/c/d;p?q"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g#s" against http://a/b/c/d;p?q answers http://a/b/c/g: the fragment is dropped.
law url_rfc_5_4_1_g_fragment:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g#s") == Some{Url.Url{"http", "a", 80, "/b/c/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g?y#s" against http://a/b/c/d;p?q answers http://a/b/c/g?y: the fragment is dropped.
law url_rfc_5_4_1_g_query_fragment:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g?y#s") == Some{Url.Url{"http", "a", 80, "/b/c/g?y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference ";x" against http://a/b/c/d;p?q answers http://a/b/c/;x.
law url_rfc_5_4_1_semicolon_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, ";x") == Some{Url.Url{"http", "a", 80, "/b/c/;x"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g;x" against http://a/b/c/d;p?q answers http://a/b/c/g;x.
law url_rfc_5_4_1_g_semicolon_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g;x") == Some{Url.Url{"http", "a", 80, "/b/c/g;x"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g;x?y#s" against http://a/b/c/d;p?q answers http://a/b/c/g;x?y.
law url_rfc_5_4_1_g_semicolon_x_query_fragment:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g;x?y#s") == Some{Url.Url{"http", "a", 80, "/b/c/g;x?y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "" against http://a/b/c/d;p?q answers http://a/b/c/d;p?q.
law url_rfc_5_4_1_empty:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "") == Some{Url.Url{"http", "a", 80, "/b/c/d;p?q"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "." against http://a/b/c/d;p?q answers http://a/b/c/.
law url_rfc_5_4_1_dot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, ".") == Some{Url.Url{"http", "a", 80, "/b/c/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "./" against http://a/b/c/d;p?q answers http://a/b/c/.
law url_rfc_5_4_1_dot_slash:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "./") == Some{Url.Url{"http", "a", 80, "/b/c/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference ".." against http://a/b/c/d;p?q answers http://a/b/.
law url_rfc_5_4_1_dotdot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "..") == Some{Url.Url{"http", "a", 80, "/b/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "../" against http://a/b/c/d;p?q answers http://a/b/.
law url_rfc_5_4_1_dotdot_slash:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../") == Some{Url.Url{"http", "a", 80, "/b/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "../g" against http://a/b/c/d;p?q answers http://a/b/g.
law url_rfc_5_4_1_dotdot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../g") == Some{Url.Url{"http", "a", 80, "/b/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "../.." against http://a/b/c/d;p?q answers http://a/.
law url_rfc_5_4_1_dotdot_dotdot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../..") == Some{Url.Url{"http", "a", 80, "/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "../../" against http://a/b/c/d;p?q answers http://a/.
law url_rfc_5_4_1_dotdot_dotdot_slash:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../../") == Some{Url.Url{"http", "a", 80, "/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "../../g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_1_dotdot_dotdot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../../g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "../../../g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_2_dotdot_x3_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../../../g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "../../../../g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_2_dotdot_x4_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../../../../g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "/./g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_2_slash_dot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "/./g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "/../g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_2_slash_dotdot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "/../g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g." against http://a/b/c/d;p?q answers http://a/b/c/g..
law url_rfc_5_4_2_g_dot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g.") == Some{Url.Url{"http", "a", 80, "/b/c/g."}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference ".g" against http://a/b/c/d;p?q answers http://a/b/c/.g.
law url_rfc_5_4_2_dot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, ".g") == Some{Url.Url{"http", "a", 80, "/b/c/.g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g.." against http://a/b/c/d;p?q answers http://a/b/c/g...
law url_rfc_5_4_2_g_dotdot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g..") == Some{Url.Url{"http", "a", 80, "/b/c/g.."}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "..g" against http://a/b/c/d;p?q answers http://a/b/c/..g.
law url_rfc_5_4_2_dotdot_g_:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "..g") == Some{Url.Url{"http", "a", 80, "/b/c/..g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "./../g" against http://a/b/c/d;p?q answers http://a/b/g.
law url_rfc_5_4_2_dot_dotdot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "./../g") == Some{Url.Url{"http", "a", 80, "/b/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "./g/." against http://a/b/c/d;p?q answers http://a/b/c/g/.
law url_rfc_5_4_2_dot_g_dot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "./g/.") == Some{Url.Url{"http", "a", 80, "/b/c/g/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g/./h" against http://a/b/c/d;p?q answers http://a/b/c/g/h.
law url_rfc_5_4_2_g_dot_h:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g/./h") == Some{Url.Url{"http", "a", 80, "/b/c/g/h"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g/../h" against http://a/b/c/d;p?q answers http://a/b/c/h.
law url_rfc_5_4_2_g_dotdot_h:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g/../h") == Some{Url.Url{"http", "a", 80, "/b/c/h"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g;x=1/./y" against http://a/b/c/d;p?q answers http://a/b/c/g;x=1/y.
law url_rfc_5_4_2_g_semicolon_x_1_dot_y:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g;x=1/./y") == Some{Url.Url{"http", "a", 80, "/b/c/g;x=1/y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g;x=1/../y" against http://a/b/c/d;p?q answers http://a/b/c/y.
law url_rfc_5_4_2_g_semicolon_x_1_dotdot_y:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g;x=1/../y") == Some{Url.Url{"http", "a", 80, "/b/c/y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g?y/./x" against http://a/b/c/d;p?q answers http://a/b/c/g?y/./x.
law url_rfc_5_4_2_g_query_dot_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g?y/./x") == Some{Url.Url{"http", "a", 80, "/b/c/g?y/./x"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g?y/../x" against http://a/b/c/d;p?q answers http://a/b/c/g?y/../x.
law url_rfc_5_4_2_g_query_dotdot_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g?y/../x") == Some{Url.Url{"http", "a", 80, "/b/c/g?y/../x"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g#s/./x" against http://a/b/c/d;p?q answers http://a/b/c/g: the fragment is dropped.
law url_rfc_5_4_2_g_fragment_dot_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g#s/./x") == Some{Url.Url{"http", "a", 80, "/b/c/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g#s/../x" against http://a/b/c/d;p?q answers http://a/b/c/g: the fragment is dropped.
law url_rfc_5_4_2_g_fragment_dotdot_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g#s/../x") == Some{Url.Url{"http", "a", 80, "/b/c/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2: the reference "http:g" is refused, since this module will not read http without an authority.
law url_rfc_5_4_2_http_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "http:g") == None{} : Maybe<&2, Url.Url>}

# pct: percent-encoding a value for a path segment or a query

# LAW: percent-encoding keeps the unreserved characters of RFC 3986 as they are.
law url_pct_keeps_unreserved:
  {Url.pct(Bytes.of_ascii("AZaz09-._~")) == "AZaz09-._~" : String}

# LAW: percent-encoding escapes the path, query and fragment separators, so a value cannot end the path or add a segment to it.
law url_pct_separators:
  {Url.pct(Bytes.of_ascii("/?#")) == "%2F%3F%23" : String}

# LAW: percent-encoding escapes a percent sign itself, so a value cannot pass off an escape of its own.
law url_pct_percent:
  {Url.pct(Bytes.of_ascii("%2F")) == "%252F" : String}

# LAW: percent-encoding writes a space as an escape, never as itself.
law url_pct_space:
  {Url.pct(Bytes.of_ascii("a b")) == "a%20b" : String}

# LAW: percent-encoding writes every byte of text outside ASCII as escapes with uppercase hex digits.
law url_pct_utf8:
  {Url.pct(Bytes.of_hex("e8 8c b6")) == "%E8%8C%B6" : String}

# LAW: percent-encoding an empty byte list gives an empty string.
law url_pct_empty:
  {Url.pct(Bytes.of_hex("")) == "" : String}

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
