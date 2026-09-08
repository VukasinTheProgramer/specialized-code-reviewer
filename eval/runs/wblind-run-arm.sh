#!/usr/bin/env bash
# Gate-1 BETWEEN extension: build artifacts for one arm (control or model)
# over eval/corpus-blind.md's 3 entries, against Boskov sajt (a real,
# unrelated repo) instead of this project's own history. Must be run with
# cwd inside that repo's checkout, since build-artifacts.sh resolves its
# own root via `git rev-parse --show-toplevel` from cwd.
#
#   usage: cd "<boskov-sajt-checkout>" && bash <this-repo>/eval/runs/wblind-run-arm.sh <control|model>
# Exit codes: 0 ok   3 bad args
set -u

ARM="${1:-}"
SPECIALIZED_ROOT="/Users/vukasinsavkovic/Documents/specialized-code-review"
case "$ARM" in
  control) PACK="$SPECIALIZED_ROOT/tests/packs/empty.md" ;;
  model)   PACK="model/pr-review-domain.md" ;;
  *) echo "usage: wblind-run-arm.sh <control|model>" >&2; exit 3 ;;
esac

corpus_entry() {
  case "$1" in
    b01) echo "3c9d966 c15064a" ;;
    b02) echo "c15064a 02d85b2" ;;
    b03) echo "02d85b2 ec8bc52" ;;
  esac
}

for id in b01 b02 b03; do
  entry="$(corpus_entry "$id")"
  base="${entry% *}"
  head="${entry#* }"
  echo "=== $id ($ARM): $base..$head ==="
  PR_REVIEW_PACK="$PACK" PR_REVIEW_HEAD="$head" PR_REVIEW_NO_GRAPH=1 \
    bash .claude/skills/pr-review/scripts/build-artifacts.sh "$base"
  echo
done
