# Sourced by build-artifacts.sh and model/validate-pack.sh — the one place
# that reads model/pack-headings.txt and checks a pack against it. Each
# caller reports missing headings its own way (build-artifacts.sh warns and
# degrades; validate-pack.sh hard-fails per heading, citing model/FORMAT.md
# §1) — those two behaviors are legitimately different, so only the actual
# matching logic is shared here, not the reporting. This existed as two
# independently hand-typed copies before, and their messages had already
# drifted apart (one carried the model/FORMAT.md citation, the other
# didn't) — the same duplication pattern eval/review-corrections.md already
# recorded once as a real accepted defect.
#
#   usage: missing_pack_headings <headings-file> <pack-file>
#   prints every heading from <headings-file> not found verbatim in
#   <pack-file>, one per line — empty output means none are missing.
#   returns 1 (nothing printed) if <headings-file> itself is unreadable —
#   the caller must check this before trusting empty output as "nothing
#   missing" rather than "couldn't check at all".
missing_pack_headings() {
  headings_file="$1"; pack_file="$2"
  [ -r "$headings_file" ] || return 1
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    grep -qxF "$h" "$pack_file" || printf '%s\n' "$h"
  done < "$headings_file"
}
