// chaki-width: regenerates lib/chaki/width.bend from the Unicode Character Database.
//
//   bun scripts/chaki-width.ts
//
// Downloads EastAsianWidth.txt, extracted/DerivedGeneralCategory.txt and emoji/emoji-data.txt
// from https://www.unicode.org/Public/<version>/ucd/ (cached under .scratch/), computes the
// display width of every code point after Markus Kuhn's mk_wcwidth, and emits the table as a
// balanced binary search: one def per range plus a def per comparison, so a lookup allocates
// nothing and holds no state. It prints the spot checks lib/chaki/width.bend is tested on.
//
// Width is 0 for the controls, the combining marks and the format characters, 2 for the East
// Asian Wide and Fullwidth characters and the emoji that present as emoji, 1 for the rest.

const VERSION = "17.0.0";
const BASE = `https://www.unicode.org/Public/${VERSION}/ucd/`;
const FILES = ["EastAsianWidth.txt", "extracted/DerivedGeneralCategory.txt", "emoji/emoji-data.txt"];
const MAX = 0x10ffff;

const repo = new URL("..", import.meta.url).pathname;
const cache = `${repo}.scratch/ucd-${VERSION}`;

type Range = [number, number, string];

async function fetchUcd(file: string): Promise<string> {
  const path = `${cache}/${file.replace(/\//g, "_")}`;
  const cached = Bun.file(path);
  if (await cached.exists()) return cached.text();
  const res = await fetch(BASE + file);
  if (!res.ok) throw new Error(`${BASE + file}: HTTP ${res.status}`);
  const text = await res.text();
  if (!text.split("\n", 8).join("\n").includes(VERSION.slice(0, 4))) throw new Error(`${file}: not version ${VERSION}`);
  await Bun.write(path, text);
  return text;
}

function parse(text: string): Range[] {
  const out: Range[] = [];
  for (const raw of text.split("\n")) {
    const line = raw.split("#")[0].trim();
    if (!line) continue;
    const [rng, prop] = line.split(";").map((s) => s.trim());
    const [a, b] = rng.split("..");
    out.push([parseInt(a, 16), b ? parseInt(b, 16) : parseInt(a, 16), prop]);
  }
  return out;
}

// one byte per code point, holding an index into `names`
function fill(ranges: Range[], filter?: string): [Uint8Array, string[]] {
  const names: string[] = [];
  const ids = new Map<string, number>();
  const arr = new Uint8Array(MAX + 1);
  for (const [a, b, prop] of ranges) {
    if (filter && prop !== filter) continue;
    let id = ids.get(prop);
    if (id === undefined) {
      id = names.length + 1;
      ids.set(prop, id);
      names.push(prop);
    }
    for (let i = a; i <= b; i++) arr[i] = id;
  }
  return [arr, names];
}

const eawRanges = parse(await fetchUcd(FILES[0]));
const gcRanges = parse(await fetchUcd(FILES[1]));
const emojiRanges = parse(await fetchUcd(FILES[2]));

const [eaw, eawNames] = fill(eawRanges);
const [gc, gcNames] = fill(gcRanges);
const [emoji] = fill(emojiRanges, "Emoji_Presentation");

const inRange = (i: number, lo: number, hi: number) => lo <= i && i <= hi;

// mk_wcwidth: the zero-width rules win over the wide ones (U+302A..U+302D and friends are
// both a combining mark and East Asian Wide).
function width(i: number): number {
  if (i < 32 || inRange(i, 0x7f, 0x9f)) return 0;
  if (i === 0x200c || i === 0x200d) return 0;
  const cat = gcNames[gc[i] - 1];
  if ((cat === "Mn" || cat === "Me" || cat === "Cf") && i !== 0xad) return 0;
  if (inRange(i, 0x1160, 0x11ff)) return 0;
  const ea = eawNames[eaw[i] - 1];
  if (ea === "W" || ea === "F") return 2;
  if (emoji[i]) return 2;
  return 1;
}

// adjacent code points of equal width become one range
const ranges: [number, number, number][] = [];
for (let i = 0, start = 0, w = width(0); i <= MAX; i++) {
  const next = i < MAX ? width(i + 1) : -1;
  if (next !== w) {
    ranges.push([start, i, w]);
    start = i + 1;
    w = next;
  }
}

// the search only needs the ranges that aren't 1; a code point that lands in none is 1
const kept = ranges.filter((r) => r[2] !== 1);

// spot checks: one code point from the middle of 20 ranges spread over the table
const spots: [number, number][] = [];
for (let j = 0; j < 20; j++) {
  const r = ranges[Math.floor((j * (ranges.length - 1)) / 19)];
  const cp = (r[0] + r[1]) >> 1;
  spots.push([cp, width(cp)]);
}

// ---- emit ----

const hex = (n: number) => `U+${n.toString(16).toUpperCase().padStart(4, "0")}`;

type Tree = { leaf: number } | { key: number, name: string, left: Tree, right: Tree };

// the balanced search over the kept ranges: the left child holds every start below `key`
function build(lo: number, hi: number): Tree {
  if (hi - lo === 1) return { leaf: lo };
  const mid = lo + Math.floor((hi - lo) / 2);
  return { key: kept[mid][0], name: "", left: build(lo, mid), right: build(mid, hi) };
}

// what the emitted defs answer for a code point
function lookup(t: Tree, c: number): number {
  if ("leaf" in t) return c <= kept[t.leaf][1] ? kept[t.leaf][2] : 1;
  return c < t.key ? lookup(t.left, c) : lookup(t.right, c);
}

let node = 0;
const lines: string[] = [];
const line = (s: string) => lines.push(s);

// emit a subtree bottom-up (a def only sees defs above it) and return the def that looks c up
function emit(t: Tree): string {
  if ("leaf" in t) {
    const name = `char.r${t.leaf}`;
    const [a, b, w] = kept[t.leaf];
    line(`# ${hex(a)}..${hex(b)}: ${w}`);
    line(`def ${name}(c: U32) -> U32:`);
    line(`  Bool.pick(U32, U32.is_le(c, ${b}), ${w}, 1)`);
    line("");
    return name;
  }
  const left = emit(t.left);
  const right = emit(t.right);
  t.name = `char.n${node++}`;
  line(`# below ${hex(t.key)}: ${left}, at or above: ${right}`);
  line(`def ${t.name}.go(c: U32, left: Bool) -> U32:`);
  line(`  match left:`);
  line(`    case True{}:`);
  line(`      ${left}(c)`);
  line(`    case False{}:`);
  line(`      ${right}(c)`);
  line("");
  line(`def ${t.name}(+c: U32) -> U32:`);
  line(`  ${t.name}.go(c, U32.is_lt(c, ${t.key}))`);
  line("");
  return t.name;
}

const root = build(0, kept.length);
const top = emit(root);

// the emitted defs must answer what the properties say for every code point
for (let c = 0; c <= MAX; c++) {
  const want = c >= 0x20 && c <= 0x7e ? 1 : width(c);
  const got = lookup(root, c);
  if (got !== want) throw new Error(`${hex(c)}: the table says ${got}, want ${want}`);
}

const header = `# width: how many terminal columns a piece of text takes, for aligned tables.
# Generated by scripts/chaki-width.ts from the Unicode Character Database ${VERSION}
# (EastAsianWidth.txt, extracted/DerivedGeneralCategory.txt, emoji/emoji-data.txt at
# ${BASE}), after Markus Kuhn's mk_wcwidth. Do not hand-edit: run \`bun scripts/chaki-width.ts\`.
#
# One character is 0 columns when it is a C0 or C1 control, DEL, a soft hyphen's neighbours
# (U+200C, U+200D), a combining or format character (Mn, Me, Cf, except U+00AD SOFT HYPHEN,
# which is 1), a variation selector or Hangul Jamo medial vowel or final consonant; 2 when it
# is East Asian Wide or Fullwidth, or emoji that present as emoji; and 1 otherwise, unassigned
# code points included.
#
# The table is ${kept.length} ranges of 0 and 2 columns, as a balanced binary search: each def
# below compares the code point once against one range start and hands it to a child. A code
# point that reaches a leaf outside that leaf's range falls in a 1-column gap.
import Base

`;

const body = lines.join("\n").trimEnd();

const tail = `
# a code point the tree's ranges don't cover is 1 (the table keeps every 1-column region out)
def char.if(+c: U32, ascii: Bool) -> U32:
  match ascii:
    case True{}:
      1
    case False{}:
      ${top}(c)

# columns one character takes: 0, 1 or 2. Printable ASCII answers before the search.
def char(+c: U32) -> U32:
  char.if(c, U32.is_le(32, c) && U32.is_le(c, 126))

def text.go(s: String, n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{Chr{c}, t}:
      text.go(t, (n + char(c) : U32))

# columns a whole String takes: the sum of its characters
def text(s: String) -> U32:
  text.go(s, 0)
`;

await Bun.write(`${repo}lib/chaki/width.bend`, `${header}${body}\n${tail}`);

console.log(`wrote lib/chaki/width.bend: ${kept.length} ranges, ${node} comparisons`);
console.log(`spot checks (lib/chaki/width.bend's own data):`);
for (const [cp, w] of spots) console.log(`  ${hex(cp)} ${cp} ${w}`);
