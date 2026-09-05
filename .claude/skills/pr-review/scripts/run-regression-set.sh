#!/usr/bin/env bash
# pr-review — 0.10.1: re-run every regression case's diff (0.10 AC: "any change
# to the reviewer re-runs the whole regression set, because a change that
# recovers one finding while losing another is not progress").
#
#   usage:  bash .claude/skills/pr-review/scripts/run-regression-set.sh
#
# Building each case's artifacts is scriptable (build-artifacts.sh already
# supports PR_REVIEW_HEAD=<sha> for exactly this — replaying a fixed
# historical diff without checking it out). Actually reviewing that diff is
# not: it fans out to five Claude subagents (SKILL.md step 3), which this
# shell script has no way to spawn. So this prints, per case, the artifacts
# directory already built and the two commands still needed:
#   1. run /pr-review's step 3 (the Workflow) against that OUT dir
#   2. check-regression-case.sh <case> <the resulting findings.json>
#
# Exit codes: 0 ok (cases may still be listed as 0)   2 not a git repo
#   4 no cases recorded yet
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "error: not inside a git repository" >&2; exit 2; }
cd "$ROOT"

CASES_DIR=".claude/references/eval/regression-set/cases"
SCRIPT_DIR=".claude/skills/pr-review/scripts"
CASES=()
while IFS= read -r f; do CASES+=("$f"); done < <(find "$CASES_DIR" -name '*.json' 2>/dev/null | sort)

if [ "${#CASES[@]}" -eq 0 ]; then
  echo "no regression cases recorded yet — see add-regression-case.sh" >&2
  exit 4
fi

echo "regression set: ${#CASES[@]} case(s)"
echo
for CASE in "${CASES[@]}"; do
  ID="$(jq -r '.id' "$CASE")"
  BASE="$(jq -r '.base' "$CASE")"
  HEAD="$(jq -r '.head' "$CASE")"
  LABEL="$(jq -r '.finding.label' "$CASE")"
  FILE="$(jq -r '.finding.file' "$CASE")"
  LINE="$(jq -r '.finding.line' "$CASE")"

  if ! git rev-parse --verify --quiet "$BASE" >/dev/null || ! git rev-parse --verify --quiet "$HEAD" >/dev/null; then
    echo "$ID — SKIPPED: $BASE or $HEAD no longer resolves in this repo"
    continue
  fi

  RUN_ERR="$(mktemp)"
  RUN_OUT="$(PR_REVIEW_HEAD="$HEAD" bash "$SCRIPT_DIR/build-artifacts.sh" "$BASE" 2>"$RUN_ERR")"
  RUN_STATUS=$?
  if [ "$RUN_STATUS" -ne 0 ]; then
    echo "$ID — SKIPPED: build-artifacts.sh exited $RUN_STATUS: $(tail -1 "$RUN_ERR")"
    rm -f "$RUN_ERR"
    echo
    continue
  fi
  rm -f "$RUN_ERR"
  OUT_DIR="$(printf '%s\n' "$RUN_OUT" | sed -n 's/^OUT=//p')"

  echo "$ID — [$LABEL] $FILE:$LINE"
  echo "  artifacts: $OUT_DIR"
  echo "  next: run /pr-review's Workflow step against these artifacts, persist its"
  echo "        findings.json, then:"
  echo "        bash $SCRIPT_DIR/check-regression-case.sh $CASE <findings.json>"
  echo
done
