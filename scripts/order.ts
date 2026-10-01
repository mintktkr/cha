// bend binds a def only to defs above it. list every call to a def of the same file defined below.
const files = process.argv.slice(2);
let bad = 0;
for (const f of files) {
  const src = await Bun.file(f).text();
  const defs: [string, number][] = [];
  const lines = src.split("\n");
  lines.forEach((l, i) => { const m = /^(?:@unsafe\s+)?def ([A-Za-z0-9_.]+)\s*[(?]/.exec(l); if (m) defs.push([m[1], i]); });
  const at = new Map(defs);
  let cur = "";
  lines.forEach((l, i) => {
    const m = /^def ([A-Za-z0-9_.]+)/.exec(l); if (m) cur = m[1];
    if (!cur || l.trimStart().startsWith("#")) return;
    for (const [name, line] of defs) {
      if (line <= i || name === cur) continue;
      const re = new RegExp(`(^|[^A-Za-z0-9_.])${name.replace(/\./g, "\\.")}\\(`);
      if (re.test(l.replace(/^def [^(]+/, ""))) { console.log(`${f}:${i + 1}: ${cur} calls ${name}, defined below at ${line + 1}`); bad++; }
    }
  });
}
process.exit(bad ? 1 : 0);
