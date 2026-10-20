# RFC 3986 encoding for one path segment or query value.
import Base
import ../lib/chaki/utf8.bend as Utf8
import ../lib/chaki/url.bend as U

def encode(s: String) -> String:
  U.pct(Utf8.encode(s))
def segs.encode(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      encode(x) <> segs.encode(rest)

# a segment a name may keep as it is: an empty one, a . or a .. moves the path to another
# endpoint, so those are refused
def seg.ok(+s: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(s)), Bool.and(Bool.not(String.eq(s, ".")), Bool.not(String.eq(s, ".."))))

def segs.ok(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{+x, rest}:
      Bool.and(seg.ok(x), segs.ok(rest))

# whether a name that keeps its slashes can go into a path as it is: every segment must be
# a plain one. A leading, trailing or doubled slash leaves an empty segment, and a . or ..
# segment walks out of the path, so a command refuses such a name before it sends a request.
def encode.path.ok(+s: String) -> Bool:
  segs.ok(String.split(s, '/'))

# whether a value can go into a path as exactly one segment: a slash of its own would make
# two, and seg.ok keeps out the empty, . and .. that walk out of the path
def encode.seg.ok(+s: String) -> Bool:
  Bool.and(seg.ok(s), Bool.not(String.contains(s, "/")))

# a branch or tag name as a path that keeps its slashes: gitea's branch routes and github's
# git refs read the rest of the path as the name, so memu/foo stays memu/foo while every
# other character that isn't safe in a path segment is still encoded
def encode.path(+s: String) -> String:
  String.join(segs.encode(String.split(s, '/')), "/")
