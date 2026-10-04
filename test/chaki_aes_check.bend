# offline checks for lib/chaki/aes.bend. The AES vectors are FIPS-197 Appendix C.1
# and C.3; the GCM vectors are test cases 1-4 and 13-16 of McGrew and Viega, "The
# Galois/Counter Mode of Operation (GCM)" (the 96-bit IV cases).
import Base
import ../lib/chaki/aes.bend as Aes
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(T.hex("FIPS-197 C.1 encrypt", Aes.encrypt(Bytes.of_hex("000102030405060708090a0b0c0d0e0f"), Bytes.of_hex("00112233445566778899aabbccddeeff")), "69c4e0d86a7b0430d8cdb78070b4c55a"))
    IO.print(T.hex("FIPS-197 C.3 encrypt", Aes.encrypt(Bytes.of_hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"), Bytes.of_hex("00112233445566778899aabbccddeeff")), "8ea2b7ca516745bfeafc49904b496089"))
    IO.print(T.ok("encrypt, a short key is refused", Bytes.eq(Aes.encrypt(Bytes.of_hex("00010203"), Bytes.of_hex("00112233445566778899aabbccddeeff")), Nil{})))
    IO.print(T.ok("encrypt, a short block is refused", Bytes.eq(Aes.encrypt(Bytes.of_hex("000102030405060708090a0b0c0d0e0f"), Bytes.of_hex("00112233")), Nil{})))
