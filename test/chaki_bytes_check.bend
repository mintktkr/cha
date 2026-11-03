# offline checks for lib/chaki/bytes.bend
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(T.eq("hex round trip", Bytes.to_hex(Bytes.of_hex("00 01 7f 80 FF")), "00017f80ff"))
    IO.print(T.eq("odd digit dropped", Bytes.to_hex(Bytes.of_hex("abc")), "ab"))
    IO.print(T.eq("ascii", Bytes.to_ascii(Bytes.of_ascii("GET / HTTP/1.1")), "GET / HTTP/1.1"))
    IO.print(T.eq("len", U32.show(Bytes.len(Bytes.of_hex("0102030405"))), "5"))
    IO.print(T.ok("eq", Bytes.eq(Bytes.of_hex("0102"), Bytes.of_hex("0102"))))
    IO.print(T.ok("ne by length", Bool.not(Bytes.eq(Bytes.of_hex("0102"), Bytes.of_hex("010203")))))
    IO.print(T.ok("ct_eq", Bytes.ct_eq(Bytes.of_hex("aabb"), Bytes.of_hex("aabb"))))
    IO.print(T.ok("ct_eq differs", Bool.not(Bytes.ct_eq(Bytes.of_hex("aabb"), Bytes.of_hex("aabc")))))
    IO.print(T.hex("cat", Bytes.cat(Bytes.of_hex("0102"), Bytes.of_hex("0304")), "01020304"))
    IO.print(T.hex("take", Bytes.take(Bytes.of_hex("01020304"), 2n), "0102"))
    IO.print(T.hex("take past the end", Bytes.take(Bytes.of_hex("01"), 3n), "01"))
    IO.print(T.hex("drop", Bytes.drop(Bytes.of_hex("01020304"), 3n), "04"))
    IO.print(T.hex("xor", Bytes.xor(Bytes.of_hex("ff00ff"), Bytes.of_hex("0f0f")), "f00f"))
    IO.print(T.hex("zeros", Bytes.zeros(3n), "000000"))
    IO.print(T.hex("be16", Bytes.be16(258), "0102"))
    IO.print(T.hex("be24", Bytes.be24(65536), "010000"))
    IO.print(T.hex("be32", Bytes.be32(3735928559), "deadbeef"))
    IO.print(T.eq("get.be", U32.show(Bytes.get.be(Bytes.of_hex("deadbeef"), 4n)), "3735928559"))
    IO.print(T.eq("get.be short", U32.show(Bytes.get.be(Bytes.of_hex("01"), 2n)), "256"))
    IO.print(T.ok("eq on a megabyte", Bytes.eq(Bytes.zeros(1000000n), Bytes.zeros(1000000n))))
    IO.print(T.eq("big list stays flat", U32.show(Bytes.len(Bytes.cat(Bytes.zeros(200000n), Bytes.zeros(200000n)))), "400000"))
