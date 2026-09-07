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
cp "$ROOT/model/validate-pack.sh" "$ROOT/model/pack-headings.txt" "$ROOT/model/pack-heading-check.sh" model/
echo "# readme" > README.md
echo one > file.txt
git add -A && git commit -q -m init
echo two >> file.txt
git add -A && git commit -q -m change
git branch base HEAD~1

# Aborts the whole suite loudly if build-artifacts.sh failed to report a
# usable $OUT (crashed, or the OUT= line never printed). Must be called
# directly, never via $(...) — `exit` inside a command-substitution
# subshell only kills the subshell, not this script (confirmed: an earlier
# version of this guard did exactly that and silently kept running with an
# empty $OUT instead of aborting). Without this guard at all, an empty
# $OUT turned "$OUT/wiring.txt" into the literal path /wiring.txt, whose
# absence made every check below pass or fail on the wrong grounds instead
# of catching that build-artifacts.sh itself was broken.
require_out() {
  if [ -z "$1" ] || [ ! -d "$1" ]; then
    echo "FATAL: build-artifacts.sh produced no usable \$OUT — aborting suite" >&2
    exit 1
  fi
}

# ---- D1: wiring.txt must never carry the Label-probes table it used to
# swallow when the wiring fence went unclosed ----
OUT="$(PR_REVIEW_PACK="$PACKS/bad-wiring-unfenced.md" PR_REVIEW_NO_GRAPH=1 \
  bash .claude/skills/pr-review/scripts/build-artifacts.sh base 2>/dev/null | grep '^OUT=' | cut -d= -f2)"
require_out "$OUT"
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
require_out "$OUT"
if grep -qxF 'BRIEF_DEGRADED=1' "$OUT/run.env" 2>/dev/null; then
  echo "ok   D3: BRIEF_DEGRADED=1 for bad-brief-runtime-err.md"
else
  echo "FAIL D3: BRIEF_DEGRADED not set"; cat "$OUT/run.env" | sed 's/^/       /'
  fail=1
fi

# ---- wiring.txt must be empty when the pack is invalid, even if the
# Wiring files section itself is perfectly well-formed — it used to skip
# the STALE gate every other pack-derived artifact respects ----
OUT="$(PR_REVIEW_PACK="$PACKS/bad-unknown-label.md" PR_REVIEW_NO_GRAPH=1 \
  bash .claude/skills/pr-review/scripts/build-artifacts.sh base 2>/dev/null | grep '^OUT=' | cut -d= -f2)"
require_out "$OUT"
if [ -s "$OUT/wiring.txt" ]; then
  echo "FAIL wiring-gate: wiring.txt non-empty for an invalid pack"; cat "$OUT/wiring.txt" | sed 's/^/       /'
  fail=1
else
  echo "ok   wiring-gate: wiring.txt empty for bad-unknown-label.md (valid wiring section, invalid pack)"
fi

# ---- a stray word before the wiring fence (e.g. "TBD") must never be
# treated as a citation and must never set PACK_STALE — nothing in
# model/FORMAT.md §2 forbids prose before the fence, so this pack is valid
# and its one real wiring path (README.md) genuinely exists ----
OUT="$(PR_REVIEW_PACK="$PACKS/bad-wiring-stray-word.md" PR_REVIEW_NO_GRAPH=1 \
  bash .claude/skills/pr-review/scripts/build-artifacts.sh base 2>/dev/null | grep '^OUT=' | cut -d= -f2)"
require_out "$OUT"
if grep -qxF 'PACK_STALE=1' "$OUT/run.env" 2>/dev/null; then
  echo "FAIL wiring-stray-word: PACK_STALE=1 from a stray word outside the fence"; cat "$OUT/run.env" | sed 's/^/       /'
  fail=1
else
  echo "ok   wiring-stray-word: PACK_STALE=0 despite a stray word before the fence"
fi

exit "$fail"
