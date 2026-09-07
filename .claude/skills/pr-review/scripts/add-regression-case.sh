#!/usr/bin/env bash
# pr-review — 0.10.1: append an accepted finding to the regression set.
#
#   usage:  bash .claude/skills/pr-review/scripts/add-regression-case.sh <label> <file> <line>
#
# Run right after a human gives a finding the "accepted" verdict (see
# eval/review-corrections.md — "How an entry is made").
# The case is pulled verbatim from .git/pr-review/findings.json, the fixed
# path the last /pr-review run persisted (SKILL.md §5.4) — never hand-typed,
# so ground truth is always the reviewer's own confirmed output, per 0.10.1.
#
# Writes eval/regression-set/cases/<id>.json. Idempotent:
# re-running for the same finding is a no-op, not a duplicate case.
#
# Exit codes: 0 ok   2 not a git repo   3 bad args
#   4 no persisted findings.json (run /pr-review and get a verdict first)
#   5 no finding in findings.json matches <label> <file> <line>
#   6 more than one finding matches (findings.json isn't deduped as expected)
#   7 case file write failed (disk full, permission) — nothing written
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "error: not inside a git repository" >&2; exit 2; }
cd "$ROOT"

LABEL="${1:-}"; FILE="${2:-}"; LINE="${3:-}"
if [ -z "$LABEL" ] || [ -z "$FILE" ] || [ -z "$LINE" ]; then
  echo "usage: add-regression-case.sh <label> <file> <line>" >&2
  exit 3
fi
case "$LINE" in
  ''|*[!0-9]*) echo "error: <line> must be a positive integer, got '$LINE'" >&2; exit 3 ;;
esac

FINDINGS=".git/pr-review/findings.json"
[ -f "$FINDINGS" ] || { echo "error: $FINDINGS not found — run /pr-review and record a verdict first." >&2; exit 4; }

MATCH="$(jq -c --arg label "$LABEL" --arg file "$FILE" --argjson line "$LINE" \
  '.findings[] | select(.label == $label and .file == $file and .line == $line)
   | {label, file, line, failure_mode}' \
  "$FINDINGS")"
[ -n "$MATCH" ] || { echo "error: no finding in $FINDINGS matches label=$LABEL file=$FILE line=$LINE" >&2; exit 5; }
MATCH_COUNT="$(printf '%s\n' "$MATCH" | grep -c .)"
[ "$MATCH_COUNT" -eq 1 ] || { echo "error: $MATCH_COUNT findings in $FINDINGS match label=$LABEL file=$FILE line=$LINE — expected exactly one" >&2; exit 6; }

BASE="$(jq -r '.base' "$FINDINGS")"
HEAD="$(jq -r '.head' "$FINDINGS")"
HEAD_SHORT="${HEAD:0:8}"
FILE_SLUG="${FILE//\//_}"
CASE_ID="${HEAD_SHORT}-${LABEL}-${FILE_SLUG}-${LINE}"
CASES_DIR="eval/regression-set/cases"
mkdir -p "$CASES_DIR"
CASE_FILE="$CASES_DIR/${CASE_ID}.json"

if [ -f "$CASE_FILE" ]; then
  echo "case $CASE_ID already recorded — no-op." >&2
else
  TMP_CASE="$(mktemp "${CASE_FILE}.XXXXXX")" || { echo "error: cannot create a temp file next to $CASE_FILE" >&2; exit 7; }
  if jq -n --arg id "$CASE_ID" --arg base "$BASE" --arg head "$HEAD" \
    --arg added "$(date -u +%Y-%m-%d)" --argjson finding "$MATCH" \
    '{id: $id, base: $base, head: $head, added: $added, finding: $finding}' \
    > "$TMP_CASE"
  then
    mv "$TMP_CASE" "$CASE_FILE"
    echo "added $CASE_FILE"
  else
    rm -f "$TMP_CASE"
    echo "error: failed to write $CASE_FILE — case not recorded" >&2
    exit 7
  fi
fi

COUNT="$(find "$CASES_DIR" -name '*.json' | grep -c .)"
echo "regression set: $COUNT case(s)"
