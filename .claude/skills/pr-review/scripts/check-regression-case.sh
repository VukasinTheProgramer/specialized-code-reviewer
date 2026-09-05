#!/usr/bin/env bash
# pr-review — 0.10.1: did a regression case's ground-truth finding survive a re-run?
#
#   usage:  bash .claude/skills/pr-review/scripts/check-regression-case.sh <case.json> <findings.json>
#           bash .claude/skills/pr-review/scripts/check-regression-case.sh --selftest
#
# <findings.json> is the output of re-running /pr-review with BASE=<case.base>
# and PR_REVIEW_HEAD=<case.head> (see build-artifacts.sh's PR_REVIEW_HEAD).
# Matches on label+file+line only — a reworded failure_mode is not a loss.
#
# Exit codes: 0 PASS (still found)   1 FAIL (lost)
#   2 not comparable (findings.json's base/head don't match the case's)
#   3 bad args / missing file
set -u

selftest() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  jq -n '{id:"t-logic-58", base:"aaa", head:"bbb",
          finding:{label:"logic", file:"x.py", line:58}}' > "$tmp/case.json"

  jq -n '{base:"aaa", head:"bbb", findings:[{label:"logic", file:"x.py", line:58}]}' \
    > "$tmp/still-found.json"
  bash "$0" "$tmp/case.json" "$tmp/still-found.json" >/dev/null
  [ $? -eq 0 ] || { echo "selftest FAILED: expected PASS on matching finding" >&2; exit 1; }

  jq -n '{base:"aaa", head:"bbb", findings:[]}' > "$tmp/lost.json"
  bash "$0" "$tmp/case.json" "$tmp/lost.json" >/dev/null
  [ $? -eq 1 ] || { echo "selftest FAILED: expected FAIL on empty findings" >&2; exit 1; }

  jq -n '{base:"aaa", head:"ccc", findings:[]}' > "$tmp/wrong-head.json"
  bash "$0" "$tmp/case.json" "$tmp/wrong-head.json" >/dev/null
  [ $? -eq 2 ] || { echo "selftest FAILED: expected NOT-COMPARABLE on head mismatch" >&2; exit 1; }

  echo "selftest OK"
  exit 0
}
[ "${1:-}" = "--selftest" ] && selftest

CASE="${1:-}"; FINDINGS="${2:-}"
if [ -z "$CASE" ] || [ -z "$FINDINGS" ]; then
  echo "usage: check-regression-case.sh <case.json> <findings.json>" >&2
  exit 3
fi
[ -f "$CASE" ] || { echo "error: $CASE not found" >&2; exit 3; }
[ -f "$FINDINGS" ] || { echo "error: $FINDINGS not found" >&2; exit 3; }

CASE_BASE="$(jq -r '.base' "$CASE")"; CASE_HEAD="$(jq -r '.head' "$CASE")"
RUN_BASE="$(jq -r '.base' "$FINDINGS")"; RUN_HEAD="$(jq -r '.head' "$FINDINGS")"
if [ "$CASE_BASE" != "$RUN_BASE" ] || [ "$CASE_HEAD" != "$RUN_HEAD" ]; then
  echo "NOT COMPARABLE: $CASE was recorded against $CASE_BASE...$CASE_HEAD, this findings.json is $RUN_BASE...$RUN_HEAD" >&2
  exit 2
fi

FOUND="$(jq -r --slurpfile c "$CASE" '
  ($c[0].finding) as $f
  | any(.findings[]; .label == $f.label and .file == $f.file and .line == $f.line)
' "$FINDINGS")"

CASE_ID="$(jq -r '.id' "$CASE")"
if [ "$FOUND" = "true" ]; then
  echo "PASS: $CASE_ID still found"
  exit 0
else
  echo "FAIL: $CASE_ID lost"
  exit 1
fi
