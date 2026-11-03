# offline checks for lib/chaki/utf8.bend
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/utf8.bend as Utf8
import ../lib/chaki/check.bend as T

# unit repeated n times, in order
def repeat(+unit: List<&2, U32>, n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      Bytes.rev(acc)
    case 1n+p:
      repeat(unit, p, Bytes.rev.onto(unit, acc))

# the bytes of a String that isn't ASCII are built from Char codes, so the source stays ASCII
def main() -> IO(Unit):
  do IO<Unit>:
    # RFC 3629: encoding, one Char at a time, over every length boundary
    IO.print(T.hex("RFC 3629 encode ascii", Utf8.encode("hello"), "68 65 6c 6c 6f"))
    IO.print(T.hex("RFC 3629 encode U+007F", Utf8.encode(SCon{Chr{127}, SNil{}}), "7f"))
    IO.print(T.hex("RFC 3629 encode U+0080", Utf8.encode(SCon{Chr{128}, SNil{}}), "c2 80"))
    IO.print(T.hex("RFC 3629 encode U+07FF", Utf8.encode(SCon{Chr{2047}, SNil{}}), "df bf"))
    IO.print(T.hex("RFC 3629 encode U+0800", Utf8.encode(SCon{Chr{2048}, SNil{}}), "e0 a0 80"))
    IO.print(T.hex("RFC 3629 encode U+FFFF", Utf8.encode(SCon{Chr{65535}, SNil{}}), "ef bf bf"))
    IO.print(T.hex("RFC 3629 encode U+10000", Utf8.encode(SCon{Chr{65536}, SNil{}}), "f0 90 80 80"))
    IO.print(T.hex("RFC 3629 encode U+10FFFF", Utf8.encode(SCon{Chr{1114111}, SNil{}}), "f4 8f bf bf"))
    IO.print(T.hex("RFC 3629 encode e-acute", Utf8.encode(SCon{Chr{233}, SNil{}}), "c3 a9"))
    IO.print(T.hex("RFC 3629 encode tea", Utf8.encode(SCon{Chr{33590}, SNil{}}), "e8 8c b6"))
    IO.print(T.hex("RFC 3629 encode grinning face", Utf8.encode(SCon{Chr{128512}, SNil{}}), "f0 9f 98 80"))
    IO.print(T.hex("encode empty", Utf8.encode(""), ""))

    # decoding well-formed bytes, back to the same text
    IO.print(T.eq("RFC 3629 decode ascii", Utf8.decode(Bytes.of_hex("68 65 6c 6c 6f")), "hello"))
    IO.print(T.eq("RFC 3629 decode e-acute", Utf8.decode(Bytes.of_hex("c3 a9")), SCon{Chr{233}, SNil{}}))
    IO.print(T.eq("RFC 3629 decode tea", Utf8.decode(Bytes.of_hex("e8 8c b6")), SCon{Chr{33590}, SNil{}}))
    IO.print(T.eq("RFC 3629 decode grinning face", Utf8.decode(Bytes.of_hex("f0 9f 98 80")), SCon{Chr{128512}, SNil{}}))
    IO.print(T.eq("decode empty", Utf8.decode(Nil{}), ""))
    IO.print(T.hex("round trip mixed", Utf8.encode(Utf8.decode(Bytes.of_hex("41 c3 a9 e8 8c b6 f0 9f 98 80 42"))), "41 c3 a9 e8 8c b6 f0 9f 98 80 42"))

    # Unicode 3.9 Table 3-8: U+FFFD substitution of maximal subparts
    IO.print(T.hex("Unicode 3.9 Table 3-8", Utf8.encode(Utf8.decode(Bytes.of_hex("61 F1 80 80 E1 80 C2 62 80 63 80 BF 64"))), "61 ef bf bd ef bf bd ef bf bd 62 ef bf bd 63 ef bf bd ef bf bd 64"))
    IO.print(T.hex("Unicode 3.9 overlong C0 AF", Utf8.encode(Utf8.decode(Bytes.of_hex("c0 af"))), "ef bf bd ef bf bd"))
    IO.print(T.hex("Unicode 3.9 overlong C1 80", Utf8.encode(Utf8.decode(Bytes.of_hex("c1 80"))), "ef bf bd ef bf bd"))
    IO.print(T.hex("Unicode 3.9 overlong E0 80 AF", Utf8.encode(Utf8.decode(Bytes.of_hex("e0 80 af"))), "ef bf bd ef bf bd ef bf bd"))
    IO.print(T.hex("Unicode 3.9 overlong F0 80 80 AF", Utf8.encode(Utf8.decode(Bytes.of_hex("f0 80 80 af"))), "ef bf bd ef bf bd ef bf bd ef bf bd"))
    IO.print(T.hex("Unicode 3.9 surrogate ED A0 80", Utf8.encode(Utf8.decode(Bytes.of_hex("ed a0 80"))), "ef bf bd ef bf bd ef bf bd"))
    IO.print(T.hex("Unicode 3.9 past U+10FFFF F4 90 80 80", Utf8.encode(Utf8.decode(Bytes.of_hex("f4 90 80 80"))), "ef bf bd ef bf bd ef bf bd ef bf bd"))
    IO.print(T.hex("Unicode 3.9 F5 80 80 80", Utf8.encode(Utf8.decode(Bytes.of_hex("f5 80 80 80"))), "ef bf bd ef bf bd ef bf bd ef bf bd"))
    IO.print(T.hex("Unicode 3.9 stray FE", Utf8.encode(Utf8.decode(Bytes.of_hex("fe"))), "ef bf bd"))
    IO.print(T.hex("Unicode 3.9 stray FF", Utf8.encode(Utf8.decode(Bytes.of_hex("ff"))), "ef bf bd"))
    IO.print(T.hex("Unicode 3.9 stray continuation", Utf8.encode(Utf8.decode(Bytes.of_hex("80"))), "ef bf bd"))
    IO.print(T.hex("Unicode 3.9 two stray continuations", Utf8.encode(Utf8.decode(Bytes.of_hex("80 bf"))), "ef bf bd ef bf bd"))
    IO.print(T.hex("Unicode 3.9 truncated C2", Utf8.encode(Utf8.decode(Bytes.of_hex("c2"))), "ef bf bd"))
    IO.print(T.hex("Unicode 3.9 truncated E1 80", Utf8.encode(Utf8.decode(Bytes.of_hex("e1 80"))), "ef bf bd"))
    IO.print(T.hex("Unicode 3.9 truncated E0 A0", Utf8.encode(Utf8.decode(Bytes.of_hex("e0 a0"))), "ef bf bd"))
    IO.print(T.hex("Unicode 3.9 truncated F1 80 80", Utf8.encode(Utf8.decode(Bytes.of_hex("f1 80 80"))), "ef bf bd"))
    IO.print(T.hex("Unicode 3.9 E0 then 41", Utf8.encode(Utf8.decode(Bytes.of_hex("e0 41"))), "ef bf bd 41"))
    IO.print(T.hex("Unicode 3.9 E0 80 then 41", Utf8.encode(Utf8.decode(Bytes.of_hex("e0 80 41"))), "ef bf bd ef bf bd 41"))
    IO.print(T.hex("decode a real U+FFFD", Utf8.encode(Utf8.decode(Bytes.of_hex("ef bf bd"))), "ef bf bd"))

    # valid: the same bytes, judged rather than repaired
    IO.print(T.ok("valid ascii", Utf8.valid(Bytes.of_hex("68 65 6c 6c 6f"))))
    IO.print(T.ok("valid e-acute", Utf8.valid(Bytes.of_hex("c3 a9"))))
    IO.print(T.ok("valid tea", Utf8.valid(Bytes.of_hex("e8 8c b6"))))
    IO.print(T.ok("valid grinning face", Utf8.valid(Bytes.of_hex("f0 9f 98 80"))))
    IO.print(T.ok("valid boundaries", Utf8.valid(Bytes.of_hex("00 7f c2 80 df bf e0 a0 80 ef bf bf f0 90 80 80 f4 8f bf bf"))))
    IO.print(T.ok("valid empty", Utf8.valid(Nil{})))
    IO.print(T.ok("valid a real U+FFFD", Utf8.valid(Bytes.of_hex("ef bf bd"))))
    IO.print(T.ok("invalid overlong C0 AF", Bool.not(Utf8.valid(Bytes.of_hex("c0 af")))))
    IO.print(T.ok("invalid overlong C1 80", Bool.not(Utf8.valid(Bytes.of_hex("c1 80")))))
    IO.print(T.ok("invalid overlong E0 80 AF", Bool.not(Utf8.valid(Bytes.of_hex("e0 80 af")))))
    IO.print(T.ok("invalid overlong F0 80 80 AF", Bool.not(Utf8.valid(Bytes.of_hex("f0 80 80 af")))))
    IO.print(T.ok("invalid surrogate ED A0 80", Bool.not(Utf8.valid(Bytes.of_hex("ed a0 80")))))
    IO.print(T.ok("invalid past U+10FFFF F4 90 80 80", Bool.not(Utf8.valid(Bytes.of_hex("f4 90 80 80")))))
    IO.print(T.ok("invalid F5", Bool.not(Utf8.valid(Bytes.of_hex("f5 80 80 80")))))
    IO.print(T.ok("invalid stray continuation", Bool.not(Utf8.valid(Bytes.of_hex("80")))))
    IO.print(T.ok("invalid truncated C2", Bool.not(Utf8.valid(Bytes.of_hex("c2")))))
    IO.print(T.ok("invalid truncated E1 80", Bool.not(Utf8.valid(Bytes.of_hex("e1 80")))))
    IO.print(T.ok("invalid truncated F1 80 80", Bool.not(Utf8.valid(Bytes.of_hex("f1 80 80")))))
    IO.print(T.ok("invalid E0 41", Bool.not(Utf8.valid(Bytes.of_hex("e0 41")))))
    IO.print(T.ok("invalid Table 3-8", Bool.not(Utf8.valid(Bytes.of_hex("61 F1 80 80 E1 80 C2 62 80 63 80 BF 64")))))

    # 300 KB of three-byte characters, both ways
    +big : List<&2, U32> = repeat(Bytes.of_hex("e8 8c b6"), 100000n, Nil{})
    IO.print(T.ok("300 KB valid", Utf8.valid(big)))
    IO.print(T.ok("300 KB round trip", Bytes.ct_eq(Utf8.encode(Utf8.decode(big)), big)))
