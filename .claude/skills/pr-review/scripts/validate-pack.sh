#!/usr/bin/env bash
# Validates a domain pack's format contract. Never repairs, never stops at
# the first problem — prints every finding it can, same doctrine the
# reviewer itself is held to (see model/FORMAT.md, once written).
#
#   usage: bash .claude/skills/pr-review/scripts/validate-pack.sh <pack-file>
# Exit codes: 0 valid   1 invalid (findings printed)   2 pack file missing   3 bad usage
set -u

PACK="${1:-}"
[ -n "$PACK" ] || { echo "usage: validate-pack.sh <pack-file>" >&2; exit 3; }
[ -r "$PACK" ] || { echo "error: cannot read '$PACK'" >&2; exit 2; }

INVALID=0
fail() { echo "invalid: $1"; INVALID=1; }

# ---- check: all five section headings present, exact match ----
for h in "## Stack scope prefixes" "## Wiring files" "## Label probes" "## Brief probes" "## Dependencies"; do
  grep -qxF "$h" "$PACK" || fail "missing or renamed heading: $h"
done

# TODO (Tuesday): wiring-fenced-before-next-heading, label-probes field count,
# label-probes closed-list membership, brief-probes bash-fence + bash -n,
# citation backtick-wrapping.

[ "$INVALID" = 1 ] && exit 1
exit 0
