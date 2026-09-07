#!/usr/bin/env bash
# Week 5 gate-1: build artifacts for one arm (control or model) over every
# frozen eval/corpus.md entry, via PR_REVIEW_HEAD. Bash 3.2 compatible
# (macOS ships it, this repo's own build-artifacts.sh already avoids
# associative arrays for the same reason) — a case statement per entry,
# not a hash.
#
#   usage: bash eval/runs/w5-run-arm.sh <control|model>
# Exit codes: 0 ok   3 bad args
set -u

ARM="${1:-}"
case "$ARM" in
  control) PACK=tests/packs/empty.md ;;
  model)   PACK=model/pr-review-domain.md ;;
  *) echo "usage: w5-run-arm.sh <control|model>" >&2; exit 3 ;;
esac

corpus_entry() {
  case "$1" in
    e01-monday)    echo "87a033d 18276dc" ;;
    e02-tuesday)   echo "18276dc 43f3f8e" ;;
    e03-wednesday) echo "43f3f8e a42f5e6" ;;
    e04-thursday)  echo "a42f5e6 270c8e9" ;;
    e05-friday)    echo "270c8e9 2887944" ;;
  esac
}

for id in e01-monday e02-tuesday e03-wednesday e04-thursday e05-friday; do
  entry="$(corpus_entry "$id")"
  base="${entry% *}"
  head="${entry#* }"
  echo "=== $id ($ARM): $base..$head ==="
  PR_REVIEW_PACK="$PACK" PR_REVIEW_HEAD="$head" PR_REVIEW_NO_GRAPH=1 \
    bash .claude/skills/pr-review/scripts/build-artifacts.sh "$base"
  echo
done
