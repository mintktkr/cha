# url: http and https URLs, as cha needs them. parse reads one out of text, resolve
# answers a reference against a base (RFC 3986 §5.2), show, origin and host_header
# write the pieces back out, and pct percent-encodes bytes for a path segment or a
# query value. Only http and https are understood: another scheme, and an http URI
# with no authority, are refused, as are userinfo, an empty host, a port past 65535
# and any space or control character.
import Base

type Url is Data:
  Url{scheme: String, host: String, port: U32, target: String}

# a reference's path and query, the query keeping its "?"
type Query is Data:
  Query{path: String, query: String}

# Text
# ----

# A-Z and a-z
def url.alpha(+c: U32) -> Bool:
  Bool.or(Bool.and(U32.is_le(65, c), U32.is_le(c, 90)), Bool.and(U32.is_le(97, c), U32.is_le(c, 122)))

# 0-9
def url.digit(+c: U32) -> Bool:
  Bool.and(U32.is_le(48, c), U32.is_le(c, 57))

def url.lower(+c: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_le(65, c), U32.is_le(c, 90)), (c + 32 : U32), c)

def url.first(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      h

def url.last.go(xs: List<&2, String>, acc: String) -> String:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      url.last.go(t, h)

def url.last(xs: List<&2, String>) -> String:
  url.last.go(xs, "")

def url.behead(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      t

def url.rev.go(xs: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      url.rev.go(t, h <> acc)

def url.rev(xs: List<&2, String>) -> List<&2, String>:
  url.rev.go(xs, Nil{})

# xs with x at the end, as a tail call
def url.push(xs: List<&2, String>, +x: String) -> List<&2, String>:
  url.rev(x <> url.rev(xs))

def url.fold.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{c}, t}:
      url.fold.go(t, SCon{Chr{url.lower(c)}, acc})

# s in ASCII lowercase: scheme names and hosts compare case-insensitively
def url.fold(s: String) -> String:
  url.fold.go(s, SNil{})

# s starts with p, ASCII case aside
def url.prefix_ci(s: String, +p: String) -> Bool:
  String.eq(url.fold(String.take(s, String.length(p))), url.fold(p))

# an absolute URL: one of the two schemes cha speaks, with an authority
def url.abs_http(+s: String) -> Bool:
  Bool.or(url.prefix_ci(s, "http://"), url.prefix_ci(s, "https://"))

# what is before the first ":" of s holds none of "/", "?" or "#"
def url.has_scheme.head(+head: String) -> Bool:
  Bool.not(Bool.or(String.contains(head, "/"), Bool.or(String.contains(head, "?"), String.contains(head, "#"))))

def url.has_scheme.at(ps: List<&2, String>) -> Bool:
  match ps:
    case Con{head, Nil{}}:
      False{}
    case Con{+head, rest}:
      url.has_scheme.head(head)
    case Nil{}:
      False{}

# s carries a scheme of its own, ours or not: a ":" before any "/", "?" or "#"
def url.has_scheme(s: String) -> Bool:
  url.has_scheme.at(String.split(s, ':'))

# 32 is the space, 127 the delete character, and everything below 32 is a control
def url.char_plain(+n: U32) -> Bool:
  Bool.not(Bool.or(U32.is_eq(n, 32), Bool.or(U32.is_lt(n, 32), U32.is_eq(n, 127))))

def url.plain.go(s: String, ok: Bool) -> Bool:
  match s:
    case SNil{}:
      ok
    case SCon{Chr{c}, t}:
      url.plain.go(t, Bool.and(ok, url.char_plain(c)))

# no space and no control character anywhere
def url.plain(s: String) -> Bool:
  url.plain.go(s, True{})

# Cutting
# -------

# a string cut at a separator: both sides, or NoCut when the separator isn't there
type Cut is Data:
  Cut{before: String, after: String}
  NoCut{}

def url.cut.of(ps: List<&2, String>, c: Char) -> Cut:
  match ps:
    case Con{p, Nil{}}:
      NoCut{}
    case Con{p, q}:
      Cut{p, String.join(q, SCon{c, SNil{}})}
    case Nil{}:
      NoCut{}

# s cut at its first c, c itself left out
def url.cut(+s: String, +c: Char) -> Cut:
  url.cut.of(String.split(s, c), c)

def url.slash.of(ps: List<&2, String>) -> String & String:
  match ps:
    case Con{h, Nil{}}:
      (h, "")
    case Con{h, t}:
      (h, "/" ++ String.join(t, "/"))
    case Nil{}:
      ("", "")

# s cut at its first "/": what is before it, and all of it from there on
def url.slash(s: String) -> String & String:
  url.slash.of(String.split(s, '/'))

def url.split_authority.c(+h: String, +rest: String, c: Cut) -> String & String:
  match c:
    case Cut{before, after}:
      (before, "?" ++ after ++ rest)
    case NoCut{}:
      (h, rest)

def url.split_authority.q(hp: String & String) -> String & String:
  (+h, rest) = hp
  url.split_authority.c(h, rest, url.cut(h, '?'))

# the authority of a URL text after its scheme, and the path plus query that follow
# it: the authority ends at the first "/", "?" or "#", and the fragment is dropped
def url.split_authority(+f: String) -> String & String:
  url.split_authority.q(url.slash(f))

def url.target.if(q: String, slash: Bool) -> String:
  match slash:
    case True{}:
      q
    case False{}:
      SCon{Chr{47}, q}

# a path plus query, "/" for an empty path
def url.target_of(+tail: String) -> String:
  url.target.if(tail, String.starts_with(tail, "/"))

# the path of a target, up to its "?"
def url.path_of(t: String) -> String:
  url.first(String.split(t, '?'))

# a path's directory: everything through its last "/"
def url.dir(p: String) -> String:
  String.join(url.rev(url.behead(url.rev(String.split(p, '/')))), "/") ++ "/"

# what a path segment does when the dot segments come out: "." is dropped, ".." pops
# the segment before it, anything else stays
type Seg is Data:
  Drop{}
  Pop{}
  Keep{s: String}

def url.seg.dotdot(s: String, dotdot: Bool) -> Seg:
  match dotdot:
    case True{}:
      Pop{}
    case False{}:
      Keep{s}

def url.seg.dot(+s: String, dot: Bool) -> Seg:
  match dot:
    case True{}:
      Drop{}
    case False{}:
      +dotdot = String.eq(s, "..")
      url.seg.dotdot(s, dotdot)

def url.seg.one(+s: String) -> Seg:
  +dot = String.eq(s, ".")
  url.seg.dot(s, dot)

def url.segs(xs: List<&2, String>) -> List<&2, Seg>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      url.seg.one(s) <> url.segs(t)

def url.dot_seg(+s: String) -> Bool:
  Bool.or(String.eq(s, "."), String.eq(s, ".."))

def url.dots.go(segs: List<&2, Seg>, acc: List<&2, String>) -> List<&2, String>:
  match segs:
    case Nil{}:
      url.rev(acc)
    case Con{Drop{}, t}:
      url.dots.go(t, acc)
    case Con{Pop{}, t}:
      match acc:
        case Nil{}:
          url.dots.go(t, Nil{})
        case Con{h, r}:
          url.dots.go(t, r)
    case Con{Keep{s}, t}:
      url.dots.go(t, s <> acc)

def url.dots.trail(xs: List<&2, String>, dot: Bool) -> List<&2, String>:
  match dot:
    case True{}:
      url.push(xs, "")
    case False{}:
      xs

# RFC 3986 §5.2.4: a path with its "." and ".." segments removed and its trailing
# "/" kept
def url.dots(path: String) -> String:
  +segs = url.behead(String.split(path, '/'))
  "/" ++ String.join(url.dots.trail(url.dots.go(url.segs(segs), Nil{}), url.dot_seg(url.last(segs))), "/")

# Query
# -----

def url.split_query.of(ps: List<&2, String>) -> Query:
  match ps:
    case Con{p, Nil{}}:
      Query{p, ""}
    case Con{p, q}:
      Query{p, "?" ++ String.join(q, "?")}
    case Nil{}:
      Query{"", ""}

# s split at its first "?": the path, and the query with its "?"
def url.split_query(s: String) -> Query:
  url.split_query.of(String.split(s, '?'))

# Parsing
# -------

def parse.port.range(p: U32, ok: Bool) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{p}
    case False{}:
      None{}

def parse.port.num(m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{+p}:
      parse.port.range(p, U32.is_le(p, 65535))

def parse.port.if(s: String, defport: U32, empty: Bool) -> Maybe<&2, U32>:
  match empty:
    case True{}:
      Some{defport}
    case False{}:
      parse.port.num(U32.read(s))

# a port's text as a number: the default when it is empty, None past 65535
def parse.port(+s: String, defport: U32) -> Maybe<&2, U32>:
  parse.port.if(s, defport, String.is_empty(s))

def parse.def_host.if(host: String, defport: U32, empty: Bool) -> Maybe<&2, Host>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Some{Host{url.fold(host), defport}}

# a host on the default port, when the host isn't empty
def parse.def_host(+host: String, defport: U32) -> Maybe<&2, Host>:
  parse.def_host.if(host, defport, String.is_empty(host))

def parse.of_host.port(host: String, p: Maybe<&2, U32>) -> Maybe<&2, Host>:
  match p:
    case None{}:
      None{}
    case Some{port}:
      Some{Host{url.fold(host), port}}

def parse.of_host.if(host: String, p: Maybe<&2, U32>, empty: Bool) -> Maybe<&2, Host>:
  match empty:
    case True{}:
      None{}
    case False{}:
      parse.of_host.port(host, p)

# a host and a port's text, when the host isn't empty
def parse.of_host(+host: String, port: String, defport: U32) -> Maybe<&2, Host>:
  parse.of_host.if(host, parse.port(port, defport), String.is_empty(host))

def parse.authority.v6.port.c(host: String, after: String, defport: U32, colon: Bool) -> Maybe<&2, Host>:
  match colon:
    case True{}:
      parse.of_host(host, String.drop(after, 1n), defport)
    case False{}:
      None{}

def parse.authority.v6.port(host: String, after: String, defport: U32, empty: Bool, colon: Bool) -> Maybe<&2, Host>:
  match empty:
    case True{}:
      parse.def_host(host, defport)
    case False{}:
      parse.authority.v6.port.c(host, after, defport, colon)

def parse.authority.v6.tail(host: String, +after: String, defport: U32) -> Maybe<&2, Host>:
  parse.authority.v6.port(host, after, defport, String.is_empty(after), String.starts_with(after, ":"))

def parse.authority.v6.cut(inner: String, defport: U32, c: Cut) -> Maybe<&2, Host>:
  match c:
    case NoCut{}:
      None{}
    case Cut{before, after}:
      parse.authority.v6.tail(before, after, defport)

# [::1]:8080: an IPv6 literal in brackets, then nothing or ":port"
def parse.authority.v6(+inner: String, defport: U32) -> Maybe<&2, Host>:
  parse.authority.v6.cut(inner, defport, url.cut(inner, ']'))

def parse.authority.plain.cut(auth: String, defport: U32, c: Cut) -> Maybe<&2, Host>:
  match c:
    case NoCut{}:
      parse.def_host(auth, defport)
    case Cut{before, after}:
      parse.of_host(before, after, defport)

def parse.authority.br(+auth: String, defport: U32, br: Bool) -> Maybe<&2, Host>:
  match br:
    case True{}:
      parse.authority.v6(String.drop(auth, 1n), defport)
    case False{}:
      parse.authority.plain.cut(auth, defport, url.cut(auth, ':'))

def parse.authority.user(+auth: String, defport: U32, at: Bool) -> Maybe<&2, Host>:
  match at:
    case True{}:
      None{}
    case False{}:
      parse.authority.br(auth, defport, String.starts_with(auth, "["))

# the host and port of an authority: no userinfo, no empty host, no port past 65535
def parse.authority(+auth: String, defport: U32) -> Maybe<&2, Host>:
  parse.authority.user(auth, defport, String.contains(auth, "@"))

# a host and the port it answers on
type Host is Data:
  Host{host: String, port: U32}

def parse.host(scheme: String, target: String, hp: Maybe<&2, Host>) -> Maybe<&2, Url>:
  match hp:
    case None{}:
      None{}
    case Some{h}:
      Host{host, port} = h
      Some{Url{scheme, host, port, target}}

def parse.rest.q(scheme: String, defport: U32, at: String & String) -> Maybe<&2, Url>:
  (auth, tail) = at
  parse.host(scheme, url.target_of(tail), parse.authority(auth, defport))

def parse.rest(scheme: String, s: String, defport: U32) -> Maybe<&2, Url>:
  parse.rest.q(scheme, defport, url.split_authority(url.first(String.split(s, '#'))))

def parse.https(s: String, tls: Bool) -> Maybe<&2, Url>:
  match tls:
    case True{}:
      parse.rest("https", String.drop(s, 8n), 443)
    case False{}:
      None{}

def parse.http(+s: String, http: Bool) -> Maybe<&2, Url>:
  match http:
    case True{}:
      parse.rest("http", String.drop(s, 7n), 80)
    case False{}:
      parse.https(s, url.prefix_ci(s, "https://"))

def parse.plain(+s: String, ok: Bool) -> Maybe<&2, Url>:
  match ok:
    case True{}:
      parse.http(s, url.prefix_ci(s, "http://"))
    case False{}:
      None{}

# an http or https URL. None for another scheme, userinfo (user@host), an empty host,
# a port past 65535, or any space or control character
def parse(+s: String) -> Maybe<&2, Url>:
  parse.plain(s, url.plain(s))

# Resolving
# ---------

def resolve.at(scheme: String, host: String, port: U32, target: String) -> Maybe<&2, Url>:
  Some{Url{scheme, host, port, target}}

def resolve.query_url(base: Url, ref: String) -> Maybe<&2, Url>:
  match base:
    case Url{scheme, host, port, target}:
      resolve.at(scheme, host, port, url.path_of(target) ++ ref)

def resolve.merge.if(base_path: String, ref_path: String, abs: Bool) -> String:
  match abs:
    case True{}:
      ref_path
    case False{}:
      url.dir(base_path) ++ ref_path

# RFC 3986 §5.3: a reference path merged with the base's path
def resolve.merge(base_path: String, +ref_path: String) -> String:
  resolve.merge.if(base_path, ref_path, String.starts_with(ref_path, "/"))

def resolve.rel.make(scheme: String, host: String, port: U32, path: String, q: Query) -> Maybe<&2, Url>:
  match q:
    case Query{rpath, rquery}:
      resolve.at(scheme, host, port, url.dots(resolve.merge(path, rpath)) ++ rquery)

def resolve.rel.at(base: Url, q: Query) -> Maybe<&2, Url>:
  match base:
    case Url{scheme, host, port, target}:
      resolve.rel.make(scheme, host, port, url.path_of(target), q)

def resolve.rel(base: Url, ref: String) -> Maybe<&2, Url>:
  +r = url.first(String.split(ref, '#'))
  resolve.rel.at(base, url.split_query(r))

def resolve.query(base: Url, ref: String, q: Bool) -> Maybe<&2, Url>:
  match q:
    case True{}:
      resolve.query_url(base, ref)
    case False{}:
      resolve.rel(base, ref)

def resolve.path(base: Url, +ref: String, empty: Bool) -> Maybe<&2, Url>:
  match empty:
    case True{}:
      Some{base}
    case False{}:
      resolve.query(base, ref, String.starts_with(ref, "?"))

def resolve.net_url(base: Url, ref: String) -> Maybe<&2, Url>:
  match base:
    case Url{scheme, host, port, target}:
      parse(scheme ++ ":" ++ ref)

def resolve.net(+base: Url, +ref: String, net: Bool) -> Maybe<&2, Url>:
  match net:
    case True{}:
      resolve.net_url(base, ref)
    case False{}:
      resolve.path(base, ref, String.is_empty(ref))

def resolve.scheme(base: Url, +ref: String, sc: Bool) -> Maybe<&2, Url>:
  match sc:
    case True{}:
      None{}
    case False{}:
      resolve.net(base, ref, String.starts_with(ref, "//"))

def resolve.abs(base: Url, +ref: String, abs: Bool) -> Maybe<&2, Url>:
  match abs:
    case True{}:
      parse(ref)
    case False{}:
      resolve.scheme(base, ref, url.has_scheme(ref))

def resolve.hash(base: Url, +ref: String, h: Bool) -> Maybe<&2, Url>:
  match h:
    case True{}:
      Some{base}
    case False{}:
      resolve.abs(base, ref, url.abs_http(ref))

def resolve.plain(base: Url, +ref: String, ok: Bool) -> Maybe<&2, Url>:
  match ok:
    case True{}:
      resolve.hash(base, ref, String.starts_with(ref, "#"))
    case False{}:
      None{}

# RFC 3986 §5.2: ref resolved against base. ref may be absolute, scheme-relative
# ("//h/p"), an absolute path, a relative path, query-only ("?q") or empty, and its
# dot segments are removed. A reference that carries a scheme of its own and isn't an
# http(s) URL with an authority answers None.
def resolve(base: Url, +ref: String) -> Maybe<&2, Url>:
  resolve.plain(base, ref, url.plain(ref))

# Writing
# -------

# the port a scheme answers on when the URL names none
def url.default_port(scheme: String) -> U32:
  Bool.pick(U32, String.eq(scheme, "https"), 443, 80)

# a host as it appears in text: an IPv6 literal in brackets
def url.host_text(+h: String) -> String:
  Bool.pick(String, String.contains(h, ":"), "[" ++ h ++ "]", h)

def url.port_text.if(p: U32, dflt: Bool) -> String:
  match dflt:
    case True{}:
      ""
    case False{}:
      ":" ++ U32.show(p)

# ":port", and nothing for a scheme's default port
def url.port_text(+p: U32, defport: U32) -> String:
  url.port_text.if(p, U32.is_eq(p, defport))

# the URL as text, its default port left out, an IPv6 host in brackets
def show(u: Url) -> String:
  match u:
    case Url{+scheme, host, port, target}:
      scheme ++ "://" ++ url.host_text(host) ++ url.port_text(port, url.default_port(scheme)) ++ target

# "scheme://host:port", the port always shown: compare these to tell same-origin hops
def origin(u: Url) -> String:
  match u:
    case Url{scheme, host, port, target}:
      scheme ++ "://" ++ url.host_text(host) ++ ":" ++ U32.show(port)

# the Host header: the host, plus ":port" when it isn't the default
def host_header(u: Url) -> String:
  match u:
    case Url{scheme, host, port, target}:
      url.host_text(host) ++ url.port_text(port, url.default_port(scheme))

# Percent-encoding
# ----------------

# A-Z a-z 0-9 and 45 "-", 46 ".", 95 "_", 126 "~": RFC 3986's unreserved set
def pct.keep(+b: U32) -> Bool:
  Bool.or(url.alpha(b), Bool.or(url.digit(b), Bool.or(U32.is_eq(b, 45), Bool.or(U32.is_eq(b, 46), Bool.or(U32.is_eq(b, 95), U32.is_eq(b, 126))))))

def pct.hex(+n: U32) -> U32:
  Bool.pick(U32, U32.is_le(n, 9), (48 + n : U32), (55 + n : U32))

def pct.push(+b: U32, acc: String, keep: Bool) -> String:
  match keep:
    case True{}:
      SCon{Chr{b}, acc}
    case False{}:
      SCon{Chr{pct.hex(U32.and(b, 15))}, SCon{Chr{pct.hex(U32.shrn(b, 4n))}, SCon{Chr{37}, acc}}}

def pct.go(bs: List<&2, U32>, acc: String) -> String:
  match bs:
    case Nil{}:
      String.reverse(acc)
    case Con{+b, t}:
      pct.go(t, pct.push(b, acc, pct.keep(b)))

# the bytes percent-encoded, everything but A-Z a-z 0-9 - . _ ~, hex uppercase
def pct(b: List<&2, U32>) -> String:
  pct.go(b, SNil{})
