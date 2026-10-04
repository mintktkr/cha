# offline checks for lib/chaki/width.bend.
#
# The named code points are the Unicode 17.0.0 property values the generator reads: East Asian
# Width from EastAsianWidth.txt, the categories from extracted/DerivedGeneralCategory.txt,
# emoji presentation from emoji/emoji-data.txt. The "spot" lines are the twenty the generator
# prints from its own table, and they pin the search's shape, not just its values.
import Base
import ../lib/chaki/check.bend as T
import ../lib/chaki/width.bend as Width

# the code point of a string's first character (every one-character string here)
def cp(s: String) -> U32:
  match s:
    case SCon{Chr{c}, _}:
      c
    case SNil{}:
      0

# a String of n copies of one code point, for the long walks
def repeat.go(+cp: U32, n: Nat, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      repeat.go(cp, p, SCon{Chr{cp}, acc})

def repeat(cp: U32, n: Nat) -> String:
  repeat.go(cp, n, SNil{})

def one(+name: String, cp: U32, +want: String) -> String:
  T.eq(name, U32.show(Width.char(cp)), want)

def all(+name: String, +s: String, +want: String) -> String:
  T.eq(name, U32.show(Width.text(s)), want)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(one("ascii a", cp("a"), "1"))
    IO.print(one("é precomposed", cp("é"), "1"))
    IO.print(one("U+0301 combining acute", 769, "0"))
    IO.print(one("あ", cp("あ"), "2"))
    IO.print(one("中", cp("中"), "2"))
    IO.print(one("한", cp("한"), "2"))
    IO.print(one("😀", cp("😀"), "2"))
    IO.print(one("U+FE0F variation selector", 65039, "0"))
    IO.print(one("U+200D ZWJ", 8205, "0"))
    IO.print(one("U+200C ZWNJ", 8204, "0"))
    IO.print(one("U+00AD soft hyphen", 173, "1"))
    IO.print(one("U+1F1E6 regional indicator A", 127462, "2"))
    IO.print(one("tab", 9, "0"))
    IO.print(one("U+0007 BEL", 7, "0"))
    IO.print(one("U+10FF last before the Jamo block", 4351, "1"))
    IO.print(one("U+1100 Jamo choseong", 4352, "2"))
    IO.print(one("U+115F Jamo filler", 4447, "2"))
    IO.print(one("U+1160 Jamo medial vowel", 4448, "0"))
    IO.print(one("U+11FF Jamo final consonant", 4607, "0"))
    IO.print(one("U+1200 just past the Jamo block", 4608, "1"))
    IO.print(all("cha 茶", "cha 茶", "6"))
    IO.print(all("日本語", "日本語", "6"))
    IO.print(all("mixed widths", "aあ中b", "6"))
    IO.print(all("e plus combining acute", "e" ++ repeat(769, 1n), "1"))
    IO.print(all("empty", "", "0"))
    IO.print(all("one space", " ", "1"))
    IO.print(one("NUL", 0, "0"))
    IO.print(one("printable ASCII starts", 32, "1"))
    IO.print(one("printable ASCII ends", 126, "1"))
    IO.print(one("DEL", 127, "0"))
    IO.print(one("C1 opens", 128, "0"))
    IO.print(one("C1 closes", 159, "0"))
    IO.print(one("U+00A0 no-break space", 160, "1"))
    IO.print(one("U+0378 unassigned", 888, "1"))
    IO.print(one("U+303F East Asian Neutral inside the wide area", 12351, "1"))
    IO.print(one("U+D800 surrogate", 55296, "1"))
    IO.print(one("U+263A emoji, text presentation", 9786, "1"))
    IO.print(one("U+2764 emoji, text presentation", 10084, "1"))
    IO.print(one("U+1F3F4 emoji presentation", 127988, "2"))
    IO.print(one("U+302A Mn and East Asian Wide", 12330, "0"))
    IO.print(one("U+3099 Mn and East Asian Wide", 12441, "0"))
    IO.print(one("U+16FE4 Mn and East Asian Wide", 94180, "0"))
    IO.print(one("U+FF21 fullwidth", 65313, "2"))
    IO.print(one("U+FFE6 fullwidth", 65510, "2"))
    IO.print(one("U+E0100 variation selector supplement", 917760, "0"))
    IO.print(one("U+E01EF variation selector supplement ends", 917999, "0"))
    IO.print(one("U+10FFFD private use, plane 16", 1114109, "1"))
    IO.print(one("U+10FFFF max", 1114111, "1"))
    IO.print(T.eq("100k ASCII characters", U32.show(Width.text(repeat(cp("a"), 100000n))), "100000"))
    IO.print(T.eq("100k wide characters", U32.show(Width.text(repeat(20013, 100000n))), "200000"))
    IO.print(one("spot U+000F", 15, "0"))
    IO.print(one("spot U+0826", 2086, "0"))
    IO.print(one("spot U+0A81", 2689, "0"))
    IO.print(one("spot U+0CBD", 3261, "1"))
    IO.print(one("spot U+0F8A", 3978, "1"))
    IO.print(one("spot U+184A", 6218, "1"))
    IO.print(one("spot U+1BAA", 7082, "1"))
    IO.print(one("spot U+2622", 9762, "1"))
    IO.print(one("spot U+2B1B", 11035, "2"))
    IO.print(one("spot U+A808", 43016, "1"))
    IO.print(one("spot U+AAF6", 43766, "0"))
    IO.print(one("spot U+10D6B", 68971, "0"))
    IO.print(one("spot U+1123F", 70207, "1"))
    IO.print(one("spot U+1163B", 71227, "1"))
    IO.print(one("spot U+11AFC", 72444, "1"))
    IO.print(one("spot U+16123", 90403, "0"))
    IO.print(one("spot U+1D183", 119171, "1"))
    IO.print(one("spot U+1E8D3", 125139, "0"))
    IO.print(one("spot U+1F595", 128405, "2"))
    IO.print(one("spot U+F80F7", 1016055, "1"))
