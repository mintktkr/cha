#!/usr/bin/env bash
# type-check everything and run the offline tests. BEND overrides the bend binary.
set -euo pipefail
cd "$(dirname "$0")/.."
bend=${BEND:-bend}
bun scripts/order.ts main.bend src/*.bend src/cmd/*.bend
check() {
  out=$("$bend" "$1" --check-only 2>&1 || true)
  if grep -q "Location" <<<"$out"; then echo "$out" | head -20; echo "✗ $1"; exit 1; fi
  echo "✓ $1"
}
check main.bend
for t in test/*.bend; do check "$t"; done
# bend PROOF.bend exits 1 because the effects ui and api pull in (tty, http) are listed
# as unsafe or foreign. That is expected, so fail only on a law error, a TODO, or a proof
# that itself appears in that list.
if [ -f PROOF.bend ]; then
  out=$("$bend" PROOF.bend 2>&1 || true)
  if grep -qE 'Location|TODO' <<<"$out" || grep -qE '^- (LAWS|PROOF|Laws)\.' <<<"$out"; then
    echo "$out" | head -20; echo "✗ PROOF.bend"; exit 1
  fi
  echo "✓ PROOF.bend ($(grep -c '^law ' LAWS.bend) laws)"
fi
# *_check.bend run offline and must exit 0; *_live.bend talk to real forges, run them by hand
for t in test/*_check.bend; do
  out=$("$bend" "$t" 2>&1) || { echo "$out" | tail -20; echo "✗ ran $t"; exit 1; }
  if grep -qE '^(FAIL|✗)|mismatch' <<<"$out"; then echo "$out" | grep -E 'FAIL|✗|mismatch' | head; echo "✗ ran $t"; exit 1; fi
  echo "✓ ran $t"
done
