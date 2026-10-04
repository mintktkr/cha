# ecdsa checks: RFC 6979 A.2.5 (P-256) and A.2.6 (P-384), the public keys with the
# SHA-256, SHA-384 and SHA-512 signatures over "sample" and "test" (P-256 with
# SHA-384 and SHA-512 exercises the digest truncation), the rejections, the curve
# OIDs, and one openssl-made signature through verify.der.
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/sha2.bend as Sha2
import ../lib/chaki/ecdsa.bend as Ecdsa
import ../lib/chaki/check.bend as T

# RFC 6979 A.2.5, P-256 public key U = xG, as 04 || X || Y
def pub256() -> String:
  "04" ++ "60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6"
    ++ "7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299"

# RFC 6979 A.2.6, P-384 public key, as 04 || X || Y
def pub384() -> String:
  "04" ++ "EC3A4E415B4E19A4568618029F427FA5DA9A8BC4AE92E02E06AAE5286B300C64DEF8F0EA9055866064A254515480BC13"
    ++ "8015D9B72D7D57244EA8EF9AC0C621896708A59367F9DFB9F54CA84B3F1C9DB1288B231C3AE0D4FE7344FD2533264720"

# P-256 order, for the s = n rejection
def n256() -> String:
  "FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551"

# verify curve c over msg hashed with a against hex r and s
def case.v(c: Ecdsa.Curve, +pub: String, a: Sha2.Alg, +msg: String, +r: String,
  +s: String) -> Bool:
  Ecdsa.verify(c, Bytes.of_hex(pub), Sha2.hash(a, Bytes.of_ascii(msg)),
    Bytes.of_hex(r), Bytes.of_hex(s))

def curve.name(m: Maybe<&2, Ecdsa.Curve>) -> String:
  match m:
    case Some{c}:
      match c:
        case Ecdsa.P256{}:
          "p256"
        case Ecdsa.P384{}:
          "p384"
    case None{}:
      "none"

# verify.der fixture, synthetic key made and signed with:
#   openssl ecparam -name prime256v1 -genkey -noout -out key.pem
#   openssl ec -in key.pem -pubout -outform DER -out pub.der
#   printf 'hello chaki' > msg.bin
#   openssl dgst -sha256 -sign key.pem -out sig.der msg.bin
# pub is the 04 || X || Y point of pub.der, sig the DER bytes of sig.der.
def ossl.pub() -> String:
  "04" ++ "93A8A58748710270388551169473DE1C9D26470BBF7634289C3D1AFD05573997"
    ++ "B9D3029C3B459563C061E4C2843649642998A33FB839F92FCE1C54EF5D2D8A3D"

def ossl.sig() -> String:
  "3045022100AA6CEA9FE16E6CE55F5C6959980FC1FA444545B0E8763465A47ADCB2853CF33E0220093B4BDCB0274D271273B3A73566655C30BEFC880FF0E7E0584E5438C20CC98D"

def ossl.sig.flip() -> String:
  "3045022100AB6CEA9FE16E6CE55F5C6959980FC1FA444545B0E8763465A47ADCB2853CF33E0220093B4BDCB0274D271273B3A73566655C30BEFC880FF0E7E0584E5438C20CC98D"

def ossl.v(+sig: String) -> Bool:
  Ecdsa.verify.der(Ecdsa.P256{}, Sha2.S256{}, Bytes.of_hex(ossl.pub()),
    Bytes.of_ascii("hello chaki"), Bytes.of_hex(sig))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(T.ok("rfc6979 a.2.5 p256 sample sha256",
      case.v(Ecdsa.P256{}, pub256(), Sha2.S256{}, "sample",
        "EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716",
        "F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8")))
    IO.print(T.ok("rfc6979 a.2.5 p256 sample sha384",
      case.v(Ecdsa.P256{}, pub256(), Sha2.S384{}, "sample",
        "0EAFEA039B20E9B42309FB1D89E213057CBF973DC0CFC8F129EDDDC800EF7719",
        "4861F0491E6998B9455193E34E7B0D284DDD7149A74B95B9261F13ABDE940954")))
    IO.print(T.ok("rfc6979 a.2.5 p256 sample sha512",
      case.v(Ecdsa.P256{}, pub256(), Sha2.S512{}, "sample",
        "8496A60B5E9B47C825488827E0495B0E3FA109EC4568FD3F8D1097678EB97F00",
        "2362AB1ADBE2B8ADF9CB9EDAB740EA6049C028114F2460F96554F61FAE3302FE")))
    IO.print(T.ok("rfc6979 a.2.5 p256 test sha256",
      case.v(Ecdsa.P256{}, pub256(), Sha2.S256{}, "test",
        "F1ABB023518351CD71D881567B1EA663ED3EFCF6C5132B354F28D3B0B7D38367",
        "019F4113742A2B14BD25926B49C649155F267E60D3814B4C0CC84250E46F0083")))
    IO.print(T.ok("rfc6979 a.2.5 p256 test sha384",
      case.v(Ecdsa.P256{}, pub256(), Sha2.S384{}, "test",
        "83910E8B48BB0C74244EBDF7F07A1C5413D61472BD941EF3920E623FBCCEBEB6",
        "8DDBEC54CF8CD5874883841D712142A56A8D0F218F5003CB0296B6B509619F2C")))
    IO.print(T.ok("rfc6979 a.2.5 p256 test sha512",
      case.v(Ecdsa.P256{}, pub256(), Sha2.S512{}, "test",
        "461D93F31B6540894788FD206C07CFA0CC35F46FA3C91816FFF1040AD1581A04",
        "39AF9F15DE0DB8D97E72719C74820D304CE5226E32DEDAE67519E840D1194E55")))
    IO.print(T.ok("rfc6979 a.2.6 p384 sample sha256",
      case.v(Ecdsa.P384{}, pub384(), Sha2.S256{}, "sample",
        "21B13D1E013C7FA1392D03C5F99AF8B30C570C6F98D4EA8E354B63A21D3DAA33BDE1E888E63355D92FA2B3C36D8FB2CD",
        "F3AA443FB107745BF4BD77CB3891674632068A10CA67E3D45DB2266FA7D1FEEBEFDC63ECCD1AC42EC0CB8668A4FA0AB0")))
    IO.print(T.ok("rfc6979 a.2.6 p384 sample sha384",
      case.v(Ecdsa.P384{}, pub384(), Sha2.S384{}, "sample",
        "94EDBB92A5ECB8AAD4736E56C691916B3F88140666CE9FA73D64C4EA95AD133C81A648152E44ACF96E36DD1E80FABE46",
        "99EF4AEB15F178CEA1FE40DB2603138F130E740A19624526203B6351D0A3A94FA329C145786E679E7B82C71A38628AC8")))
    IO.print(T.ok("rfc6979 a.2.6 p384 sample sha512",
      case.v(Ecdsa.P384{}, pub384(), Sha2.S512{}, "sample",
        "ED0959D5880AB2D869AE7F6C2915C6D60F96507F9CB3E047C0046861DA4A799CFE30F35CC900056D7C99CD7882433709",
        "512C8CCEEE3890A84058CE1E22DBC2198F42323CE8ACA9135329F03C068E5112DC7CC3EF3446DEFCEB01A45C2667FDD5")))
    IO.print(T.ok("rfc6979 a.2.6 p384 test sha256",
      case.v(Ecdsa.P384{}, pub384(), Sha2.S256{}, "test",
        "6D6DEFAC9AB64DABAFE36C6BF510352A4CC27001263638E5B16D9BB51D451559F918EEDAF2293BE5B475CC8F0188636B",
        "2D46F3BECBCC523D5F1A1256BF0C9B024D879BA9E838144C8BA6BAEB4B53B47D51AB373F9845C0514EEFB14024787265")))
    IO.print(T.ok("rfc6979 a.2.6 p384 test sha384",
      case.v(Ecdsa.P384{}, pub384(), Sha2.S384{}, "test",
        "8203B63D3C853E8D77227FB377BCF7B7B772E97892A80F36AB775D509D7A5FEB0542A7F0812998DA8F1DD3CA3CF023DB",
        "DDD0760448D42D8A43AF45AF836FCE4DE8BE06B485E9B61B827C2F13173923E06A739F040649A667BF3B828246BAA5A5")))
    IO.print(T.ok("rfc6979 a.2.6 p384 test sha512",
      case.v(Ecdsa.P384{}, pub384(), Sha2.S512{}, "test",
        "A0D5D090C9980FAF3C2CE57B7AE951D31977DD11C775D314AF55F76C676447D06FB6495CD21B4B6E340FC236584FB277",
        "976984E59B4C77B0E8E4460DCA3D9F20E07B9BB1F63BEEFAF576F6B2E8B224634A2092CD3792E0159AD9CEE37659C736")))
    IO.print(T.ok("flip r",
      Bool.not(case.v(Ecdsa.P256{}, pub256(), Sha2.S256{}, "sample",
        "FFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716",
        "F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8"))))
    IO.print(T.ok("flip s",
      Bool.not(case.v(Ecdsa.P256{}, pub256(), Sha2.S256{}, "sample",
        "EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716",
        "E7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8"))))
    IO.print(T.ok("flip msg",
      Bool.not(case.v(Ecdsa.P256{}, pub256(), Sha2.S256{}, "samplf",
        "EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716",
        "F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8"))))
    IO.print(T.ok("r zero",
      Bool.not(case.v(Ecdsa.P256{}, pub256(), Sha2.S256{}, "sample", "",
        "F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8"))))
    IO.print(T.ok("s is n",
      Bool.not(case.v(Ecdsa.P256{}, pub256(), Sha2.S256{}, "sample",
        "EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716", n256()))))
    IO.print(T.ok("pub off curve",
      Bool.not(Ecdsa.verify(Ecdsa.P256{}, Bytes.of_hex("04" ++ Bytes.to_hex(Bytes.zeros(64n))),
        Sha2.hash(Sha2.S256{}, Bytes.of_ascii("sample")),
        Bytes.of_hex("EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716"),
        Bytes.of_hex("F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8")))))
    IO.print(T.ok("p256 key as p384",
      Bool.not(Ecdsa.verify(Ecdsa.P384{}, Bytes.of_hex(pub256()),
        Sha2.hash(Sha2.S256{}, Bytes.of_ascii("sample")),
        Bytes.of_hex("EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716"),
        Bytes.of_hex("F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8")))))
    IO.print(T.ok("bad tag",
      Bool.not(Ecdsa.verify(Ecdsa.P256{},
        Bytes.cat(Bytes.of_hex("03"), Bytes.drop(Bytes.of_hex(pub256()), 1n)),
        Sha2.hash(Sha2.S256{}, Bytes.of_ascii("sample")),
        Bytes.of_hex("EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716"),
        Bytes.of_hex("F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8")))))
    IO.print(T.ok("empty pub",
      Bool.not(Ecdsa.verify(Ecdsa.P256{}, Nil{},
        Sha2.hash(Sha2.S256{}, Bytes.of_ascii("sample")),
        Bytes.of_hex("EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716"),
        Bytes.of_hex("F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8")))))
    IO.print(T.eq("curve prime256v1", curve.name(Ecdsa.curve("1.2.840.10045.3.1.7")), "p256"))
    IO.print(T.eq("curve secp384r1", curve.name(Ecdsa.curve("1.3.132.0.34")), "p384"))
    IO.print(T.eq("curve unknown", curve.name(Ecdsa.curve("1.2.3")), "none"))
    IO.print(T.ok("verify.der openssl", ossl.v(ossl.sig())))
    IO.print(T.ok("verify.der openssl flip", Bool.not(ossl.v(ossl.sig.flip()))))
    IO.print(T.ok("verify.der empty sig",
      Bool.not(Ecdsa.verify.der(Ecdsa.P256{}, Sha2.S256{}, Bytes.of_hex(ossl.pub()),
        Bytes.of_ascii("hello chaki"), Nil{}))))
    t0 : Nat <- IO.now()
    w256 : Bool = case.v(Ecdsa.P256{}, pub256(), Sha2.S256{}, "sample",
      "EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716",
      "F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8")
    t1 : Nat <- IO.now()
    IO.print(T.ok("timed p256 true", w256))
    IO.print("time one p256 verify " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
    t2 : Nat <- IO.now()
    w384 : Bool = case.v(Ecdsa.P384{}, pub384(), Sha2.S384{}, "sample",
      "94EDBB92A5ECB8AAD4736E56C691916B3F88140666CE9FA73D64C4EA95AD133C81A648152E44ACF96E36DD1E80FABE46",
      "99EF4AEB15F178CEA1FE40DB2603138F130E740A19624526203B6351D0A3A94FA329C145786E679E7B82C71A38628AC8")
    t3 : Nat <- IO.now()
    IO.print(T.ok("timed p384 true", w384))
    IO.print("time one p384 verify " ++ Nat.show(Nat.sub(t3, t2)) ++ " ms")
