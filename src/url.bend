# RFC 3986 encoding for one path segment or query value.
import Base
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import 0xcfc8be7b076f41f95c8e118383892d55/encoding.bend as Enc

def enc.keep(+c: U32) -> Bool:
  Bool.or(Bool.and(U32.is_le(65, c), U32.is_le(c, 90)), Bool.or(Bool.and(U32.is_le(97, c), U32.is_le(c, 122)), Bool.or(Bool.and(U32.is_le(48, c), U32.is_le(c, 57)), Bool.or(U32.is_eq(c, 45), Bool.or(U32.is_eq(c, 46), Bool.or(U32.is_eq(c, 95), U32.is_eq(c, 126)))))))

def enc.hex(+n: U32) -> U32:
  Bool.pick(U32, U32.is_le(n, 9), (48 + n : U32), (55 + n : U32))

def enc.push(+c: U32, acc: String, keep: Bool) -> String:
  match keep:
    case True{}:
      SCon{Chr{c}, acc}
    case False{}:
      SCon{Chr{enc.hex(U32.mod(c, 16))}, SCon{Chr{enc.hex(U32.div(c, 16))}, SCon{Chr{37}, acc}}}

def enc.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{+c}, t}:
      enc.go(t, enc.push(c, acc, enc.keep(c)))

def encode(+s: String) -> String:
  enc.go(Bytes.to_string(Enc.utf8.encode(s)), SNil{})

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
