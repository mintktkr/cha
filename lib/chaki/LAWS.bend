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
import ./hop.bend as Hop

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
# Both modules decide every result with U32 arithmetic and comparison, and bend reduces those
# only on a constructor, so a claim over a symbolic U32 is stuck at its first division or
# comparison. Base proves commutativity of addition and nothing else about a 32-bit word. So
# the calendar and the width table are pinned by known answers: each law names its inputs, and
# each side of it is a closed term. Where the shape of a claim could hide a wrong answer, the
# law carries its neighbours too (the two ends of a range, or the whole range at once).

# LAW: showing the epoch writes the RFC 3339 text 1970-01-01T00:00:00Z.
law time_show_epoch:
  {Time.show(0) == "1970-01-01T00:00:00Z" : String}

# LAW: the day count and the civil date are inverse at the epoch: 1970-01-01 is day 0, and day
# 0 is 1970-01-01.
law time_civil_days_epoch:
  {Time.days(1970, 1, 1) == 0 : U32} & {Time.civil(0) == (1970, 1, 1) : U32 & U32 & U32}

# LAW: the two are inverse on a leap day: 2000-02-29 is day 11016, and day 11016 is 2000-02-29.
law time_civil_days_leap:
  {Time.days(2000, 2, 29) == 11016 : U32} & {Time.civil(11016) == (2000, 2, 29) : U32 & U32 & U32}

# LAW: the two are inverse on 2100-02-28, the last day of February in a century that skips its
# leap day: it is day 47540, and day 47540 is 2100-02-28.
law time_civil_days_century:
  {Time.days(2100, 2, 28) == 47540 : U32} & {Time.civil(47540) == (2100, 2, 28) : U32 & U32 & U32}

# LAW: showing a leap day, a skipped century's last February day, the second a signed 32-bit
# clock overflows at, and the last instant a U32 holds, each writes its RFC 3339 text.
law time_show_known:
  {Time.show(951782400) == "2000-02-29T00:00:00Z" : String} &
  {Time.show(4107456000) == "2100-02-28T00:00:00Z" : String} &
  {Time.show(2147483647) == "2038-01-19T03:14:07Z" : String} &
  {Time.show(4294967295) == "2106-02-07T06:28:15Z" : String}

# LAW: parsing what showing wrote gives the instant back, at the epoch, a leap day, a skipped
# century's last February day, the 2038 overflow and the last second a U32 holds.
law time_parse_show_roundtrip:
  {Time.parse(Time.show(0)) == Some{0} : Maybe<&2, U32>} &
  {Time.parse(Time.show(951782400)) == Some{951782400} : Maybe<&2, U32>} &
  {Time.parse(Time.show(4107456000)) == Some{4107456000} : Maybe<&2, U32>} &
  {Time.parse(Time.show(2147483647)) == Some{2147483647} : Maybe<&2, U32>} &
  {Time.parse(Time.show(4294967295)) == Some{4294967295} : Maybe<&2, U32>}

# LAW: a stamp that names a day or a month or an hour that doesn't exist is refused: February
# 29 in 2023, April 31, month 13 and hour 24.
law time_parse_refuses:
  {Time.parse("2023-02-29T00:00:00Z") == None{} : Maybe<&2, U32>} &
  {Time.parse("2023-04-31T00:00:00Z") == None{} : Maybe<&2, U32>} &
  {Time.parse("2023-13-01T00:00:00Z") == None{} : Maybe<&2, U32>} &
  {Time.parse("2023-01-01T24:00:00Z") == None{} : Maybe<&2, U32>}

# LAW: an offset is applied to the wall time before the instant is taken: 09:00 at -03:00 is
# 12:00 UTC, and 09:00 at +05:30 is 03:30 UTC.
law time_parse_offset:
  {Time.parse("2026-09-30T09:00:00-03:00") == Some{1790769600} : Maybe<&2, U32>} &
  {Time.parse("2026-09-30T09:00:00+05:30") == Some{1790739000} : Maybe<&2, U32>}

# LAW: February has 29 days in 2024 and 2000, and 28 in 1900 and 2100: a leap year is
# divisible by four, but not by a hundred, unless by four hundred.
law time_february_len:
  {Time.month.len(2024, 2) == 29 : U32} &
  {Time.month.len(2000, 2) == 29 : U32} &
  {Time.month.len(1900, 2) == 28 : U32} &
  {Time.month.len(2100, 2) == 28 : U32}

# LAW: every printable ASCII character is one column: the run from space to tilde is 95 columns
# wide, and the two ends of it are one column each.
law width_ascii_printable:
  {Width.text(" !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\u{5c}]^_`abc" ++
    "defghijklmnopqrstuvwxyz{|}~") == 95 : U32} &
  {Width.char(32) == 1 : U32} & {Width.char(126) == 1 : U32}

# LAW: every C0 control, every C1 control and DEL take no column.
law width_ascii_controls:
  {Width.text("\u{0}\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{9}\u{a}\u{b}\u{c}\u{d}\u{e}\u{f}" ++
    "\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{1a}\u{1b}\u{1c}\u{1d}" ++
    "\u{1e}\u{1f}\u{7f}\u{80}\u{81}\u{82}\u{83}\u{84}\u{85}\u{86}\u{87}\u{88}\u{89}\u{8a}" ++
    "\u{8b}\u{8c}\u{8d}\u{8e}\u{8f}\u{90}\u{91}\u{92}\u{93}\u{94}\u{95}\u{96}\u{97}\u{98}" ++
    "\u{99}\u{9a}\u{9b}\u{9c}\u{9d}\u{9e}\u{9f}") == 0 : U32}

# LAW: a combining mark (U+0300) takes no column, so a letter carrying its accent is one column.
law width_combining_mark:
  {Width.char(768) == 0 : U32} & {Width.text("e\u{301}") == 1 : U32}

# LAW: the East Asian wide blocks and an emoji take two columns: a Han character (U+4E00), a
# Hangul syllable (U+AC00) and an emoji (U+1F600).
law width_wide:
  {Width.char(19968) == 2 : U32} & {Width.char(44032) == 2 : U32} & {Width.char(128512) == 2 : U32}

# LAW: widths add up when text sits side by side: "cha " is 4 columns, "茶" is 2, and the
# two together are 6; the same holds for "日本" and "語".
law width_text_concat:
  {Width.text("cha 茶") == (Width.text("cha ") + Width.text("茶") : U32) : U32} &
  {Width.text("日本語") == (Width.text("日本") + Width.text("語") : U32) : U32}

# end time

# sha2, chacha [hash]
# -------------------

# end hash

# aes, x25519 [block]
# -------------------
# The block cipher, GCM around it, and the field arithmetic X25519 is built from. A law
# over every input is out of reach for a cipher, so these are the vectors of the documents
# that define the algorithms and the refusals that decide before a byte is encrypted.
# What GCM itself promises (McGrew and Viega's test cases with their tags, a sealed message
# opening back to its plaintext, a forged tag refused) is not here: every one of those needs
# GHASH, which the BendTT kernel runs out of fuel on, so they stay as lines in
# test/chaki_aes_check.bend. X25519's RFC 7748 vectors are left out for the same reason: one
# X25519 costs the checker more than a minute and its memory, so only the clamping it does
# to the scalar can be stated.

# LAW: the AES-128 key and block of FIPS-197 Appendix C.1 encrypt to the ciphertext the
# standard prints.
law aes_encrypt_fips_197_c1:
  {Aes.encrypt(Bytes.of_hex("000102030405060708090a0b0c0d0e0f"), Bytes.of_hex("00112233445566778899aabbccddeeff")) == Bytes.of_hex("69c4e0d86a7b0430d8cdb78070b4c55a") : List<&2, U32>}

# LAW: the AES-256 key and block of FIPS-197 Appendix C.3 encrypt to the ciphertext the
# standard prints.
law aes_encrypt_fips_197_c3:
  {Aes.encrypt(Bytes.of_hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"), Bytes.of_hex("00112233445566778899aabbccddeeff")) == Bytes.of_hex("8ea2b7ca516745bfeafc49904b496089") : List<&2, U32>}

# LAW: a key of a length this module does not take encrypts nothing, rather than something
# wrong.
law aes_encrypt_refuses_short_key:
  {Aes.encrypt(Bytes.of_hex("00010203"), Bytes.of_hex("00112233445566778899aabbccddeeff")) == Nil{} : List<&2, U32>}

# LAW: a message shorter than a tag opens to nothing, before any key is scheduled.
law aes_open_refuses_short_message:
  {Aes.open(Bytes.of_hex("feffe9928665731c6d6a8f9467308308"), Bytes.of_hex("cafebabefacedbaddecaf888"), Nil{}, Bytes.of_hex("00112233445566778899aabbccddee")) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: a nonce that is not 12 bytes opens to nothing, whatever the message holds.
law aes_open_refuses_short_nonce:
  {Aes.open(Bytes.of_hex("feffe9928665731c6d6a8f9467308308"), Bytes.of_hex("cafebabefacedbaddecaf88"), Nil{}, Bytes.of_hex("0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf")) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: clamping a 32-byte scalar changes only its two ends, for every value of the bytes it
# touches: the first byte loses its low three bits, the last byte loses bit 255 and gains
# bit 254, and the bytes in between pass through untouched (RFC 7748 section 5).
law x25519_clamp_bytes:
  for +b0: U32
  for +mid: U32
  for +last: U32
  {X25519.clamp(Bytes.cat(Bytes.cat([b0], Bytes.zeros(29n)), [mid, last])) == Bytes.cat(Bytes.cat([U32.and(b0, 248)], Bytes.zeros(29n)), [mid, U32.or(U32.and(last, 127), 64)]) : List<&2, U32>}

# end block

# big, rsa, ecdsa [pk]
# --------------------

# end pk

# asn1, x509, x509v [x509]
# ------------------------

# end x509

# tlsmsg, tls [tls]
# -----------------
# The TLS 1.3 client core and its wire format. The record layer's length bound and the three
# ServerHello refusals are known answers, built out of RFC 8448 3's own recording so the
# checks run on real bytes; the state machine's refusals hold over every state and message,
# because the client is one pure state machine whose failures are final.

# Reading a state, and implication
# --------------------------------

# a Boolean implication, so a law can say "whenever this, then that" without carrying a
# hypothesis: false implies anything, true implies b only if b
def tls_implies(a: Bool, b: Bool) -> Bool:
  Bool.or(Bool.not(a), b)

# whether a phase is the failed one
def tls_dead(p: Tls.Phase) -> Bool:
  match p:
    case Tls.Phase.dead{why}:
      True{}
    case _:
      False{}

# the state an answer carries: hs.input and hs.send hand back a state beside their records
# and events
def tls_state(p: Tls.Hs & List<&2, U32> & List<&2, Tls.Reply>) -> Tls.Hs:
  match p:
    case (st, rest):
      st

# the records an answer hands back
def tls_records(p: Tls.Hs & List<&2, U32>) -> List<&2, U32>:
  match p:
    case (st, out):
      out

# the events a state has gathered
def tls_events(st: Tls.Hs) -> List<&2, Tls.Reply>:
  Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
  evs

# those events with one more after them
def tls_events.plus(st: Tls.Hs, e: Tls.Reply) -> List<&2, Tls.Reply>:
  List.append(&2, Tls.Reply, tls_events(st), [e])

# a traffic key's record sequence number
def tls_traffic_n(t: Tls.Traffic) -> U32:
  Tls.Traffic{secret, k, iv, n} = t
  n

# the transcript: the raw handshake messages as they came in (RFC 8446 4.4.1)
def tls_tx(st: Tls.Hs) -> List<&2, U32>:
  Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
  tx

# the type of each handshake message at the front of a buffer, in order
def tls_tags.go(ms: List<&2, Tlsmsg.Msg>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ms:
    case Nil{}:
      List.reverse(&2, U32, acc)
    case m <> t:
      Tlsmsg.Msg{htype, body, raw} = m
      tls_tags.go(t, htype <> acc)

def tls_tags(p: List<&2, Tlsmsg.Msg> & List<&2, U32>) -> List<&2, U32>:
  match p:
    case (ms, rest):
      tls_tags.go(ms, Nil{})

# the messages glued back together, with the bytes after them
def tls_glue.raws(ms: List<&2, Tlsmsg.Msg>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ms:
    case Nil{}:
      acc
    case m <> t:
      Tlsmsg.Msg{htype, body, raw} = m
      tls_glue.raws(t, Bytes.cat(acc, raw))

def tls_glue(p: List<&2, Tlsmsg.Msg> & List<&2, U32>) -> List<&2, U32>:
  match p:
    case (ms, rest):
      Bytes.cat(tls_glue.raws(ms, Nil{}), rest)

# the same bytes with their last one gone
def tls_cut(+xs: List<&2, U32>) -> List<&2, U32>:
  Bytes.take(xs, Nat.sub(U32.to_nat(Bytes.len(xs)), 1n))

# whether a ServerHello was accepted
def tls_takes(r: Result<&1, &1, String, Tlsmsg.Hello>) -> Bool:
  match r:
    case Fail{e}:
      False{}
    case Done{v}:
      True{}

# Records
# -------

# LAW: a record header may claim the largest ciphertext RFC 8446 5.2 allows, 2^14 + 256
# bytes, and a record that long is accepted.
law tlsmsg_record_max:
  {Tlsmsg.record.hdr.ok(23, 771, 16640) == True{} : Bool}

# LAW: one ciphertext byte past that bound is refused (RFC 8446 5.2), so a record can never
# be longer than 2^14 + 256 bytes.
law tlsmsg_record_overflow:
  {Tlsmsg.record.hdr.ok(23, 771, 16641) == False{} : Bool}

# LAW: the record layer drops a record whose header claims one byte past the bound, refusing
# the whole buffer rather than reading the record (RFC 8446 5.2).
law tlsmsg_record_overflow_refused:
  {Tlsmsg.records(Bytes.of_hex("1703034101")) == None{} : Maybe<&2, Tlsmsg.Split()>}

# The RFC 8448 3 recording
# ------------------------

# the ClientHello of RFC 8448 3, handshake header and all
def tls_c8448.hello() -> List<&2, U32>:
  Bytes.of_hex("010000c00303cb34ecb1e78163ba1c38c6dacb196a6dffa21a8d9912ec18a2ef6283024dece7000006130113031302010000910000000b0009000006736572766572ff01000100000a00140012001d0017001800190100010101020103010400230000003300260024001d002099381de560e4bd43d23d8e435a7dbafeb3c06e51c13cae4d5413691e529aaf2c002b0003020304000d0020001e040305030603020308040805080604010501060102010402050206020202002d00020101001c00024001")

# the ServerHello's random (RFC 8448 3) and its key share
def tls_c8448.random() -> List<&2, U32>:
  Bytes.of_hex("a6af06a4121860dc5e6e60249cd34c95930c8ac5cb1434dac155772ed3e26928")

def tls_c8448.share() -> List<&2, U32>:
  Bytes.of_hex("c9828876112095fe66762bdbf7c672e156d6cc253b833df1dd69b1b04e751f0f")

# a ServerHello body: legacy_version, the random, an empty session id echo, the suite, null
# compression, and the key_share and supported_versions extensions (RFC 8446 4.1.3, 4.2.7)
def tls_sh(+random: List<&2, U32>, +suite: List<&2, U32>, +group: List<&2, U32>, +share: List<&2, U32>) -> List<&2, U32>:
  +keyshare = Tlsmsg.ext.pair(51, Bytes.cat(group, Bytes.cat(Bytes.be16(32), share)))
  +versions = Tlsmsg.ext.pair(43, [3, 4])
  +exts = Bytes.cat(keyshare, versions)
  Bytes.cat(Bytes.of_hex("0303"), Bytes.cat(random, Bytes.cat([0], Bytes.cat(suite, Bytes.cat([1], Bytes.cat(Bytes.be16(Bytes.len(exts)), exts))))))

# the recorded ServerHello: TLS_AES_128_GCM_SHA256 over the x25519 group
def tls_sh.recorded() -> List<&2, U32>:
  tls_sh(tls_c8448.random(), Bytes.be16(4865), Bytes.be16(29), tls_c8448.share())

# the recorded ServerHello, one cipher suite over: TLS_AES_256_GCM_SHA384 (4866), which the
# ClientHello never offers
def tls_sh.suite() -> List<&2, U32>:
  tls_sh(tls_c8448.random(), Bytes.be16(4866), Bytes.be16(29), tls_c8448.share())

# the recorded ServerHello over secp256r1 (24) instead of the only group offered
def tls_sh.group() -> List<&2, U32>:
  tls_sh(tls_c8448.random(), Bytes.be16(4865), Bytes.be16(24), tls_c8448.share())

# the recorded ServerHello with the TLS 1.2 downgrade sentinel in the last 8 bytes of its
# random (RFC 8446 4.1.3)
def tls_sh.downgrade() -> List<&2, U32>:
  +random = Bytes.cat(Bytes.of_hex("a6af06a4121860dc5e6e60249cd34c95930c8ac5cb1434dac"), Bytes.of_hex("444f574e47524401"))
  tls_sh(random, Bytes.be16(4865), Bytes.be16(29), tls_c8448.share())

# LAW: the recorded ServerHello of RFC 8448 3 is accepted: TLS_AES_128_GCM_SHA256, the one
# suite offered that it picks, over an x25519 key share.
law tlsmsg_serverhello_taken:
  {tls_takes(Tlsmsg.server_hello(tls_sh.recorded())) == True{} : Bool}

# LAW: a ServerHello that picks a cipher suite the ClientHello didn't offer is refused.
law tlsmsg_serverhello_suite:
  {tls_takes(Tlsmsg.server_hello(tls_sh.suite())) == False{} : Bool}

# LAW: a ServerHello whose key share isn't the x25519 group the ClientHello offered is
# refused.
law tlsmsg_serverhello_group:
  {tls_takes(Tlsmsg.server_hello(tls_sh.group())) == False{} : Bool}

# LAW: a ServerHello whose random carries the TLS 1.2 downgrade sentinel is refused, whatever
# else it says (RFC 8446 4.1.3).
law tlsmsg_serverhello_downgrade:
  {tls_takes(Tlsmsg.server_hello(tls_sh.downgrade())) == False{} : Bool}

# Handshake messages
# ------------------

# LAW: the recorded ClientHello of RFC 8448 3 splits into handshake messages that, glued
# back together with the bytes after them, are the recording itself, byte for byte.
law tlsmsg_clienthello_roundtrip:
  {tls_glue(Tlsmsg.messages(tls_c8448.hello())) == tls_c8448.hello() : List<&2, U32>}

# LAW: the recorded ClientHello is exactly one handshake message, a ClientHello (type 1).
law tlsmsg_clienthello_one:
  {tls_tags(Tlsmsg.messages(tls_c8448.hello())) == [1] : List<&2, U32>}

# LAW: a handshake length that runs past the bytes present is no message: the recorded
# ClientHello cut one byte short holds none.
law tlsmsg_clienthello_short:
  {tls_tags(Tlsmsg.messages(tls_cut(tls_c8448.hello()))) == Nil{} : List<&2, U32>}

# The client's state machine
# --------------------------

# LAW: application data that arrives before the handshake is done ends the connection, so no
# byte of it ever reaches the shell.
law tls_app_needs_ready:
  for +p: Tls.Phase
  for +k: Tls.Keys
  for +st: Tls.Hs
  for body: List<&2, U32>
  {tls_implies(Bool.not(Tls.ready.of(p)), tls_dead(Tls.phase.of(Tls.hs.app(p, k, st, body)))) == True{} : Bool}

# LAW: once the handshake is done, application data reaches the shell unchanged, as one more
# data event.
law tls_app_when_ready:
  for +k: Tls.Keys
  for +st: Tls.Hs
  for body: List<&2, U32>
  {tls_events(Tls.hs.app(Tls.Phase.ready{}, k, st, body)) == tls_events.plus(st, Tls.Reply.data{body}) : List<&2, Tls.Reply>}

# LAW: a server Finished whose verify_data doesn't check ends the connection.
law tls_finished_refused:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  {Tls.phase.of(Tls.hs.fin.by(False{}, st, m)) == Tls.Phase.dead{"the server's Finished doesn't check"} : Tls.Phase}

# LAW: a server Finished whose verify_data checks moves the handshake on to the shell's
# verdict, and asks for it.
law tls_finished_asks:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  {Tls.phase.of(Tls.hs.fin.by(True{}, st, m)) == Tls.Phase.asked{} : Tls.Phase}

# LAW: a certificate the shell rejects ends the connection.
law tls_trusted_refused:
  for +st: Tls.Hs
  {Tls.phase.of(tls_state(Tls.hs.trusted.at(True{}, st, False{}))) == Tls.Phase.dead{"the server's certificate was rejected"} : Tls.Phase}

# LAW: the shell's verdict before the server's flight is in is refused rather than believed.
law tls_trusted_early:
  for +st: Tls.Hs
  for ok: Bool
  {Tls.phase.of(tls_state(Tls.hs.trusted.at(False{}, st, ok))) == Tls.Phase.dead{"hs.trusted before the server's flight is in"} : Tls.Phase}

# a ServerHello that is really a HelloRetryRequest: SHA-256("HelloRetryRequest") as its
# random, and a key_share that names x25519 with no key in it (RFC 8446 4.1.3, 4.1.4)
def tls_hrr() -> Tlsmsg.Msg:
  +keyshare = Tlsmsg.ext.pair(51, Bytes.be16(29))
  +versions = Tlsmsg.ext.pair(43, [3, 4])
  +exts = Bytes.cat(keyshare, versions)
  +body = Bytes.cat(Bytes.of_hex("0303"), Bytes.cat(Tlsmsg.hrr.random(), Bytes.cat([0], Bytes.cat(Bytes.be16(4865), Bytes.cat([1], Bytes.cat(Bytes.be16(Bytes.len(exts)), exts))))))
  Tlsmsg.Msg{2, body, Tlsmsg.handshake(2, body)}

# LAW: a HelloRetryRequest that comes off the wire is refused, so a second one can never be
# answered either: x25519 is the only group the ClientHello offers.
law tls_retry_refused:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  for suite: U32
  for share: List<&2, U32>
  {Tls.phase.of(Tls.hs.server.retry(True{}, suite, share, st, m)) == Tls.Phase.dead{"the server sent a HelloRetryRequest, and x25519 is all we offer"} : Tls.Phase}

# LAW: the HelloRetryRequest of RFC 8446 4.1.3, read through the wire format, ends the
# connection the same way.
law tls_retry_wire_refused:
  for +st: Tls.Hs
  {Tls.phase.of(Tls.hs.server(st, tls_hrr())) == Tls.Phase.dead{"the server sent a HelloRetryRequest, and x25519 is all we offer"} : Tls.Phase}

# LAW: an encrypted record that doesn't authenticate ends the connection, so a modified
# record never reaches the handshake or the shell.
law tls_record_refused:
  for +st: Tls.Hs
  for k: Tls.Keys
  {Tls.phase.of(Tls.hs.opened.at(None{}, k, st)) == Tls.Phase.dead{"a record that didn't authenticate"} : Tls.Phase}

# LAW: a legacy ChangeCipherSpec is only ignored during the handshake: after it, one ends the
# connection (RFC 8446 D.4).
law tls_ccs_after_ready:
  for +st: Tls.Hs
  for one: Bool
  {Tls.phase.of(Tls.hs.ccs.at(False{}, one, st)) == Tls.Phase.dead{"a legacy ChangeCipherSpec after the handshake"} : Tls.Phase}

# LAW: every record's sequence number is one more than the record before it, so a record's
# nonce is never used twice.
law tls_traffic_next:
  for +t: Tls.Traffic
  {tls_traffic_n(Tls.traffic.next(t)) == (tls_traffic_n(t) + 1 : U32) : U32}

# LAW: nothing is sent before the handshake is done: application data waits in the shell.
law tls_send_needs_ready:
  for +st: Tls.Hs
  for +data: List<&2, U32>
  {tls_records(Tls.hs.send.at(False{}, st, data)) == Nil{} : List<&2, U32>}

# LAW: no close_notify is sent before the handshake is done.
law tls_close_needs_ready:
  for +st: Tls.Hs
  {Tls.hs.close.at(False{}, st) == Nil{} : List<&2, U32>}

# LAW: moving the handshake on appends the message's raw bytes to the transcript, which is
# what the CertificateVerify and the Finished are checked against.
law tls_transcript_grows:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  for +p: Tls.Phase
  {tls_tx(Tls.hs.next(st, m, p)) == Bytes.cat(tls_tx(st), Tls.msg.raw(m)) : List<&2, U32>}

# LAW: a KeyUpdate that isn't exactly one byte of 0 or 1 ends the connection (RFC 8446 4.6.3).
law tls_update_refused:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  {Tls.phase.of(Tls.hs.update.ok(False{}, st, m)) == Tls.Phase.dead{"a KeyUpdate that isn't one byte of 0 or 1"} : Tls.Phase}

# LAW: a legacy ChangeCipherSpec that isn't exactly one byte of 0x01 ends the connection,
# even in the one window where a ChangeCipherSpec may be ignored (RFC 8446 D.4).
law tls_ccs_bad_refused:
  for +st: Tls.Hs
  {Tls.phase.of(Tls.hs.ccs.at(True{}, False{}, st)) == Tls.Phase.dead{"a legacy ChangeCipherSpec that isn't one byte of 0x01"} : Tls.Phase}

# LAW: a Certificate message with no certificate in it ends the connection, so the shell is
# never asked to verify an empty chain (RFC 8446 4.4.2).
law tls_cert_empty_refused:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  for certs: List<&2, List<&2, U32>>
  {Tls.phase.of(Tls.hs.cert.by(True{}, certs, st, m)) == Tls.Phase.dead{"the server sent no certificate"} : Tls.Phase}

# LAW: a KeyUpdate starts its new traffic keys at sequence number zero, so the counter only
# ever restarts beside a key it has never sealed with (RFC 8446 4.6.3, 7.2).
law tls_update_fresh_seq:
  for +t: Tls.Traffic
  for a: Tls.Aead
  {tls_traffic_n(Tls.traffic.up(t, a)) == 0 : U32}

# LAW: failure is final: once a connection has failed, every further byte from the server
# leaves it failed, so one bad message cannot be walked back.
law tls_dead_absorbs:
  for +st: Tls.Hs
  for +why: String
  for +bytes: List<&2, U32>
  {tls_dead(Tls.phase.of(tls_state(Tls.hs.input(Tls.hs.die(st, why), bytes)))) == True{} : Bool}

# end tls

# hop (http's pure decisions) [http]
# --------------------------------

# LAW: a hop to another origin carries no credentials: a request that sends AUTHORIZATION and
# Cookie reaches it as the same request without them.
law hop_cross_origin_drops_credentials:
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.Hop{"GET", "http://a.example/x", ("AUTHORIZATION", "t") <> ("Cookie", "c") <> hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307) == Hop.judge.go(Hop.Hop{"GET", "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307) : Hop.Hop}

# LAW: a hop within one origin sends the same request again at the new url: a 307 keeps the
# method, every header and the body.
law hop_same_origin_keeps_request:
  for +m: String
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.Hop{m, "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "a.example", 80, "/y"}, 307) == Hop.Hop{m, "http://a.example/y", hs, b} : Hop.Hop}

# LAW: a 308, like a 307, sends the same request again.
law hop_308_keeps_request:
  for +m: String
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.Hop{m, "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "a.example", 80, "/y"}, 308) == Hop.Hop{m, "http://a.example/y", hs, b} : Hop.Hop}

# LAW: only 307 and 308 send the method and the body again; 301, 302 and 303 don't.
law hop_keeps_status:
  {[Hop.redirect.keeps(301), Hop.redirect.keeps(302), Hop.redirect.keeps(303), Hop.redirect.keeps(307), Hop.redirect.keeps(308)] == [False{}, False{}, False{}, True{}, True{}] : List<Bool>}

# LAW: a redirect from https to http is refused, whatever the request and the status.
law hop_downgrade_refused:
  for h: Hop.Hop
  for status: U32
  {Hop.judge.next(h, Url.Url{"https", "a.example", 443, "/x"}, status, Some{Url.Url{"http", "a.example", 80, "/y"}}) == Hop.Refuse{"refused a redirect from https to http"} : Hop.Next}

# LAW: a 303 sends a POST again as a GET with no body, and the headers that framed the body
# go with it.
law hop_see_other_get:
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.Hop{"POST", "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "a.example", 80, "/y"}, 303) == Hop.Hop{"GET", "http://a.example/y", Hop.drop(["content-type", "content-length"], hs), Nil{}} : Hop.Hop}

# LAW: a 303 leaves a HEAD a HEAD: it has no body to give up.
law hop_see_other_head:
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.Hop{"HEAD", "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "a.example", 80, "/y"}, 303) == Hop.Hop{"HEAD", "http://a.example/y", Hop.drop(["content-type", "content-length"], hs), Nil{}} : Hop.Hop}

# LAW: a status that isn't a redirect sends nothing further: the response is the answer.
law hop_no_redirect_no_hop:
  for h: Hop.Hop
  {Hop.judge.resp(h, Url.Url{"http", "a.example", 80, "/x"}, 200, "http://a.example/y", Hop.judge.follows(200, "http://a.example/y")) == Hop.Answer{h} : Hop.Next}

# LAW: a redirect that names no Location sends nothing further either.
law hop_empty_location_no_hop:
  for h: Hop.Hop
  {Hop.judge.resp(h, Url.Url{"http", "a.example", 80, "/x"}, 302, "", Hop.judge.follows(302, "")) == Hop.Answer{h} : Hop.Next}

# LAW: a redirect to a Location that isn't an http(s) url is refused.
law hop_bad_location_refused:
  for h: Hop.Hop
  for status: U32
  {Hop.judge.next(h, Url.Url{"http", "a.example", 80, "/x"}, status, Url.resolve(Url.Url{"http", "a.example", 80, "/x"}, "ftp://a.example/y")) == Hop.Refuse{"a redirect to a location that isn't a url"} : Hop.Next}

# LAW: drop takes out exactly the headers it names, whatever their case, and keeps the rest in
# the order they came: two names, spelled in another case, gone from three headers.
law hop_drop_named:
  for v: String
  {Hop.drop(["authorization", "cookie"], [("Authorization", v), ("x-other", "1"), ("COOKIE", "c")]) == [("x-other", "1")] : List<&2, Http1.Field()>}

# LAW: credentials dropped at one hop stay dropped: after a.example -> b.example -> a.example,
# the request carries none, even back at the origin that was sent them.
law hop_credentials_stay_dropped:
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.judge.go(Hop.judge.go(Hop.Hop{"GET", "http://a.example/x", ("authorization", "t") <> hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307), Url.Url{"http", "b.example", 80, "/y"}, Url.Url{"http", "a.example", 80, "/x"}, 307), Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307) == Hop.judge.go(Hop.judge.go(Hop.judge.go(Hop.Hop{"GET", "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307), Url.Url{"http", "b.example", 80, "/y"}, Url.Url{"http", "a.example", 80, "/x"}, 307), Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307) : Hop.Hop}

# end http
