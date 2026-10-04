# offline checks for lib/chaki/tlsmsg.bend. The server's flight is RFC 8448 section 3 and
# the HelloRetryRequest RFC 8448 section 5, copied verbatim. The ClientHello is checked
# against the layout RFC 8446 4.1.2 asks for: the bytes by hand, then walked back field by
# field. The alert payload is RFC 8448 3's.
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T
import ../lib/chaki/tlsmsg.bend as Tls

# RFC 8448 3 (Simple 1-RTT), the server's flight and RFC 8448 5's HelloRetryRequest
# --------------------------------------------------------------------------------

def sh() -> List<&2, U32>:
  Bytes.of_hex("02 00 00 56 03 03 a6 af 06 a4 12 18 60 dc 5e 6e 60 24 9c d3 4c 95 93 0c 8a c5 cb 14 34 da c1 55 77 2e d3 e2 69 28 00 13 01 00 00 2e 00 33 00 24 00 1d 00 20 c9 82 88 76 11 20 95 fe 66 76 2b db f7 c6 72 e1 56 d6 cc 25 3b 83 3d f1 dd 69 b1 b0 4e 75 1f 0f 00 2b 00 02 03 04")

def sh.rec() -> List<&2, U32>:
  Bytes.of_hex("16 03 03 00 5a 02 00 00 56 03 03 a6 af 06 a4 12 18 60 dc 5e 6e 60 24 9c d3 4c 95 93 0c 8a c5 cb 14 34 da c1 55 77 2e d3 e2 69 28 00 13 01 00 00 2e 00 33 00 24 00 1d 00 20 c9 82 88 76 11 20 95 fe 66 76 2b db f7 c6 72 e1 56 d6 cc 25 3b 83 3d f1 dd 69 b1 b0 4e 75 1f 0f 00 2b 00 02 03 04")

def ee() -> List<&2, U32>:
  Bytes.of_hex("08 00 00 24 00 22 00 0a 00 14 00 12 00 1d 00 17 00 18 00 19 01 00 01 01 01 02 01 03 01 04 00 1c 00 02 40 01 00 00 00 00")

def cert() -> List<&2, U32>:
  Bytes.of_hex("0b 00 01 b9 00 00 01 b5 00 01 b0 30 82 01 ac 30 82 01 15 a0 03 02 01 02 02 01 02 30 0d 06 09 2a 86 48 86 f7 0d 01 01 0b 05 00 30 0e 31 0c 30 0a 06 03 55 04 03 13 03 72 73 61 30 1e 17 0d 31 36 30 37 33 30 30 31 32 33 35 39 5a 17 0d 32 36 30 37 33 30 30 31 32 33 35 39 5a 30 0e 31 0c 30 0a 06 03 55 04 03 13 03 72 73 61 30 81 9f 30 0d 06 09 2a 86 48 86 f7 0d 01 01 01 05 00 03 81 8d 00 30 81 89 02 81 81 00 b4 bb 49 8f 82 79 30 3d 98 08 36 39 9b 36 c6 98 8c 0c 68 de 55 e1 bd b8 26 d3 90 1a 24 61 ea fd 2d e4 9a 91 d0 15 ab bc 9a 95 13 7a ce 6c 1a f1 9e aa 6a f9 8c 7c ed 43 12 09 98 e1 87 a8 0e e0 cc b0 52 4b 1b 01 8c 3e 0b 63 26 4d 44 9a 6d 38 e2 2a 5f da 43 08 46 74 80 30 53 0e f0 46 1c 8c a9 d9 ef bf ae 8e a6 d1 d0 3e 2b d1 93 ef f0 ab 9a 80 02 c4 74 28 a6 d3 5a 8d 88 d7 9f 7f 1e 3f 02 03 01 00 01 a3 1a 30 18 30 09 06 03 55 1d 13 04 02 30 00 30 0b 06 03 55 1d 0f 04 04 03 02 05 a0 30 0d 06 09 2a 86 48 86 f7 0d 01 01 0b 05 00 03 81 81 00 85 aa d2 a0 e5 b9 27 6b 90 8c 65 f7 3a 72 67 17 06 18 a5 4c 5f 8a 7b 33 7d 2d f7 a5 94 36 54 17 f2 ea e8 f8 a5 8c 8f 81 72 f9 31 9c f3 6b 7f d6 c5 5b 80 f2 1a 03 01 51 56 72 60 96 fd 33 5e 5e 67 f2 db f1 02 70 2e 60 8c ca e6 be c1 fc 63 a4 2a 99 be 5c 3e b7 10 7c 3c 54 e9 b9 eb 2b d5 20 3b 1c 3b 84 e0 a8 b2 f7 59 40 9b a3 ea c9 d9 1d 40 2d cc 0c c8 f8 96 12 29 ac 91 87 b4 2b 4d e1 00 00")

def cert.verify() -> List<&2, U32>:
  Bytes.of_hex("0f 00 00 84 08 04 00 80 5a 74 7c 5d 88 fa 9b d2 e5 5a b0 85 a6 10 15 b7 21 1f 82 4c d4 84 14 5a b3 ff 52 f1 fd a8 47 7b 0b 7a bc 90 db 78 e2 d3 3a 5c 14 1a 07 86 53 fa 6b ef 78 0c 5e a2 48 ee aa a7 85 c4 f3 94 ca b6 d3 0b be 8d 48 59 ee 51 1f 60 29 57 b1 54 11 ac 02 76 71 45 9e 46 44 5c 9e a5 8c 18 1e 81 8e 95 b8 c3 fb 0b f3 27 84 09 d3 be 15 2a 3d a5 04 3e 06 3d da 65 cd f5 ae a2 0d 53 df ac d4 2f 74 f3")

def fin() -> List<&2, U32>:
  Bytes.of_hex("14 00 00 20 9b 9b 14 1d 90 63 37 fb d2 cb dc e7 1d f4 de da 4a b4 2c 30 95 72 cb 7f ff ee 54 54 b7 8f 07 18")

def flight() -> List<&2, U32>:
  Bytes.of_hex("08 00 00 24 00 22 00 0a 00 14 00 12 00 1d 00 17 00 18 00 19 01 00 01 01 01 02 01 03 01 04 00 1c 00 02 40 01 00 00 00 00 0b 00 01 b9 00 00 01 b5 00 01 b0 30 82 01 ac 30 82 01 15 a0 03 02 01 02 02 01 02 30 0d 06 09 2a 86 48 86 f7 0d 01 01 0b 05 00 30 0e 31 0c 30 0a 06 03 55 04 03 13 03 72 73 61 30 1e 17 0d 31 36 30 37 33 30 30 31 32 33 35 39 5a 17 0d 32 36 30 37 33 30 30 31 32 33 35 39 5a 30 0e 31 0c 30 0a 06 03 55 04 03 13 03 72 73 61 30 81 9f 30 0d 06 09 2a 86 48 86 f7 0d 01 01 01 05 00 03 81 8d 00 30 81 89 02 81 81 00 b4 bb 49 8f 82 79 30 3d 98 08 36 39 9b 36 c6 98 8c 0c 68 de 55 e1 bd b8 26 d3 90 1a 24 61 ea fd 2d e4 9a 91 d0 15 ab bc 9a 95 13 7a ce 6c 1a f1 9e aa 6a f9 8c 7c ed 43 12 09 98 e1 87 a8 0e e0 cc b0 52 4b 1b 01 8c 3e 0b 63 26 4d 44 9a 6d 38 e2 2a 5f da 43 08 46 74 80 30 53 0e f0 46 1c 8c a9 d9 ef bf ae 8e a6 d1 d0 3e 2b d1 93 ef f0 ab 9a 80 02 c4 74 28 a6 d3 5a 8d 88 d7 9f 7f 1e 3f 02 03 01 00 01 a3 1a 30 18 30 09 06 03 55 1d 13 04 02 30 00 30 0b 06 03 55 1d 0f 04 04 03 02 05 a0 30 0d 06 09 2a 86 48 86 f7 0d 01 01 0b 05 00 03 81 81 00 85 aa d2 a0 e5 b9 27 6b 90 8c 65 f7 3a 72 67 17 06 18 a5 4c 5f 8a 7b 33 7d 2d f7 a5 94 36 54 17 f2 ea e8 f8 a5 8c 8f 81 72 f9 31 9c f3 6b 7f d6 c5 5b 80 f2 1a 03 01 51 56 72 60 96 fd 33 5e 5e 67 f2 db f1 02 70 2e 60 8c ca e6 be c1 fc 63 a4 2a 99 be 5c 3e b7 10 7c 3c 54 e9 b9 eb 2b d5 20 3b 1c 3b 84 e0 a8 b2 f7 59 40 9b a3 ea c9 d9 1d 40 2d cc 0c c8 f8 96 12 29 ac 91 87 b4 2b 4d e1 00 00 0f 00 00 84 08 04 00 80 5a 74 7c 5d 88 fa 9b d2 e5 5a b0 85 a6 10 15 b7 21 1f 82 4c d4 84 14 5a b3 ff 52 f1 fd a8 47 7b 0b 7a bc 90 db 78 e2 d3 3a 5c 14 1a 07 86 53 fa 6b ef 78 0c 5e a2 48 ee aa a7 85 c4 f3 94 ca b6 d3 0b be 8d 48 59 ee 51 1f 60 29 57 b1 54 11 ac 02 76 71 45 9e 46 44 5c 9e a5 8c 18 1e 81 8e 95 b8 c3 fb 0b f3 27 84 09 d3 be 15 2a 3d a5 04 3e 06 3d da 65 cd f5 ae a2 0d 53 df ac d4 2f 74 f3 14 00 00 20 9b 9b 14 1d 90 63 37 fb d2 cb dc e7 1d f4 de da 4a b4 2c 30 95 72 cb 7f ff ee 54 54 b7 8f 07 18")

def flight.rec() -> List<&2, U32>:
  Bytes.of_hex("17 03 03 02 a2 d1 ff 33 4a 56 f5 bf f6 59 4a 07 cc 87 b5 80 23 3f 50 0f 45 e4 89 e7 f3 3a f3 5e df 78 69 fc f4 0a a4 0a a2 b8 ea 73 f8 48 a7 ca 07 61 2e f9 f9 45 cb 96 0b 40 68 90 51 23 ea 78 b1 11 b4 29 ba 91 91 cd 05 d2 a3 89 28 0f 52 61 34 aa dc 7f c7 8c 4b 72 9d f8 28 b5 ec f7 b1 3b d9 ae fb 0e 57 f2 71 58 5b 8e a9 bb 35 5c 7c 79 02 07 16 cf b9 b1 18 3e f3 ab 20 e3 7d 57 a6 b9 d7 47 76 09 ae e6 e1 22 a4 cf 51 42 73 25 25 0c 7d 0e 50 92 89 44 4c 9b 3a 64 8f 1d 71 03 5d 2e d6 5b 0e 3c dd 0c ba e8 bf 2d 0b 22 78 12 cb b3 60 98 72 55 cc 74 41 10 c4 53 ba a4 fc d6 10 92 8d 80 98 10 e4 b7 ed 1a 8f d9 91 f0 6a a6 24 82 04 79 7e 36 a6 a7 3b 70 a2 55 9c 09 ea d6 86 94 5b a2 46 ab 66 e5 ed d8 04 4b 4c 6d e3 fc f2 a8 94 41 ac 66 27 2f d8 fb 33 0e f8 19 05 79 b3 68 45 96 c9 60 bd 59 6e ea 52 0a 56 a8 d6 50 f5 63 aa d2 74 09 96 0d ca 63 d3 e6 88 61 1e a5 e2 2f 44 15 cf 95 38 d5 1a 20 0c 27 03 42 72 96 8a 26 4e d6 54 0c 84 83 8d 89 f7 2c 24 46 1a ad 6d 26 f5 9e ca ba 9a cb bb 31 7b 66 d9 02 f4 f2 92 a3 6a c1 b6 39 c6 37 ce 34 31 17 b6 59 62 22 45 31 7b 49 ee da 0c 62 58 f1 00 d7 d9 61 ff b1 38 64 7e 92 ea 33 0f ae ea 6d fa 31 c7 a8 4d c3 bd 7e 1b 7a 6c 71 78 af 36 87 90 18 e3 f2 52 10 7f 24 3d 24 3d c7 33 9d 56 84 c8 b0 37 8b f3 02 44 da 8c 87 c8 43 f5 e5 6e b4 c5 e8 28 0a 2b 48 05 2c f9 3b 16 49 9a 66 db 7c ca 71 e4 59 94 26 f7 d4 61 e6 6f 99 88 2b d8 9f c5 08 00 be cc a6 2d 6c 74 11 6d bd 29 72 fd a1 fa 80 f8 5d f8 81 ed be 5a 37 66 89 36 b3 35 58 3b 59 91 86 dc 5c 69 18 a3 96 fa 48 a1 81 d6 b6 fa 4f 9d 62 d5 13 af bb 99 2f 2b 99 2f 67 f8 af e6 7f 76 91 3f a3 88 cb 56 30 c8 ca 01 e0 c6 5d 11 c6 6a 1e 2a c4 c8 59 77 b7 c7 a6 99 9b bf 10 dc 35 ae 69 f5 51 56 14 63 6c 0b 9b 68 c1 9e d2 e3 1c 0b 3b 66 76 30 38 eb ba 42 f3 b3 8e dc 03 99 f3 a9 f2 3f aa 63 97 8c 31 7f c9 fa 66 a7 3f 60 f0 50 4d e9 3b 5b 84 5e 27 55 92 c1 23 35 ee 34 0b bc 4f dd d5 02 78 40 16 e4 b3 be 7e f0 4d da 49 f4 b4 40 a3 0c b5 d2 af 93 98 28 fd 4a e3 79 4e 44 f9 4d f5 a6 31 ed e4 2c 17 19 bf da bf 02 53 fe 51 75 be 89 8e 75 0e dc 53 37 0d 2b")

def app() -> List<&2, U32>:
  Bytes.of_hex("50 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25 26 27 28 29 2a 2b 2c 2d 2e 2f 30")

def hrr() -> List<&2, U32>:
  Bytes.of_hex("02 00 00 ac 03 03 cf 21 ad 74 e5 9a 61 11 be 1d 8c 02 1e 65 b8 91 c2 a2 11 16 7a bb 8c 5e 07 9e 09 e2 c8 a8 33 9c 00 13 01 00 00 84 00 33 00 02 00 17 00 2c 00 74 00 72 71 dc d0 4b b8 8b c3 18 91 19 39 8a 00 00 00 00 ee fa fc 76 c1 46 b8 23 b0 96 f8 aa ca d3 65 dd 00 30 95 3f 4e df 62 56 36 e5 f2 1b b2 e2 3f cc 65 4b 1b 5b 40 31 8d 10 d1 37 ab cb b8 75 74 e3 6e 8a 1f 02 5f 7d fa 5d 6e 50 78 1b 5e da 4a a1 5b 0c 8b e7 78 25 7d 16 aa 30 30 e9 e7 84 1d d9 e4 c0 34 22 67 e8 ca 0c af 57 1f b2 b7 cf f0 f9 34 b0 00 2b 00 02 03 04")

def close() -> List<&2, U32>:
  Bytes.of_hex("01 00")

# Digging out of the types the module answers with
# ------------------------------------------------

def recs(m: Maybe<&1, List<&2, Tls.Rec> & List<&2, U32>>) -> List<&2, Tls.Rec>:
  match m:
    case None{}:
      Nil{}
    case Some{(rs, rest)}:
      rs

def rest.of(m: Maybe<&1, List<&2, Tls.Rec> & List<&2, U32>>) -> List<&2, U32>:
  match m:
    case None{}:
      Nil{}
    case Some{(rs, rest)}:
      rest

def still.none(m: Maybe<&1, List<&2, Tls.Rec> & List<&2, U32>>) -> String:
  match m:
    case Some{v}:
      "some"
    case None{}:
      "none"

def rec.count(rs: List<&2, Tls.Rec>) -> String:
  Nat.show(List.length(&2, Tls.Rec, rs))

def rec.ctype(rs: List<&2, Tls.Rec>) -> U32:
  match rs:
    case Nil{}:
      0
    case Con{Tls.Rec{ctype, body}, t}:
      ctype

def rec.body(rs: List<&2, Tls.Rec>) -> List<&2, U32>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{Tls.Rec{ctype, body}, t}:
      body

def rec.body2(rs: List<&2, Tls.Rec>) -> List<&2, U32>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      rec.body(t)

def rec.bodies.go(rs: List<&2, Tls.Rec>, acc: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case Nil{}:
      acc
    case Con{Tls.Rec{ctype, body}, t}:
      rec.bodies.go(t, Bytes.cat(acc, body))

# the record bodies of a buffer, concatenated the way the transcript wants them
def rec.bodies(m: Maybe<&1, List<&2, Tls.Rec> & List<&2, U32>>) -> List<&2, U32>:
  rec.bodies.go(recs(m), Nil{})

# Tls.messages answers a pair, and a destructuring let may not open a computed value
def msgs.pair(p: List<&2, Tls.Msg> & List<&2, U32>) -> List<&2, Tls.Msg>:
  match p:
    case (xs, rest):
      xs

def msgs.left.of(p: List<&2, Tls.Msg> & List<&2, U32>) -> List<&2, U32>:
  match p:
    case (xs, rest):
      rest

def msgs(buf: List<&2, U32>) -> List<&2, Tls.Msg>:
  msgs.pair(Tls.messages(buf))

def msgs.left(buf: List<&2, U32>) -> List<&2, U32>:
  msgs.left.of(Tls.messages(buf))

def msg.count(xs: List<&2, Tls.Msg>) -> String:
  Nat.show(List.length(&2, Tls.Msg, xs))

def msg.raws.go(xs: List<&2, Tls.Msg>, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match xs:
    case Nil{}:
      List.reverse(&2, List<&2, U32>, acc)
    case Con{Tls.Msg{htype, body, +raw}, t}:
      msg.raws.go(t, raw <> acc)

def msg.raws(xs: List<&2, Tls.Msg>) -> List<&2, List<&2, U32>>:
  msg.raws.go(xs, Nil{})

def nth(xs: List<&2, List<&2, U32>>, n: Nat) -> List<&2, U32>:
  Maybe.default(&2, List<&2, U32>, List.get(&2, List<&2, U32>, xs, n), Nil{})

def ok.alpn(r: Result<&1, &1, String, String>) -> String:
  match r:
    case Done{v}:
      v
    case Fail{e}:
      "fail"

def ok.der(r: Result<&1, &1, String, List<&2, List<&2, U32>>>) -> List<&2, List<&2, U32>>:
  match r:
    case Done{v}:
      v
    case Fail{e}:
      Nil{}

def said.der(r: Result<&1, &1, String, List<&2, List<&2, U32>>>) -> String:
  match r:
    case Done{v}:
      "done"
    case Fail{e}:
      "fail"

def der.count(xs: List<&2, List<&2, U32>>) -> String:
  Nat.show(List.length(&2, List<&2, U32>, xs))

def der.head(xs: List<&2, List<&2, U32>>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      h

def ok.scheme(r: Result<&1, &1, String, Tls.Verify>) -> U32:
  match r:
    case Done{Tls.Verify{scheme, sig}}:
      scheme
    case Fail{e}:
      0

def ok.sig(r: Result<&1, &1, String, Tls.Verify>) -> List<&2, U32>:
  match r:
    case Done{Tls.Verify{scheme, sig}}:
      sig
    case Fail{e}:
      Nil{}

def said.verify(r: Result<&1, &1, String, Tls.Verify>) -> String:
  match r:
    case Done{v}:
      "done"
    case Fail{e}:
      "fail"

def ok.suite(r: Result<&1, &1, String, Tls.Hello>) -> String:
  match r:
    case Done{Tls.Hello{suite, share, retry}}:
      U32.show(suite)
    case Fail{e}:
      "fail"

def ok.share(r: Result<&1, &1, String, Tls.Hello>) -> List<&2, U32>:
  match r:
    case Done{Tls.Hello{suite, share, retry}}:
      share
    case Fail{e}:
      Nil{}

def ok.retry(r: Result<&1, &1, String, Tls.Hello>) -> String:
  match r:
    case Done{Tls.Hello{suite, share, retry}}:
      T.yes(retry)
    case Fail{e}:
      "fail"

def ok.hello(r: Result<&1, &1, String, Tls.Hello>) -> String:
  match r:
    case Done{v}:
      "done"
    case Fail{e}:
      "fail"

def inner.ctype(m: Maybe<&2, Tls.Rec>) -> U32:
  match m:
    case Some{Tls.Rec{ctype, body}}:
      ctype
    case None{}:
      0

def inner.body(m: Maybe<&2, Tls.Rec>) -> List<&2, U32>:
  match m:
    case Some{Tls.Rec{ctype, body}}:
      body
    case None{}:
      Nil{}

def inner.state(m: Maybe<&2, Tls.Rec>) -> String:
  match m:
    case Some{v}:
      "some"
    case None{}:
      "none"

# Building blocks and the ClientHello
# -----------------------------------

# the two bytes at off replaced by a 16-bit value, for the ServerHello negatives
def with16(+body: List<&2, U32>, +off: Nat, +v: U32) -> List<&2, U32>:
  Bytes.cat(Bytes.take(body, off), Bytes.cat(Bytes.be16(v), Bytes.drop(body, Nat.add(off, 2n))))

def sh.body() -> List<&2, U32>:
  Bytes.drop(sh(), 4n)

def hrr.body() -> List<&2, U32>:
  Bytes.drop(hrr(), 4n)

def cert.body() -> List<&2, U32>:
  Bytes.drop(cert(), 4n)

def cv.body() -> List<&2, U32>:
  Bytes.drop(cert.verify(), 4n)

def ee.body() -> List<&2, U32>:
  Bytes.drop(ee(), 4n)

def app.inner() -> List<&2, U32>:
  Bytes.cat(app(), [23])

def app.padded() -> List<&2, U32>:
  Bytes.cat(app(), [23, 0, 0, 0])

def random() -> List<&2, U32>:
  Bytes.of_hex("00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f")

def session() -> List<&2, U32>:
  Bytes.of_hex("a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 aa ab ac ad ae af b0 b1 b2 b3 b4 b5 b6 b7 b8 b9 ba bb bc bd be bf")

def share() -> List<&2, U32>:
  Bytes.of_hex("99 38 1d e5 60 e4 bd 43 d2 3d 8e 43 5a 7d ba fe b3 c0 6e 51 c1 3c ae 4d 54 13 69 1e 52 9a af 2c")

def hello() -> List<&2, U32>:
  Tls.client_hello(random(), session(), "server", share())

def hello.ip() -> List<&2, U32>:
  Tls.client_hello(random(), session(), "", share())

# the extension block of a ClientHello message: 4 header bytes and 77 bytes of fields
def ch.exts(+h: List<&2, U32>) -> List<&2, U32>:
  Bytes.drop(h, 81n)

def main() -> IO(Unit):
  do IO<Unit>:
    # Record layer
    IO.print(T.hex("record: a header", Tls.record(22, Bytes.of_hex("aabb")), "16 03 03 00 02 aa bb"))
    IO.print(T.hex("record: no payload", Tls.record(21, Nil{}), "15 03 03 00 00"))
    IO.print(T.hex("record: a full 2^14 payload", Bytes.take(Tls.record(23, Bytes.zeros(16384n)), 5n), "17 03 03 40 00"))
    IO.print(T.hex("handshake: a header", Tls.handshake(1, Bytes.of_hex("aabb")), "01 00 00 02 aa bb"))
    IO.print(T.hex("handshake: a 24-bit length", Bytes.take(Tls.handshake(11, Bytes.zeros(300n)), 4n), "0b 00 01 2c"))

    # records on RFC 8448 3's flight
    IO.print(T.eq("RFC 8448 3: one record in the buffer", rec.count(recs(Tls.records(sh.rec()))), "1"))
    IO.print(T.eq("RFC 8448 3: it is a handshake record", U32.show(rec.ctype(recs(Tls.records(sh.rec())))), "22"))
    IO.print(T.hex("RFC 8448 3: its body is the ServerHello", rec.body(recs(Tls.records(sh.rec()))), "02 00 00 56 03 03 a6 af 06 a4 12 18 60 dc 5e 6e 60 24 9c d3 4c 95 93 0c 8a c5 cb 14 34 da c1 55 77 2e d3 e2 69 28 00 13 01 00 00 2e 00 33 00 24 00 1d 00 20 c9 82 88 76 11 20 95 fe 66 76 2b db f7 c6 72 e1 56 d6 cc 25 3b 83 3d f1 dd 69 b1 b0 4e 75 1f 0f 00 2b 00 02 03 04"))
    IO.print(T.hex("RFC 8448 3: nothing is left over", rest.of(Tls.records(sh.rec())), ""))
    IO.print(T.eq("RFC 8448 3: two records in the buffer", rec.count(recs(Tls.records(Bytes.cat(sh.rec(), flight.rec())))), "2"))
    IO.print(T.eq("RFC 8448 3: the second is application_data", U32.show(rec.ctype(recs(Tls.records(Bytes.cat(sh.rec(), flight.rec()))))), "22"))
    IO.print(T.eq("RFC 8448 3: the second record's body", U32.show(Bytes.len(rec.body2(recs(Tls.records(Bytes.cat(sh.rec(), flight.rec())))))), "674"))
    IO.print(T.hex("RFC 8448 3: the rest after both records", rest.of(Tls.records(Bytes.cat(sh.rec(), flight.rec()))), ""))
    IO.print(T.hex("records: an empty buffer", rest.of(Tls.records(Nil{})), ""))
    IO.print(T.eq("records: an empty buffer holds none", rec.count(recs(Tls.records(Nil{}))), "0"))
    IO.print(T.hex("records: three bytes are not a header", rest.of(Tls.records(Bytes.take(sh.rec(), 3n))), "16 03 03"))
    IO.print(T.eq("records: three bytes hold none", rec.count(recs(Tls.records(Bytes.take(sh.rec(), 3n)))), "0"))
    IO.print(T.hex("records: a record cut mid-flight comes back", rest.of(Tls.records(Bytes.cat(sh.rec(), Bytes.take(flight.rec(), 100n)))), "17 03 03 02 a2 d1 ff 33 4a 56 f5 bf f6 59 4a 07 cc 87 b5 80 23 3f 50 0f 45 e4 89 e7 f3 3a f3 5e df 78 69 fc f4 0a a4 0a a2 b8 ea 73 f8 48 a7 ca 07 61 2e f9 f9 45 cb 96 0b 40 68 90 51 23 ea 78 b1 11 b4 29 ba 91 91 cd 05 d2 a3 89 28 0f 52 61 34 aa dc 7f c7 8c 4b 72 9d f8 28 b5 ec f7 b1 3b d9 ae fb 0e"))
    IO.print(T.eq("records: the whole record before the cut", rec.count(recs(Tls.records(Bytes.cat(sh.rec(), Bytes.take(flight.rec(), 100n))))), "1"))
    IO.print(T.eq("records: a bad type answers None", still.none(Tls.records(Bytes.of_hex("05 03 03 00 00"))), "none"))
    IO.print(T.eq("records: a bad version answers None", still.none(Tls.records(Bytes.of_hex("16 03 00 00 00"))), "none"))
    IO.print(T.eq("records: 2^14+257 answers None", still.none(Tls.records(Bytes.of_hex("16 03 03 41 01"))), "none"))
    IO.print(T.eq("records: 2^14+256 is a header", still.none(Tls.records(Bytes.of_hex("16 03 03 41 00"))), "some"))
    IO.print(T.hex("records: 2^14+256 comes back short", rest.of(Tls.records(Bytes.of_hex("16 03 03 41 00"))), "16 03 03 41 00"))
    IO.print(T.hex("records: a 0x0301 legacy version", rec.body(recs(Tls.records(Bytes.of_hex("16 03 01 00 01 ff")))), "ff"))

    # messages on RFC 8448 3's flight
    IO.print(T.eq("RFC 8448 3: four handshake messages", msg.count(msgs(flight())), "4"))
    IO.print(T.hex("RFC 8448 3: EncryptedExtensions", nth(msg.raws(msgs(flight())), 0n), "08 00 00 24 00 22 00 0a 00 14 00 12 00 1d 00 17 00 18 00 19 01 00 01 01 01 02 01 03 01 04 00 1c 00 02 40 01 00 00 00 00"))
    IO.print(T.hex("RFC 8448 3: Certificate", nth(msg.raws(msgs(flight())), 1n), "0b 00 01 b9 00 00 01 b5 00 01 b0 30 82 01 ac 30 82 01 15 a0 03 02 01 02 02 01 02 30 0d 06 09 2a 86 48 86 f7 0d 01 01 0b 05 00 30 0e 31 0c 30 0a 06 03 55 04 03 13 03 72 73 61 30 1e 17 0d 31 36 30 37 33 30 30 31 32 33 35 39 5a 17 0d 32 36 30 37 33 30 30 31 32 33 35 39 5a 30 0e 31 0c 30 0a 06 03 55 04 03 13 03 72 73 61 30 81 9f 30 0d 06 09 2a 86 48 86 f7 0d 01 01 01 05 00 03 81 8d 00 30 81 89 02 81 81 00 b4 bb 49 8f 82 79 30 3d 98 08 36 39 9b 36 c6 98 8c 0c 68 de 55 e1 bd b8 26 d3 90 1a 24 61 ea fd 2d e4 9a 91 d0 15 ab bc 9a 95 13 7a ce 6c 1a f1 9e aa 6a f9 8c 7c ed 43 12 09 98 e1 87 a8 0e e0 cc b0 52 4b 1b 01 8c 3e 0b 63 26 4d 44 9a 6d 38 e2 2a 5f da 43 08 46 74 80 30 53 0e f0 46 1c 8c a9 d9 ef bf ae 8e a6 d1 d0 3e 2b d1 93 ef f0 ab 9a 80 02 c4 74 28 a6 d3 5a 8d 88 d7 9f 7f 1e 3f 02 03 01 00 01 a3 1a 30 18 30 09 06 03 55 1d 13 04 02 30 00 30 0b 06 03 55 1d 0f 04 04 03 02 05 a0 30 0d 06 09 2a 86 48 86 f7 0d 01 01 0b 05 00 03 81 81 00 85 aa d2 a0 e5 b9 27 6b 90 8c 65 f7 3a 72 67 17 06 18 a5 4c 5f 8a 7b 33 7d 2d f7 a5 94 36 54 17 f2 ea e8 f8 a5 8c 8f 81 72 f9 31 9c f3 6b 7f d6 c5 5b 80 f2 1a 03 01 51 56 72 60 96 fd 33 5e 5e 67 f2 db f1 02 70 2e 60 8c ca e6 be c1 fc 63 a4 2a 99 be 5c 3e b7 10 7c 3c 54 e9 b9 eb 2b d5 20 3b 1c 3b 84 e0 a8 b2 f7 59 40 9b a3 ea c9 d9 1d 40 2d cc 0c c8 f8 96 12 29 ac 91 87 b4 2b 4d e1 00 00"))
    IO.print(T.hex("RFC 8448 3: CertificateVerify", nth(msg.raws(msgs(flight())), 2n), "0f 00 00 84 08 04 00 80 5a 74 7c 5d 88 fa 9b d2 e5 5a b0 85 a6 10 15 b7 21 1f 82 4c d4 84 14 5a b3 ff 52 f1 fd a8 47 7b 0b 7a bc 90 db 78 e2 d3 3a 5c 14 1a 07 86 53 fa 6b ef 78 0c 5e a2 48 ee aa a7 85 c4 f3 94 ca b6 d3 0b be 8d 48 59 ee 51 1f 60 29 57 b1 54 11 ac 02 76 71 45 9e 46 44 5c 9e a5 8c 18 1e 81 8e 95 b8 c3 fb 0b f3 27 84 09 d3 be 15 2a 3d a5 04 3e 06 3d da 65 cd f5 ae a2 0d 53 df ac d4 2f 74 f3"))
    IO.print(T.hex("RFC 8448 3: Finished", nth(msg.raws(msgs(flight())), 3n), "14 00 00 20 9b 9b 14 1d 90 63 37 fb d2 cb dc e7 1d f4 de da 4a b4 2c 30 95 72 cb 7f ff ee 54 54 b7 8f 07 18"))
    IO.print(T.hex("messages: nothing is left over", msgs.left(flight()), ""))
    IO.print(T.ok("messages: a message cut mid-body comes back", Bytes.eq(msgs.left(Bytes.take(flight(), 100n)), Bytes.take(Bytes.drop(flight(), 40n), 60n))))
    IO.print(T.eq("messages: the whole message before the cut", msg.count(msgs(Bytes.take(flight(), 100n))), "1"))
    IO.print(T.eq("messages: a three byte header is not one", msg.count(msgs(Bytes.of_hex("01 00 00"))), "0"))
    IO.print(T.hex("messages: a three byte header comes back", msgs.left(Bytes.of_hex("01 00 00")), "01 00 00"))
    IO.print(T.hex("messages: an empty body", nth(msg.raws(msgs(Tls.handshake(24, Nil{}))), 0n), "18 00 00 00"))
    IO.print(T.hex("messages: a body of 300 bytes", Bytes.take(nth(msg.raws(msgs(Tls.handshake(24, Bytes.zeros(300n)))), 0n), 4n), "18 00 01 2c"))

    # the same, through two records: the caller concatenates the bodies
    IO.print(T.eq("RFC 8448 3: a message spanning two records", msg.count(msgs(rec.bodies(Tls.records(Bytes.cat(Tls.record(22, Bytes.take(flight(), 100n)), Tls.record(22, Bytes.drop(flight(), 100n))))))), "4"))
    IO.print(T.hex("RFC 8448 3: EncryptedExtensions after the split", nth(msg.raws(msgs(rec.bodies(Tls.records(Bytes.cat(Tls.record(22, Bytes.take(flight(), 100n)), Tls.record(22, Bytes.drop(flight(), 100n))))))), 0n), "08 00 00 24 00 22 00 0a 00 14 00 12 00 1d 00 17 00 18 00 19 01 00 01 01 01 02 01 03 01 04 00 1c 00 02 40 01 00 00 00 00"))

    # ServerHello
    IO.print(T.eq("RFC 8448 3: the suite", ok.suite(Tls.server_hello(sh.body())), "4865"))
    IO.print(T.hex("RFC 8448 3: the server's key share", ok.share(Tls.server_hello(sh.body())), "c9 82 88 76 11 20 95 fe 66 76 2b db f7 c6 72 e1 56 d6 cc 25 3b 83 3d f1 dd 69 b1 b0 4e 75 1f 0f"))
    IO.print(T.eq("RFC 8448 3: not a HelloRetryRequest", ok.retry(Tls.server_hello(sh.body())), "no"))
    IO.print(T.eq("RFC 8448 3: the encrypted extensions record's ctype", U32.show(rec.ctype(recs(Tls.records(flight.rec())))), "23"))
    IO.print(T.eq("RFC 8448 5: a P-256 HelloRetryRequest fails", ok.hello(Tls.server_hello(hrr.body())), "fail"))
    IO.print(T.eq("RFC 8448 5: the same for x25519 is one", ok.hello(Tls.server_hello(with16(hrr.body(), 44n, 29))), "done"))
    IO.print(T.eq("RFC 8448 5: it is recognized as a retry", ok.retry(Tls.server_hello(with16(hrr.body(), 44n, 29))), "yes"))
    IO.print(T.hex("RFC 8448 5: it carries no key", ok.share(Tls.server_hello(with16(hrr.body(), 44n, 29))), ""))
    IO.print(T.eq("server_hello: a wrong supported_versions fails", ok.hello(Tls.server_hello(with16(sh.body(), 84n, 771))), "fail"))
    IO.print(T.eq("server_hello: an unoffered suite fails", ok.hello(Tls.server_hello(with16(sh.body(), 35n, 4866))), "fail"))
    IO.print(T.eq("server_hello: a P-256 key share fails", ok.hello(Tls.server_hello(with16(sh.body(), 44n, 23))), "fail"))
    IO.print(T.eq("server_hello: a body cut short fails", ok.hello(Tls.server_hello(Bytes.take(sh.body(), 20n))), "fail"))
    IO.print(T.eq("server_hello: an empty body fails", ok.hello(Tls.server_hello(Nil{})), "fail"))
    IO.print(T.eq("server_hello: extensions past the body fail", ok.hello(Tls.server_hello(with16(sh.body(), 38n, 200))), "fail"))

    # EncryptedExtensions
    IO.print(T.eq("RFC 8448 3: no ALPN in EncryptedExtensions", ok.alpn(Tls.encrypted_extensions(ee.body())), ""))
    IO.print(T.eq("encrypted_extensions: the ALPN the server picked", ok.alpn(Tls.encrypted_extensions(Bytes.of_hex("00 0f 00 10 00 0b 00 09 08 68 74 74 70 2f 31 2e 31"))), "http/1.1"))
    IO.print(T.eq("encrypted_extensions: no extensions at all", ok.alpn(Tls.encrypted_extensions(Bytes.of_hex("00 00"))), ""))
    IO.print(T.eq("encrypted_extensions: an empty server_name only", ok.alpn(Tls.encrypted_extensions(Bytes.of_hex("00 04 00 00 00 00"))), ""))
    IO.print(T.eq("encrypted_extensions: RFC 8448 3's odd ALPN bytes fail", ok.alpn(Tls.encrypted_extensions(Bytes.of_hex("00 06 00 10 00 02 40 01"))), "fail"))
    IO.print(T.eq("encrypted_extensions: an extension past the block fails", ok.alpn(Tls.encrypted_extensions(Bytes.of_hex("00 04 00 10 00 08"))), "fail"))
    IO.print(T.eq("encrypted_extensions: trailing bytes fail", ok.alpn(Tls.encrypted_extensions(Bytes.of_hex("00 04 00 00 00 00 00"))), "fail"))
    IO.print(T.eq("encrypted_extensions: an empty body fails", ok.alpn(Tls.encrypted_extensions(Nil{})), "fail"))
    IO.print(T.eq("encrypted_extensions: a cut protocol name fails", ok.alpn(Tls.encrypted_extensions(Bytes.of_hex("00 06 00 10 00 02 00 04"))), "fail"))

    # Certificate
    IO.print(T.eq("RFC 8448 3: one certificate", der.count(ok.der(Tls.certificate(cert.body()))), "1"))
    IO.print(T.eq("RFC 8448 3: its DER is 432 bytes", U32.show(Bytes.len(der.head(ok.der(Tls.certificate(cert.body()))))), "432"))
    IO.print(T.hex("RFC 8448 3: the DER head", Bytes.take(der.head(ok.der(Tls.certificate(cert.body()))), 4n), "30 82 01 ac"))
    IO.print(T.ok("RFC 8448 3: the DER bytes", Bytes.eq(der.head(ok.der(Tls.certificate(cert.body()))), Bytes.take(Bytes.drop(cert(), 11n), 432n))))
    IO.print(T.eq("certificate: an empty list", der.count(ok.der(Tls.certificate(Bytes.of_hex("00 00 00 00")))), "0"))
    IO.print(T.eq("certificate: a list past the body fails", said.der(Tls.certificate(Bytes.of_hex("00 00 01 00 00"))), "fail"))
    IO.print(T.eq("certificate: a cut entry fails", said.der(Tls.certificate(Bytes.of_hex("00 00 00 05 00 00 04 30"))), "fail"))
    IO.print(T.eq("certificate: an empty body fails", said.der(Tls.certificate(Nil{})), "fail"))

    # CertificateVerify
    IO.print(T.eq("RFC 8448 3: the signature scheme", U32.show(ok.scheme(Tls.certificate_verify(cv.body()))), "2052"))
    IO.print(T.eq("RFC 8448 3: the signature is 128 bytes", U32.show(Bytes.len(ok.sig(Tls.certificate_verify(cv.body())))), "128"))
    IO.print(T.ok("RFC 8448 3: the signature bytes", Bytes.eq(ok.sig(Tls.certificate_verify(cv.body())), Bytes.drop(cert.verify(), 8n))))
    IO.print(T.eq("certificate_verify: a length past the body fails", said.verify(Tls.certificate_verify(Bytes.of_hex("08 04 00 ff 00"))), "fail"))
    IO.print(T.eq("certificate_verify: a short body fails", said.verify(Tls.certificate_verify(Bytes.of_hex("08 04"))), "fail"))
    IO.print(T.eq("certificate_verify: an empty body fails", said.verify(Tls.certificate_verify(Nil{})), "fail"))

    # Alerts
    IO.print(T.eq("RFC 8448 3: close_notify", Tls.alert(close()), "close_notify"))
    IO.print(T.eq("alert: handshake_failure", Tls.alert(Bytes.of_hex("02 28")), "handshake_failure (40)"))
    IO.print(T.eq("alert: a warning names no code", Tls.alert(Bytes.of_hex("01 5a")), "user_canceled"))
    IO.print(T.eq("alert: a fatal alert carries its code", Tls.alert(Bytes.of_hex("02 50")), "internal_error (80)"))
    IO.print(T.eq("alert: a code the RFC doesn't name", Tls.alert(Bytes.of_hex("02 63")), "unknown (99)"))
    IO.print(T.eq("alert: one byte", Tls.alert(Bytes.of_hex("01")), "malformed alert"))
    IO.print(T.eq("alert: three bytes", Tls.alert(Bytes.of_hex("01 00 00")), "malformed alert"))
    IO.print(T.eq("alert: no bytes", Tls.alert(Nil{}), "malformed alert"))

    # TLSInnerPlaintext
    IO.print(T.eq("RFC 8448 3: an inner plaintext", U32.show(inner.ctype(Tls.inner(app.inner()))), "23"))
    IO.print(T.ok("RFC 8448 3: its content", Bytes.eq(inner.body(Tls.inner(app.inner())), app())))
    IO.print(T.eq("inner: the same with padding", U32.show(inner.ctype(Tls.inner(app.padded()))), "23"))
    IO.print(T.ok("inner: the padding is stripped", Bytes.eq(inner.body(Tls.inner(app.padded())), app())))
    IO.print(T.eq("inner: all zeros", inner.state(Tls.inner(Bytes.zeros(3n))), "none"))
    IO.print(T.eq("inner: no bytes", inner.state(Tls.inner(Nil{})), "none"))
    IO.print(T.eq("inner: a lone content type", U32.show(inner.ctype(Tls.inner(Bytes.of_hex("16")))), "22"))
    IO.print(T.hex("inner: its content is empty", inner.body(Tls.inner(Bytes.of_hex("16"))), ""))
    IO.print(T.hex("inner: a zero inside the content", inner.body(Tls.inner(Bytes.of_hex("01 00 16 00"))), "01 00"))
    IO.print(T.eq("inner: the content type after a zero", U32.show(inner.ctype(Tls.inner(Bytes.of_hex("01 00 16 00")))), "22"))

    # the ClientHello, byte for byte
    IO.print(T.hex("client_hello: RFC 8446 4.1.2 layout", hello(), "01 00 00 b6 03 03 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f 20 a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 aa ab ac ad ae af b0 b1 b2 b3 b4 b5 b6 b7 b8 b9 ba bb bc bd be bf 00 04 13 03 13 01 01 00 00 69 00 00 00 0b 00 09 00 00 06 73 65 72 76 65 72 00 0a 00 04 00 02 00 1d 00 0d 00 0e 00 0c 04 03 05 03 08 04 08 05 04 01 05 01 00 2b 00 03 02 03 04 00 33 00 26 00 24 00 1d 00 20 99 38 1d e5 60 e4 bd 43 d2 3d 8e 43 5a 7d ba fe b3 c0 6e 51 c1 3c ae 4d 54 13 69 1e 52 9a af 2c 00 10 00 0b 00 09 08 68 74 74 70 2f 31 2e 31"))
    IO.print(T.eq("client_hello: 186 octets", U32.show(Bytes.len(hello())), "186"))

    # and walked back from the bytes
    IO.print(T.hex("client_hello: the handshake header", Bytes.take(hello(), 4n), "01 00 00 b6"))
    IO.print(T.eq("client_hello: its 24-bit length", U32.show(Bytes.get.be(Bytes.drop(hello(), 1n), 3n)), "182"))
    IO.print(T.hex("client_hello: legacy_version", Bytes.take(Bytes.drop(hello(), 4n), 2n), "03 03"))
    IO.print(T.hex("client_hello: the random", Bytes.take(Bytes.drop(hello(), 6n), 32n), "00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f"))
    IO.print(T.hex("client_hello: the session id", Bytes.take(Bytes.drop(hello(), 38n), 33n), "20 a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 aa ab ac ad ae af b0 b1 b2 b3 b4 b5 b6 b7 b8 b9 ba bb bc bd be bf"))
    IO.print(T.hex("client_hello: the cipher suites", Bytes.take(Bytes.drop(hello(), 71n), 6n), "00 04 13 03 13 01"))
    IO.print(T.hex("client_hello: the compression method", Bytes.take(Bytes.drop(hello(), 77n), 2n), "01 00"))
    IO.print(T.hex("client_hello: the extensions length", Bytes.take(Bytes.drop(hello(), 79n), 2n), "00 69"))
    IO.print(T.eq("client_hello: the extensions add up", U32.show(Bytes.len(ch.exts(hello()))), "105"))
    IO.print(T.hex("client_hello: server_name", Bytes.take(ch.exts(hello()), 15n), "00 00 00 0b 00 09 00 00 06 73 65 72 76 65 72"))
    IO.print(T.hex("client_hello: supported_groups", Bytes.take(Bytes.drop(ch.exts(hello()), 15n), 8n), "00 0a 00 04 00 02 00 1d"))
    IO.print(T.hex("client_hello: signature_algorithms", Bytes.take(Bytes.drop(ch.exts(hello()), 23n), 18n), "00 0d 00 0e 00 0c 04 03 05 03 08 04 08 05 04 01 05 01"))
    IO.print(T.hex("client_hello: supported_versions", Bytes.take(Bytes.drop(ch.exts(hello()), 41n), 7n), "00 2b 00 03 02 03 04"))
    IO.print(T.hex("client_hello: key_share", Bytes.take(Bytes.drop(ch.exts(hello()), 48n), 42n), "00 33 00 26 00 24 00 1d 00 20 99 38 1d e5 60 e4 bd 43 d2 3d 8e 43 5a 7d ba fe b3 c0 6e 51 c1 3c ae 4d 54 13 69 1e 52 9a af 2c"))
    IO.print(T.hex("client_hello: ALPN", Bytes.take(Bytes.drop(ch.exts(hello()), 90n), 15n), "00 10 00 0b 00 09 08 68 74 74 70 2f 31 2e 31"))

    # an IP literal sends no server_name
    IO.print(T.hex("client_hello: no SNI for an IP literal", hello.ip(), "01 00 00 a7 03 03 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f 20 a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 aa ab ac ad ae af b0 b1 b2 b3 b4 b5 b6 b7 b8 b9 ba bb bc bd be bf 00 04 13 03 13 01 01 00 00 5a 00 0a 00 04 00 02 00 1d 00 0d 00 0e 00 0c 04 03 05 03 08 04 08 05 04 01 05 01 00 2b 00 03 02 03 04 00 33 00 26 00 24 00 1d 00 20 99 38 1d e5 60 e4 bd 43 d2 3d 8e 43 5a 7d ba fe b3 c0 6e 51 c1 3c ae 4d 54 13 69 1e 52 9a af 2c 00 10 00 0b 00 09 08 68 74 74 70 2f 31 2e 31"))
    IO.print(T.eq("client_hello: 171 octets without SNI", U32.show(Bytes.len(hello.ip())), "171"))
    IO.print(T.eq("client_hello: 90 extension bytes without SNI", U32.show(Bytes.len(ch.exts(hello.ip()))), "90"))
    IO.print(T.hex("client_hello: it starts at supported_groups", Bytes.take(ch.exts(hello.ip()), 8n), "00 0a 00 04 00 02 00 1d"))
