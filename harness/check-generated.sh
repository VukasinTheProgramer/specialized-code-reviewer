#!/usr/bin/env bash
# Regenerates from core/ into a scratch dir (AGENTS_OUT override — see
# build-agents.sh) and diffs it against .claude/agents/. Non-zero exit means
# someone (you, in six weeks) hand-edited a generated file and lost it on
# the next build, or core/ changed without regenerating. Run before every
# commit that touches core/ or .claude/agents/.
set -eu
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

AGENTS_OUT="$TMP" bash harness/build-agents.sh >/dev/null

if diff -rq .claude/agents "$TMP" >/dev/null 2>&1; then
  echo "ok: .claude/agents/ matches what core/ generates"
  exit 0
else
  echo "DRIFT: .claude/agents/ does not match core/'s output. Diff:" >&2
  diff -ru .claude/agents "$TMP" >&2 || true
  echo "Someone hand-edited a generated file, or core/ changed without regenerating. Run harness/build-agents.sh and commit the result." >&2
  exit 1
fi
