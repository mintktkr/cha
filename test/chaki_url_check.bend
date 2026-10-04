# offline checks for lib/chaki/url.bend
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/url.bend as Url
import ../lib/chaki/check.bend as T

# a URL through show, "none" when there is none
def shown(m: Maybe<&2, Url.Url>) -> String:
  match m:
    case None{}:
      "none"
    case Some{u}:
      Url.show(u)

# a URL through origin
def origined(m: Maybe<&2, Url.Url>) -> String:
  match m:
    case None{}:
      "none"
    case Some{u}:
      Url.origin(u)

# a URL through host_header
def hosted(m: Maybe<&2, Url.Url>) -> String:
  match m:
    case None{}:
      "none"
    case Some{u}:
      Url.host_header(u)

def resolved.at(base: Url.Url, ref: String) -> String:
  shown(Url.resolve(base, ref))

def resolved.step(ref: String, m: Maybe<&2, Url.Url>) -> String:
  match m:
    case None{}:
      "bad base"
    case Some{b}:
      resolved.at(b, ref)

# ref resolved against a base string, through show
def resolved(base: String, ref: String) -> String:
  resolved.step(ref, Url.parse(base))

# one of RFC 3986 §5.4's examples, its base http://a/b/c/d;p?q
def rfc(+sect: String, +ref: String, want: String) -> String:
  T.eq(sect ++ " \"" ++ ref ++ "\"", resolved("http://a/b/c/d;p?q", ref), want)

# an RFC 3986 §5.4 example that isn't an http(s) URL with an authority: refused
def rfc.none(+sect: String, +ref: String) -> String:
  T.eq(sect ++ " \"" ++ ref ++ "\" refused", resolved("http://a/b/c/d;p?q", ref), "none")

# two URLs as text share an origin
def same.origin(a: String, b: String) -> Bool:
  String.eq(origined(Url.parse(a)), origined(Url.parse(b)))

def main() -> IO(Unit):
  do IO<Unit>:
    # parse
    IO.print(T.eq("parse: an empty path", shown(Url.parse("http://example.com")), "http://example.com/"))
    IO.print(T.eq("parse: the default port is 80", origined(Url.parse("http://example.com")), "http://example.com:80"))
    IO.print(T.eq("parse: an explicit port", shown(Url.parse("http://example.com:8080/x")), "http://example.com:8080/x"))
    IO.print(T.eq("parse: uppercase scheme and host", shown(Url.parse("HTTPS://Example.COM/")), "https://example.com/"))
    IO.print(T.eq("parse: the default port is 443", origined(Url.parse("HTTPS://Example.COM/")), "https://example.com:443"))
    IO.print(T.eq("parse: an IPv6 host", shown(Url.parse("http://[::1]:8080/")), "http://[::1]:8080/"))
    IO.print(T.eq("parse: an IPv6 host folded", shown(Url.parse("http://[2001:DB8::1]/x")), "http://[2001:db8::1]/x"))
    IO.print(T.eq("parse: an IPv6 Host header", hosted(Url.parse("http://[::1]:8080/")), "[::1]:8080"))
    IO.print(T.eq("parse: no port in the Host header when it is the default", hosted(Url.parse("http://example.com:80/x")), "example.com"))
    IO.print(T.eq("parse: a port in the Host header", hosted(Url.parse("https://h:8443/x")), "h:8443"))
    IO.print(T.eq("parse: a query", shown(Url.parse("http://a/b?q=1")), "http://a/b?q=1"))
    IO.print(T.eq("parse: an empty query", shown(Url.parse("http://a/b?")), "http://a/b?"))
    IO.print(T.eq("parse: a query with no path", shown(Url.parse("http://a?q")), "http://a/?q"))
    IO.print(T.eq("parse: the fragment is dropped", shown(Url.parse("http://a/b?q=1#frag")), "http://a/b?q=1"))
    IO.print(T.eq("parse: a fragment with no path", shown(Url.parse("http://a#f")), "http://a/"))
    IO.print(T.eq("parse: another scheme", shown(Url.parse("ftp://h/")), "none"))
    IO.print(T.eq("parse: userinfo", shown(Url.parse("https://u@h/")), "none"))
    IO.print(T.eq("parse: a port past 65535", shown(Url.parse("https://h:99999/")), "none"))
    IO.print(T.eq("parse: an empty host", shown(Url.parse("https:///x")), "none"))
    IO.print(T.eq("parse: no authority", shown(Url.parse("http://")), "none"))
    IO.print(T.eq("parse: an empty string", shown(Url.parse("")), "none"))
    IO.print(T.eq("parse: no scheme", shown(Url.parse("/a/b")), "none"))
    IO.print(T.eq("parse: a space", shown(Url.parse("http://a b/")), "none"))
    # 9 is the tab character
    IO.print(T.eq("parse: a control character", shown(Url.parse("http://a/" ++ SCon{Chr{9}, SNil{}})), "none"))
    # RFC 3986 §5.4.1 normal examples. "//g" and the fragment cases print the module's
    # canonical text: "/" for an empty path, no fragment
    IO.print(rfc.none("RFC 3986 5.4.1", "g:h"))
    IO.print(rfc("RFC 3986 5.4.1", "g", "http://a/b/c/g"))
    IO.print(rfc("RFC 3986 5.4.1", "./g", "http://a/b/c/g"))
    IO.print(rfc("RFC 3986 5.4.1", "g/", "http://a/b/c/g/"))
    IO.print(rfc("RFC 3986 5.4.1", "/g", "http://a/g"))
    IO.print(rfc("RFC 3986 5.4.1", "//g", "http://g/"))
    IO.print(rfc("RFC 3986 5.4.1", "?y", "http://a/b/c/d;p?y"))
    IO.print(rfc("RFC 3986 5.4.1", "g?y", "http://a/b/c/g?y"))
    IO.print(rfc("RFC 3986 5.4.1", "#s", "http://a/b/c/d;p?q"))
    IO.print(rfc("RFC 3986 5.4.1", "g#s", "http://a/b/c/g"))
    IO.print(rfc("RFC 3986 5.4.1", "g?y#s", "http://a/b/c/g?y"))
    IO.print(rfc("RFC 3986 5.4.1", ";x", "http://a/b/c/;x"))
    IO.print(rfc("RFC 3986 5.4.1", "g;x", "http://a/b/c/g;x"))
    IO.print(rfc("RFC 3986 5.4.1", "g;x?y#s", "http://a/b/c/g;x?y"))
    IO.print(rfc("RFC 3986 5.4.1", "", "http://a/b/c/d;p?q"))
    IO.print(rfc("RFC 3986 5.4.1", ".", "http://a/b/c/"))
    IO.print(rfc("RFC 3986 5.4.1", "./", "http://a/b/c/"))
    IO.print(rfc("RFC 3986 5.4.1", "..", "http://a/b/"))
    IO.print(rfc("RFC 3986 5.4.1", "../", "http://a/b/"))
    IO.print(rfc("RFC 3986 5.4.1", "../g", "http://a/b/g"))
    IO.print(rfc("RFC 3986 5.4.1", "../..", "http://a/"))
    IO.print(rfc("RFC 3986 5.4.1", "../../", "http://a/"))
    IO.print(rfc("RFC 3986 5.4.1", "../../g", "http://a/g"))
    # RFC 3986 §5.4.2 abnormal examples
    IO.print(rfc("RFC 3986 5.4.2", "../../../g", "http://a/g"))
    IO.print(rfc("RFC 3986 5.4.2", "../../../../g", "http://a/g"))
    IO.print(rfc("RFC 3986 5.4.2", "/./g", "http://a/g"))
    IO.print(rfc("RFC 3986 5.4.2", "/../g", "http://a/g"))
    IO.print(rfc("RFC 3986 5.4.2", "g.", "http://a/b/c/g."))
    IO.print(rfc("RFC 3986 5.4.2", ".g", "http://a/b/c/.g"))
    IO.print(rfc("RFC 3986 5.4.2", "g..", "http://a/b/c/g.."))
    IO.print(rfc("RFC 3986 5.4.2", "..g", "http://a/b/c/..g"))
    IO.print(rfc("RFC 3986 5.4.2", "./../g", "http://a/b/g"))
    IO.print(rfc("RFC 3986 5.4.2", "./g/.", "http://a/b/c/g/"))
    IO.print(rfc("RFC 3986 5.4.2", "g/./h", "http://a/b/c/g/h"))
    IO.print(rfc("RFC 3986 5.4.2", "g/../h", "http://a/b/c/h"))
    IO.print(rfc("RFC 3986 5.4.2", "g;x=1/./y", "http://a/b/c/g;x=1/y"))
    IO.print(rfc("RFC 3986 5.4.2", "g;x=1/../y", "http://a/b/c/y"))
    IO.print(rfc("RFC 3986 5.4.2", "g?y/./x", "http://a/b/c/g?y/./x"))
    IO.print(rfc("RFC 3986 5.4.2", "g?y/../x", "http://a/b/c/g?y/../x"))
    IO.print(rfc("RFC 3986 5.4.2", "g#s/./x", "http://a/b/c/g"))
    IO.print(rfc("RFC 3986 5.4.2", "g#s/../x", "http://a/b/c/g"))
    # the RFC's legacy reading of "http:g" is "http://a/b/c/g"; this module refuses an
    # http URI with no authority, so neither applies
    IO.print(rfc.none("RFC 3986 5.4.2", "http:g"))
    # cha's own case: a path under an API base
    IO.print(T.eq("cha: a relative api path", resolved("https://gitea.example/api/v1/", "repos/o/n/issues?limit=50"), "https://gitea.example/api/v1/repos/o/n/issues?limit=50"))
    IO.print(T.eq("cha: an absolute URL wins", resolved("https://gitea.example/api/v1/", "https://other.example/x"), "https://other.example/x"))
    # origin
    IO.print(T.ok("origin: https://a/x and https://a:443/y", same.origin("https://a/x", "https://a:443/y")))
    IO.print(T.ok("origin: http://a/ differs", Bool.not(same.origin("https://a/x", "http://a/"))))
    # pct
    IO.print(T.eq("pct: unreserved kept", Url.pct(Bytes.of_ascii("AZaz09-._~")), "AZaz09-._~"))
    IO.print(T.eq("pct: a space", Url.pct(Bytes.of_ascii("a b")), "a%20b"))
    IO.print(T.eq("pct: a slash", Url.pct(Bytes.of_ascii("a/b")), "a%2Fb"))
    IO.print(T.eq("pct: a percent", Url.pct(Bytes.of_ascii("%2F")), "%252F"))
    IO.print(T.eq("pct: empty", Url.pct(Bytes.of_hex("")), ""))
    # "茶" is e8 8c b6 in UTF-8
    IO.print(T.eq("pct: the UTF-8 bytes of tea", Url.pct(Bytes.of_hex("e8 8c b6")), "%E8%8C%B6"))
