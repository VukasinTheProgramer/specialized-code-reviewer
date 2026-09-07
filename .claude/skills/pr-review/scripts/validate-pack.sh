#!/usr/bin/env bash
# Validates a domain pack's format contract, defined in model/FORMAT.md.
# Never repairs, never stops at the first problem — prints every finding it
# can, same doctrine the reviewer itself is held to.
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
  grep -qxF "$h" "$PACK" || fail "missing or renamed heading (model/FORMAT.md §1): $h"
done

# ---- check: Wiring files section has a fenced block, closed before the
# next heading — the exact shape D1 breaks (build-artifacts.sh's own
# extraction resets on the next fence, not the next heading, so an unclosed
# fence there swallows everything up to the next ```) ----
WIRING_FENCES=$(awk '/^## Wiring files/{f=1;next} /^## /{f=0} f' "$PACK" | grep -c '^```')
if [ "$WIRING_FENCES" -eq 0 ]; then
  fail "Wiring files: no fenced block found (model/FORMAT.md §2)"
elif [ $((WIRING_FENCES % 2)) -ne 0 ]; then
  fail "Wiring files: fenced block not closed before the next heading (model/FORMAT.md §2)"
fi

# ---- check: Label probes rows — field count and closed-label membership,
# both read off the section using the same heading-bounded extraction (not
# build-artifacts.sh's contiguous-until-fence scan) ----
LABEL_RC=0
awk -F'|' -v labels="auth ownership security data-exposure db concurrency logic validation control-flow state contract layering duplication dead-code a11y" '
  BEGIN { n = split(labels, arr, " "); for (i = 1; i <= n; i++) valid[arr[i]] = 1 }
  /^## Label probes/ { f = 1; next }
  /^## / { f = 0 }
  f && /^\|/ {
    label = $2; gsub(/^[ \t]+|[ \t]+$/, "", label); gsub(/`/, "", label)
    if (label == "" || label ~ /^-+$/ || tolower(label) == "label") next
    if (NF != 4) {
      print "invalid: Label probes row does not split into exactly one label + one probe cell (unescaped `|` in a cell?) (model/FORMAT.md §3): " $0
      bad = 1
    } else if (!(label in valid)) {
      print "invalid: Label probes label `" label "` is not one of the 15 closed labels (model/FORMAT.md §4): " $0
      bad = 1
    }
  }
  END { exit bad }
' "$PACK" || LABEL_RC=1
[ "$LABEL_RC" = 1 ] && INVALID=1

# ---- check: Brief probes has a ```bash fence, and the extracted block
# passes `bash -n` — D3, where a syntax error there is currently swallowed
# by build-artifacts.sh's `eval ... 2>/dev/null` with no flag raised ----
BRIEF_HAS_FENCE=$(awk '/^## Brief probes/{f=1;next} /^## /{f=0} f&&/^```bash/{print "yes"; exit}' "$PACK")
if [ "$BRIEF_HAS_FENCE" != "yes" ]; then
  fail "Brief probes: no \`\`\`bash fence found (model/FORMAT.md §5)"
else
  BRIEF_BLOCK=$(awk '/^## Brief probes/{f=1;next} f&&/^```bash/{b=1;next} f&&b&&/^```/{exit} f&&b' "$PACK")
  if [ -n "$BRIEF_BLOCK" ]; then
    BRIEF_ERR=$(printf '%s\n' "$BRIEF_BLOCK" | bash -n 2>&1 >/dev/null)
    [ -n "$BRIEF_ERR" ] && fail "Brief probes: bash syntax error (model/FORMAT.md §5) — $(printf '%s' "$BRIEF_ERR" | head -1)"
  fi
fi

# ---- check: every path.ext[:line] citation containing a '/' is backtick-
# wrapped — D4. Scanned outside fenced code blocks only: the Wiring files
# and Brief probes blocks legitimately hold bare paths/shell code, not
# citations. ----
STRIPPED=$(awk '/^```/{f=!f;next} !f' "$PACK")
BARE_CITES=$(printf '%s\n' "$STRIPPED" \
  | grep -oE '`[^`]*`|[A-Za-z0-9_./-]+\.[a-zA-Z]+(:[0-9]+(-[0-9]+)?)?' \
  | grep -v '^`' | grep '/')
if [ -n "$BARE_CITES" ]; then
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    fail "citation not backtick-wrapped, invisible to staleness checking (model/FORMAT.md §6): $c"
  done <<CITES_EOF
$BARE_CITES
CITES_EOF
fi

[ "$INVALID" = 1 ] && exit 1
exit 0
