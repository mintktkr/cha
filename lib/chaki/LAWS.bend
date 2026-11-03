# laws: what chaki promises, stated before it is proven. Each law is a claim about a pure
# module; PROOF.bend beside this file proves it. The gate is scripts/check.sh: this file's
# PROOF.bend must exit 0 with ALL PROOFS CHECK, so no law here may lean on @unsafe or foreign
# code, and `bend lib/chaki/PROOF.bend --verdict` rechecks every proof with the BendTT kernel.
# sys, ossl, tlsio and http's IO stay out: their decisions move into pure defs that are stated
# here. Law names start with their module (b64_, tls_, ...).
import Base
import ./bytes.bend as Bytes
import ./utf8.bend as Utf8
import ./b64.bend as B64
import ./time.bend as Time
import ./width.bend as Width
import ./url.bend as Url
import ./http1.bend as Http1
import ./sha2.bend as Sha2
import ./chacha.bend as Chacha
import ./aes.bend as Aes
import ./x25519.bend as X25519
import ./big.bend as Big
import ./rsa.bend as Rsa
import ./ecdsa.bend as Ecdsa
import ./asn1.bend as Asn1
import ./x509.bend as X509
import ./x509v.bend as X509v
import ./tlsmsg.bend as Tlsmsg
import ./tls.bend as Tls
import ./hop.bend as Hop
import ./json.bend as Json

# bytes, utf8, b64 [enc]
# ----------------------

# bytes: the byte-string shape the protocol code is built from
# ----------------------------------------------------------
# Reversal and length are laws over every byte string; the rest pin the hex and comparison
# answers the protocol code reads.

# LAW: reversing a byte string twice gives the byte string back.
law bytes_rev_rev:
  for +b: List<&2, U32>
  {Bytes.rev(Bytes.rev(b)) == b : List<&2, U32>}

# LAW: reversing a byte string keeps its length, so a length written before a body still
# fits the body after a reversal.
law bytes_len_rev:
  for +b: List<&2, U32>
  {Bytes.len(Bytes.rev(b)) == Bytes.len(b) : U32}

# LAW: reversing a concatenation is the concatenation of the reversals, in the other order.
law bytes_rev_cat:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  {Bytes.rev(Bytes.cat(a, b)) == Bytes.cat(Bytes.rev(b), Bytes.rev(a)) : List<&2, U32>}

# LAW: hex text that parsed to bytes survives being written back out and parsed again.
law bytes_hex_round_trip:
  {Bytes.of_hex(Bytes.to_hex(Bytes.of_hex("00 01 7f 80 ff fe 0d 0a"))) == Bytes.of_hex("00017f80fffe0d0a") : List<&2, U32>}

# LAW: a byte string holding every byte value, high ones included, equals itself.
law bytes_eq_self:
  {Bytes.eq(Bytes.of_hex("00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f 7f 80 ff"), Bytes.of_hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f7f80ff")) == True{} : Bool}

# LAW: the constant-time compare agrees with the cheap one on bytes that match.
law bytes_ct_eq_agrees:
  {Bytes.ct_eq(Bytes.of_hex("deadbeef"), Bytes.of_hex("deadbeef")) == Bytes.eq(Bytes.of_hex("deadbeef"), Bytes.of_hex("deadbeef")) : Bool}

# LAW: the constant-time compare agrees with the cheap one on bytes that differ in their
# last byte, the one a MAC's comparison must not miss.
law bytes_ct_eq_agrees_differs:
  {Bytes.ct_eq(Bytes.of_hex("deadbeef"), Bytes.of_hex("deadbeee")) == Bytes.eq(Bytes.of_hex("deadbeef"), Bytes.of_hex("deadbeee")) : Bool}

# utf8: text and bytes
# --------------------
# Encoding is how text becomes bytes on the wire, and validation is what keeps a surrogate or
# a value past U+10FFFF out of a parser. These are known answers rather than laws over every
# input: RFC 3629's table and Unicode 3.9's repair examples, at the values that decide each
# branch of the encoder and the decoder.

# LAW: decoding what encode wrote gives the text back, for a text holding a code point of
# each of the four UTF-8 lengths.
law utf8_decode_encode:
  {Utf8.decode(Utf8.encode("a\u{e9}\u{8316}\u{1f600}")) == "a\u{e9}\u{8316}\u{1f600}" : String}

# LAW: RFC 3629 section 3's table: the smallest and largest scalar value of each length
# encodes to the bytes it lists, 7F, C2 80 .. DF BF, E0 A0 80 .. EF BF BF, F0 90 80 80 ..
# F4 8F BF BF.
law utf8_encode_boundaries:
  {Bytes.to_hex(Utf8.encode("\u{7f}\u{80}\u{7ff}\u{800}\u{ffff}\u{10000}\u{10ffff}")) == "7fc280dfbfe0a080efbfbff0908080f48fbfbf" : String}

# LAW: a scalar value takes one byte up to U+007F, two up to U+07FF, three up to U+FFFF and
# four above it, so those seven boundary values take 1+2+2+3+3+4+4 = 19 bytes.
law utf8_encode_length:
  {Bytes.len(Utf8.encode("\u{7f}\u{80}\u{7ff}\u{800}\u{ffff}\u{10000}\u{10ffff}")) == 19 : U32}

# LAW: validate accepts what encode wrote, at every length boundary.
law utf8_valid_encode:
  {Utf8.valid(Utf8.encode("\u{7f}\u{80}\u{7ff}\u{800}\u{ffff}\u{10000}\u{10ffff}")) == True{} : Bool}

# LAW: text decoded from well-formed bytes encodes back to the same bytes.
law utf8_decode_valid:
  {Utf8.encode(Utf8.decode(Bytes.of_hex("41 c3 a9 e8 8c b6 f0 9f 98 80 42"))) == Bytes.of_hex("41 c3 a9 e8 8c b6 f0 9f 98 80 42") : List<&2, U32>}

# LAW: an overlong form, which names a scalar value in more bytes than it takes, is refused.
law utf8_reject_overlong:
  {Utf8.valid(Bytes.of_hex("c0 af c1 80 e0 80 af f0 80 80 af")) == False{} : Bool}

# LAW: an overlong NUL, the byte a filter that only looks for a zero byte would miss, is
# refused.
law utf8_reject_overlong_nul:
  {Utf8.valid(Bytes.of_hex("c0 80")) == False{} : Bool}

# LAW: a surrogate, U+D800 through U+DFFF, is no Unicode scalar value and is refused.
law utf8_reject_surrogate:
  {Utf8.valid(Bytes.of_hex("ed a0 80 ed bf bf")) == False{} : Bool}

# LAW: a value past U+10FFFF is refused, whether a valid lead byte spells it or one from
# U+F5 up.
law utf8_reject_past_limit:
  {Utf8.valid(Bytes.of_hex("f4 90 80 80 f5 80 80 80")) == False{} : Bool}

# LAW: a sequence cut off by the end of the input is refused, so a chunk boundary can't hand
# a parser half a character.
law utf8_reject_truncated:
  {Utf8.valid(Bytes.of_hex("e1 80")) == False{} : Bool}

# LAW: a sequence cut off by the end of the input decodes to one replacement character.
law utf8_decode_truncated:
  {Utf8.decode(Bytes.of_hex("e1 80")) == "\u{fffd}" : String}

# LAW: a NUL byte is text like any other, so it decodes and encodes back unchanged and does
# not end the text.
law utf8_decode_nul:
  {Utf8.encode(Utf8.decode(Bytes.of_hex("00 41 00"))) == Bytes.of_hex("00 41 00") : List<&2, U32>}

# LAW: Unicode 3.9's Table 3-8: the decoder answers one U+FFFD for each maximal ill-formed
# subpart, so a cut-off sequence costs one replacement character and two stray continuation
# bytes cost two.
law utf8_decode_subparts:
  {Utf8.decode(Bytes.of_hex("61 f1 80 80 e1 80 c2 62 80 63 80 bf 64")) == "a\u{fffd}\u{fffd}\u{fffd}b\u{fffd}c\u{fffd}\u{fffd}d" : String}

# b64: RFC 4648 base64 and the PEM blocks a certificate travels in
# -----------------------------------------------------------------
# The table is RFC 4648 section 10's, both ways. The last two laws are the shape a
# certificate arrives in: a block, and a block that never ended.

# LAW: RFC 4648 section 10's test vector for the empty input.
law b64_rfc4648_empty:
  {B64.encode(Nil{}) == "" : String}

# LAW: RFC 4648 section 10's "f" vector, one byte under two pads.
law b64_rfc4648_f:
  {B64.encode(Bytes.of_ascii("f")) == "Zg==" : String}

# LAW: RFC 4648 section 10's "fo" vector, two bytes under one pad.
law b64_rfc4648_fo:
  {B64.encode(Bytes.of_ascii("fo")) == "Zm8=" : String}

# LAW: RFC 4648 section 10's "foo" vector, one group and no pad.
law b64_rfc4648_foo:
  {B64.encode(Bytes.of_ascii("foo")) == "Zm9v" : String}

# LAW: RFC 4648 section 10's "foob" vector.
law b64_rfc4648_foob:
  {B64.encode(Bytes.of_ascii("foob")) == "Zm9vYg==" : String}

# LAW: RFC 4648 section 10's "fooba" vector.
law b64_rfc4648_fooba:
  {B64.encode(Bytes.of_ascii("fooba")) == "Zm9vYmE=" : String}

# LAW: RFC 4648 section 10's "foobar" vector, two full groups.
law b64_rfc4648_foobar:
  {B64.encode(Bytes.of_ascii("foobar")) == "Zm9vYmFy" : String}

# LAW: RFC 4648 section 10's one-byte vector decodes back to that byte.
law b64_decode_one:
  {B64.decode("Zg==") == Some{Bytes.of_ascii("f")} : Maybe<&2, List<&2, U32>>}

# LAW: RFC 4648 section 10's two-byte vector decodes back to those bytes.
law b64_decode_two:
  {B64.decode("Zm8=") == Some{Bytes.of_ascii("fo")} : Maybe<&2, List<&2, U32>>}

# LAW: RFC 4648 section 10's group without a pad decodes back to its three bytes.
law b64_decode_three:
  {B64.decode("Zm9v") == Some{Bytes.of_ascii("foo")} : Maybe<&2, List<&2, U32>>}

# LAW: decoding what encode wrote gives the bytes back, for a body holding every low byte.
law b64_decode_encode:
  {B64.decode(B64.encode(Bytes.of_hex("000102030405060708090a0b0c0d0e0f"))) == Some{Bytes.of_hex("000102030405060708090a0b0c0d0e0f")} : Maybe<&2, List<&2, U32>>}

# LAW: seven bytes take three groups of four characters, so the text is 4 * ceil(7 / 3) = 12
# characters long.
law b64_length:
  {String.length(B64.encode(Bytes.of_hex("00010203040506"))) == 12n : Nat}

# LAW: a character outside the base64 alphabet is refused, not skipped.
law b64_reject_char:
  {B64.decode("Zm9v!") == None{} : Maybe<&2, List<&2, U32>>}

# LAW: a character outside ASCII is refused too, so a stray high byte can't slip through.
law b64_reject_non_ascii:
  {B64.decode(SCon{Chr{233}, SNil{}}) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: a pad over bits that are not zero is refused, so one body has one spelling.
law b64_reject_pad_bits:
  {B64.decode("Zh==") == None{} : Maybe<&2, List<&2, U32>>}

# LAW: a PEM body wrapped over lines decodes to the one payload its lines spell together.
law b64_decode_wrapped:
  {B64.decode("Zm9v\nYmFy") == Some{Bytes.of_ascii("foobar")} : Maybe<&2, List<&2, U32>>}

# LAW: a trailing newline, which every PEM line but the last carries, doesn't change what
# base64 text decodes to.
law b64_decode_newline:
  for +s: String
  {B64.decode(String.append(s, "\n")) == B64.decode(s) : Maybe<&2, List<&2, U32>>}

# LAW: a newline in front of the text doesn't change what base64 text decodes to either, so
# whitespace at either end of a payload is ignored.
law b64_decode_leading_newline:
  for +s: String
  {B64.decode(String.append("\n", s)) == B64.decode(s) : Maybe<&2, List<&2, U32>>}

# LAW: a trailing newline adds no line, so the text a PEM block is scanned from is the same
# either way.
law b64_lines_newline:
  for +s: String
  {B64.lines(String.append(s, "\n")) == B64.lines(s) : List<&2, String>}

# LAW: a well-formed PEM block's body is found and decoded, whatever sits around it.
law b64_pem_block:
  {B64.pem("junk\n-----BEGIN CERTIFICATE-----\nZm9v\nYmFy\n-----END CERTIFICATE-----\njunk\n", "CERTIFICATE") == [Bytes.of_ascii("foobar")] : List<&2, List<&2, U32>>}

# LAW: a block whose END line never comes is refused, so a truncated body is not read as a
# certificate.
law b64_pem_no_end:
  {B64.pem("-----BEGIN CERTIFICATE-----\nZm9v\n", "CERTIFICATE") == Nil{} : List<&2, List<&2, U32>>}

# LAW: two blocks in a row are two payloads, in the order they appear.
law b64_pem_two_blocks:
  {B64.pem("-----BEGIN CERTIFICATE-----\nZm9v\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nYmFy\n-----END CERTIFICATE-----\n", "CERTIFICATE") == [Bytes.of_ascii("foo"), Bytes.of_ascii("bar")] : List<&2, List<&2, U32>>}

# LAW: a block of another label is not a certificate, so it is left out.
law b64_pem_other_label:
  {B64.pem("-----BEGIN PRIVATE KEY-----\nYmFy\n-----END PRIVATE KEY-----\n-----BEGIN CERTIFICATE-----\nZm9v\n-----END CERTIFICATE-----\n", "CERTIFICATE") == [Bytes.of_ascii("foo")] : List<&2, List<&2, U32>>}

# LAW: a block whose body is empty yields an empty payload, so a bad block is caught by the
# parse and not by the scan.
law b64_pem_empty_body:
  {B64.pem("-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n", "CERTIFICATE") == [Nil{}] : List<&2, List<&2, U32>>}

# end enc

# json [json]
# -----------
# The reader turns a document into dotted-key rows and refuses anything RFC 8259 forbids.
# The writer's escaping is stated as a worked case rather than over every string: what the
# writer decides per character turns on comparing a code point, and Bend's checker cannot
# split on a comparison it cannot compute, so a law pins down the text it hands the reader
# and the answer that comes back.

# LAW: the writer writes a quote, a backslash, each of the thirty-two control characters
# below 0x20 (a short escape where JSON has one, \u00XX for the rest) and non-ASCII text as
# itself: the text it makes of them is exactly this.
law json_encode_escapes:
  {Json.encode(Json.Str{SCon{Chr{34}, SCon{Chr{92}, SCon{Chr{0}, SCon{Chr{1}, SCon{Chr{2}, SCon{Chr{3}, SCon{Chr{4}, SCon{Chr{5}, SCon{Chr{6}, SCon{Chr{7}, SCon{Chr{8}, SCon{Chr{9}, SCon{Chr{10}, SCon{Chr{11}, SCon{Chr{12}, SCon{Chr{13}, SCon{Chr{14}, SCon{Chr{15}, SCon{Chr{16}, SCon{Chr{17}, SCon{Chr{18}, SCon{Chr{19}, SCon{Chr{20}, SCon{Chr{21}, SCon{Chr{22}, SCon{Chr{23}, SCon{Chr{24}, SCon{Chr{25}, SCon{Chr{26}, SCon{Chr{27}, SCon{Chr{28}, SCon{Chr{29}, SCon{Chr{30}, SCon{Chr{31}, SCon{Chr{233}, SCon{Chr{128512}, SNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}) == Utf8.decode(Bytes.of_hex("22 5c 22 5c 5c 5c 75 30 30 30 30 5c 75 30 30 30 31 5c 75 30 30 30 32 5c 75 30 30 30 33 5c 75 30 30 30 34 5c 75 30 30 30 35 5c 75 30 30 30 36 5c 75 30 30 30 37 5c 62 5c 74 5c 6e 5c 75 30 30 30 62 5c 66 5c 72 5c 75 30 30 30 65 5c 75 30 30 30 66 5c 75 30 30 31 30 5c 75 30 30 31 31 5c 75 30 30 31 32 5c 75 30 30 31 33 5c 75 30 30 31 34 5c 75 30 30 31 35 5c 75 30 30 31 36 5c 75 30 30 31 37 5c 75 30 30 31 38 5c 75 30 30 31 39 5c 75 30 30 31 61 5c 75 30 30 31 62 5c 75 30 30 31 63 5c 75 30 30 31 64 5c 75 30 30 31 65 5c 75 30 30 31 66 c3 a9 f0 9f 98 80 22")) : String}

# LAW: that text, read back, is the string the writer started with.
law json_encode_str_read_back:
  {Json.flat(Utf8.encode(Json.encode(Json.Str{SCon{Chr{34}, SCon{Chr{92}, SCon{Chr{0}, SCon{Chr{1}, SCon{Chr{2}, SCon{Chr{3}, SCon{Chr{4}, SCon{Chr{5}, SCon{Chr{6}, SCon{Chr{7}, SCon{Chr{8}, SCon{Chr{9}, SCon{Chr{10}, SCon{Chr{11}, SCon{Chr{12}, SCon{Chr{13}, SCon{Chr{14}, SCon{Chr{15}, SCon{Chr{16}, SCon{Chr{17}, SCon{Chr{18}, SCon{Chr{19}, SCon{Chr{20}, SCon{Chr{21}, SCon{Chr{22}, SCon{Chr{23}, SCon{Chr{24}, SCon{Chr{25}, SCon{Chr{26}, SCon{Chr{27}, SCon{Chr{28}, SCon{Chr{29}, SCon{Chr{30}, SCon{Chr{31}, SCon{Chr{233}, SCon{Chr{128512}, SNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}))) == Some{Map.set(&2, String, Map.new(&2, String), "", SCon{Chr{34}, SCon{Chr{92}, SCon{Chr{0}, SCon{Chr{1}, SCon{Chr{2}, SCon{Chr{3}, SCon{Chr{4}, SCon{Chr{5}, SCon{Chr{6}, SCon{Chr{7}, SCon{Chr{8}, SCon{Chr{9}, SCon{Chr{10}, SCon{Chr{11}, SCon{Chr{12}, SCon{Chr{13}, SCon{Chr{14}, SCon{Chr{15}, SCon{Chr{16}, SCon{Chr{17}, SCon{Chr{18}, SCon{Chr{19}, SCon{Chr{20}, SCon{Chr{21}, SCon{Chr{22}, SCon{Chr{23}, SCon{Chr{24}, SCon{Chr{25}, SCon{Chr{26}, SCon{Chr{27}, SCon{Chr{28}, SCon{Chr{29}, SCon{Chr{30}, SCon{Chr{31}, SCon{Chr{233}, SCon{Chr{128512}, SNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}})} : Maybe<&2, Map<&2, String>>}

# LAW: an object the writer made reads back as its members, under their own names: an
# escaped name, an escaped string, a number's text, a flag, null as empty text, and an
# array's elements under their indices with its count.
law json_encode_obj_read_back:
  {Json.obj(Utf8.encode(Json.encode(Json.Obj{[Json.field("s", Json.Str{SCon{Chr{34}, SCon{Chr{10}, SNil{}}}}), Json.field("n", Json.Num{"-1.5e+3"}), Json.field("f", Json.Flag{False{}}), Json.field("z", Json.Null{}), Json.field("a", Json.Arr{[Json.Num{"1"}, Json.Num{"2"}]}), Json.field(SCon{Chr{34}, SCon{Chr{10}, SNil{}}}, Json.Flag{True{}})]}))) == Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), SCon{Chr{34}, SCon{Chr{10}, SNil{}}}, "true"), "z", ""), "f", "false"), "n", "-1.5e+3"), "a.#", "2"), "a.1", "2"), "a.0", "1"), "s", SCon{Chr{34}, SCon{Chr{10}, SNil{}}}) : Map<&2, String>}

# LAW: a number reads back as the text it was written with, so nothing rounds it.
law json_read_number_text:
  {Json.flat(Bytes.of_ascii("{\"n\":-1.5e+3}")) == Some{Map.set(&2, String, Map.new(&2, String), "n", "-1.5e+3")} : Maybe<&2, Map<&2, String>>}

# LAW: a surrogate pair escapes one character: \ud83d\ude00 is U+1F600.
law json_read_surrogate_pair:
  {Json.flat(Bytes.of_hex("22 5c 75 64 38 33 64 5c 75 64 65 30 30 22")) == Some{Map.set(&2, String, Map.new(&2, String), "", SCon{Chr{128512}, SNil{}})} : Maybe<&2, Map<&2, String>>}

# LAW: half a surrogate pair becomes U+FFFD, the replacement the module documents, rather
# than a claim that the document is valid text.
law json_read_lone_surrogate:
  {Json.flat(Bytes.of_hex("22 5c 75 64 38 30 30 22")) == Some{Map.set(&2, String, Map.new(&2, String), "", SCon{Chr{65533}, SNil{}})} : Maybe<&2, Map<&2, String>>}

# LAW: an unterminated string makes the whole document invalid.
law json_read_unterminated_string:
  {Json.flat(Bytes.of_ascii("{\"a\":\"x")) == None{} : Maybe<&2, Map<&2, String>>}

# LAW: a trailing comma in an object makes the whole document invalid.
law json_read_trailing_comma:
  {Json.flat(Bytes.of_ascii("{\"a\":1,}")) == None{} : Maybe<&2, Map<&2, String>>}

# LAW: a trailing comma in an array makes the whole document invalid.
law json_read_trailing_comma_array:
  {Json.flat(Bytes.of_ascii("[1,]")) == None{} : Maybe<&2, Map<&2, String>>}

# LAW: a raw control character below 0x20 inside a string makes the whole document
# invalid: it has to be escaped.
law json_read_raw_control:
  {Json.flat(Bytes.of_hex("22 01 22")) == None{} : Maybe<&2, Map<&2, String>>}

# LAW: a number with a leading zero is refused, so 01 never reads as a number.
law json_read_leading_zero:
  {Json.flat(Bytes.of_ascii("[01]")) == None{} : Maybe<&2, Map<&2, String>>}

# LAW: sixteen nested arrays are read and not refused, the scalar at the bottom under all
# sixteen indices and every enclosing array recording its own count: the reader keeps its
# open containers on an explicit stack, so depth costs it no stack.
law json_read_deep:
  {Json.flat(Bytes.of_ascii("[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]")) == Some{Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), "#", "1"), "0.#", "1"), "0.0.#", "1"), "0.0.0.#", "1"), "0.0.0.0.#", "1"), "0.0.0.0.0.#", "1"), "0.0.0.0.0.0.#", "1"), "0.0.0.0.0.0.0.#", "1"), "0.0.0.0.0.0.0.0.#", "1"), "0.0.0.0.0.0.0.0.0.#", "1"), "0.0.0.0.0.0.0.0.0.0.#", "1"), "0.0.0.0.0.0.0.0.0.0.0.#", "1"), "0.0.0.0.0.0.0.0.0.0.0.0.#", "1"), "0.0.0.0.0.0.0.0.0.0.0.0.0.#", "1"), "0.0.0.0.0.0.0.0.0.0.0.0.0.0.#", "1"), "0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.#", "1"), "0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0", "1")} : Maybe<&2, Map<&2, String>>}

# LAW: the same sixteen containers left unclosed are refused, not read as a document.
law json_read_deep_unclosed:
  {Json.flat(Bytes.of_ascii("[[[[[[[[[[[[[[[[")) == None{} : Maybe<&2, Map<&2, String>>}

# LAW: the elements of the array at a named key are one row each, which is the shape an
# actions/runs envelope is read with.
law json_rows_at:
  {Json.rows.at(Bytes.of_ascii("{\"total_count\":2,\"workflow_runs\":[{\"id\":5},{\"id\":6}]}"), "workflow_runs") == [Map.set(&2, String, Map.new(&2, String), "id", "5"), Map.set(&2, String, Map.new(&2, String), "id", "6")] : List<&2, Map<&2, String>>}

# LAW: a member under a non-empty prefix is answered under prefix.member, the dotted key
# every command reads its rows by.
law json_child_under_prefix:
  for c: Char
  for t: String
  for k: String
  {Json.child(SCon{c, t}, k) == SCon{c, t} ++ "." ++ k : String}

# end json

# url [url]
# ---------

# parse: an http or https URL out of text

# LAW: parsing an https URL fills in the port https answers on, 443.
law url_parse_https_port:
  {Url.parse("https://example.com/x") == Some{Url.Url{"https", "example.com", 443, "/x"}} : Maybe<&2, Url.Url>}

# LAW: parsing an http URL fills in port 80, and a URL with no path gets the root as its path.
law url_parse_http_port:
  {Url.parse("http://a") == Some{Url.Url{"http", "a", 80, "/"}} : Maybe<&2, Url.Url>}

# LAW: parsing folds a scheme and a host to lowercase, so a URL carries them in one spelling.
law url_parse_folds_case:
  {Url.parse("HTTPS://Example.COM/") == Some{Url.Url{"https", "example.com", 443, "/"}} : Maybe<&2, Url.Url>}

# LAW: case never decides what URL a text names: a scheme and a host compare lowercased.
law url_parse_case_insensitive:
  {Url.parse("HTTPS://Example.COM/x") == Url.parse("https://example.com/x") : Maybe<&2, Url.Url>}

# LAW: spelling out the port a scheme answers on gives the same URL as leaving it out.
law url_parse_default_port_equal:
  {Url.parse("https://a:443/x") == Url.parse("https://a/x") : Maybe<&2, Url.Url>}

# LAW: an explicit port is kept as it is written.
law url_parse_port:
  {Url.parse("http://a:8080/x") == Some{Url.Url{"http", "a", 8080, "/x"}} : Maybe<&2, Url.Url>}

# LAW: a port that is written but empty is the scheme's default port.
law url_parse_empty_port:
  {Url.parse("http://a:/x") == Some{Url.Url{"http", "a", 80, "/x"}} : Maybe<&2, Url.Url>}

# LAW: an IPv6 host keeps no brackets and is folded like any other host.
law url_parse_ipv6:
  {Url.parse("http://[2001:DB8::1]:8080/x") == Some{Url.Url{"http", "2001:db8::1", 8080, "/x"}} : Maybe<&2, Url.Url>}

# LAW: a query is kept and a fragment is dropped.
law url_parse_drops_fragment:
  {Url.parse("http://a/b?q=1#frag") == Some{Url.Url{"http", "a", 80, "/b?q=1"}} : Maybe<&2, Url.Url>}

# LAW: a query that is only a question mark is kept as an empty query.
law url_parse_empty_query:
  {Url.parse("http://a/b?") == Some{Url.Url{"http", "a", 80, "/b?"}} : Maybe<&2, Url.Url>}

# LAW: a query with no path before it hangs off the root.
law url_parse_query_no_path:
  {Url.parse("http://a?q") == Some{Url.Url{"http", "a", 80, "/?q"}} : Maybe<&2, Url.Url>}

# LAW: a URL carrying a name and a password is refused: userinfo is not understood.
law url_parse_userinfo_refused:
  {Url.parse("https://user:pass@h/x") == None{} : Maybe<&2, Url.Url>}

# LAW: a URL carrying only a name before the host is refused too.
law url_parse_user_only_refused:
  {Url.parse("https://u@h/") == None{} : Maybe<&2, Url.Url>}

# LAW: a scheme that is not http or https is refused.
law url_parse_scheme_refused:
  {Url.parse("ftp://h/x") == None{} : Maybe<&2, Url.Url>}

# LAW: a reference that names a scheme and nothing else is refused, since http and https need a host.
law url_parse_no_authority_refused:
  {Url.parse("javascript:alert(1)") == None{} : Maybe<&2, Url.Url>}

# LAW: a port past 65535 is refused.
law url_parse_port_refused:
  {Url.parse("https://h:99999/") == None{} : Maybe<&2, Url.Url>}

# LAW: a port that is not a number is refused.
law url_parse_bad_port_refused:
  {Url.parse("http://a:b/") == None{} : Maybe<&2, Url.Url>}

# LAW: a URL with an empty host is refused.
law url_parse_empty_host_refused:
  {Url.parse("https:///x") == None{} : Maybe<&2, Url.Url>}

# LAW: a URL with no authority at all is refused.
law url_parse_no_host_refused:
  {Url.parse("http://") == None{} : Maybe<&2, Url.Url>}

# LAW: a URL with no scheme is refused.
law url_parse_no_scheme_refused:
  {Url.parse("/a/b") == None{} : Maybe<&2, Url.Url>}

# LAW: a space refuses the whole URL, whatever the rest of the text holds.
law url_parse_space_refused:
  for +cs: List<&2, Char>
  {Url.parse("http://a/ " ++ String.from_list(cs)) == None{} : Maybe<&2, Url.Url>}

# LAW: a control character refuses the whole URL, whatever the rest of the text holds.
law url_parse_control_refused:
  for +cs: List<&2, Char>
  {Url.parse("http://a/" ++ SCon{Chr{9}, String.from_list(cs)}) == None{} : Maybe<&2, Url.Url>}

# show, the Host header, and reading a URL back from its text

# LAW: showing a URL leaves the port out when it is the one the scheme answers on.
law url_show_default_port:
  {Url.show(Url.Url{"http", "a", 80, "/x"}) == "http://a/x" : String}

# LAW: showing a URL keeps a port that is not the scheme's default.
law url_show_port:
  {Url.show(Url.Url{"https", "h", 8443, "/x"}) == "https://h:8443/x" : String}

# LAW: showing a URL puts an IPv6 host back in brackets.
law url_show_ipv6:
  {Url.show(Url.Url{"http", "::1", 8080, "/"}) == "http://[::1]:8080/" : String}

# LAW: showing a URL writes its path and query back unchanged, whatever they hold.
law url_show_target:
  for +t: String
  {Url.show(Url.Url{"http", "a", 80, t}) == "http://a" ++ t : String}

# LAW: showing a URL and parsing that text back gives the same URL.
law url_parse_show_https:
  {Url.parse(Url.show(Url.Url{"https", "example.com", 443, "/x?q=1"})) == Some{Url.Url{"https", "example.com", 443, "/x?q=1"}} : Maybe<&2, Url.Url>}

# LAW: showing a URL and parsing that text back gives the same URL when a port is written too.
law url_parse_show_port:
  {Url.parse(Url.show(Url.Url{"https", "h", 8443, "/x"})) == Some{Url.Url{"https", "h", 8443, "/x"}} : Maybe<&2, Url.Url>}

# LAW: showing a URL and parsing that text back gives the same URL for an IPv6 host.
law url_parse_show_ipv6:
  {Url.parse(Url.show(Url.Url{"http", "::1", 8080, "/x"})) == Some{Url.Url{"http", "::1", 8080, "/x"}} : Maybe<&2, Url.Url>}

# LAW: the Host header is the bare host when the port is the scheme's default.
law url_host_header_default:
  {Url.host_header(Url.Url{"https", "a", 443, "/x"}) == "a" : String}

# LAW: the Host header spells a port out when it is not the scheme's default.
law url_host_header_port:
  {Url.host_header(Url.Url{"https", "a", 8443, "/x"}) == "a:8443" : String}

# LAW: the Host header keeps an IPv6 host in brackets.
law url_host_header_ipv6:
  {Url.host_header(Url.Url{"http", "::1", 8080, "/x"}) == "[::1]:8080" : String}

# origin

# LAW: a URL's origin is its scheme, host and port, so no path or query changes it.
law url_origin_ignores_target:
  for +t: String
  {Url.origin(Url.Url{"https", "a", 443, t}) == "https://a:443" : String}

# LAW: an origin always spells its port out, the default one included.
law url_origin_default_port_spelled:
  {Url.origin(Url.Url{"http", "a", 80, "/x"}) == "http://a:80" : String}

# LAW: URLs on different ports have different origins.
law url_origin_differs_port:
  {Bool.not(String.eq(Url.origin(Url.Url{"https", "a", 443, "/"}), Url.origin(Url.Url{"https", "a", 8443, "/"}))) == True{} : Bool}

# LAW: URLs on different hosts have different origins.
law url_origin_differs_host:
  {Bool.not(String.eq(Url.origin(Url.Url{"https", "a", 443, "/"}), Url.origin(Url.Url{"https", "b", 443, "/"}))) == True{} : Bool}

# LAW: URLs on different schemes have different origins, even on one port.
law url_origin_differs_scheme:
  {Bool.not(String.eq(Url.origin(Url.Url{"https", "a", 443, "/"}), Url.origin(Url.Url{"http", "a", 443, "/"}))) == True{} : Bool}

# dots: RFC 3986 section 5.2.4

# LAW: removing dot segments never lifts a path above the root: the path always starts at the root.
law url_dots_rooted:
  for +p: String
  {String.starts_with(Url.url.dots(p), "/") == True{} : Bool}

# resolve: RFC 3986 section 5.2, and the examples of its section 5.4

# LAW: an empty reference resolves to the base URL itself.
law url_resolve_empty:
  for +u: Url.Url
  {Url.resolve(u, "") == Some{u} : Maybe<&2, Url.Url>}

# LAW: a reference that is only a fragment resolves to the base URL, with the fragment dropped.
law url_resolve_fragment:
  for +u: Url.Url
  {Url.resolve(u, "#s") == Some{u} : Maybe<&2, Url.Url>}

# LAW: a reference that is a whole URL wins over the base it was resolved against.
law url_resolve_absolute_wins:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "https://other.example/x") == Some{Url.Url{"https", "other.example", 443, "/x"}} : Maybe<&2, Url.Url>}

# LAW: a reference that names only a host and a port keeps the base's scheme.
law url_resolve_net_port:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "//g:8080/x") == Some{Url.Url{"http", "g", 8080, "/x"}} : Maybe<&2, Url.Url>}

# LAW: a reference that is a whole URL arrives with its dot segments removed, like any other reference.
law url_resolve_absolute_dots:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "http://a/b/../c") == Some{Url.Url{"http", "a", 80, "/c"}} : Maybe<&2, Url.Url>}

# LAW: a reference that names only a host arrives with its dot segments removed too.
law url_resolve_net_dots:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "//h/a/./b") == Some{Url.Url{"http", "h", 80, "/a/b"}} : Maybe<&2, Url.Url>}

# LAW: a query-only reference replaces the base's query.
law url_resolve_query_only:
  {Url.resolve(Url.Url{"https", "a", 443, "/b"}, "?q") == Some{Url.Url{"https", "a", 443, "/b?q"}} : Maybe<&2, Url.Url>}

# LAW: a path resolved against an API base lands under that base, which is what cha asks for.
law url_resolve_api_path:
  {Url.resolve(Url.Url{"https", "gitea.example", 443, "/api/v1/"}, "repos/o/n/issues?limit=50") == Some{Url.Url{"https", "gitea.example", 443, "/api/v1/repos/o/n/issues?limit=50"}} : Maybe<&2, Url.Url>}

# RFC 3986 section 5.4, against its base http://a/b/c/d;p?q. The examples are known answers:
# the module's own resolve decides each one, and its canonical text fills in port 80, keeps a
# query, and drops a fragment.

# LAW: parsing the base URL the RFC's resolution examples use gives the URL they resolve against.
law url_parse_rfc_base:
  {Url.parse("http://a/b/c/d;p?q") == Some{Url.Url{"http", "a", 80, "/b/c/d;p?q"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1: the reference "g:h" is refused, since g is not a scheme this module speaks.
law url_rfc_5_4_1_g_h:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g:h") == None{} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g" against http://a/b/c/d;p?q answers http://a/b/c/g.
law url_rfc_5_4_1_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g") == Some{Url.Url{"http", "a", 80, "/b/c/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "./g" against http://a/b/c/d;p?q answers http://a/b/c/g.
law url_rfc_5_4_1_dot_slash_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "./g") == Some{Url.Url{"http", "a", 80, "/b/c/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g/" against http://a/b/c/d;p?q answers http://a/b/c/g/.
law url_rfc_5_4_1_g_slash:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g/") == Some{Url.Url{"http", "a", 80, "/b/c/g/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "/g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_1_slash_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "/g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "//g" against http://a/b/c/d;p?q answers http://g/.
law url_rfc_5_4_1_scheme_relative_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "//g") == Some{Url.Url{"http", "g", 80, "/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "?y" against http://a/b/c/d;p?q answers http://a/b/c/d;p?y.
law url_rfc_5_4_1_query:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "?y") == Some{Url.Url{"http", "a", 80, "/b/c/d;p?y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "?y#s" against http://a/b/c/d;p?q answers http://a/b/c/d;p?y: the fragment is dropped.
law url_rfc_5_4_1_query_fragment:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "?y#s") == Some{Url.Url{"http", "a", 80, "/b/c/d;p?y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g?y" against http://a/b/c/d;p?q answers http://a/b/c/g?y.
law url_rfc_5_4_1_g_query:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g?y") == Some{Url.Url{"http", "a", 80, "/b/c/g?y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "#s" against http://a/b/c/d;p?q answers http://a/b/c/d;p?q: the fragment is dropped.
law url_rfc_5_4_1_fragment:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "#s") == Some{Url.Url{"http", "a", 80, "/b/c/d;p?q"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g#s" against http://a/b/c/d;p?q answers http://a/b/c/g: the fragment is dropped.
law url_rfc_5_4_1_g_fragment:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g#s") == Some{Url.Url{"http", "a", 80, "/b/c/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g?y#s" against http://a/b/c/d;p?q answers http://a/b/c/g?y: the fragment is dropped.
law url_rfc_5_4_1_g_query_fragment:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g?y#s") == Some{Url.Url{"http", "a", 80, "/b/c/g?y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference ";x" against http://a/b/c/d;p?q answers http://a/b/c/;x.
law url_rfc_5_4_1_semicolon_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, ";x") == Some{Url.Url{"http", "a", 80, "/b/c/;x"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g;x" against http://a/b/c/d;p?q answers http://a/b/c/g;x.
law url_rfc_5_4_1_g_semicolon_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g;x") == Some{Url.Url{"http", "a", 80, "/b/c/g;x"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "g;x?y#s" against http://a/b/c/d;p?q answers http://a/b/c/g;x?y.
law url_rfc_5_4_1_g_semicolon_x_query_fragment:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g;x?y#s") == Some{Url.Url{"http", "a", 80, "/b/c/g;x?y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "" against http://a/b/c/d;p?q answers http://a/b/c/d;p?q.
law url_rfc_5_4_1_empty:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "") == Some{Url.Url{"http", "a", 80, "/b/c/d;p?q"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "." against http://a/b/c/d;p?q answers http://a/b/c/.
law url_rfc_5_4_1_dot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, ".") == Some{Url.Url{"http", "a", 80, "/b/c/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "./" against http://a/b/c/d;p?q answers http://a/b/c/.
law url_rfc_5_4_1_dot_slash:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "./") == Some{Url.Url{"http", "a", 80, "/b/c/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference ".." against http://a/b/c/d;p?q answers http://a/b/.
law url_rfc_5_4_1_dotdot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "..") == Some{Url.Url{"http", "a", 80, "/b/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "../" against http://a/b/c/d;p?q answers http://a/b/.
law url_rfc_5_4_1_dotdot_slash:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../") == Some{Url.Url{"http", "a", 80, "/b/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "../g" against http://a/b/c/d;p?q answers http://a/b/g.
law url_rfc_5_4_1_dotdot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../g") == Some{Url.Url{"http", "a", 80, "/b/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "../.." against http://a/b/c/d;p?q answers http://a/.
law url_rfc_5_4_1_dotdot_dotdot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../..") == Some{Url.Url{"http", "a", 80, "/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "../../" against http://a/b/c/d;p?q answers http://a/.
law url_rfc_5_4_1_dotdot_dotdot_slash:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../../") == Some{Url.Url{"http", "a", 80, "/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.1, reference "../../g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_1_dotdot_dotdot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../../g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "../../../g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_2_dotdot_x3_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../../../g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "../../../../g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_2_dotdot_x4_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "../../../../g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "/./g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_2_slash_dot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "/./g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "/../g" against http://a/b/c/d;p?q answers http://a/g.
law url_rfc_5_4_2_slash_dotdot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "/../g") == Some{Url.Url{"http", "a", 80, "/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g." against http://a/b/c/d;p?q answers http://a/b/c/g..
law url_rfc_5_4_2_g_dot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g.") == Some{Url.Url{"http", "a", 80, "/b/c/g."}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference ".g" against http://a/b/c/d;p?q answers http://a/b/c/.g.
law url_rfc_5_4_2_dot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, ".g") == Some{Url.Url{"http", "a", 80, "/b/c/.g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g.." against http://a/b/c/d;p?q answers http://a/b/c/g...
law url_rfc_5_4_2_g_dotdot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g..") == Some{Url.Url{"http", "a", 80, "/b/c/g.."}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "..g" against http://a/b/c/d;p?q answers http://a/b/c/..g.
law url_rfc_5_4_2_dotdot_g_:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "..g") == Some{Url.Url{"http", "a", 80, "/b/c/..g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "./../g" against http://a/b/c/d;p?q answers http://a/b/g.
law url_rfc_5_4_2_dot_dotdot_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "./../g") == Some{Url.Url{"http", "a", 80, "/b/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "./g/." against http://a/b/c/d;p?q answers http://a/b/c/g/.
law url_rfc_5_4_2_dot_g_dot:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "./g/.") == Some{Url.Url{"http", "a", 80, "/b/c/g/"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g/./h" against http://a/b/c/d;p?q answers http://a/b/c/g/h.
law url_rfc_5_4_2_g_dot_h:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g/./h") == Some{Url.Url{"http", "a", 80, "/b/c/g/h"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g/../h" against http://a/b/c/d;p?q answers http://a/b/c/h.
law url_rfc_5_4_2_g_dotdot_h:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g/../h") == Some{Url.Url{"http", "a", 80, "/b/c/h"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g;x=1/./y" against http://a/b/c/d;p?q answers http://a/b/c/g;x=1/y.
law url_rfc_5_4_2_g_semicolon_x_1_dot_y:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g;x=1/./y") == Some{Url.Url{"http", "a", 80, "/b/c/g;x=1/y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g;x=1/../y" against http://a/b/c/d;p?q answers http://a/b/c/y.
law url_rfc_5_4_2_g_semicolon_x_1_dotdot_y:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g;x=1/../y") == Some{Url.Url{"http", "a", 80, "/b/c/y"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g?y/./x" against http://a/b/c/d;p?q answers http://a/b/c/g?y/./x.
law url_rfc_5_4_2_g_query_dot_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g?y/./x") == Some{Url.Url{"http", "a", 80, "/b/c/g?y/./x"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g?y/../x" against http://a/b/c/d;p?q answers http://a/b/c/g?y/../x.
law url_rfc_5_4_2_g_query_dotdot_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g?y/../x") == Some{Url.Url{"http", "a", 80, "/b/c/g?y/../x"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g#s/./x" against http://a/b/c/d;p?q answers http://a/b/c/g: the fragment is dropped.
law url_rfc_5_4_2_g_fragment_dot_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g#s/./x") == Some{Url.Url{"http", "a", 80, "/b/c/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2, reference "g#s/../x" against http://a/b/c/d;p?q answers http://a/b/c/g: the fragment is dropped.
law url_rfc_5_4_2_g_fragment_dotdot_x:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "g#s/../x") == Some{Url.Url{"http", "a", 80, "/b/c/g"}} : Maybe<&2, Url.Url>}

# LAW: RFC 3986 section 5.4.2: the reference "http:g" is refused, since this module will not read http without an authority.
law url_rfc_5_4_2_http_g:
  {Url.resolve(Url.Url{"http", "a", 80, "/b/c/d;p?q"}, "http:g") == None{} : Maybe<&2, Url.Url>}

# pct: percent-encoding a value for a path segment or a query

# LAW: percent-encoding keeps the unreserved characters of RFC 3986 as they are.
law url_pct_keeps_unreserved:
  {Url.pct(Bytes.of_ascii("AZaz09-._~")) == "AZaz09-._~" : String}

# LAW: percent-encoding escapes the path, query and fragment separators, so a value cannot end the path or add a segment to it.
law url_pct_separators:
  {Url.pct(Bytes.of_ascii("/?#")) == "%2F%3F%23" : String}

# LAW: percent-encoding escapes a percent sign itself, so a value cannot pass off an escape of its own.
law url_pct_percent:
  {Url.pct(Bytes.of_ascii("%2F")) == "%252F" : String}

# LAW: percent-encoding writes a space as an escape, never as itself.
law url_pct_space:
  {Url.pct(Bytes.of_ascii("a b")) == "a%20b" : String}

# LAW: percent-encoding writes every byte of text outside ASCII as escapes with uppercase hex digits.
law url_pct_utf8:
  {Url.pct(Bytes.of_hex("e8 8c b6")) == "%E8%8C%B6" : String}

# LAW: percent-encoding an empty byte list gives an empty string.
law url_pct_empty:
  {Url.pct(Bytes.of_hex("")) == "" : String}

# end url

# http1 [http1]
# -------------
# http1 writes the request and reads the response, so it is where cha's own bytes meet a
# peer's bytes. A refusal here is a security property, not a nicety: a header nobody named,
# or a body whose end two headers disagree on, is how a request is split and a response
# smuggled. Known-answer laws name their source. The response laws give the parser a room
# big enough for their response rather than the default 64 MiB: nothing about them turns on
# the default, and the kernel recheck cannot count to 64 MiB.

# LAW: (known answer) a GET with one header is exactly these bytes on the wire.
law http1_request_bytes:
  {Http1.request("GET", "example.com", "/x", [("X-Test", "1")], Nil{}) == Some{Bytes.of_ascii("GET /x HTTP/1.1\r\nHost: example.com\r\nX-Test: 1\r\nConnection: close\r\n\r\n")} : Maybe<&2, List<&2, U32>>}

# LAW: (known answer) a method that isn't a token is refused, so no method can end the
# request line early.
law http1_method_not_token:
  {Http1.request("GE T", "example.com", "/x", Nil{}, Nil{}) == None{} : Maybe<&2, List<&2, U32>>} & {Http1.request("GET\r", "example.com", "/x", Nil{}, Nil{}) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: a request target holding a CR or a LF is refused, so it can never start a header line.
law http1_target_ctl:
  for +p: String
  for +q: String
  {Http1.request("GET", "example.com", String.append(p, String.append("\r", q)), Nil{}, Nil{}) == None{} : Maybe<&2, List<&2, U32>>} & {Http1.request("GET", "example.com", String.append(p, String.append("\n", q)), Nil{}, Nil{}) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: a host holding a CR or a LF is refused, so it can never start a header of its own.
law http1_host_ctl:
  for +p: String
  for +q: String
  {Http1.request("GET", String.append(p, String.append("\r", q)), "/x", Nil{}, Nil{}) == None{} : Maybe<&2, List<&2, U32>>} & {Http1.request("GET", String.append(p, String.append("\n", q)), "/x", Nil{}, Nil{}) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: a header value holding a CR or a LF is refused, so it can never end its header line.
law http1_value_ctl:
  for +p: String
  for +q: String
  {Http1.request("GET", "example.com", "/x", [("x", String.append(p, String.append("\r", q)))], Nil{}) == None{} : Maybe<&2, List<&2, U32>>} & {Http1.request("GET", "example.com", "/x", [("x", String.append(p, String.append("\n", q)))], Nil{}) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: a header name with a byte outside the RFC 9110 token set is refused, so no name can
# mean one header to the writer and another to the peer.
law http1_name_not_token:
  for +p: String
  for +q: String
  {Http1.request("GET", "example.com", "/x", [(String.append(p, String.append(" ", q)), "v")], Nil{}) == None{} : Maybe<&2, List<&2, U32>>} & {Http1.request("GET", "example.com", "/x", [(String.append(p, String.append("\r", q)), "v")], Nil{}) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: (known answer) a header name with a byte outside the RFC 9110 token set is refused
# here too: a response header named "content-length " is not a content-length.
law http1_bad_header_name:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\ncontent-length : 5\r\n\r\n"))) == Http1.Bad{"bad header name"} : Http1.Step}

# LAW: (known answer) a header value holding a NUL is refused, so no NUL can hide the rest
# of a head.
law http1_value_nul:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.cat(Bytes.of_ascii("HTTP/1.1 200 OK\r\nx: a"), Bytes.cat([0], Bytes.of_ascii("b\r\n\r\n"))))) == Http1.Bad{"bad header value"} : Http1.Step}

# LAW: (known answer) bytes after a complete response are ignored, so nothing in the tail is
# read as a second response.
law http1_trailing_bytes:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhelloGET /evil HTTP/1.1\r\n\r\n"))) == Http1.Got{Http1.Resp{Http1.Head{200, [("content-length", "5")]}, Bytes.of_ascii("hello")}} : Http1.Step}

# LAW: (known answer) a status line that isn't HTTP/1.x followed by three digits is refused.
law http1_status_not_http:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/2 200 OK\r\n\r\n"))) == Http1.Bad{"bad status line"} : Http1.Step} & {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("200 OK\r\n\r\n"))) == Http1.Bad{"bad status line"} : Http1.Step} & {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 20 OK\r\n\r\n"))) == Http1.Bad{"bad status line"} : Http1.Step}

# LAW: (known answer) a response with both a transfer-encoding and a content-length is
# refused, as RFC 9112 section 6.3 says: the two are two readings of where the body ends.
law http1_te_and_cl:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 6\r\n\r\n0\r\n\r\n"))) == Http1.Bad{"both transfer-encoding and content-length"} : Http1.Step}

# LAW: (known answer) two content-length headers that disagree are refused, so no body has
# two ends.
law http1_cl_differs:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\nhello"))) == Http1.Bad{"content-length headers differ"} : Http1.Step}

# LAW: (known answer) a content-length repeated with the same value is that length, so
# refusing two that differ is not a blanket refusal.
law http1_cl_agree:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello"))) == Http1.Got{Http1.Resp{Http1.Head{200, [("content-length", "5"), ("content-length", "5")]}, Bytes.of_ascii("hello")}} : Http1.Step}

# LAW: (known answer) a header line folded onto the next one is refused, so a head can't be
# read two ways.
law http1_folded_header:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nx: a\r\n\tb\r\n\r\n"))) == Http1.Bad{"folded header"} : Http1.Step}

# LAW: (known answer) a content-length that isn't all digits is refused.
law http1_cl_not_digits:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 5x\r\n\r\nhello"))) == Http1.Bad{"bad content-length"} : Http1.Step} & {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\n"))) == Http1.Bad{"bad content-length"} : Http1.Step}

# LAW: (known answer: RFC 7230 section 7.1) a chunked body decodes to the bytes it carries.
law http1_chunked_body:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n"))) == Http1.Got{Http1.Resp{Http1.Head{200, [("transfer-encoding", "chunked")]}, Bytes.of_ascii("Wikipedia")}} : Http1.Step}

# LAW: (known answer) a chunk size that isn't hex is refused.
law http1_chunk_not_hex:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nz\r\nhello\r\n0\r\n\r\n"))) == Http1.Bad{"bad chunk size"} : Http1.Step}

# LAW: (known answer) a header is stored and looked up without regard to its case.
law http1_header_case:
  {Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 0\r\n\r\n"))) == Http1.Got{Http1.Resp{Http1.Head{200, [("content-type", "text/html"), ("content-length", "0")]}, Nil{}}} : Http1.Step} & {Http1.header(Http1.Head{200, [("content-type", "text/html")]}, "CONTENT-TYPE") == "text/html" : String}

# LAW: (known answer) a response cut in two parses to what it parses to whole, wherever the
# cut falls: in the status line, in the head, or in the body.
law http1_feed_split:
  {Http1.step(Http1.feed(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.take(Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"), 10n)), Bytes.drop(Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"), 10n))) == Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"))) : Http1.Step} & {Http1.step(Http1.feed(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.take(Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"), 25n)), Bytes.drop(Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"), 25n))) == Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"))) : Http1.Step} & {Http1.step(Http1.feed(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.take(Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"), 39n)), Bytes.drop(Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"), 39n))) == Http1.step(Http1.feed(Http1.parser.room(False{}, 200n), Bytes.of_ascii("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"))) : Http1.Step}

# end http1

# time, width [time]
# ------------------
# Both modules decide every result with U32 arithmetic and comparison, and bend reduces those
# only on a constructor, so a claim over a symbolic U32 is stuck at its first division or
# comparison. Base proves commutativity of addition and nothing else about a 32-bit word. So
# the calendar and the width table are pinned by known answers: each law names its inputs, and
# each side of it is a closed term. Where the shape of a claim could hide a wrong answer, the
# law carries its neighbours too (the two ends of a range, or the whole range at once).

# LAW: showing the epoch writes the RFC 3339 text 1970-01-01T00:00:00Z.
law time_show_epoch:
  {Time.show(0) == "1970-01-01T00:00:00Z" : String}

# LAW: the day count and the civil date are inverse at the epoch: 1970-01-01 is day 0, and day
# 0 is 1970-01-01.
law time_civil_days_epoch:
  {Time.days(1970, 1, 1) == 0 : U32} & {Time.civil(0) == (1970, 1, 1) : U32 & U32 & U32}

# LAW: the two are inverse on a leap day: 2000-02-29 is day 11016, and day 11016 is 2000-02-29.
law time_civil_days_leap:
  {Time.days(2000, 2, 29) == 11016 : U32} & {Time.civil(11016) == (2000, 2, 29) : U32 & U32 & U32}

# LAW: the two are inverse on 2100-02-28, the last day of February in a century that skips its
# leap day: it is day 47540, and day 47540 is 2100-02-28.
law time_civil_days_century:
  {Time.days(2100, 2, 28) == 47540 : U32} & {Time.civil(47540) == (2100, 2, 28) : U32 & U32 & U32}

# LAW: showing a leap day, a skipped century's last February day, the second a signed 32-bit
# clock overflows at, and the last instant a U32 holds, each writes its RFC 3339 text.
law time_show_known:
  {Time.show(951782400) == "2000-02-29T00:00:00Z" : String} &
  {Time.show(4107456000) == "2100-02-28T00:00:00Z" : String} &
  {Time.show(2147483647) == "2038-01-19T03:14:07Z" : String} &
  {Time.show(4294967295) == "2106-02-07T06:28:15Z" : String}

# LAW: parsing what showing wrote gives the instant back, at the epoch, a leap day, a skipped
# century's last February day, the 2038 overflow and the last second a U32 holds.
law time_parse_show_roundtrip:
  {Time.parse(Time.show(0)) == Some{0} : Maybe<&2, U32>} &
  {Time.parse(Time.show(951782400)) == Some{951782400} : Maybe<&2, U32>} &
  {Time.parse(Time.show(4107456000)) == Some{4107456000} : Maybe<&2, U32>} &
  {Time.parse(Time.show(2147483647)) == Some{2147483647} : Maybe<&2, U32>} &
  {Time.parse(Time.show(4294967295)) == Some{4294967295} : Maybe<&2, U32>}

# LAW: a stamp that names a day or a month or an hour that doesn't exist is refused: February
# 29 in 2023, April 31, month 13 and hour 24.
law time_parse_refuses:
  {Time.parse("2023-02-29T00:00:00Z") == None{} : Maybe<&2, U32>} &
  {Time.parse("2023-04-31T00:00:00Z") == None{} : Maybe<&2, U32>} &
  {Time.parse("2023-13-01T00:00:00Z") == None{} : Maybe<&2, U32>} &
  {Time.parse("2023-01-01T24:00:00Z") == None{} : Maybe<&2, U32>}

# LAW: an offset is applied to the wall time before the instant is taken: 09:00 at -03:00 is
# 12:00 UTC, and 09:00 at +05:30 is 03:30 UTC.
law time_parse_offset:
  {Time.parse("2026-09-30T09:00:00-03:00") == Some{1790769600} : Maybe<&2, U32>} &
  {Time.parse("2026-09-30T09:00:00+05:30") == Some{1790739000} : Maybe<&2, U32>}

# LAW: February has 29 days in 2024 and 2000, and 28 in 1900 and 2100: a leap year is
# divisible by four, but not by a hundred, unless by four hundred.
law time_february_len:
  {Time.month.len(2024, 2) == 29 : U32} &
  {Time.month.len(2000, 2) == 29 : U32} &
  {Time.month.len(1900, 2) == 28 : U32} &
  {Time.month.len(2100, 2) == 28 : U32}

# LAW: every printable ASCII character is one column: the run from space to tilde is 95 columns
# wide, and the two ends of it are one column each.
law width_ascii_printable:
  {Width.text(" !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\u{5c}]^_`abc" ++
    "defghijklmnopqrstuvwxyz{|}~") == 95 : U32} &
  {Width.char(32) == 1 : U32} & {Width.char(126) == 1 : U32}

# LAW: every C0 control, every C1 control and DEL take no column.
law width_ascii_controls:
  {Width.text("\u{0}\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{9}\u{a}\u{b}\u{c}\u{d}\u{e}\u{f}" ++
    "\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{1a}\u{1b}\u{1c}\u{1d}" ++
    "\u{1e}\u{1f}\u{7f}\u{80}\u{81}\u{82}\u{83}\u{84}\u{85}\u{86}\u{87}\u{88}\u{89}\u{8a}" ++
    "\u{8b}\u{8c}\u{8d}\u{8e}\u{8f}\u{90}\u{91}\u{92}\u{93}\u{94}\u{95}\u{96}\u{97}\u{98}" ++
    "\u{99}\u{9a}\u{9b}\u{9c}\u{9d}\u{9e}\u{9f}") == 0 : U32}

# LAW: a combining mark (U+0300) takes no column, so a letter carrying its accent is one column.
law width_combining_mark:
  {Width.char(768) == 0 : U32} & {Width.text("e\u{301}") == 1 : U32}

# LAW: the East Asian wide blocks and an emoji take two columns: a Han character (U+4E00), a
# Hangul syllable (U+AC00) and an emoji (U+1F600).
law width_wide:
  {Width.char(19968) == 2 : U32} & {Width.char(44032) == 2 : U32} & {Width.char(128512) == 2 : U32}

# LAW: widths add up when text sits side by side: "cha " is 4 columns, "茶" is 2, and the
# two together are 6; the same holds for "日本" and "語".
law width_text_concat:
  {Width.text("cha 茶") == (Width.text("cha ") + Width.text("茶") : U32) : U32} &
  {Width.text("日本語") == (Width.text("日本") + Width.text("語") : U32) : U32}

# end time

# sha2, chacha [hash]
# -------------------
# Known answers from the primary texts: the digests of FIPS 180-4 B.1, the HMAC of RFC 4231
# 4.2, and the ChaCha20 block, Poly1305 and AEAD of RFC 8439 2.3.2, 2.5.2 and 2.8.2. A cipher
# is not something a law can state from first principles, so it is pinned to what its document
# says it must produce. Each of those is one closed input, so the checker runs the code itself
# when it checks the law. The rest are over every input, on a code path that never reads the
# symbolic part.
#
# The AEAD's 2.8.2 known answer is not stated: the tag over the RFC's 114-byte plaintext costs
# the BendTT kernel (`--verdict`) more fuel than it has, and so does one seal and one open over
# a plaintext of 16 bytes. What the kernel can afford is the tag flip over an empty plaintext,
# below, which seals to the tag alone.

# The RFC 8439 2.8.2 key, nonce and additional data, which the AEAD laws below use.
def chacha_key_2_8_2() -> List<&2, U32>:
  Bytes.of_hex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")

def chacha_nonce_2_8_2() -> List<&2, U32>:
  Bytes.of_hex("070000004041424344454647")

def chacha_aad_2_8_2() -> List<&2, U32>:
  Bytes.of_hex("50515253c0c1c2c3c4c5c6c7")

# A 16-byte plaintext for the round trip. The RFC's own 114-byte one costs the kernel too much
# fuel, and so does the aad here: the round trip below seals without any.
def chacha_plain_16() -> List<&2, U32>:
  Bytes.of_ascii("sixteen bytes!!!")

# SHA-256, SHA-384 and SHA-512 (FIPS 180-4 B.1)
# ---------------------------------------------
# "abc" is the one-block example the standard prints for all three, the 56-byte message the one
# that tips the padding into a second block, and the empty message the digest every
# implementation is expected to print.

# LAW: SHA-256 of the empty message is the digest NIST publishes for it (FIPS 180-4 B.1).
law sha2_sha256_empty:
  {Sha2.hash(Sha2.S256{}, Nil{}) == Bytes.of_hex("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") : List<&2, U32>}

# LAW: SHA-256 of "abc" is the digest FIPS 180-4 B.1 lists for it.
law sha2_sha256_abc:
  {Sha2.hash(Sha2.S256{}, Bytes.of_ascii("abc")) == Bytes.of_hex("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") : List<&2, U32>}

# LAW: SHA-256 of FIPS 180-4 B.1's 56-byte message is the digest it lists for it, at the length
# that makes the padding push over into a second block.
law sha2_sha256_two_block:
  {Sha2.hash(Sha2.S256{}, Bytes.of_ascii("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")) == Bytes.of_hex("248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1") : List<&2, U32>}

# LAW: SHA-384 of "abc" is the digest FIPS 180-4 B.1 lists for it.
law sha2_sha384_abc:
  {Sha2.hash(Sha2.S384{}, Bytes.of_ascii("abc")) == Bytes.of_hex("cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7") : List<&2, U32>}

# LAW: SHA-512 of the empty message is the digest NIST publishes for it (FIPS 180-4 B.1).
law sha2_sha512_empty:
  {Sha2.hash(Sha2.S512{}, Nil{}) == Bytes.of_hex("cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e") : List<&2, U32>}

# LAW: SHA-512 of "abc" is the digest FIPS 180-4 B.1 lists for it.
law sha2_sha512_abc:
  {Sha2.hash(Sha2.S512{}, Bytes.of_ascii("abc")) == Bytes.of_hex("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f") : List<&2, U32>}

# Padding (FIPS 180-4 5.1.1)
# -------------------------

# LAW: a 55-byte message pads to one SHA-256 block, so the 0x80 and the length still fit in it.
law sha2_pad_55_one_block:
  {Bytes.len(Sha2.pad.to(Bytes.zeros(55n), 64n, 8n)) == 64 : U32}

# LAW: one byte more and the padding takes a second block.
law sha2_pad_56_two_blocks:
  {Bytes.len(Sha2.pad.to(Bytes.zeros(56n), 64n, 8n)) == 128 : U32}

# HMAC and HKDF (RFC 4231, RFC 5869)
# ----------------------------------

# LAW: HMAC-SHA-256 of RFC 4231 test case 1 is the MAC it lists.
law sha2_hmac_sha256_rfc4231_1:
  {Sha2.hmac(Sha2.S256{}, Bytes.of_hex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), Bytes.of_ascii("Hi There")) == Bytes.of_hex("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7") : List<&2, U32>}

# LAW: HKDF-Expand asked for no bytes answers none, whatever the secret and info are.
law sha2_expand_zero:
  for prk: List<&2, U32>
  for info: List<&2, U32>
  {Sha2.expand(Sha2.S256{}, prk, info, 0) == Nil{} : List<&2, U32>}

# ChaCha20, Poly1305 and the AEAD (RFC 8439)
# ------------------------------------------

# LAW: the ChaCha20 block function of RFC 8439 2.3.2 is the 64 bytes it lists.
law chacha20_block_rfc8439_2_3_2:
  {Chacha.block(Bytes.of_hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"), 1, Bytes.of_hex("000000090000004a00000000")) == Bytes.of_hex("10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4ed2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e") : List<&2, U32>}

# LAW: Poly1305 of RFC 8439 2.5.2's message is the tag it lists.
law chacha_poly1305_rfc8439_2_5_2:
  {Chacha.poly1305(Bytes.of_hex("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b"), Bytes.of_ascii("Cryptographic Forum Research Group")) == Bytes.of_hex("a8061dc1305136c6c22b8baf0c0127a9") : List<&2, U32>}

# LAW: sealing a message and opening it again gives the message back.
law chacha_aead_open_seal:
  {Chacha.open(chacha_key_2_8_2(), chacha_nonce_2_8_2(), Nil{}, Chacha.seal(chacha_key_2_8_2(), chacha_nonce_2_8_2(), Nil{}, chacha_plain_16())) == Some{chacha_plain_16()} : Maybe<&2, List<&2, U32>>}

# LAW: opening a message whose tag is one bit off is refused, not decrypted. An empty plaintext
# seals to the tag alone, so the mask turns over the last bit of that tag.
law chacha_aead_open_refuses_tag_flip:
  {Chacha.open(chacha_key_2_8_2(), chacha_nonce_2_8_2(), chacha_aad_2_8_2(), Bytes.xor(Chacha.seal(chacha_key_2_8_2(), chacha_nonce_2_8_2(), chacha_aad_2_8_2(), Nil{}), Bytes.cat(Bytes.zeros(15n), [1]))) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: a sealed message with no room for a tag is refused before anything is decrypted.
law chacha_aead_open_refuses_empty:
  for key: List<&2, U32>
  for nonce: List<&2, U32>
  for aad: List<&2, U32>
  {Chacha.open(key, nonce, aad, Nil{}) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: a sealed message one byte short of a tag is refused too, whatever the key, nonce and
# additional data are.
law chacha_aead_open_refuses_short:
  for key: List<&2, U32>
  for nonce: List<&2, U32>
  for aad: List<&2, U32>
  {Chacha.open(key, nonce, aad, Bytes.zeros(15n)) == None{} : Maybe<&2, List<&2, U32>>}

# end hash

# aes, x25519 [block]
# -------------------
# The block cipher, GCM around it, and the field arithmetic X25519 is built from. A law
# over every input is out of reach for a cipher, so these are the vectors of the documents
# that define the algorithms and the refusals that decide before a byte is encrypted.
# What GCM itself promises (McGrew and Viega's test cases with their tags, a sealed message
# opening back to its plaintext, a forged tag refused) is not here: every one of those needs
# GHASH, which the BendTT kernel runs out of fuel on, so they stay as lines in
# test/chaki_aes_check.bend. X25519's RFC 7748 vectors are left out for the same reason: one
# X25519 costs the checker more than a minute and its memory, so only the clamping it does
# to the scalar can be stated.

# LAW: the AES-128 key and block of FIPS-197 Appendix C.1 encrypt to the ciphertext the
# standard prints.
law aes_encrypt_fips_197_c1:
  {Aes.encrypt(Bytes.of_hex("000102030405060708090a0b0c0d0e0f"), Bytes.of_hex("00112233445566778899aabbccddeeff")) == Bytes.of_hex("69c4e0d86a7b0430d8cdb78070b4c55a") : List<&2, U32>}

# LAW: the AES-256 key and block of FIPS-197 Appendix C.3 encrypt to the ciphertext the
# standard prints.
law aes_encrypt_fips_197_c3:
  {Aes.encrypt(Bytes.of_hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"), Bytes.of_hex("00112233445566778899aabbccddeeff")) == Bytes.of_hex("8ea2b7ca516745bfeafc49904b496089") : List<&2, U32>}

# LAW: a key of a length this module does not take encrypts nothing, rather than something
# wrong.
law aes_encrypt_refuses_short_key:
  {Aes.encrypt(Bytes.of_hex("00010203"), Bytes.of_hex("00112233445566778899aabbccddeeff")) == Nil{} : List<&2, U32>}

# LAW: a message shorter than a tag opens to nothing, before any key is scheduled.
law aes_open_refuses_short_message:
  {Aes.open(Bytes.of_hex("feffe9928665731c6d6a8f9467308308"), Bytes.of_hex("cafebabefacedbaddecaf888"), Nil{}, Bytes.of_hex("00112233445566778899aabbccddee")) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: a nonce that is not 12 bytes opens to nothing, whatever the message holds.
law aes_open_refuses_short_nonce:
  {Aes.open(Bytes.of_hex("feffe9928665731c6d6a8f9467308308"), Bytes.of_hex("cafebabefacedbaddecaf88"), Nil{}, Bytes.of_hex("0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf")) == None{} : Maybe<&2, List<&2, U32>>}

# LAW: clamping a 32-byte scalar changes only its two ends, for every value of the bytes it
# touches: the first byte loses its low three bits, the last byte loses bit 255 and gains
# bit 254, and the bytes in between pass through untouched (RFC 7748 section 5).
law x25519_clamp_bytes:
  for +b0: U32
  for +mid: U32
  for +last: U32
  {X25519.clamp(Bytes.cat(Bytes.cat([b0], Bytes.zeros(29n)), [mid, last])) == Bytes.cat(Bytes.cat([U32.and(b0, 248)], Bytes.zeros(29n)), [mid, U32.or(U32.and(last, 127), 64)]) : List<&2, U32>}

# end block

# big, rsa, ecdsa [pk]
# --------------------
# big and the two signature schemes are checked on known answers, not over every input.
# Bend's U32 is a bit-vector and Base carries no arithmetic lemmas for it, so a law over
# every limb list stops at the first symbolic comparison or division. The numbers below are
# the word boundaries a carry, a borrow or a squaring crosses, and one 2048-bit modulus.
# rsa and ecdsa are checked where they decide on their own inputs, before any public-key
# operation is worth starting: a length, a range, an exponent, a key's shape, and the whole
# encoded message that PKCS#1 v1.5 rebuilds from the hash and compares byte for byte.
# A law that needs a 2048-bit modexp or a P-256 double-and-add is out of reach: minutes at
# check time, and the kernel recheck runs out of fuel on it.

# LAW: reading the bytes a 2048-bit number was written to gives that number back.
law big_of_bytes_to_bytes:
  {Big.of_bytes(Big.to_bytes(Big.of_bytes(Bytes.of_hex("ABBF9B281BCE15A774CEEC1D1251D44BEE242F3D6A3F23F6F3996F5122C6B3086E0E274C56EA567A8A0AB07CD210CC8E73437930845E4FA6FA240D963A136F009C0C0717B23AD7AB23EC8401DAB34F90BA18AEC8BCF787D7E4D950ED2F8AFDEA558255F6EB60BC385839CC0E8D02577D88DC274BF2219332E492D0DBB0E02248E85A81EB4BD497066ADEF39568957CA78D661359879C17959B8D50863ABB517C891EBEF102DCE1313B2EA87CCFD6D9B8CB848830ED84F8161D4EDFE9251228DFF0EF6380022D1F3B565FBFE5766970EA13BAE84B484E7D887B97002A5A205E4ACA2628AD7893A8BC32CB5C090E8924FDFEB371E366E38E7163643C524FA89C43")), 256)) == Big.of_bytes(Bytes.of_hex("ABBF9B281BCE15A774CEEC1D1251D44BEE242F3D6A3F23F6F3996F5122C6B3086E0E274C56EA567A8A0AB07CD210CC8E73437930845E4FA6FA240D963A136F009C0C0717B23AD7AB23EC8401DAB34F90BA18AEC8BCF787D7E4D950ED2F8AFDEA558255F6EB60BC385839CC0E8D02577D88DC274BF2219332E492D0DBB0E02248E85A81EB4BD497066ADEF39568957CA78D661359879C17959B8D50863ABB517C891EBEF102DCE1313B2EA87CCFD6D9B8CB848830ED84F8161D4EDFE9251228DFF0EF6380022D1F3B565FBFE5766970EA13BAE84B484E7D887B97002A5A205E4ACA2628AD7893A8BC32CB5C090E8924FDFEB371E366E38E7163643C524FA89C43")) : List<&2, U32>}

# LAW: 2^31 - 1 plus one carries out of the limb: it is 2^31.
law big_add_word_31:
  {Big.add(Big.of_bytes(Bytes.of_hex("7fffffff")), Big.of_bytes(Bytes.of_hex("01"))) == Big.of_u32(2147483648) : List<&2, U32>}

# LAW: taking one from 2^62 borrows through three zero limbs: it is 2^62 - 1.
law big_sub_word_62:
  {Big.sub(Big.of_bytes(Bytes.of_hex("4000000000000000")), Big.of_bytes(Bytes.of_hex("01"))) == Big.of_bytes(Bytes.of_hex("3fffffffffffffff")) : List<&2, U32>}

# LAW: 2^31 - 1 squared is 2^62 - 2^32 + 1.
law big_mul_word_31:
  {Big.mul(Big.of_bytes(Bytes.of_hex("7fffffff")), Big.of_bytes(Bytes.of_hex("7fffffff"))) == Big.of_bytes(Bytes.of_hex("3fffffff00000001")) : List<&2, U32>}

# LAW: 2^62 leaves 1 modulo 2^31 - 1, since 2^31 is 1 modulo 2^31 - 1.
law big_mod_word_31:
  {Big.mod(Big.of_bytes(Bytes.of_hex("4000000000000000")), Big.of_bytes(Bytes.of_hex("7fffffff"))) == Big.of_u32(1) : List<&2, U32>}

# LAW: 2^31 minus one is 2^31 - 1.
law big_sub_word_31:
  {Big.sub(Big.of_bytes(Bytes.of_hex("80000000")), Big.of_bytes(Bytes.of_hex("01"))) == Big.of_bytes(Bytes.of_hex("7fffffff")) : List<&2, U32>}

# LAW: subtracting below zero gives zero, not a wrapped borrow.
law big_sub_below_zero:
  {Big.sub(Big.of_bytes(Bytes.of_hex("01")), Big.of_bytes(Bytes.of_hex("02"))) == Nil{} : List<&2, U32>}

# LAW: a number modulo zero is itself, so a broken modulus leaves the number alone instead
# of answering zero.
law big_mod_by_zero:
  {Big.mod(Big.of_bytes(Bytes.of_hex("0102")), Nil{}) == Big.of_u32(258) : List<&2, U32>}

# LAW: comparison puts 2^31 - 1 below 2^31, so the carry really made the larger number.
law big_cmp_word_31:
  {Big.cmp(Big.of_bytes(Bytes.of_hex("7fffffff")), Big.of_bytes(Bytes.of_hex("80000000"))) == LT{} : Cmp}

# LAW: a 2048-bit modulus measures 2048 bits, which is the floor key.ok holds a certificate
# key to.
law rsa_mod_bits_2048:
  {Rsa.mod.bits(Bytes.of_hex("ABBF9B281BCE15A774CEEC1D1251D44BEE242F3D6A3F23F6F3996F5122C6B3086E0E274C56EA567A8A0AB07CD210CC8E73437930845E4FA6FA240D963A136F009C0C0717B23AD7AB23EC8401DAB34F90BA18AEC8BCF787D7E4D950ED2F8AFDEA558255F6EB60BC385839CC0E8D02577D88DC274BF2219332E492D0DBB0E02248E85A81EB4BD497066ADEF39568957CA78D661359879C17959B8D50863ABB517C891EBEF102DCE1313B2EA87CCFD6D9B8CB848830ED84F8161D4EDFE9251228DFF0EF6380022D1F3B565FBFE5766970EA13BAE84B484E7D887B97002A5A205E4ACA2628AD7893A8BC32CB5C090E8924FDFEB371E366E38E7163643C524FA89C43")) == 2048 : U32}

# LAW: an even public exponent is refused: it shares a factor with the modulus.
law rsa_refuses_even_exponent:
  {Rsa.exp.rule(Bytes.of_hex("010002")) == False{} : Bool}

# LAW: an exponent of 1 is refused: it would make every signature the message.
law rsa_refuses_exponent_one:
  {Rsa.exp.rule(Bytes.of_hex("01")) == False{} : Bool}

# LAW: 65537, the exponent every real RSA key uses, is accepted.
law rsa_accepts_exponent_65537:
  {Rsa.exp.rule(Bytes.of_hex("010001")) == True{} : Bool}

# LAW: a PKCS#1 v1.5 signature shorter than the modulus is refused.
law rsa_pkcs1_refuses_short_signature:
  {Rsa.pkcs1(Sha2.S256{}, Bytes.of_hex("ABBF9B281BCE15A774CEEC1D1251D44BEE242F3D6A3F23F6F3996F5122C6B3086E0E274C56EA567A8A0AB07CD210CC8E73437930845E4FA6FA240D963A136F009C0C0717B23AD7AB23EC8401DAB34F90BA18AEC8BCF787D7E4D950ED2F8AFDEA558255F6EB60BC385839CC0E8D02577D88DC274BF2219332E492D0DBB0E02248E85A81EB4BD497066ADEF39568957CA78D661359879C17959B8D50863ABB517C891EBEF102DCE1313B2EA87CCFD6D9B8CB848830ED84F8161D4EDFE9251228DFF0EF6380022D1F3B565FBFE5766970EA13BAE84B484E7D887B97002A5A205E4ACA2628AD7893A8BC32CB5C090E8924FDFEB371E366E38E7163643C524FA89C43"), Bytes.of_hex("010001"), Bytes.of_ascii("chaki rsa check\n"), Bytes.of_hex("00")) == False{} : Bool}

# LAW: a PKCS#1 v1.5 signature that is not smaller than the modulus is refused.
law rsa_pkcs1_refuses_signature_at_modulus:
  {Rsa.pkcs1(Sha2.S256{}, Bytes.of_hex("ABBF9B281BCE15A774CEEC1D1251D44BEE242F3D6A3F23F6F3996F5122C6B3086E0E274C56EA567A8A0AB07CD210CC8E73437930845E4FA6FA240D963A136F009C0C0717B23AD7AB23EC8401DAB34F90BA18AEC8BCF787D7E4D950ED2F8AFDEA558255F6EB60BC385839CC0E8D02577D88DC274BF2219332E492D0DBB0E02248E85A81EB4BD497066ADEF39568957CA78D661359879C17959B8D50863ABB517C891EBEF102DCE1313B2EA87CCFD6D9B8CB848830ED84F8161D4EDFE9251228DFF0EF6380022D1F3B565FBFE5766970EA13BAE84B484E7D887B97002A5A205E4ACA2628AD7893A8BC32CB5C090E8924FDFEB371E366E38E7163643C524FA89C43"), Bytes.of_hex("010001"), Bytes.of_ascii("chaki rsa check\n"), Bytes.of_hex("ABBF9B281BCE15A774CEEC1D1251D44BEE242F3D6A3F23F6F3996F5122C6B3086E0E274C56EA567A8A0AB07CD210CC8E73437930845E4FA6FA240D963A136F009C0C0717B23AD7AB23EC8401DAB34F90BA18AEC8BCF787D7E4D950ED2F8AFDEA558255F6EB60BC385839CC0E8D02577D88DC274BF2219332E492D0DBB0E02248E85A81EB4BD497066ADEF39568957CA78D661359879C17959B8D50863ABB517C891EBEF102DCE1313B2EA87CCFD6D9B8CB848830ED84F8161D4EDFE9251228DFF0EF6380022D1F3B565FBFE5766970EA13BAE84B484E7D887B97002A5A205E4ACA2628AD7893A8BC32CB5C090E8924FDFEB371E366E38E7163643C524FA89C43")) == False{} : Bool}

# Two laws stand in for a whole verification, which no check can afford at 2048 bits: 7^3 mod
# 1013 is 343, so the representative is 0157, and verify.if is the comparison the scheme
# ends on. The modulus is small here; the shape of the decision is the same one RSAVP1's
# answer goes through at any length.

# LAW: verification accepts a representative that is exactly the encoding it rebuilt.
law rsa_verify_accepts_exact_encoding:
  {Rsa.verify.if(True{}, Bytes.of_hex("03f5"), Bytes.of_hex("03"), Bytes.of_hex("07"), Bytes.of_hex("0157")) == True{} : Bool}

# LAW: verification refuses that representative with one byte of the encoding changed, so a
# signature is never accepted on a near miss.
law rsa_verify_refuses_changed_encoding:
  {Rsa.verify.if(True{}, Bytes.of_hex("03f5"), Bytes.of_hex("03"), Bytes.of_hex("07"), Bytes.of_hex("0156")) == False{} : Bool}

# LAW: the encoded message PKCS#1 v1.5 verification rebuilds is exactly RFC 8017 9.2's for
# the SHA-256 digest of that message: 00, 01, 202 octets of 0xff, 00, the SHA-256
# DigestInfo and the digest. Anything else in the signature's representative — a different
# DigestInfo, a shorter run of 0xff, one padding byte that is not 0xff — misses the compare
# of the whole encoding, which is what keeps Bleichenbacher's forgeries out.
law rsa_pkcs1_encoding_is_rfc8017:
  {Rsa.pkcs1.em(Sha2.S256{}, Bytes.of_hex("ABBF9B281BCE15A774CEEC1D1251D44BEE242F3D6A3F23F6F3996F5122C6B3086E0E274C56EA567A8A0AB07CD210CC8E73437930845E4FA6FA240D963A136F009C0C0717B23AD7AB23EC8401DAB34F90BA18AEC8BCF787D7E4D950ED2F8AFDEA558255F6EB60BC385839CC0E8D02577D88DC274BF2219332E492D0DBB0E02248E85A81EB4BD497066ADEF39568957CA78D661359879C17959B8D50863ABB517C891EBEF102DCE1313B2EA87CCFD6D9B8CB848830ED84F8161D4EDFE9251228DFF0EF6380022D1F3B565FBFE5766970EA13BAE84B484E7D887B97002A5A205E4ACA2628AD7893A8BC32CB5C090E8924FDFEB371E366E38E7163643C524FA89C43"), Bytes.of_ascii("chaki rsa check\n")) == Bytes.of_hex("0001ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff003031300d060960864801650304020105000420aac9b79268cc6d4070d329ba4d5ea8c8bc40446d33be262f088cad2dcebd906f") : List<&2, U32>}

# LAW: MGF1 with SHA-256 is the SHA-256 of the seed and a big-endian counter from zero
# (RFC 8017 B.2.1), which is the mask PSS unmasks DB with.
law rsa_mgf1_sha256:
  {Rsa.mgf1(Sha2.S256{}, Bytes.of_ascii("chaki"), 32) == Bytes.of_hex("a027ba00ffecb8c10a1d6419aa87ac76337e1a54a131cf87e065ecc598c09a5d") : List<&2, U32>}

# LAW: a PSS signature shorter than the modulus is refused.
law rsa_pss_refuses_short_signature:
  {Rsa.pss(Sha2.S256{}, Bytes.of_hex("ABBF9B281BCE15A774CEEC1D1251D44BEE242F3D6A3F23F6F3996F5122C6B3086E0E274C56EA567A8A0AB07CD210CC8E73437930845E4FA6FA240D963A136F009C0C0717B23AD7AB23EC8401DAB34F90BA18AEC8BCF787D7E4D950ED2F8AFDEA558255F6EB60BC385839CC0E8D02577D88DC274BF2219332E492D0DBB0E02248E85A81EB4BD497066ADEF39568957CA78D661359879C17959B8D50863ABB517C891EBEF102DCE1313B2EA87CCFD6D9B8CB848830ED84F8161D4EDFE9251228DFF0EF6380022D1F3B565FBFE5766970EA13BAE84B484E7D887B97002A5A205E4ACA2628AD7893A8BC32CB5C090E8924FDFEB371E366E38E7163643C524FA89C43"), Bytes.of_hex("010001"), Bytes.of_ascii("chaki rsa check\n"), Bytes.of_hex("00")) == False{} : Bool}

# LAW: PSS encodes into modBits - 1 bits, so a 2047-bit modulus still fills 256 octets.
law rsa_pss_emlen_2047:
  {Rsa.pss.emlen(2047) == 256 : U32}

# LAW: a signature value of zero is refused, so neither r nor s may be 0.
law ecdsa_refuses_zero_r:
  {Ecdsa.range.ok(Big.of_bytes(Bytes.of_hex("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551")), Nil{}) == False{} : Bool}

# LAW: a signature value equal to the group order is refused, so both r and s stay below n.
law ecdsa_refuses_value_at_order:
  {Ecdsa.range.ok(Big.of_bytes(Bytes.of_hex("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551")), Big.of_bytes(Bytes.of_hex("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551"))) == False{} : Bool}

# LAW: the r of RFC 6979 A.2.5's P-256 vector passes the range rule, so it is not refusing
# every value.
law ecdsa_accepts_rfc6979_r:
  {Ecdsa.range.ok(Big.of_bytes(Bytes.of_hex("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551")), Big.of_bytes(Bytes.of_hex("EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716"))) == True{} : Bool}

# LAW: a public key coordinate that is not below the field prime is refused.
law ecdsa_refuses_coordinate_at_p:
  {Ecdsa.coord.ok(Big.of_bytes(Bytes.of_hex("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff")), Big.of_bytes(Bytes.of_hex("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff"))) == False{} : Bool}

# LAW: an uncompressed key that stops after x, with no y, is refused.
law ecdsa_refuses_key_missing_y:
  {Ecdsa.pub.split(Bytes.of_hex("0460FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6"), 32) == None{} : Maybe<&2, X509.Two()>}

# LAW: a compressed key, which starts 02 rather than 04, is refused.
law ecdsa_refuses_compressed_key:
  {Ecdsa.pub.split(Bytes.of_hex("0260FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB67903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299"), 32) == None{} : Maybe<&2, X509.Two()>}

# end pk

# asn1, x509, x509v [x509]
# ------------------------

# Constructed certificates
# ------------------------
# Some of these laws are about a decision rather than about DER: what the checks make of a
# certificate whose fields are already known. These three build one, with only the fields a
# check reads set.

# a certificate with only the fields the checks read: a validity, the CA flag,
# pathLenConstraint, and the dNSName entries. The key usage is absent (every bit), the
# critical extensions are none, and the certificate is for TLS servers.
def x509v_cert(nb: U32, na: U32, ca: Bool, path_len: U32, dns: List<&2, String>) -> X509.Cert:
  X509.Cert{Nil{}, Nil{}, "", Nil{}, Nil{}, Nil{}, nb, na, "", "", Nil{}, dns, ca, path_len, 4294967295, False{}, True{}}

# a certificate for the checks that can refuse it: whether it carries a critical extension the
# engine doesn't read, and whether it is for TLS servers. Everything else is at its
# permissive default.
def x509v_cert_flags(unknown_critical: Bool, server_auth: Bool) -> X509.Cert:
  X509.Cert{Nil{}, Nil{}, "", Nil{}, Nil{}, Nil{}, 1000, 3000, "", "", Nil{}, Nil{}, False{}, 0, 4294967295, unknown_critical, server_auth}

# a certificate for the signature check: the algorithm its signature names, and the algorithm
# of the key it carries
def x509v_cert_sig(sig_alg: String, key_alg: String) -> X509.Cert:
  X509.Cert{Nil{}, Nil{}, sig_alg, Nil{}, Nil{}, Nil{}, 1000, 3000, key_alg, "", Nil{}, Nil{}, False{}, 0, 4294967295, False{}, True{}}

# Strict DER
# ----------
# Two readers that agree on an element's bytes but not on where it ends disagree about what
# was signed, so asn1.read takes one encoding per element and refuses everything DER leaves
# out: another form of tag, another form of length, or a length that runs past the bytes it
# was given. None of those refusals reads the byte string that follows, so each holds for
# every tail.

# LAW: a tag in the high-tag-number form is refused.
law asn1_read_high_tag:
  for +t: List<&2, U32>
  {Asn1.read(Con{31, t}) == None{} : Maybe<&2, Asn1.Tlv>}

# LAW: the indefinite length form, which DER forbids, is refused.
law asn1_read_indefinite:
  for +t: List<&2, U32>
  {Asn1.read(Con{4, Con{128, t}}) == None{} : Maybe<&2, Asn1.Tlv>}

# LAW: a long-form length with a leading zero byte is refused, so 82 00 80 can't stand in
# for the one-byte form of 128.
law asn1_read_long_zero:
  for +t: List<&2, U32>
  {Asn1.read(Con{4, Con{130, Con{0, Con{128, t}}}}) == None{} : Maybe<&2, Asn1.Tlv>}

# LAW: a long-form length that the short form could carry is refused.
law asn1_read_long_short:
  for +t: List<&2, U32>
  {Asn1.read(Con{4, Con{129, Con{127, t}}}) == None{} : Maybe<&2, Asn1.Tlv>}

# LAW: a count octet naming more than four length bytes is refused.
law asn1_read_long_count:
  for +t: List<&2, U32>
  {Asn1.read(Con{4, Con{133, t}}) == None{} : Maybe<&2, Asn1.Tlv>}

# LAW: a length that runs past the end of the input is refused: five bytes are announced and
# two follow.
law asn1_read_past_end:
  {Asn1.read(Bytes.of_hex("04 05 01 02")) == None{} : Maybe<&2, Asn1.Tlv>}

# LAW: 127 bytes is still a short-form length, so it is carried by the one-byte form.
law asn1_read_short_max:
  {Asn1.read(Bytes.cat(Bytes.of_hex("04 7f"), Bytes.zeros(127n))) == Some{Asn1.Tlv{4, Bytes.zeros(127n), Nil{}}} : Maybe<&2, Asn1.Tlv>}

# LAW: a short-form element hands back exactly its value and exactly the bytes after it, so
# no byte is read that wasn't there and none is swallowed.
law asn1_read_exact:
  for +v: U32
  for +t: List<&2, U32>
  {Asn1.read(Con{4, Con{1, Con{v, t}}}) == Some{Asn1.Tlv{4, [v], t}} : Maybe<&2, Asn1.Tlv>}

# LAW: an element of length zero carries no value and leaves the rest where it was.
law asn1_read_zero_len:
  for +t: List<&2, U32>
  {Asn1.read(Con{4, Con{0, t}}) == Some{Asn1.Tlv{4, Nil{}, t}} : Maybe<&2, Asn1.Tlv>}

# LAW: a UTCTime's two-digit year reads as 20xx below 50, so 49 is 2049 and not 1949.
law asn1_time_pivot:
  {Asn1.time(23, Bytes.of_ascii("491231235959Z")) == Some{2524607999} : Maybe<&2, U32>}

# dNSNames
# --------
# Only a dNSName entry becomes a name to match, and it is lowercased as it is parsed, so a
# certificate can't rely on case to hide the host it carries, and an iPAddress entry can't be
# read as one.

# LAW: a dNSName entry is lowercased as it is parsed.
law x509_san_lower:
  {X509.x509.san.names([Asn1.Tlv{130, Bytes.of_ascii("A.Example"), Nil{}}]) == Some{["a.example"]} : Maybe<&2, List<&2, String>>}

# LAW: an iPAddress entry, or any other kind of general name, is not a name to match.
law x509_san_skips_ip:
  {X509.x509.san.names([Asn1.Tlv{135, [127, 0, 0, 1], Nil{}}, Asn1.Tlv{130, Bytes.of_ascii("a.example"), Nil{}}]) == Some{["a.example"]} : Maybe<&2, List<&2, String>>}

# Hosts
# -----
# The name in a certificate decides which host is served, so a wildcard may stand for one
# label and no more: not the bare domain, not several labels, not the labels on either side
# of a name it only appears to end. Case is settled before the comparison (the host is
# lowercased and the dNSName entries are lowercased as they are parsed), and an IP literal
# is never a name.

# LAW: *.example.com matches a host one label below example.com.
law x509v_name_wild_one_label:
  {X509v.name.ok("*.example.com", "a.example.com") == True{} : Bool}

# LAW: *.example.com does not match example.com itself.
law x509v_name_wild_not_apex:
  {X509v.name.ok("*.example.com", "example.com") == False{} : Bool}

# LAW: *.example.com does not match a host two labels below it.
law x509v_name_wild_not_two_labels:
  {X509v.name.ok("*.example.com", "a.b.example.com") == False{} : Bool}

# LAW: *.example.com does not match a longer domain that ends in its name.
law x509v_name_wild_not_suffix:
  {X509v.name.ok("*.example.com", "a.example.com.evil") == False{} : Bool}

# LAW: a * that isn't the whole leftmost label is an ordinary character, not a wildcard.
law x509v_name_wild_leftmost:
  {X509v.name.ok("a*.example.com", "ab.example.com") == False{} : Bool}

# LAW: a wildcard under a bare top-level domain matches nothing.
law x509v_name_wild_two_labels:
  {X509v.name.ok("*.com", "a.com") == False{} : Bool}

# LAW: a wildcard stands for one label, so it doesn't match an empty one.
law x509v_name_wild_no_empty_label:
  {X509v.name.ok("*.example.com", ".example.com") == False{} : Bool}

# LAW: a certificate that names no host in a dNSName entry matches no host at all.
law x509v_names_empty:
  for +h: String
  {X509v.names.ok(Nil{}, h) == False{} : Bool}

# LAW: the host is lowercased before it is compared, so X.Example.Com is x.example.com.
law x509v_host_norm:
  {X509v.host.norm("X.Example.Test") == "x.example.test" : String}

# LAW: a name with no wildcard matches the host equal to it, and no other host.
law x509v_name_exact_only_itself:
  for +h: String
  {X509v.name.ok("cha.test", h) == String.eq("cha.test", h) : Bool}

# LAW: when the host is an IP literal, no certificate name matches it, wildcard or not.
law x509v_ip_never_matches:
  for c: X509.Cert
  for +n: String
  for ok: {X509v.host.ip(n) == True{} : Bool}
  {X509v.host_ok.if(X509v.host.ip(n), c, n) == False{} : Bool}

# LAW: a host with one trailing dot is the host without it.
law x509v_host_trailing_dot:
  {X509v.host_ok(x509v_cert(1000, 3000, False{}, 0, ["cha.test"]), "cha.test.") == True{} : Bool}

# LAW: an IPv4 literal is read as an address, so no name is compared against it.
law x509v_ip_is_address:
  {X509v.host.ip("127.0.0.1") == True{} : Bool}

# Time and issuers
# ----------------
# The leaf is checked before the chain is walked, and every issuer above it is checked as
# the walk passes it. These are those decisions over constructed certificates: the fields
# they read, and nothing else, set.

# LAW: a certificate whose notAfter is before now is refused, whatever else is right with it.
law x509v_leaf_expired:
  {X509v.leaf.why(x509v_cert(1000, 2000, False{}, 0, Nil{}), "cha.test", 2001, True{}) == "the server's certificate has expired" : String}

# LAW: a certificate whose notBefore is after now is refused.
law x509v_leaf_not_yet:
  {X509v.leaf.why(x509v_cert(2000, 3000, False{}, 0, Nil{}), "cha.test", 1999, True{}) == "the server's certificate isn't valid yet" : String}

# LAW: a certificate that is valid now, for TLS servers and for this host, is accepted.
law x509v_leaf_ok:
  {X509v.leaf.why(x509v_cert(1000, 3000, False{}, 0, Nil{}), "cha.test", 2000, True{}) == "" : String}

# LAW: a critical extension the engine doesn't read refuses the certificate, rather than being
# skipped.
law x509v_leaf_unknown_critical:
  {X509v.leaf.why(x509v_cert_flags(True{}, True{}), "cha.test", 2000, True{}) == "the server's certificate has a critical extension chaki doesn't know" : String}

# LAW: a certificate that isn't for TLS servers is refused.
law x509v_leaf_not_server_auth:
  {X509v.leaf.why(x509v_cert_flags(False{}, False{}), "cha.test", 2000, True{}) == "the server's certificate isn't for TLS servers" : String}

# LAW: an issuer without the CA basicConstraints flag is refused, so a leaf can't sign for
# another host.
law x509v_inter_not_ca:
  {X509v.inter.why(x509v_cert(1000, 3000, False{}, 0, Nil{}), 1, 2000) == "an issuer in the chain isn't a CA" : String}

# LAW: an issuer's pathLenConstraint caps how many issuers may sit between it and the leaf.
law x509v_inter_pathlen:
  {X509v.inter.why(x509v_cert(1000, 3000, True{}, 0, Nil{}), 1, 2000) == "the chain is longer than an issuer allows" : String}

# LAW: the same issuer is accepted when it sits directly above the leaf.
law x509v_inter_pathlen_room:
  {X509v.inter.why(x509v_cert(1000, 3000, True{}, 0, Nil{}), 0, 2000) == "" : String}

# LAW: an issuer that has expired is refused, even a CA with room below it.
law x509v_inter_expired:
  {X509v.inter.why(x509v_cert(1000, 2000, True{}, 5, Nil{}), 0, 2001) == "an issuer in the chain has expired" : String}

# LAW: a certificate that issued the one at hand ends the walk as trusted.
law x509v_chain_anchor_trusted:
  for a: X509.Cert
  for c: X509.Cert
  {X509v.path.anchor(Some{a}, c, 0, Nil{}, 2000) == X509v.Trusted{} : X509v.Path}

# LAW: a chain that ends at no trust anchor is refused.
law x509v_chain_no_anchor:
  for c: X509.Cert
  {X509v.path.anchor(None{}, c, 0, Nil{}, 2000) == X509v.Refused{"the chain doesn't lead to a trusted root"} : X509v.Path}

# LAW: a walk that hasn't reached an anchor when its eight steps are spent is refused, so a
# chain can't be arbitrarily long.
law x509v_chain_too_long:
  for c: X509.Cert
  {X509v.path.go(0n, Nil{}, Nil{}, 2000, X509v.At{c, 0}) == Fail{"the chain is too long"} : Result<&1, &1, String, Unit>}

# Signature algorithms
# --------------------
# A certificate names the algorithm its issuer signed it with, and the issuer's key names its
# own. The two must be the same kind, and the algorithm must be one the engine checks: an
# unchecked algorithm is a refusal, never a pass.

# LAW: an RSA signature is not accepted under an EC key.
law x509v_signed_rsa_under_ec:
  {X509v.signed_by(x509v_cert_sig("1.2.840.113549.1.1.11", X509v.EC()), x509v_cert_sig("1.2.840.113549.1.1.11", X509v.EC())) == False{} : Bool}

# LAW: an ECDSA signature is not accepted under an RSA key.
law x509v_signed_ec_under_rsa:
  {X509v.signed_by(x509v_cert_sig("1.2.840.10045.4.3.2", X509v.RSA()), x509v_cert_sig("1.2.840.10045.4.3.2", X509v.RSA())) == False{} : Bool}

# LAW: a signature algorithm the engine doesn't check is refused, not trusted by default.
law x509v_signed_unknown_alg:
  {X509v.signed_by(x509v_cert_sig("1.2.3.4", X509v.RSA()), x509v_cert_sig("1.2.3.4", X509v.RSA())) == False{} : Bool}

# end x509

# tlsmsg, tls [tls]
# -----------------
# The TLS 1.3 client core and its wire format. The record layer's length bound and the three
# ServerHello refusals are known answers, built out of RFC 8448 3's own recording so the
# checks run on real bytes; the state machine's refusals hold over every state and message,
# because the client is one pure state machine whose failures are final.

# Reading a state, and implication
# --------------------------------

# a Boolean implication, so a law can say "whenever this, then that" without carrying a
# hypothesis: false implies anything, true implies b only if b
def tls_implies(a: Bool, b: Bool) -> Bool:
  Bool.or(Bool.not(a), b)

# whether a phase is the failed one
def tls_dead(p: Tls.Phase) -> Bool:
  match p:
    case Tls.Phase.dead{why}:
      True{}
    case _:
      False{}

# the state an answer carries: hs.input and hs.send hand back a state beside their records
# and events
def tls_state(p: Tls.Hs & List<&2, U32> & List<&2, Tls.Reply>) -> Tls.Hs:
  match p:
    case (st, rest):
      st

# the records an answer hands back
def tls_records(p: Tls.Hs & List<&2, U32>) -> List<&2, U32>:
  match p:
    case (st, out):
      out

# the events a state has gathered
def tls_events(st: Tls.Hs) -> List<&2, Tls.Reply>:
  Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
  evs

# those events with one more after them
def tls_events.plus(st: Tls.Hs, e: Tls.Reply) -> List<&2, Tls.Reply>:
  List.append(&2, Tls.Reply, tls_events(st), [e])

# a traffic key's record sequence number
def tls_traffic_n(t: Tls.Traffic) -> U32:
  Tls.Traffic{secret, k, iv, n} = t
  n

# the transcript: the raw handshake messages as they came in (RFC 8446 4.4.1)
def tls_tx(st: Tls.Hs) -> List<&2, U32>:
  Tls.Hs{phase, tx, keys, priv, proof, buf, msgs, out, evs} = st
  tx

# the type of each handshake message at the front of a buffer, in order
def tls_tags.go(ms: List<&2, Tlsmsg.Msg>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ms:
    case Nil{}:
      List.reverse(&2, U32, acc)
    case m <> t:
      Tlsmsg.Msg{htype, body, raw} = m
      tls_tags.go(t, htype <> acc)

def tls_tags(p: List<&2, Tlsmsg.Msg> & List<&2, U32>) -> List<&2, U32>:
  match p:
    case (ms, rest):
      tls_tags.go(ms, Nil{})

# the messages glued back together, with the bytes after them
def tls_glue.raws(ms: List<&2, Tlsmsg.Msg>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ms:
    case Nil{}:
      acc
    case m <> t:
      Tlsmsg.Msg{htype, body, raw} = m
      tls_glue.raws(t, Bytes.cat(acc, raw))

def tls_glue(p: List<&2, Tlsmsg.Msg> & List<&2, U32>) -> List<&2, U32>:
  match p:
    case (ms, rest):
      Bytes.cat(tls_glue.raws(ms, Nil{}), rest)

# the same bytes with their last one gone
def tls_cut(+xs: List<&2, U32>) -> List<&2, U32>:
  Bytes.take(xs, Nat.sub(U32.to_nat(Bytes.len(xs)), 1n))

# whether a ServerHello was accepted
def tls_takes(r: Result<&1, &1, String, Tlsmsg.Hello>) -> Bool:
  match r:
    case Fail{e}:
      False{}
    case Done{v}:
      True{}

# Records
# -------

# LAW: a record header may claim the largest ciphertext RFC 8446 5.2 allows, 2^14 + 256
# bytes, and a record that long is accepted.
law tlsmsg_record_max:
  {Tlsmsg.record.hdr.ok(23, 771, 16640) == True{} : Bool}

# LAW: one ciphertext byte past that bound is refused (RFC 8446 5.2), so a record can never
# be longer than 2^14 + 256 bytes.
law tlsmsg_record_overflow:
  {Tlsmsg.record.hdr.ok(23, 771, 16641) == False{} : Bool}

# LAW: the record layer drops a record whose header claims one byte past the bound, refusing
# the whole buffer rather than reading the record (RFC 8446 5.2).
law tlsmsg_record_overflow_refused:
  {Tlsmsg.records(Bytes.of_hex("1703034101")) == None{} : Maybe<&2, Tlsmsg.Split()>}

# The RFC 8448 3 recording
# ------------------------

# the ClientHello of RFC 8448 3, handshake header and all
def tls_c8448.hello() -> List<&2, U32>:
  Bytes.of_hex("010000c00303cb34ecb1e78163ba1c38c6dacb196a6dffa21a8d9912ec18a2ef6283024dece7000006130113031302010000910000000b0009000006736572766572ff01000100000a00140012001d0017001800190100010101020103010400230000003300260024001d002099381de560e4bd43d23d8e435a7dbafeb3c06e51c13cae4d5413691e529aaf2c002b0003020304000d0020001e040305030603020308040805080604010501060102010402050206020202002d00020101001c00024001")

# the ServerHello's random (RFC 8448 3) and its key share
def tls_c8448.random() -> List<&2, U32>:
  Bytes.of_hex("a6af06a4121860dc5e6e60249cd34c95930c8ac5cb1434dac155772ed3e26928")

def tls_c8448.share() -> List<&2, U32>:
  Bytes.of_hex("c9828876112095fe66762bdbf7c672e156d6cc253b833df1dd69b1b04e751f0f")

# a ServerHello body: legacy_version, the random, an empty session id echo, the suite, null
# compression, and the key_share and supported_versions extensions (RFC 8446 4.1.3, 4.2.7)
def tls_sh(+random: List<&2, U32>, +suite: List<&2, U32>, +group: List<&2, U32>, +share: List<&2, U32>) -> List<&2, U32>:
  +keyshare = Tlsmsg.ext.pair(51, Bytes.cat(group, Bytes.cat(Bytes.be16(32), share)))
  +versions = Tlsmsg.ext.pair(43, [3, 4])
  +exts = Bytes.cat(keyshare, versions)
  Bytes.cat(Bytes.of_hex("0303"), Bytes.cat(random, Bytes.cat([0], Bytes.cat(suite, Bytes.cat([1], Bytes.cat(Bytes.be16(Bytes.len(exts)), exts))))))

# the recorded ServerHello: TLS_AES_128_GCM_SHA256 over the x25519 group
def tls_sh.recorded() -> List<&2, U32>:
  tls_sh(tls_c8448.random(), Bytes.be16(4865), Bytes.be16(29), tls_c8448.share())

# the recorded ServerHello, one cipher suite over: TLS_AES_256_GCM_SHA384 (4866), which the
# ClientHello never offers
def tls_sh.suite() -> List<&2, U32>:
  tls_sh(tls_c8448.random(), Bytes.be16(4866), Bytes.be16(29), tls_c8448.share())

# the recorded ServerHello over secp256r1 (24) instead of the only group offered
def tls_sh.group() -> List<&2, U32>:
  tls_sh(tls_c8448.random(), Bytes.be16(4865), Bytes.be16(24), tls_c8448.share())

# the recorded ServerHello with the TLS 1.2 downgrade sentinel in the last 8 bytes of its
# random (RFC 8446 4.1.3)
def tls_sh.downgrade() -> List<&2, U32>:
  +random = Bytes.cat(Bytes.of_hex("a6af06a4121860dc5e6e60249cd34c95930c8ac5cb1434dac"), Bytes.of_hex("444f574e47524401"))
  tls_sh(random, Bytes.be16(4865), Bytes.be16(29), tls_c8448.share())

# LAW: the recorded ServerHello of RFC 8448 3 is accepted: TLS_AES_128_GCM_SHA256, the one
# suite offered that it picks, over an x25519 key share.
law tlsmsg_serverhello_taken:
  {tls_takes(Tlsmsg.server_hello(tls_sh.recorded())) == True{} : Bool}

# LAW: a ServerHello that picks a cipher suite the ClientHello didn't offer is refused.
law tlsmsg_serverhello_suite:
  {tls_takes(Tlsmsg.server_hello(tls_sh.suite())) == False{} : Bool}

# LAW: a ServerHello whose key share isn't the x25519 group the ClientHello offered is
# refused.
law tlsmsg_serverhello_group:
  {tls_takes(Tlsmsg.server_hello(tls_sh.group())) == False{} : Bool}

# LAW: a ServerHello whose random carries the TLS 1.2 downgrade sentinel is refused, whatever
# else it says (RFC 8446 4.1.3).
law tlsmsg_serverhello_downgrade:
  {tls_takes(Tlsmsg.server_hello(tls_sh.downgrade())) == False{} : Bool}

# Handshake messages
# ------------------

# LAW: the recorded ClientHello of RFC 8448 3 splits into handshake messages that, glued
# back together with the bytes after them, are the recording itself, byte for byte.
law tlsmsg_clienthello_roundtrip:
  {tls_glue(Tlsmsg.messages(tls_c8448.hello())) == tls_c8448.hello() : List<&2, U32>}

# LAW: the recorded ClientHello is exactly one handshake message, a ClientHello (type 1).
law tlsmsg_clienthello_one:
  {tls_tags(Tlsmsg.messages(tls_c8448.hello())) == [1] : List<&2, U32>}

# LAW: a handshake length that runs past the bytes present is no message: the recorded
# ClientHello cut one byte short holds none.
law tlsmsg_clienthello_short:
  {tls_tags(Tlsmsg.messages(tls_cut(tls_c8448.hello()))) == Nil{} : List<&2, U32>}

# The client's state machine
# --------------------------

# LAW: application data that arrives before the handshake is done ends the connection, so no
# byte of it ever reaches the shell.
law tls_app_needs_ready:
  for +p: Tls.Phase
  for +k: Tls.Keys
  for +st: Tls.Hs
  for body: List<&2, U32>
  {tls_implies(Bool.not(Tls.ready.of(p)), tls_dead(Tls.phase.of(Tls.hs.app(p, k, st, body)))) == True{} : Bool}

# LAW: once the handshake is done, application data reaches the shell unchanged, as one more
# data event.
law tls_app_when_ready:
  for +k: Tls.Keys
  for +st: Tls.Hs
  for body: List<&2, U32>
  {tls_events(Tls.hs.app(Tls.Phase.ready{}, k, st, body)) == tls_events.plus(st, Tls.Reply.data{body}) : List<&2, Tls.Reply>}

# LAW: a server Finished whose verify_data doesn't check ends the connection.
law tls_finished_refused:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  {Tls.phase.of(Tls.hs.fin.by(False{}, st, m)) == Tls.Phase.dead{"the server's Finished doesn't check"} : Tls.Phase}

# LAW: a server Finished whose verify_data checks moves the handshake on to the shell's
# verdict, and asks for it.
law tls_finished_asks:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  {Tls.phase.of(Tls.hs.fin.by(True{}, st, m)) == Tls.Phase.asked{} : Tls.Phase}

# LAW: a certificate the shell rejects ends the connection.
law tls_trusted_refused:
  for +st: Tls.Hs
  {Tls.phase.of(tls_state(Tls.hs.trusted.at(True{}, st, False{}))) == Tls.Phase.dead{"the server's certificate was rejected"} : Tls.Phase}

# LAW: the shell's verdict before the server's flight is in is refused rather than believed.
law tls_trusted_early:
  for +st: Tls.Hs
  for ok: Bool
  {Tls.phase.of(tls_state(Tls.hs.trusted.at(False{}, st, ok))) == Tls.Phase.dead{"hs.trusted before the server's flight is in"} : Tls.Phase}

# a ServerHello that is really a HelloRetryRequest: SHA-256("HelloRetryRequest") as its
# random, and a key_share that names x25519 with no key in it (RFC 8446 4.1.3, 4.1.4)
def tls_hrr() -> Tlsmsg.Msg:
  +keyshare = Tlsmsg.ext.pair(51, Bytes.be16(29))
  +versions = Tlsmsg.ext.pair(43, [3, 4])
  +exts = Bytes.cat(keyshare, versions)
  +body = Bytes.cat(Bytes.of_hex("0303"), Bytes.cat(Tlsmsg.hrr.random(), Bytes.cat([0], Bytes.cat(Bytes.be16(4865), Bytes.cat([1], Bytes.cat(Bytes.be16(Bytes.len(exts)), exts))))))
  Tlsmsg.Msg{2, body, Tlsmsg.handshake(2, body)}

# LAW: a HelloRetryRequest that comes off the wire is refused, so a second one can never be
# answered either: x25519 is the only group the ClientHello offers.
law tls_retry_refused:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  for suite: U32
  for share: List<&2, U32>
  {Tls.phase.of(Tls.hs.server.retry(True{}, suite, share, st, m)) == Tls.Phase.dead{"the server sent a HelloRetryRequest, and x25519 is all we offer"} : Tls.Phase}

# LAW: the HelloRetryRequest of RFC 8446 4.1.3, read through the wire format, ends the
# connection the same way.
law tls_retry_wire_refused:
  for +st: Tls.Hs
  {Tls.phase.of(Tls.hs.server(st, tls_hrr())) == Tls.Phase.dead{"the server sent a HelloRetryRequest, and x25519 is all we offer"} : Tls.Phase}

# LAW: an encrypted record that doesn't authenticate ends the connection, so a modified
# record never reaches the handshake or the shell.
law tls_record_refused:
  for +st: Tls.Hs
  for k: Tls.Keys
  {Tls.phase.of(Tls.hs.opened.at(None{}, k, st)) == Tls.Phase.dead{"a record that didn't authenticate"} : Tls.Phase}

# LAW: a legacy ChangeCipherSpec is only ignored during the handshake: after it, one ends the
# connection (RFC 8446 D.4).
law tls_ccs_after_ready:
  for +st: Tls.Hs
  for one: Bool
  {Tls.phase.of(Tls.hs.ccs.at(False{}, one, st)) == Tls.Phase.dead{"a legacy ChangeCipherSpec after the handshake"} : Tls.Phase}

# LAW: every record's sequence number is one more than the record before it, so a record's
# nonce is never used twice.
law tls_traffic_next:
  for +t: Tls.Traffic
  {tls_traffic_n(Tls.traffic.next(t)) == (tls_traffic_n(t) + 1 : U32) : U32}

# LAW: nothing is sent before the handshake is done: application data waits in the shell.
law tls_send_needs_ready:
  for +st: Tls.Hs
  for +data: List<&2, U32>
  {tls_records(Tls.hs.send.at(False{}, st, data)) == Nil{} : List<&2, U32>}

# LAW: no close_notify is sent before the handshake is done.
law tls_close_needs_ready:
  for +st: Tls.Hs
  {Tls.hs.close.at(False{}, st) == Nil{} : List<&2, U32>}

# LAW: moving the handshake on appends the message's raw bytes to the transcript, which is
# what the CertificateVerify and the Finished are checked against.
law tls_transcript_grows:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  for +p: Tls.Phase
  {tls_tx(Tls.hs.next(st, m, p)) == Bytes.cat(tls_tx(st), Tls.msg.raw(m)) : List<&2, U32>}

# LAW: a KeyUpdate that isn't exactly one byte of 0 or 1 ends the connection (RFC 8446 4.6.3).
law tls_update_refused:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  {Tls.phase.of(Tls.hs.update.ok(False{}, st, m)) == Tls.Phase.dead{"a KeyUpdate that isn't one byte of 0 or 1"} : Tls.Phase}

# LAW: a legacy ChangeCipherSpec that isn't exactly one byte of 0x01 ends the connection,
# even in the one window where a ChangeCipherSpec may be ignored (RFC 8446 D.4).
law tls_ccs_bad_refused:
  for +st: Tls.Hs
  {Tls.phase.of(Tls.hs.ccs.at(True{}, False{}, st)) == Tls.Phase.dead{"a legacy ChangeCipherSpec that isn't one byte of 0x01"} : Tls.Phase}

# LAW: a Certificate message with no certificate in it ends the connection, so the shell is
# never asked to verify an empty chain (RFC 8446 4.4.2).
law tls_cert_empty_refused:
  for +st: Tls.Hs
  for +m: Tlsmsg.Msg
  for certs: List<&2, List<&2, U32>>
  {Tls.phase.of(Tls.hs.cert.by(True{}, certs, st, m)) == Tls.Phase.dead{"the server sent no certificate"} : Tls.Phase}

# LAW: a KeyUpdate starts its new traffic keys at sequence number zero, so the counter only
# ever restarts beside a key it has never sealed with (RFC 8446 4.6.3, 7.2).
law tls_update_fresh_seq:
  for +t: Tls.Traffic
  for a: Tls.Aead
  {tls_traffic_n(Tls.traffic.up(t, a)) == 0 : U32}

# LAW: failure is final: once a connection has failed, every further byte from the server
# leaves it failed, so one bad message cannot be walked back.
law tls_dead_absorbs:
  for +st: Tls.Hs
  for +why: String
  for +bytes: List<&2, U32>
  {tls_dead(Tls.phase.of(tls_state(Tls.hs.input(Tls.hs.die(st, why), bytes)))) == True{} : Bool}

# end tls

# hop (http's pure decisions) [http]
# --------------------------------

# LAW: a hop to another origin carries no credentials: a request that sends AUTHORIZATION and
# Cookie reaches it as the same request without them.
law hop_cross_origin_drops_credentials:
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.Hop{"GET", "http://a.example/x", ("AUTHORIZATION", "t") <> ("Cookie", "c") <> hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307) == Hop.judge.go(Hop.Hop{"GET", "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307) : Hop.Hop}

# LAW: a hop within one origin sends the same request again at the new url: a 307 keeps the
# method, every header and the body.
law hop_same_origin_keeps_request:
  for +m: String
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.Hop{m, "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "a.example", 80, "/y"}, 307) == Hop.Hop{m, "http://a.example/y", hs, b} : Hop.Hop}

# LAW: a 308, like a 307, sends the same request again.
law hop_308_keeps_request:
  for +m: String
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.Hop{m, "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "a.example", 80, "/y"}, 308) == Hop.Hop{m, "http://a.example/y", hs, b} : Hop.Hop}

# LAW: only 307 and 308 send the method and the body again; 301, 302 and 303 don't.
law hop_keeps_status:
  {[Hop.redirect.keeps(301), Hop.redirect.keeps(302), Hop.redirect.keeps(303), Hop.redirect.keeps(307), Hop.redirect.keeps(308)] == [False{}, False{}, False{}, True{}, True{}] : List<Bool>}

# LAW: a redirect from https to http is refused, whatever the request and the status.
law hop_downgrade_refused:
  for h: Hop.Hop
  for status: U32
  {Hop.judge.next(h, Url.Url{"https", "a.example", 443, "/x"}, status, Some{Url.Url{"http", "a.example", 80, "/y"}}) == Hop.Refuse{"refused a redirect from https to http"} : Hop.Next}

# LAW: a 303 sends a POST again as a GET with no body, and the headers that framed the body
# go with it.
law hop_see_other_get:
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.Hop{"POST", "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "a.example", 80, "/y"}, 303) == Hop.Hop{"GET", "http://a.example/y", Hop.drop(["content-type", "content-length"], hs), Nil{}} : Hop.Hop}

# LAW: a 303 leaves a HEAD a HEAD: it has no body to give up.
law hop_see_other_head:
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.Hop{"HEAD", "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "a.example", 80, "/y"}, 303) == Hop.Hop{"HEAD", "http://a.example/y", Hop.drop(["content-type", "content-length"], hs), Nil{}} : Hop.Hop}

# LAW: a status that isn't a redirect sends nothing further: the response is the answer.
law hop_no_redirect_no_hop:
  for h: Hop.Hop
  {Hop.judge.resp(h, Url.Url{"http", "a.example", 80, "/x"}, 200, "http://a.example/y", Hop.judge.follows(200, "http://a.example/y")) == Hop.Answer{h} : Hop.Next}

# LAW: a redirect that names no Location sends nothing further either.
law hop_empty_location_no_hop:
  for h: Hop.Hop
  {Hop.judge.resp(h, Url.Url{"http", "a.example", 80, "/x"}, 302, "", Hop.judge.follows(302, "")) == Hop.Answer{h} : Hop.Next}

# LAW: a redirect to a Location that isn't an http(s) url is refused.
law hop_bad_location_refused:
  for h: Hop.Hop
  for status: U32
  {Hop.judge.next(h, Url.Url{"http", "a.example", 80, "/x"}, status, Url.resolve(Url.Url{"http", "a.example", 80, "/x"}, "ftp://a.example/y")) == Hop.Refuse{"a redirect to a location that isn't a url"} : Hop.Next}

# LAW: drop takes out exactly the headers it names, whatever their case, and keeps the rest in
# the order they came: two names, spelled in another case, gone from three headers.
law hop_drop_named:
  for v: String
  {Hop.drop(["authorization", "cookie"], [("Authorization", v), ("x-other", "1"), ("COOKIE", "c")]) == [("x-other", "1")] : List<&2, Http1.Field()>}

# LAW: credentials dropped at one hop stay dropped: after a.example -> b.example -> a.example,
# the request carries none, even back at the origin that was sent them.
law hop_credentials_stay_dropped:
  for +hs: List<&2, Http1.Field()>
  for +b: List<&2, U32>
  {Hop.judge.go(Hop.judge.go(Hop.judge.go(Hop.Hop{"GET", "http://a.example/x", ("authorization", "t") <> hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307), Url.Url{"http", "b.example", 80, "/y"}, Url.Url{"http", "a.example", 80, "/x"}, 307), Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307) == Hop.judge.go(Hop.judge.go(Hop.judge.go(Hop.Hop{"GET", "http://a.example/x", hs, b}, Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307), Url.Url{"http", "b.example", 80, "/y"}, Url.Url{"http", "a.example", 80, "/x"}, 307), Url.Url{"http", "a.example", 80, "/x"}, Url.Url{"http", "b.example", 80, "/y"}, 307) : Hop.Hop}

# end http
