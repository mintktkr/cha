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
for t in test/*_check.bend; do check "$t"; done
if [ -f PROOF.bend ]; then "$bend" PROOF.bend 2>&1 | tail -3; fi
"$bend" test/ctx_check.bend
