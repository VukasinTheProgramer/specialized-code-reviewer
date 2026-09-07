#!/usr/bin/env bash
# Spec for validate-pack.sh (written before the validator — see todays-work/).
# Each bad-*.md pack must exit 1; good.md must exit 0.
set -u
ROOT="$(git rev-parse --show-toplevel)"
VALIDATOR="$ROOT/.claude/skills/pr-review/scripts/validate-pack.sh"
PACKS="$ROOT/tests/packs"
fail=0

check() {
  pack="$1"; want="$2"
  out="$(bash "$VALIDATOR" "$PACKS/$pack" 2>&1)"; got=$?
  if [ "$got" = "$want" ]; then
    echo "ok   $pack (exit $got)"
  else
    echo "FAIL $pack (exit $got, want $want)"
    echo "$out" | sed 's/^/       /'
    fail=1
  fi
}

check "good.md"                  0
check "bad-heading-case.md"      1
check "bad-wiring-unfenced.md"   1
check "bad-pipe-in-cell.md"      1
check "bad-brief-syntax.md"      1
check "bad-citation-unquoted.md" 1
check "bad-unknown-label.md"     1

exit "$fail"
