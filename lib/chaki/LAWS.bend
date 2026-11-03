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
