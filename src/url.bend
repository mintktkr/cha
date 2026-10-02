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

