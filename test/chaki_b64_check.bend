# offline checks for lib/chaki/b64.bend
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/b64.bend as B64
import ../lib/chaki/check.bend as T

# unit repeated n times, in order
def repeat(+unit: List<&2, U32>, n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      Bytes.rev(acc)
    case 1n+p:
      repeat(unit, p, Bytes.rev.onto(unit, acc))

# the bytes a decoded text holds, as hex, or "none" when the text was refused
def show(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case Some{b}:
      Bytes.to_hex(b)
    case None{}:
      "none"

def blocks.join(h: String, t: String) -> String:
  match t:
    case SNil{}:
      h
    case _:
      h ++ "," ++ t

# the payloads pem found, as hex, one pair of brackets each
def blocks(xs: List<&2, List<&2, U32>>) -> String:
  match xs:
    case Nil{}:
      SNil{}
    case Con{h, t}:
      blocks.join("(" ++ Bytes.to_hex(h) ++ ")", blocks(t))

# the bytes a decoded text holds, or an empty list when it was refused
def show.bytes(m: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  match m:
    case Some{b}:
      b
    case None{}:
      Nil{}

# a self-signed P-256 certificate, generated for this test: no private key here
def cert() -> String:
  "-----BEGIN CERTIFICATE-----\nMIIBiTCCAS+gAwIBAgIUE5C68ltDdTM0nllhEQG2UqO6iXQwCgYIKoZIzj0EAwIw\nGjEYMBYGA1UEAwwPY2hha2ktdGV4dC10ZXN0MB4XDTI2MTAwNDA0MTA0NVoXDTI2\nMTEwMzA0MTA0NVowGjEYMBYGA1UEAwwPY2hha2ktdGV4dC10ZXN0MFkwEwYHKoZI\nzj0CAQYIKoZIzj0DAQcDQgAElWbs49CryUba07+VLW42DOCCBN0LlfF0eQ0xqSFQ\nX39mlYUBHfhguqeZZwwGTH6zE/ChNlRKNngE5i0n7yk1l6NTMFEwHQYDVR0OBBYE\nFOXHEpqWOAS9VBDwkL8yHGBBg9WaMB8GA1UdIwQYMBaAFOXHEpqWOAS9VBDwkL8y\nHGBBg9WaMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIgEvmcT2l+\nxOhwaLJvuepfmGdXbyKcqN9Hm7cT7bKxhqkCIQDSEFS0DntoAhsVdHeuQ4noDE9t\nhWKK6CcLxfYNAmM9kQ==\n-----END CERTIFICATE-----"

def main() -> IO(Unit):
  do IO<Unit>:
    # RFC 4648 10: the test vectors, both ways
    IO.print(T.eq("RFC 4648 10 encode empty", B64.encode(Nil{}), ""))
    IO.print(T.eq("RFC 4648 10 encode f", B64.encode(Bytes.of_ascii("f")), "Zg=="))
    IO.print(T.eq("RFC 4648 10 encode fo", B64.encode(Bytes.of_ascii("fo")), "Zm8="))
    IO.print(T.eq("RFC 4648 10 encode foo", B64.encode(Bytes.of_ascii("foo")), "Zm9v"))
    IO.print(T.eq("RFC 4648 10 encode foob", B64.encode(Bytes.of_ascii("foob")), "Zm9vYg=="))
    IO.print(T.eq("RFC 4648 10 encode fooba", B64.encode(Bytes.of_ascii("fooba")), "Zm9vYmE="))
    IO.print(T.eq("RFC 4648 10 encode foobar", B64.encode(Bytes.of_ascii("foobar")), "Zm9vYmFy"))
    IO.print(T.eq("RFC 4648 10 decode empty", show(B64.decode("")), ""))
    IO.print(T.eq("RFC 4648 10 decode Zg==", show(B64.decode("Zg==")), "66"))
    IO.print(T.eq("RFC 4648 10 decode Zm8=", show(B64.decode("Zm8=")), "666f"))
    IO.print(T.eq("RFC 4648 10 decode Zm9v", show(B64.decode("Zm9v")), "666f6f"))
    IO.print(T.eq("RFC 4648 10 decode Zm9vYg==", show(B64.decode("Zm9vYg==")), "666f6f62"))
    IO.print(T.eq("RFC 4648 10 decode Zm9vYmE=", show(B64.decode("Zm9vYmE=")), "666f6f6261"))
    IO.print(T.eq("RFC 4648 10 decode Zm9vYmFy", show(B64.decode("Zm9vYmFy")), "666f6f626172"))
    IO.print(T.eq("decode the last group of one byte", show(B64.decode("Zg==")), "66"))
    IO.print(T.eq("decode the last group of two bytes", show(B64.decode("Zm8=")), "666f"))

    # whatever is not the padded alphabet, and a group the padding does not close
    IO.print(T.eq("reject bad character", show(B64.decode("Zm9v!")), "none"))
    IO.print(T.eq("reject bad character first", show(B64.decode("!m9v")), "none"))
    IO.print(T.eq("reject a non-ASCII character", show(B64.decode(SCon{Chr{233}, SNil{}})), "none"))
    IO.print(T.eq("reject Zg=", show(B64.decode("Zg=")), "none"))
    IO.print(T.eq("reject Zg===", show(B64.decode("Zg===")), "none"))
    IO.print(T.eq("reject Z", show(B64.decode("Z")), "none"))
    IO.print(T.eq("reject Zg", show(B64.decode("Zg")), "none"))
    IO.print(T.eq("reject a lone pad", show(B64.decode("=")), "none"))
    IO.print(T.eq("reject only pads", show(B64.decode("====")), "none"))
    IO.print(T.eq("reject a pad after a full group", show(B64.decode("Zm9v=")), "none"))
    IO.print(T.eq("reject a group left open", show(B64.decode("Zg==Zg")), "none"))
    IO.print(T.eq("reject non-zero pad bits Zh==", show(B64.decode("Zh==")), "none"))
    IO.print(T.eq("reject non-zero pad bits ZZ==", show(B64.decode("ZZ==")), "none"))
    IO.print(T.eq("reject non-zero pad bits Zm+=", show(B64.decode("Zm+=")), "none"))
    IO.print(T.eq("reject data after a closed group", show(B64.decode("Zg==!")), "none"))

    # whitespace is skipped, anywhere
    IO.print(T.eq("whitespace around", show(B64.decode(" Zg==\n")), "66"))
    IO.print(T.eq("whitespace inside a group", show(B64.decode("Z g\t=\n=")), "66"))
    IO.print(T.eq("whitespace between groups", show(B64.decode("Zm9v Zm9v")), "666f6f666f6f"))
    IO.print(T.eq("crlf between groups", show(B64.decode("Zm9v\r\nZm9v\r\n")), "666f6f666f6f"))
    IO.print(T.eq("whitespace only", show(B64.decode(" \t\r\n ")), ""))

    # PEM
    IO.print(T.eq("pem one certificate", blocks(B64.pem(cert(), "CERTIFICATE")), "(308201893082012fa00302010202141390baf25b437533349e59611101b652a3ba8974300a06082a8648ce3d040302301a3118301606035504030c0f6368616b692d746578742d74657374301e170d3236313030343034313034355a170d3236313130333034313034355a301a3118301606035504030c0f6368616b692d746578742d746573743059301306072a8648ce3d020106082a8648ce3d030107034200049566ece3d0abc946dad3bf952d6e360ce08204dd0b95f174790d31a921505f7f669585011df860baa799670c064c7eb313f0a136544a367804e62d27ef293597a3533051301d0603551d0e04160414e5c7129a963804bd5410f090bf321c604183d59a301f0603551d23041830168014e5c7129a963804bd5410f090bf321c604183d59a300f0603551d130101ff040530030101ff300a06082a8648ce3d0403020348003045022012f99c4f697ec4e87068b26fb9ea5f9867576f229ca8df479bb713edb2b186a9022100d21054b40e7b68021b157477ae4389e80c4f6d85628ae8270bc5f60d02633d91)"))
    IO.print(T.eq("pem another label", blocks(B64.pem(cert(), "PRIVATE KEY")), ""))
    IO.print(T.eq("pem no block", blocks(B64.pem("nothing to see here\n", "CERTIFICATE")), ""))
    IO.print(T.eq("pem two blocks", blocks(B64.pem("junk before\n-----BEGIN CERTIFICATE-----\nZm9v\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nYmFy\n-----END CERTIFICATE-----\njunk after\n", "CERTIFICATE")), "(666f6f),(626172)"))
    IO.print(T.eq("pem other blocks ignored", blocks(B64.pem("-----BEGIN PRIVATE KEY-----\nYmFy\n-----END PRIVATE KEY-----\n-----BEGIN CERTIFICATE-----\nZm9v\n-----END CERTIFICATE-----\n", "CERTIFICATE")), "(666f6f)"))
    IO.print(T.eq("pem lines joined", blocks(B64.pem("-----BEGIN CERTIFICATE-----\nZm9v\nYmFy\n-----END CERTIFICATE-----\n", "CERTIFICATE")), "(666f6f626172)"))
    IO.print(T.eq("pem crlf and trailing space", blocks(B64.pem("-----BEGIN CERTIFICATE-----\r\nZm9v  \r\n-----END CERTIFICATE----- \r\n", "CERTIFICATE")), "(666f6f)"))
    IO.print(T.eq("pem unterminated block", blocks(B64.pem("-----BEGIN CERTIFICATE-----\nZm9v\n", "CERTIFICATE")), ""))
    IO.print(T.eq("pem block that is not base64", blocks(B64.pem("-----BEGIN CERTIFICATE-----\nnot base64!\n-----END CERTIFICATE-----\n", "CERTIFICATE")), ""))
    IO.print(T.eq("pem block with an empty body", blocks(B64.pem("-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n", "CERTIFICATE")), "()"))
    IO.print(T.eq("pem two certificates in a row", blocks(B64.pem(cert() ++ "\n" ++ cert(), "CERTIFICATE")), "(308201893082012fa00302010202141390baf25b437533349e59611101b652a3ba8974300a06082a8648ce3d040302301a3118301606035504030c0f6368616b692d746578742d74657374301e170d3236313030343034313034355a170d3236313130333034313034355a301a3118301606035504030c0f6368616b692d746578742d746573743059301306072a8648ce3d020106082a8648ce3d030107034200049566ece3d0abc946dad3bf952d6e360ce08204dd0b95f174790d31a921505f7f669585011df860baa799670c064c7eb313f0a136544a367804e62d27ef293597a3533051301d0603551d0e04160414e5c7129a963804bd5410f090bf321c604183d59a301f0603551d23041830168014e5c7129a963804bd5410f090bf321c604183d59a300f0603551d130101ff040530030101ff300a06082a8648ce3d0403020348003045022012f99c4f697ec4e87068b26fb9ea5f9867576f229ca8df479bb713edb2b186a9022100d21054b40e7b68021b157477ae4389e80c4f6d85628ae8270bc5f60d02633d91),(308201893082012fa00302010202141390baf25b437533349e59611101b652a3ba8974300a06082a8648ce3d040302301a3118301606035504030c0f6368616b692d746578742d74657374301e170d3236313030343034313034355a170d3236313130333034313034355a301a3118301606035504030c0f6368616b692d746578742d746573743059301306072a8648ce3d020106082a8648ce3d030107034200049566ece3d0abc946dad3bf952d6e360ce08204dd0b95f174790d31a921505f7f669585011df860baa799670c064c7eb313f0a136544a367804e62d27ef293597a3533051301d0603551d0e04160414e5c7129a963804bd5410f090bf321c604183d59a301f0603551d23041830168014e5c7129a963804bd5410f090bf321c604183d59a300f0603551d130101ff040530030101ff300a06082a8648ce3d0403020348003045022012f99c4f697ec4e87068b26fb9ea5f9867576f229ca8df479bb713edb2b186a9022100d21054b40e7b68021b157477ae4389e80c4f6d85628ae8270bc5f60d02633d91)"))

    # 150 KB, both ways
    +big : List<&2, U32> = repeat(Bytes.of_hex("000102030405060708090a0b0c0d0e0f"), 10000n, Nil{})
    IO.print(T.ok("150 KB round trip", Bytes.ct_eq(show.bytes(B64.decode(B64.encode(big))), big)))
