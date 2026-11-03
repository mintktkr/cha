// chaki big: prints the bend lines of test/chaki_big_check.bend whose expected values are
// computed here with BigInt. Everything is deterministic from a fixed seed, so a rerun
// prints the same vectors: run `bun scripts/chaki-big-vectors.ts` and paste its output
// into the check's main.
//
// Hex operands are big-endian bytes, which is what Bytes.of_hex reads; the check turns
// them into limbs with Big.of_bytes.

const sizes = [1, 2, 17, 64, 256, 2048, 4096];

// mulberry32: a small deterministic PRNG, so the vectors are reproducible
function rng(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function rand(seed: number, n: number, odd: boolean): bigint {
  const r = rng(seed);
  let v = 0n;
  for (let i = 0; i < Math.ceil(n / 32) + 1; i++) {
    v = (v << 32n) | BigInt(Math.floor(r() * 4294967296));
  }
  v &= (1n << BigInt(n)) - 1n;
  v |= 1n << BigInt(n - 1);
  if (odd) v |= 1n;
  return v;
}

// big-endian hex, no leading zero bytes; "" is zero, as the check's hex() answers it
function hex(v: bigint): string {
  if (v === 0n) return "";
  const s = v.toString(16);
  return s.length % 2 ? "0" + s : s;
}

function modinv(a: bigint, m: bigint): bigint {
  let [g, x] = [m, 0n];
  let [h, y] = [((a % m) + m) % m, 1n];
  while (h !== 0n) {
    const q = g / h;
    [g, h] = [h, g - q * h];
    [x, y] = [y, x - q * y];
  }
  return ((x % m) + m) % m;
}

function modexp(b: bigint, e: bigint, m: bigint): bigint {
  let r = 1n;
  b %= m;
  while (e > 0n) {
    if (e & 1n) r = (r * b) % m;
    b = (b * b) % m;
    e >>= 1n;
  }
  return r;
}

const out: string[] = [];
const eq = (name: string, got: string, want: string) =>
  out.push(`    IO.print(T.eq("${name}", ${got}, "${want}"))`);
const D = (v: bigint) => `x("${hex(v)}")`;

for (const n of sizes) {
  const a = rand(1000 + n, n, false);
  const b = rand(2000 + n, n, false) | 1n;
  const big = a >= b ? a : b;
  const small = a >= b ? b : a;
  eq(`add ${n} bits`, `hex(Big.add(${D(a)}, ${D(b)}))`, hex(a + b));
  eq(`sub ${n} bits`, `hex(Big.sub(${D(big)}, ${D(small)}))`, hex(big - small));
  eq(`mul ${n} bits`, `hex(Big.mul(${D(a)}, ${D(b)}))`, hex(a * b));
  eq(`mod ${n} bits`, `hex(Big.mod(${D(a)}, ${D(b)}))`, hex(a % b));
  out.push(
    `    IO.print(div.lines(Big.divmod(${D(a)}, ${D(b)}), "divmod ${n} bits", ` +
      `"${hex(a / b)}", "${hex(a % b)}"))`,
  );
}

// divisions whose quotient has more than one limb: the limb-wise estimate and its
// correction only get exercised when the dividend is much longer than the divisor
for (const [na, nb] of [[2, 1], [17, 2], [32, 1], [64, 17], [256, 17], [2048, 64],
  [2048, 2048], [4096, 17], [4096, 2048]] as const) {
  const a = rand(8000 + na * 3 + nb, na, false);
  const b = rand(8100 + na * 3 + nb, nb, false) | 1n;
  out.push(
    `    IO.print(div.lines(Big.divmod(${D(a)}, ${D(b)}), "divmod ${na} by ${nb} bits", ` +
      `"${hex(a / b)}", "${hex(a % b)}"))`,
  );
}

// zero, one and powers of two
eq("zero plus zero", `hex(Big.add(x(""), x("")))`, "");
eq("one plus one", `hex(Big.add(x("01"), x("01")))`, "02");
eq("2^64 times 2^64", `hex(Big.mul(x("010000000000000000"), x("010000000000000000")))`,
  "0100000000000000000000000000000000");
eq("2^255 mod 2^17", `hex(Big.mod(${D(1n << 255n)}, x("010000")))`,
  hex((1n << 255n) % 65536n));
eq("2^255 minus one, plus one", `hex(Big.add(${D((1n << 255n) - 1n)}, x("01")))`,
  hex(1n << 255n));
eq("zero mod one", `hex(Big.mod(x(""), x("01")))`, "");
eq("one mod 2^16", `hex(Big.mod(x("01"), x("010000")))`, "01");
eq("zero minus zero", `hex(Big.sub(x(""), x("")))`, "");
eq("sub below zero is zero", `hex(Big.sub(x("01"), x("02")))`, "");

// of_bytes / to_bytes round trips, padding and truncation
for (const n of [1, 2, 3, 15, 16, 17, 32, 33, 64, 65]) {
  const v = rand(3000 + n, n * 8, false);
  eq(`of_bytes to_bytes ${n} bytes`, `hex(Big.of_bytes(Big.to_bytes(${D(v)}, ${n})))`, hex(v));
}
eq("to_bytes pads high", `Bytes.to_hex(Big.to_bytes(x("0102"), 4))`, "00000102");
eq("to_bytes to no bytes", `Bytes.to_hex(Big.to_bytes(x("0102"), 0))`, "");
eq("to_bytes drops high", `Bytes.to_hex(Big.to_bytes(x("0102030405"), 3))`, "030405");
eq("to_bytes of zero", `Bytes.to_hex(Big.to_bytes(x(""), 3))`, "000000");
eq("of_bytes of a zero limb", `hex(Big.of_bytes(x("0000")))`, "");
eq("bits of zero", `U32.show(Big.bits(x("")))`, "0");
eq("bits of one", `U32.show(Big.bits(x("01")))`, "1");
eq("bits of 2^255", `U32.show(Big.bits(${D(1n << 255n)}))`, "256");
eq("of_u32 65536", `hex(Big.of_u32(65536))`, "010000");
eq("of_u32 0", `hex(Big.of_u32(0))`, "");
eq("cmp above", `cmp.show(Big.cmp(x("0100"), x("00ff")))`, "GT");
eq("cmp equal", `cmp.show(Big.cmp(x("0100"), x("0100")))`, "EQ");
eq("cmp below", `cmp.show(Big.cmp(x(""), x("01")))`, "LT");
{
  const m = 0xfffdn;
  const a = 65530n;
  const b = 65500n;
  eq("modadd wraps", `hex(Big.modadd(${D(a)}, ${D(b)}, ${D(m)}))`, hex((a + b) % m));
  eq("modadd plain", `hex(Big.modadd(${D(5n)}, ${D(7n)}, ${D(m)}))`, hex(12n));
  eq("modsub wraps", `hex(Big.modsub(${D(b)}, ${D(a)}, ${D(m)}))`, hex((b - a + m) % m));
  eq("modsub plain", `hex(Big.modsub(${D(a)}, ${D(b)}, ${D(m)}))`, hex((a - b) % m));
  eq("modmul", `hex(Big.modmul(${D(65535n)}, ${D(65534n)}, ${D(m)}))`, hex((65535n * 65534n) % m));
}

// modexp: the RSA public exponent against odd moduli, a 256-bit exponent mod P-256, and
// the Montgomery context those go through
const p256 = 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffffn;
const n256 = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n;
const p384 = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffffn;
const n384 = 0xffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973n;
for (const [name, n] of [["2048", 2048], ["4096", 4096]] as const) {
  const m = rand(4000 + n, n, true);
  const a = rand(5000 + n, n, false) % m;
  const b = rand(5500 + n, n, false) % m;
  if (name === "4096") {
    out.push(`    t0 : Nat <- IO.now()`);
    eq(`modexp ${name} e=65537`, `hex(Big.modexp(${D(a)}, x("010001"), ${D(m)}))`,
      hex(modexp(a, 65537n, m)));
    out.push(`    t1 : Nat <- IO.now()`);
    out.push(`    IO.print("ok   modexp 4096 e=65537 took " ++ ` +
      `Nat.show(Nat.sub(t1, t0)) ++ " ms")`);
  } else {
    eq(`modexp ${name} e=65537`, `hex(Big.modexp(${D(a)}, x("010001"), ${D(m)}))`,
      hex(modexp(a, 65537n, m)));
  }
  out.push(
    `    IO.print(mont.lines(${D(m)}, ${D(a)}, ${D(b)}, "mont ${name}", ` +
      `"${hex(a % m)}", "${hex((a * b) % m)}"))`,
  );
}
{
  const a = rand(6001, 256, false) % p256;
  const e = rand(6002, 256, false);
  eq("modexp p256 exponent 256 bits", `hex(Big.modexp(${D(a)}, ${D(e)}, ${D(p256)}))`,
    hex(modexp(a, e, p256)));
}

// modinv against the P-256 and P-384 primes and group orders
for (const [name, m] of [["p256", p256], ["n256", n256], ["p384", p384], ["n384", n384]] as const) {
  const a = rand(7000 + m.toString().length, 512, false) % m;
  eq(`modinv ${name}`, `hex(Big.modinv(${D(a)}, ${D(m)}))`, hex(modinv(a, m)));
}

console.log(out.join("\n"));
