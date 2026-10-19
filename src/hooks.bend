# hooks: the pure core of `cha hooks`. A hook's config carries its secret, so every row
# is redacted here before either output reads it, and a hook id is only ever a number.
import Base
import ./ctx.bend as Ctx

# Secrets
# -------
# config.secret is a hook's signing key. GitHub masks it, Gitea can hand it back, so no
# row reaches a printer or --json until the secret fields are gone.

# a field names a secret when its last path segment is one of these, in any case:
# config.secret, config.password and metadata.token are dropped, config.url is kept
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
