#!/usr/bin/env bash
# type-check everything, prove the laws and run the offline tests. BEND overrides the bend binary.
# Every gate fails closed: a file passes when bend exits 0, or when its whole output is the
# list of defs that rely on foreign code (the tty and http effects ui and api pull in).
# Any other output (an error, a TODO, a crash, a missing hub package) fails.
set -euo pipefail
cd "$(dirname "$0")/.."
bend=${BEND:-bend}
# as in CI: no update notice on stderr, which would read as a failure below
export BEND_NO_TELEMETRY=1
bun scripts/order.ts main.bend src/*.bend src/cmd/*.bend
# foreign_only: "SOME PROOFS FAIL", the foreign-code header, then nothing but "- def" lines
foreign_only() {
  [ "$(sed -n 1p <<<"$1")" = "SOME PROOFS FAIL" ] &&
    sed -n 2p <<<"$1" | grep -qE '^Error: [0-9]+ defs? rel(y|ies) on unsafe or foreign code:$' &&
    ! sed '1,2d' <<<"$1" | grep -qv '^- '
}
check() {
  if out=$("$bend" "$1" --check-only 2>&1) || foreign_only "$out"; then echo "✓ $1"; return; fi
  echo "$out" | head -20; echo "✗ $1"; exit 1
}
check main.bend
for t in test/*.bend; do check "$t"; done
# the laws also pass with the foreign-code list, as long as no law or proof is on it
if [ -f PROOF.bend ]; then
  if { out=$("$bend" PROOF.bend 2>&1) && grep -qx 'ALL PROOFS CHECK' <<<"$out"; } ||
    { foreign_only "$out" && ! grep -qiE '^- (LAWS|PROOF)\.' <<<"$out"; }; then
    echo "✓ PROOF.bend ($(grep -c '^law ' LAWS.bend) laws)"
  else
    echo "$out" | head -20; echo "✗ PROOF.bend"; exit 1
  fi
fi
# *_check.bend run offline and must exit 0; *_live.bend talk to real forges, run them by hand
for t in test/*_check.bend; do
  out=$("$bend" "$t" 2>&1) || { echo "$out" | tail -20; echo "✗ ran $t"; exit 1; }
  if grep -qE '^(FAIL|✗)|mismatch' <<<"$out"; then echo "$out" | grep -E 'FAIL|✗|mismatch' | head; echo "✗ ran $t"; exit 1; fi
  echo "✓ ran $t"
done
