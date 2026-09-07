#!/usr/bin/env bash
# Locks in D1 and D3's fixes against build-artifacts.sh itself (not just
# validate-pack.sh's static checks). Builds a throwaway git repo, copies the
# real scripts in, and asserts on the artifacts produced.
set -u
ROOT="$(git rev-parse --show-toplevel)"
SCRIPTS="$ROOT/.claude/skills/pr-review/scripts"
PACKS="$ROOT/tests/packs"
fail=0

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

cd "$TMP"
git init -q
git config user.email test@test.com
git config user.name test
mkdir -p .claude/skills/pr-review/scripts model
cp "$SCRIPTS/build-artifacts.sh" .claude/skills/pr-review/scripts/
cp "$ROOT/model/validate-pack.sh" model/
echo "# readme" > README.md
echo one > file.txt
git add -A && git commit -q -m init
echo two >> file.txt
git add -A && git commit -q -m change
git branch base HEAD~1

# ---- D1: wiring.txt must never carry the Label-probes table it used to
# swallow when the wiring fence went unclosed ----
OUT="$(PR_REVIEW_PACK="$PACKS/bad-wiring-unfenced.md" PR_REVIEW_NO_GRAPH=1 \
  bash .claude/skills/pr-review/scripts/build-artifacts.sh base 2>/dev/null | grep '^OUT=' | cut -d= -f2)"
if grep -qE '\$\(|echo' "$OUT/wiring.txt" 2>/dev/null; then
  echo "FAIL D1: wiring.txt contaminated with shell code"; cat "$OUT/wiring.txt" | sed 's/^/       /'
  fail=1
else
  echo "ok   D1: wiring.txt clean for bad-wiring-unfenced.md"
fi

# ---- D3: a Brief-probes runtime error (bash -n can't see it — bad -n only
# catches syntax, not "command not found") must set BRIEF_DEGRADED=1 ----
OUT="$(PR_REVIEW_PACK="$PACKS/bad-brief-runtime-err.md" PR_REVIEW_NO_GRAPH=1 \
  bash .claude/skills/pr-review/scripts/build-artifacts.sh base 2>/dev/null | grep '^OUT=' | cut -d= -f2)"
if grep -qxF 'BRIEF_DEGRADED=1' "$OUT/run.env" 2>/dev/null; then
  echo "ok   D3: BRIEF_DEGRADED=1 for bad-brief-runtime-err.md"
else
  echo "FAIL D3: BRIEF_DEGRADED not set"; cat "$OUT/run.env" | sed 's/^/       /'
  fail=1
fi

exit "$fail"
