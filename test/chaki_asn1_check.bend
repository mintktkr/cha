# offline checks for lib/chaki/asn1.bend
# Vectors are X.690 (DER) encodings, written here as the RFCs print them.
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/asn1.bend as Asn1
import ../lib/chaki/check.bend as T

# a Tlv read as "F" (fail) when it didn't parse
def tag.of(m: Maybe<&2, Asn1.Tlv>) -> String:
  match m:
    case None{}:
      "F"
    case Some{Asn1.Tlv{tag, _, _}}:
      U32.show(tag)

def value.of(m: Maybe<&2, Asn1.Tlv>) -> List<&2, U32>:
  match m:
    case None{}:
      Bytes.of_ascii("F")
    case Some{Asn1.Tlv{_, value, _}}:
      value

def rest.of(m: Maybe<&2, Asn1.Tlv>) -> List<&2, U32>:
  match m:
    case None{}:
      Bytes.of_ascii("F")
    case Some{Asn1.Tlv{_, _, rest}}:
      rest

def len.of(m: Maybe<&2, Asn1.Tlv>) -> String:
  match m:
    case None{}:
      "F"
    case Some{Asn1.Tlv{_, value, _}}:
      U32.show(Bytes.len(value))

def tlvs.count(xs: List<&2, Asn1.Tlv>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{_, t}:
      U32.add(tlvs.count(t), 1)

def items.count(m: Maybe<&2, List<&2, Asn1.Tlv>>) -> String:
  match m:
    case None{}:
      "F"
    case Some{xs}:
      U32.show(tlvs.count(xs))

def tlv.text(t: Asn1.Tlv) -> String:
  match t:
    case Asn1.Tlv{tag, value, _}:
      U32.show(tag) ++ ":" ++ Bytes.to_hex(value)

def items.first(m: Maybe<&2, List<&2, Asn1.Tlv>>) -> String:
  match m:
    case Some{Con{t, _}}:
      tlv.text(t)
    case _:
      "F"

def time.of(m: Maybe<&2, U32>) -> String:
  match m:
    case None{}:
      "F"
    case Some{s}:
      U32.show(s)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(T.eq("X.690 8.1.3 short length: tag", tag.of(Asn1.read(Bytes.of_hex("04 03 41 42 43"))), "4"))
    IO.print(T.hex("X.690 8.1.3 short length: value", value.of(Asn1.read(Bytes.of_hex("04 03 41 42 43"))), "414243"))
    IO.print(T.hex("X.690 8.1.3 short length: rest", rest.of(Asn1.read(Bytes.of_hex("04 03 41 42 43"))), ""))
    IO.print(T.hex("element followed by bytes", rest.of(Asn1.read(Bytes.of_hex("30 03 02 01 05 ff"))), "ff"))
    IO.print(T.eq("zero length: tag", tag.of(Asn1.read(Bytes.of_hex("05 00"))), "5"))
    IO.print(T.hex("zero length: value", value.of(Asn1.read(Bytes.of_hex("05 00"))), ""))
    IO.print(T.eq("long form 0x81 0x80: tag", tag.of(Asn1.read(Bytes.cat(Bytes.of_hex("04 81 80"), Bytes.zeros(128n)))), "4"))
    IO.print(T.eq("long form 0x81 0x80: length", len.of(Asn1.read(Bytes.cat(Bytes.of_hex("04 81 80"), Bytes.zeros(128n)))), "128"))
    IO.print(T.eq("long form 0x82 0x0100: length", len.of(Asn1.read(Bytes.cat(Bytes.of_hex("04 82 01 00"), Bytes.zeros(256n)))), "256"))
    IO.print(T.eq("non-minimal long form refused", tag.of(Asn1.read(Bytes.cat(Bytes.of_hex("04 81 7f"), Bytes.zeros(127n)))), "F"))
    IO.print(T.eq("long form with a leading zero refused", tag.of(Asn1.read(Bytes.cat(Bytes.of_hex("04 82 00 80"), Bytes.zeros(128n)))), "F"))
    IO.print(T.eq("X.690 8.1.3.6 indefinite length refused", tag.of(Asn1.read(Bytes.of_hex("04 80 00 00"))), "F"))
    IO.print(T.eq("length past the end refused", tag.of(Asn1.read(Bytes.of_hex("04 05 01 02"))), "F"))
    IO.print(T.eq("five length bytes refused", tag.of(Asn1.read(Bytes.of_hex("04 85 01 02 03 04 05"))), "F"))
    IO.print(T.eq("high tag number 0x1f refused", tag.of(Asn1.read(Bytes.of_hex("1f 01 02"))), "F"))
    IO.print(T.eq("high tag number 0x9f refused", tag.of(Asn1.read(Bytes.of_hex("9f 01 02"))), "F"))
    IO.print(T.eq("empty input refused", tag.of(Asn1.read(Nil{})), "F"))
    IO.print(T.eq("tag alone refused", tag.of(Asn1.read(Bytes.of_hex("04"))), "F"))
    IO.print(T.eq("items: count", items.count(Asn1.items(Bytes.of_hex("02 01 01 02 01 02"))), "2"))
    IO.print(T.eq("items: first", items.first(Asn1.items(Bytes.of_hex("02 01 01 02 01 02"))), "2:01"))
    IO.print(T.eq("items: empty", items.count(Asn1.items(Nil{})), "0"))
    IO.print(T.eq("items: truncated element refused", items.count(Asn1.items(Bytes.of_hex("02 01"))), "F"))
    IO.print(T.eq("items: high tag number refused", items.count(Asn1.items(Bytes.of_hex("9f 01 02"))), "F"))
    IO.print(T.eq("OID rsaEncryption (1.2.840.113549.1.1.11)", Asn1.oid(Bytes.of_hex("2a 86 48 86 f7 0d 01 01 0b")), "1.2.840.113549.1.1.11"))
    IO.print(T.eq("OID ecdsa-with-SHA384 (1.2.840.10045.4.3.3)", Asn1.oid(Bytes.of_hex("2a 86 48 ce 3d 04 03 03")), "1.2.840.10045.4.3.3"))
    IO.print(T.eq("OID two arcs", Asn1.oid(Bytes.of_hex("2a")), "1.2"))
    IO.print(T.eq("OID 1.2.3", Asn1.oid(Bytes.of_hex("2a 03")), "1.2.3"))
    IO.print(T.eq("OID first arc over 80", Asn1.oid(Bytes.of_hex("81 34")), "2.100"))
    IO.print(T.hex("uint strips the sign padding", Asn1.uint(Bytes.of_hex("00 80")), "80"))
    IO.print(T.hex("uint of zero", Asn1.uint(Bytes.of_hex("00")), "00"))
    IO.print(T.hex("uint keeps a leading byte over 0x7f", Asn1.uint(Bytes.of_hex("01 00")), "0100"))
    IO.print(T.hex("uint of empty", Asn1.uint(Nil{}), ""))
    IO.print(T.eq("UTCTime 2049", time.of(Asn1.time(23, Bytes.of_ascii("491231235959Z"))), "2524607999"))
    IO.print(T.eq("UTCTime 1950 is before the epoch", time.of(Asn1.time(23, Bytes.of_ascii("500101000000Z"))), "F"))
    IO.print(T.eq("UTCTime 1970", time.of(Asn1.time(23, Bytes.of_ascii("700101000000Z"))), "0"))
    IO.print(T.eq("UTCTime 1999", time.of(Asn1.time(23, Bytes.of_ascii("991231235959Z"))), "946684799"))
    IO.print(T.eq("UTCTime 2000", time.of(Asn1.time(23, Bytes.of_ascii("000101000000Z"))), "946684800"))
    IO.print(T.eq("GeneralizedTime 2049", time.of(Asn1.time(24, Bytes.of_ascii("20491231235959Z"))), "2524607999"))
    IO.print(T.eq("GeneralizedTime 2106-02-07 06:28:15 is the last second", time.of(Asn1.time(24, Bytes.of_ascii("21060207062815Z"))), "4294967295"))
    IO.print(T.eq("GeneralizedTime 2106-02-07 06:28:16 is past the U32", time.of(Asn1.time(24, Bytes.of_ascii("21060207062816Z"))), "F"))
    IO.print(T.eq("GeneralizedTime 1900 is before the epoch", time.of(Asn1.time(24, Bytes.of_ascii("19000101000000Z"))), "F"))
    IO.print(T.eq("UTCTime without the Z refused", time.of(Asn1.time(23, Bytes.of_ascii("491231235959 "))), "F"))
    IO.print(T.eq("UTCTime of twelve bytes refused", time.of(Asn1.time(23, Bytes.of_ascii("49123123595Z"))), "F"))
    IO.print(T.eq("UTCTime with a non-digit refused", time.of(Asn1.time(23, Bytes.of_ascii("49123123595AZ"))), "F"))
    IO.print(T.eq("UTCTime with second 60 refused", time.of(Asn1.time(23, Bytes.of_ascii("700101000060Z"))), "F"))
    IO.print(T.eq("UTCTime under the wrong tag refused", time.of(Asn1.time(2, Bytes.of_ascii("700101000000Z"))), "F"))
    IO.print(T.eq("UTCTime February 31 refused", time.of(Asn1.time(23, Bytes.of_ascii("260231000000Z"))), "F"))
    IO.print(T.eq("UTCTime April 31 refused", time.of(Asn1.time(23, Bytes.of_ascii("260431000000Z"))), "F"))
    IO.print(T.eq("GeneralizedTime 2024-02-29 is a leap day", time.of(Asn1.time(24, Bytes.of_ascii("20240229000000Z"))), "1709164800"))
    IO.print(T.eq("GeneralizedTime 2100-02-29 refused", time.of(Asn1.time(24, Bytes.of_ascii("21000229000000Z"))), "F"))
    IO.print(T.eq("GeneralizedTime of the wrong length refused", time.of(Asn1.time(24, Bytes.of_ascii("204901010000Z"))), "F"))
