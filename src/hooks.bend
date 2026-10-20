# hooks: the pure core of `cha hooks`. A hook's config carries its secret, so every row
# is redacted here before either output reads it, and a hook id is only ever a number.
import Base
import ./ctx.bend as Ctx

# Secrets
# -------
# config.secret is a hook's signing key. GitHub masks it, Gitea can hand it back, so no
# row reaches a printer or --json until the secret fields are gone.

# a field names a secret when its last path segment is one of these, in any case:
# config.secret, config.password and metadata.token are dropped, config.url is kept but
# shown redacted (Url below): a webhook URL is often the secret itself
def word.secret(+w: String) -> Bool:
  Bool.or(String.eq(w, "secret"), Bool.or(String.eq(w, "password"), String.eq(w, "token")))

# keys are the flat paths Api.rows builds, so only the last segment names the field
def field.secret(+key: String) -> Bool:
  word.secret(String.to_lower(Ctx.last(String.split(key, '.'))))

def row.keep(+k: String, later: List<&2, String>, keep: Bool) -> List<&2, String>:
  match keep:
    case True{}:
      Con{k, later}
    case False{}:
      later

# the fields of a row that may be printed, in the order given
def row.fields(ks: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{+k, rest}:
      row.keep(k, row.fields(rest), Bool.not(field.secret(k)))

def row.drop.if(+k: String, row: Map<&2, String>, secret: Bool) -> Map<&2, String>:
  match secret:
    case True{}:
      Map.del(&2, String, row, k)
    case False{}:
      row

def row.redact.go(ks: List<&2, String>, row: Map<&2, String>) -> Map<&2, String>:
  match ks:
    case Nil{}:
      row
    case Con{+k, rest}:
      row.redact.go(rest, row.drop.if(k, row, field.secret(k)))

# a row with every secret field removed, whatever the forge named it
def row.redact(+row: Map<&2, String>) -> Map<&2, String>:
  row.redact.go(Map.keys(&2, String, row), row)

# Url
# ---
# A webhook URL is often the secret itself: a Slack or Discord URL carries its token in
# the path, and any URL can carry user:pass@ or a ?token=. So a url is shown as
# scheme://host[:port] and /… for a path, in the text line and in --json alike.

# the first segment, or "" when there is none
def first(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, rest}:
      x

# the second segment, or "" when there is none
def second(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, rest}:
      first(rest)

# every segment after the first
def later(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, rest}:
      rest

# the target without its query or fragment, which are cut before anything else is read
def target(+u: String) -> String:
  first(String.split(first(String.split(u, '?')), '#'))

# a scheme is the first segment ending in ':' with an empty second one, which is exactly
# the "://" it was split on; without one the host is the first segment
def segments(xs: List<&2, String>, scheme: Bool) -> List<&2, String>:
  match scheme:
    case True{}:
      later(later(xs))
    case False{}:
      xs

# "user:pass@host:8080" keeps "host:8080": the part before the @ is a credential
def host.of(+auth: String, userinfo: Bool) -> String:
  match userinfo:
    case True{}:
      Ctx.last(String.split(auth, '@'))
    case False{}:
      auth

# the scheme keeps its colon, so it plus "//" is the "://" that was cut away
def scheme.pre(+s: String, scheme: Bool) -> String:
  match scheme:
    case True{}:
      s ++ "//"
    case False{}:
      ""

# any non-empty segment after the host means the url has a path
# (a url that ends in / alone has none)
def path.any(xs: List<&2, String>) -> Bool:
  Bool.not(String.is_empty(String.join(xs, "")))

def path.pre(+s: String, has: Bool) -> String:
  match has:
    case True{}:
      s ++ "/…"
    case False{}:
      s

# a hook's target as anything may print it: scheme, host and port, then /… for a path
def url.redact(+u: String) -> String:
  +xs = String.split(target(u), '/')
  +head = first(xs)
  +scheme = Bool.and(String.ends_with(head, ":"), String.is_empty(second(xs)))
  +parts = segments(xs, scheme)
  +auth = first(parts)
  +host = host.of(auth, String.contains(auth, "@"))
  scheme.pre(head, scheme) ++ path.pre(host, path.any(later(parts)))

# Ids
# ---
# A hook id becomes a path segment. U32.read alone is no check: it reads ".." as Some{0},
# which would leave something other than a number in the path.

def digits(cs: List<&2, Char>) -> Bool:
  match cs:
    case Nil{}:
      True{}
    case Con{+c, rest}:
      Bool.and(Char.is_digit(c), digits(rest))

# digits and nothing else, at least one
def id.ok(+raw: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(raw)), digits(String.to_list(raw)))
