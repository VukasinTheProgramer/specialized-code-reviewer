#!/usr/bin/env bash
# /pr-review — Steps 0.1, 1, 2 and 4: build the run's artifacts. No model, no judgment.
#
#   usage:  bash .claude/skills/pr-review/scripts/build-artifacts.sh [BASE]
#   env:    PR_REVIEW_NO_GRAPH=1   skip the graphify refresh (tests, CI)
#           PR_REVIEW_PACK=<path>  use another domain pack (tests; a foreign repo's pack)
#           PR_REVIEW_HEAD=<sha>   diff BASE...<sha> instead of BASE...current-HEAD (eval corpus
#                                  reruns against a fixed historical head, without checking out —
#                                  keeps this worktree's own pipeline code, not that commit's)
#           PR_REVIEW_LARGE_DIFF=<n>  changed-line threshold for the LARGE_DIFF warning (default 2500)
#           PR_REVIEW_KEEP_DAYS=<n>   age in days before a stale pr-review.* run dir is pruned (default 7)
#           PR_REVIEW_IMPACTED_CAP=<n>  max impacted-caller candidates to emit (default 24)
#
# Writes into a fresh $OUT under .git/:  patch.diff  manifest.txt  brief.txt  wiring.txt
#   probes-{access,data,answer,structure,all}.txt  known-non-defects.txt
#   impacted-candidates.txt  run.env
# Prints run.env (key=value) followed by brief.txt. Exit codes:
#   0 ok (EMPTY=1 in run.env when there is nothing to review)   2 not a git repo
#   3 base does not resolve    4 no merge base (unrelated histories)    5 cannot create $OUT
set -u
BASE_ARG="${1:-dev}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "error: not inside a git repository" >&2; exit 2; }
cd "$ROOT"
PACK="${PR_REVIEW_PACK:-.claude/references/pr-review-domain.md}"

# ---------- 0.1 domain pack + ledger: existence and path:line staleness,
# batched. One `git ls-files` call across every cited path from both files,
# and one `awk` pass computing line counts for every path with a line
# citation — instead of a spawn pair per citation (up to ~70 subprocesses for
# ~35 citations before batching). Plain newline-delimited strings throughout,
# never bash arrays: this repo's bash is 3.2 (macOS ships it) where
# `"${arr[@]}"` on an *empty* array throws "unbound variable" under `set -u`
# — confirmed, not theoretical — and every list built below can legitimately
# be empty (no pack, no ledger, no line-numbered citations at all).

extract_citations() {  # every `path.ext[:line[-line2]]` citation containing a '/'
  grep -oE '`[A-Za-z0-9_./-]+\.[a-zA-Z]+(:[0-9]+(-[0-9]+)?)?`' "$1" 2>/dev/null | tr -d '`' | grep '/'
}

PACK_PRESENT=0; STALE=0; PACK_CITES=""; PACK_WIRING_PATHS=""
if [ -f "$PACK" ]; then
  PACK_PRESENT=1
  # A section is matched below by its exact `## Heading` string — every
  # extraction downstream (`awk '/^## X/{f=1;next} /^## /{f=0} f'`) degrades
  # to silently empty if that heading is retyped even slightly (a capital
  # letter, an extra space, a rename) and no other check here would notice:
  # PACK_STALE only validates citations *inside* a matched section, so a
  # section matching nothing has no citations to flag as stale either. Catch
  # that directly — exact-match every required heading against the pack
  # before relying on any of the sections below.
  MISSING_HEADINGS=""
  for h in "## Stack scope prefixes" "## Wiring files" "## Label probes" "## Brief probes" "## Dependencies"; do
    grep -qxF "$h" "$PACK" || MISSING_HEADINGS="$MISSING_HEADINGS
$h"
  done
  MISSING_HEADINGS="$(printf '%s\n' "$MISSING_HEADINGS" | grep -v '^$')"
  if [ -n "$MISSING_HEADINGS" ]; then
    echo "warning: domain pack is missing (or has renamed) these section headings — each degrades silently to empty otherwise: $(printf '%s' "$MISSING_HEADINGS" | tr '\n' '|' | sed 's/|/, /g; s/, $//')" >&2
  fi
  # Only repo-relative citations (containing a '/') are paths. A bare `card_repository.py:59`
  # is shorthand for a full path cited earlier in the same row, and `brief.txt` is an artifact
  # name — checking those against the tree flagged the pack stale on every run.
  PACK_CITES="$(extract_citations "$PACK" | sort -u)"
  PACK_WIRING_PATHS="$(awk '/^## Wiring files/{f=1;next} /^## /{f=0} f' "$PACK" | grep -E '^[A-Za-z0-9_./-]+$')"
fi

# ---------- 0.1c format validation — wiring-fenced, label field count,
# closed-label membership, brief bash-fence + bash -n, citation
# backtick-wrapping (validate-pack.sh; the heading check above is cheap and
# stays inline, this covers everything it doesn't). An invalid pack is
# treated exactly like a stale one below (STALE=1) rather than refused —
# same doctrine as PACK_STALE: never block a review, degrade to generic
# probes and say so loudly. ----------
PACK_INVALID=0
VALIDATOR=".claude/skills/pr-review/scripts/validate-pack.sh"
if [ "$PACK_PRESENT" = 1 ] && [ -f "$VALIDATOR" ]; then
  VALIDATE_OUT="$(bash "$VALIDATOR" "$PACK" 2>&1)"
  if [ $? = 1 ]; then
    PACK_INVALID=1; STALE=1
    echo "warning: domain pack fails format validation — treating as stale (empty probes, generic fallback):" >&2
    printf '%s\n' "$VALIDATE_OUT" | sed 's/^/  /' >&2
  fi
fi

# ---------- 0.1b ledger: same path:line staleness, scoped to the section that
# actually reaches an agent (Known non-defects + Label corrections) — a drifted
# citation in Run tally history doesn't feed any prompt, so it isn't checked. ----------
LEDGER=".claude/references/eval/review-corrections.md"
LEDGER_PRESENT=0; LEDGER_STALE=0; LEDGER_CITES=""; KNOWN_NON_DEFECTS_TEXT=""
if [ -f "$LEDGER" ]; then
  LEDGER_PRESENT=1
  KNOWN_NON_DEFECTS_TEXT="$(awk '/^## Known non-defects/{f=1} /^## Run tally/{f=0} f' "$LEDGER")"
  LEDGER_CITES="$(printf '%s\n' "$KNOWN_NON_DEFECTS_TEXT" | extract_citations /dev/stdin | sort -u)"
fi

# ---- batched lookups, built once from every citation collected above ----
ALL_TOKENS="$(printf '%s\n%s\n%s\n' "$PACK_CITES" "$PACK_WIRING_PATHS" "$LEDGER_CITES" | grep -v '^$')"
TRACKED=""
if [ -n "$ALL_TOKENS" ]; then
  TRACKED="$(printf '%s\n' "$ALL_TOKENS" | sed 's/:.*//' | sort -u | xargs git ls-files -- 2>/dev/null)"
fi
path_exists() {
  if [ "${1%/}" != "$1" ]; then printf '%s\n' "$TRACKED" | grep -q "^$1"
  else printf '%s\n' "$TRACKED" | grep -qxF "$1"; fi
}

LINE_COUNTS=""
if [ -n "$ALL_TOKENS" ]; then
  # Only paths confirmed to exist go into the batched awk call below — awk
  # aborts the *entire* multi-file pass on the first unreadable file (tested:
  # every file after it silently loses its count too), so a stale path here
  # must be filtered out first rather than let it poison every path after it.
  EXISTING_LINE_PATHS=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    path_exists "$p" && EXISTING_LINE_PATHS="$EXISTING_LINE_PATHS
$p"
  done <<LINE_PATHS_EOF
$(printf '%s\n' "$ALL_TOKENS" | grep ':' | sed 's/:.*//' | sort -u)
LINE_PATHS_EOF
  EXISTING_LINE_PATHS="$(printf '%s\n' "$EXISTING_LINE_PATHS" | grep -v '^$')"
  if [ -n "$EXISTING_LINE_PATHS" ]; then
    LINE_COUNTS="$(printf '%s\n' "$EXISTING_LINE_PATHS" | xargs awk \
      'FNR==1 && NR>1 {print prevfile, prevcount} {prevfile=FILENAME; prevcount=FNR} END{if (prevfile != "") print prevfile, prevcount}' \
      2>/dev/null)"  # one call, every file's count via the FNR==1/NR>1 file-boundary — not gawk's ENDFILE, this repo's awk doesn't have it
  fi
fi
line_count_of() { printf '%s\n' "$LINE_COUNTS" | grep "^$1 " | awk '{print $2}'; }

# citation_ok returns 0 (OK) or 1 (STALE) for one `path` or `path:line`/`path:line-line2`
# citation — path existence plus, when a line number is present, a bounds check
# against the file's line count, checking both ends of a range (a start still
# inside a shrunk file with the end now past EOF is still stale). This catches
# a citation pointing past EOF; it does NOT catch a citation pointing at a
# *valid but wrong* line in a file that grew or shrank elsewhere (that needs a
# human/LLM read, same as any other content check) — bounds, not semantics.
citation_ok() {
  path="$1"; line=""; end_line=""
  case "$1" in
    */*:*)
      path="${1%%:*}"; linespec="${1#*:}"; line="${linespec%%-*}"
      case "$linespec" in *-*) end_line="${linespec#*-}";; *) end_line="$line";; esac
      ;;
  esac
  path_exists "$path" || return 1
  if [ -n "$line" ]; then
    case "$line" in ''|*[!0-9]*) return 0;; esac
    case "$end_line" in ''|*[!0-9]*) return 0;; esac
    n="$(line_count_of "$path")"
    [ -n "$n" ] && [ "$line" -ge 1 ] && [ "$end_line" -ge "$line" ] && [ "$end_line" -le "$n" ]
  fi
}

if [ "$PACK_PRESENT" = 1 ]; then
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    citation_ok "$c" || STALE=1
  done <<PACK_CITES_EOF
$(printf '%s\n%s\n' "$PACK_CITES" "$PACK_WIRING_PATHS")
PACK_CITES_EOF
  [ "$STALE" = 1 ] && echo "note: domain pack cites a path or line that no longer matches this repo — treating as stale." >&2
fi

if [ "$LEDGER_PRESENT" = 1 ]; then
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    citation_ok "$c" || LEDGER_STALE=1
  done <<LEDGER_CITES_EOF
$LEDGER_CITES
LEDGER_CITES_EOF
  # Warn only — never gate on this. A drifted line number inside one rule's
  # supporting citation doesn't invalidate the rule (the rule is the prose,
  # the citation is evidence for it), and unlike the pack — where staleness
  # falls back to generic probes, a safe degrade — emptying the whole
  # known-non-defects corpus over one bad citation would silently un-suppress
  # every other rule's false positive, the opposite of what this file is for.
  [ "$LEDGER_STALE" = 1 ] && echo "warning: ledger's Known non-defects/Label corrections cite a path or line that no longer matches this repo — a citation has drifted, go fix it (still passed to the scout: gating on this would drop every other rule too)." >&2
fi

# ---------- 1.1 base ----------
if git rev-parse --verify --quiet "$BASE_ARG" >/dev/null; then
  BASE="$BASE_ARG"; BASE_NOTE=""
  # local branch resolved — check it against origin's copy (no fetch: whatever origin/* the
  # last fetch left behind) so a stale local base doesn't silently review against old history.
  if git rev-parse --verify --quiet "origin/$BASE_ARG" >/dev/null; then
    LOCAL_SHA="$(git rev-parse "$BASE_ARG")"; ORIGIN_SHA="$(git rev-parse "origin/$BASE_ARG")"
    if [ "$LOCAL_SHA" != "$ORIGIN_SHA" ]; then
      if git merge-base --is-ancestor "$ORIGIN_SHA" "$LOCAL_SHA" 2>/dev/null; then
        BASE_NOTE="local $BASE_ARG is ahead of origin/$BASE_ARG (unpushed commits)"
      elif git merge-base --is-ancestor "$LOCAL_SHA" "$ORIGIN_SHA" 2>/dev/null; then
        BASE_NOTE="local $BASE_ARG is behind origin/$BASE_ARG — run 'git pull' or 'git fetch' before reviewing"
      else
        BASE_NOTE="local $BASE_ARG and origin/$BASE_ARG have diverged — run 'git pull' or 'git fetch' before reviewing"
      fi
      echo "warning: $BASE_NOTE" >&2
    fi
  fi
elif git rev-parse --verify --quiet "origin/$BASE_ARG" >/dev/null; then BASE="origin/$BASE_ARG"; BASE_NOTE="only origin/$BASE_ARG resolved — reviewing against it"
else echo "error: base '$BASE_ARG' resolves neither locally nor as origin/$BASE_ARG. Not substituting another base." >&2; exit 3; fi
HEAD_REF="${PR_REVIEW_HEAD:-HEAD}"
git rev-parse --verify --quiet "$HEAD_REF" >/dev/null || { echo "error: PR_REVIEW_HEAD '$HEAD_REF' does not resolve." >&2; exit 3; }
git merge-base "$BASE" "$HEAD_REF" >/dev/null 2>&1 || { echo "error: no merge base between $BASE and $HEAD_REF (unrelated histories)." >&2; exit 4; }
HEAD_SHA="$(git rev-parse "$HEAD_REF")"
if [ "$HEAD_REF" = HEAD ]; then
  git symbolic-ref -q HEAD >/dev/null || BASE_NOTE="${BASE_NOTE:+$BASE_NOTE; }HEAD is detached"
fi

# ---------- 1.4 excludes ----------
# *.lock already covers yarn.lock/Cargo.lock/Pipfile.lock/composer.lock (they
# all end in ".lock") — pnpm-lock.yaml and go.sum don't, so this repo's own
# npm lockfile isn't the only lockfile shape a foreign repo running this same
# pack (SKILL.md's own portability story) could hit.
EXCLUDES=(
  ':(exclude)**/*.lock' ':(exclude)**/package-lock.json' ':(exclude)**/pnpm-lock.yaml'
  ':(exclude)**/go.sum' ':(exclude)**/*.snap'
  ':(exclude)**/dist/**' ':(exclude)**/build/**' ':(exclude)**/*.min.*' ':(exclude)**/*.rdb'
  ':(exclude)**/*.png' ':(exclude)**/*.jpg' ':(exclude)**/*.jpeg' ':(exclude)**/*.gif'
  ':(exclude)**/*.ico' ':(exclude)**/*.pdf' ':(exclude)**/*.woff*'
)

# ---------- 1.5 artifacts, run-scoped ----------
GIT_DIR="$(git rev-parse --git-dir)"
# Prune old run dirs from past reviews — mktemp -d never cleans up after
# itself, and these accumulate forever otherwise. Only the dotted glob
# (past run dirs); .git/pr-review/ (no dot) is the fixed findings.json path
# /explain-bug reads and is never touched here.
KEEP_DAYS="${PR_REVIEW_KEEP_DAYS:-7}"
find "$GIT_DIR" -maxdepth 1 -type d -name 'pr-review.*' -mtime "+$KEEP_DAYS" -exec rm -rf {} + 2>/dev/null
OUT="$(mktemp -d "$GIT_DIR/pr-review.XXXXXX")" || { echo "error: cannot create run directory under .git/" >&2; exit 5; }
OUT="$(cd "$OUT" && pwd)"
git diff --unified=15 "$BASE...$HEAD_REF" -- . "${EXCLUDES[@]}" > "$OUT/patch.diff"   || { echo "error: cannot write patch.diff" >&2; exit 5; }
git diff --name-only  "$BASE...$HEAD_REF" -- . "${EXCLUDES[@]}" > "$OUT/manifest.txt" || { echo "error: cannot write manifest.txt" >&2; exit 5; }
CHANGED=$(git diff --numstat "$BASE...$HEAD_REF" -- . "${EXCLUDES[@]}" | awk '{a+=$1; d+=$2} END {print a+d+0}')
FILES=$(grep -c . "$OUT/manifest.txt")
RAW_FILES=$(git diff --name-only "$BASE...$HEAD_REF" | grep -c .)

# ---------- 1.5b large-diff warning (no trim — a warning costs nothing extra,
# and a silent trim would change recall no one asked to change) ----------
LARGE_DIFF_THRESHOLD="${PR_REVIEW_LARGE_DIFF:-2500}"
LARGE_DIFF=0
if [ "$CHANGED" -gt "$LARGE_DIFF_THRESHOLD" ]; then
  LARGE_DIFF=1
  echo "warning: $CHANGED changed lines across $FILES files, above the ${LARGE_DIFF_THRESHOLD}-line guideline — all five spawns (scout + 4 verifiers) each read the full patch at 15 lines of context; consider a narrower review or splitting the PR." >&2
fi

# ---------- 1.6 empty diff ----------
EMPTY=0
if [ "$CHANGED" -eq 0 ]; then
  EMPTY=1
  if [ "$RAW_FILES" -gt 0 ]; then echo "Nothing to review: every changed file was excluded (lockfiles/binaries/build output). $RAW_FILES file(s) swallowed." >&2
  else echo "Nothing to review: HEAD matches $BASE (after exclusions)." >&2; fi
fi

# ---------- 1.7 dirty tree ----------
DIRTY=0; git status --porcelain | grep -q . && DIRTY=1

# ---------- 1.8 graph refresh ----------
# No more precompute/paste here: pr-review-scout and the pr-verify-* agents hold
# live graphify MCP tools (get_node/get_neighbors/query_graph/shortest_path,
# registered in .mcp.json) and call the graph themselves, per file, as needed.
# This step only keeps graph.json fresh before they do.
GRAPH=off
if [ "$EMPTY" = 0 ] && [ -f graphify-out/graph.json ] && [ "${PR_REVIEW_NO_GRAPH:-0}" != 1 ]; then
  if command -v graphify >/dev/null 2>&1 && graphify update . >/dev/null 2>&1; then
    GRAPH=on
  else echo "note: 'graphify update' unavailable/failed — graph off." >&2; fi
fi

# ---------- 1.9 impacted callers — candidate list, graph-independent ----------
# Unchanged files that reference something this diff changed. The scout used to
# resolve these only from graphify's incoming edges, which made `impacted` empty
# on every repo without a graph — i.e. every new adopter, and the check is most
# valuable exactly there. This computes candidates deterministically instead, so
# `impacted` is populated on both paths: graph-on adds precision (real edges,
# symbol-level), graph-off still gets a real list rather than nothing.
#
# Deliberately a *candidate* list, not an answer. A word-boundary reference is
# not proof of a call — the scout confirms each one against the file and drops
# what doesn't hold, exactly as it does with a grep-resolved `related`.
#
# Format: one `caller<TAB>changed-file` per line. Caps are what keep this
# "one cheap pass": at most PROBE_CAP changed files probed, PER_FILE_CAP callers
# each, IMPACTED_CAP total, and each caller path appears once.
IMPACTED_CAP="${PR_REVIEW_IMPACTED_CAP:-24}"
IMPACTED_PER_FILE_CAP=3
IMPACTED_PROBE_CAP=60
: > "$OUT/impacted-candidates.txt"
IMPACTED_TRUNCATED=0
IMPACTED_SEEN=""
if [ "$EMPTY" = 0 ]; then
  probed=0; emitted=0
  while IFS= read -r changed; do
    [ -n "$changed" ] || continue
    [ "$emitted" -ge "$IMPACTED_CAP" ] && { IMPACTED_TRUNCATED=1; break; }
    if [ "$probed" -ge "$IMPACTED_PROBE_CAP" ]; then IMPACTED_TRUNCATED=1; break; fi
    # Non-code files have no callers to break; a data/config file's name is also
    # the token most likely to false-match prose.
    case "$changed" in
      *.md|*.txt|*.rst|*.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|*.env|*.lock|*.snap|*.csv|*.sql) continue ;;
    esac
    tok="${changed##*/}"; tok="${tok%.*}"
    # A token this generic matches most of the repo, so every hit is noise.
    case "$tok" in
      __init__|__main__|index|main|app|application|utils|util|types|type|const|constants|helpers|helper|config|conf|settings|setup|test|tests|spec|mod|lib|base|core|common) continue ;;
    esac
    [ "${#tok}" -ge 4 ] || continue
    probed=$((probed+1))
    n=0
    while IFS= read -r caller; do
      [ -n "$caller" ] || continue
      # Already in the diff: covered by the patch itself, not an impacted caller.
      grep -qxF "$caller" "$OUT/manifest.txt" && continue
      printf '%s\n' "$IMPACTED_SEEN" | grep -qxF "$caller" && continue
      IMPACTED_SEEN="$IMPACTED_SEEN
$caller"
      printf '%s\t%s\n' "$caller" "$changed" >> "$OUT/impacted-candidates.txt"
      n=$((n+1)); emitted=$((emitted+1))
      # Per-file cap counts as truncation too — the list is not exhaustive, and
      # a run that silently showed 3 of 30 callers would read as "only 3 exist".
      [ "$n" -ge "$IMPACTED_PER_FILE_CAP" ] && { IMPACTED_TRUNCATED=1; break; }
      [ "$emitted" -ge "$IMPACTED_CAP" ] && break
    done <<IMPACTED_EOF
$(git grep -lwF "$tok" "$HEAD_SHA" -- . "${EXCLUDES[@]}" 2>/dev/null | sed 's|^[^:]*:||')
IMPACTED_EOF
  done < "$OUT/manifest.txt"
fi
IMPACTED_CANDIDATES=$(grep -c . "$OUT/impacted-candidates.txt" 2>/dev/null || true)
IMPACTED_CANDIDATES="${IMPACTED_CANDIDATES:-0}"

# ---------- 2 stack scope (path-prefix test) ----------
BACKEND_PREFIX='^Backend/'; FRONTEND_PREFIX='^Frontend/'; CODE_DIRS=()
if [ "$PACK_PRESENT" = 1 ]; then
  # first backtick token of each row in the "## Stack scope prefixes" table, paired with its stack
  while IFS='|' read -r _ pre stack _; do
    pre="$(printf '%s' "$pre" | grep -oE '`[^`]+`' | head -1 | tr -d '`')"; stack="$(printf '%s' "$stack" | tr -d ' ')"
    [ -z "$pre" ] && continue
    case "$stack" in backend) BACKEND_PREFIX="^$pre";; frontend) FRONTEND_PREFIX="^$pre";; esac
    CODE_DIRS+=("$pre")
  done < <(awk '/^## Stack scope prefixes/{f=1;next} /^## /{f=0} f' "$PACK" | grep -E '^\|' | grep -vE '^\|[- |]+\|$' | grep -v 'Prefix')
fi
if [ "${#CODE_DIRS[@]}" -eq 0 ]; then
  # no pack: every top-level directory the manifest touches
  while IFS= read -r d; do CODE_DIRS+=("$d/"); done < <(grep '/' "$OUT/manifest.txt" | cut -d/ -f1 | sort -u)
fi
grep -qE "$BACKEND_PREFIX"  "$OUT/manifest.txt" && BE=1 || BE=0
grep -qE "$FRONTEND_PREFIX" "$OUT/manifest.txt" && FE=1 || FE=0
if   [ "$BE" = 1 ] && [ "$FE" = 1 ]; then SCOPE=both
elif [ "$BE" = 1 ];                  then SCOPE=backend
elif [ "$FE" = 1 ];                  then SCOPE=frontend
else                                      SCOPE=neither; fi

# ---------- 4 orientation brief — facts only, grep/awk only ----------
BRIEF="$OUT/brief.txt"
if [ "${#CODE_DIRS[@]}" -gt 0 ]; then
  git diff --unified=15 "$BASE...$HEAD_REF" -- "${CODE_DIRS[@]}" "${EXCLUDES[@]}" > "$OUT/code.diff"
else : > "$OUT/code.diff"; fi
added() { grep '^+' "$OUT/code.diff" | grep -v '^+++'; }
# Deleted lines matter as much as added ones — a probe over added() alone is
# blind to a removed guard (an ownership filter, a lock call, an await), which
# reads as "nothing here" instead of "something was taken out." In scope for
# the pack's own probes below, same as added().
removed() { grep '^-' "$OUT/code.diff" | grep -v '^---'; }
BRIEF_DEGRADED=0
{
  echo "scope:                  $SCOPE"
  echo "changed lines:          $CHANGED"
  echo "files:                  $FILES"
  if [ "$PACK_PRESENT" = 1 ] && [ "$STALE" = 0 ]; then
    # the pack's own probes, verbatim, run in a subshell with added(), removed() and $OUT in scope
    PROBES="$(awk '/^## Brief probes/{f=1;next} f&&/^```bash/{b=1;next} f&&b&&/^```/{exit} f&&b' "$PACK")"
    # D3 fix: stderr used to go straight to /dev/null — a broken probe block
    # (bad quoting, an undefined command) failed silently mid-brief with no
    # trace anywhere. Captured to $OUT/brief-probes-stderr instead; non-empty
    # means the block errored, so flag it rather than let brief.txt look
    # complete when a field silently never got written.
    ( eval "$PROBES"; echo "router registered:      ${ROUTERS:-none}" ) 2>"$OUT/brief-probes-stderr"
    if [ -s "$OUT/brief-probes-stderr" ]; then
      BRIEF_DEGRADED=1
      echo "note: domain pack's Brief probes block raised an error — brief.txt may be missing whatever it would have added: $(head -1 "$OUT/brief-probes-stderr")" >&2
    fi
  else
    echo "migrations:             $(grep -c 'migrations/\|/versions/' "$OUT/manifest.txt")"
    echo "lockfiles/deps touched: $(grep -cE 'package\.json$|requirements\.txt$|pyproject\.toml$|go\.mod$|Cargo\.toml$' "$OUT/manifest.txt")"
  fi
} > "$BRIEF"

# ---------- wiring files, verbatim from the pack (empty file when absent) ----------
if [ "$PACK_PRESENT" = 1 ]; then
  # D1 fix: reset f at the *next heading*, not only at the next fence — an
  # unclosed fence used to make this scan straight past "## Wiring files"
  # into whatever section followed, up to that section's own fence.
  awk '/^## Wiring files/{f=1;next} /^## /{f=0} f&&/^```/{if(b){exit} b=1;next} f&&b' "$PACK" > "$OUT/wiring.txt"
else : > "$OUT/wiring.txt"; fi

# ---------- per-slice label probes, split once here instead of 4 spawns each reading
# the whole pack (empty files when absent/stale — verifiers already carry their own
# fallback prose for that case, same signal as an empty wiring.txt) ----------
for f in access data answer structure; do : > "$OUT/probes-$f.txt"; done
UNMATCHED_LABELS=""
if [ "$PACK_PRESENT" = 1 ] && [ "$STALE" = 0 ]; then
  UNMATCHED_LABELS="$(awk -F'|' '
    /^## Label probes/{f=1;next} /^## /{f=0} f&&/^\|/{print}
  ' "$PACK" | awk -F'|' -v out="$OUT" '
    BEGIN {
      slice["auth"]="access"; slice["ownership"]="access"; slice["security"]="access"; slice["data-exposure"]="access";
      slice["db"]="data"; slice["concurrency"]="data";
      slice["logic"]="answer"; slice["validation"]="answer"; slice["control-flow"]="answer"; slice["state"]="answer"; slice["contract"]="answer";
      slice["layering"]="structure"; slice["duplication"]="structure"; slice["dead-code"]="structure"; slice["a11y"]="structure";
    }
    {
      label = $2; gsub(/^[ \t]+|[ \t]+$/, "", label); gsub(/`/, "", label)
      if (label == "label" || label ~ /^-+$/) next  # the table header/separator rows, not a real row
      if (!(label in slice)) { print label; next }
      probes = $3; gsub(/^[ \t]+|[ \t]+$/, "", probes)
      print "`" label "` — " probes >> (out "/probes-" slice[label] ".txt")
    }
  ')"
  # A row whose first column doesn't match one of the 15 closed-list labels
  # (a typo, a renamed label) is dropped by the awk above with no signal —
  # that label's citations silently vanish from every verifier's prompt and
  # it falls back to generic fallback prose, same failure shape PACK_STALE
  # exists to catch, just via a different cause (bad label, not bad path).
  [ -n "$UNMATCHED_LABELS" ] && echo "warning: domain pack has a row whose label doesn't match any of the 15 known labels — dropped, not split into any probes-*.txt: $(printf '%s' "$UNMATCHED_LABELS" | tr '\n' ' ')" >&2
fi

# ---------- scout gets every label's probes in one file — it has no slice
# restriction (unlike the four verifiers), so it needs the union, not a split.
# Built from the four files above, not re-parsed from the pack. Concatenated
# BEFORE the Dependencies append below, so that block lands once per file
# rather than four times over in this one. ----------
cat "$OUT/probes-access.txt" "$OUT/probes-data.txt" "$OUT/probes-answer.txt" "$OUT/probes-structure.txt" > "$OUT/probes-all.txt" 2>/dev/null

# ---------- the pack's ## Dependencies list, appended to every slice's probes
# and to the scout's union, and so to every spawn's prompt. Not its own
# artifact/payload field: no label owns it — any of the 15 can hit the "is this
# import new?" question, and the rule it carries (check the manifest before
# calling a dependency newly-added) is a false-positive guard, not a probe for
# one defect shape. Appending here is what makes it reachable at all: no agent
# may open the pack itself, so a pack section landing in no probes-*.txt lands
# in no prompt. ----------
if [ "$PACK_PRESENT" = 1 ] && [ "$STALE" = 0 ]; then
  DEPS_TEXT="$(awk '/^## Dependencies/{f=1;next} /^## /{f=0} f' "$PACK" | grep -v '^$')"
  if [ -n "$DEPS_TEXT" ]; then
    # Deliberately NOT formatted as "`name` — text" like the label rows above.
    # That shape is what an agent reads as "here is another label", and a
    # hypothesis or finding carrying a label outside the closed 15 is dropped
    # silently by the workflow (labelToSlice lookup misses -> droppedHypotheses),
    # so a row that merely looks like a label can cost a real finding.
    for f in access data answer structure all; do
      printf '\nIN-BOUNDS DEPENDENCIES (reference, not a label — never report a finding under this name):\n%s\n' "$DEPS_TEXT" >> "$OUT/probes-$f.txt"
    done
  fi
fi

# ---------- known non-defects, scout-only — the ledger's "Known non-defects"
# and "Label corrections" sections (extracted in 0.1b above, along with the
# staleness check on the citations in them), never "Run tally" onward. That
# tail grows every verdicted run; scout needs the evergreen rules, not the run
# history, so this stays flat-cost regardless of how much tally accumulates
# later. Empty when no ledger, or the heading exists with nothing under it.
# Not gated on LEDGER_STALE (0.1b already warned) — a drifted citation in one
# rule's evidence doesn't invalidate the other six, and dropping all of them
# over one bad line number would re-introduce exactly the false positives
# this file exists to suppress. ----------
if [ "$LEDGER_PRESENT" = 1 ] && [ -n "$KNOWN_NON_DEFECTS_TEXT" ]; then
  # -n guards a section that matched but was empty (e.g. a ledger with a
  # "## Known non-defects" heading and nothing under it before "## Run tally")
  # — printf '%s\n' on an empty string still writes one newline, a 1-byte file
  # that reads as truthy in JS (pr-review-verify.js's `probesAllText ? ... : ...`
  # pattern) though there is nothing in it to show the scout.
  printf '%s\n' "$KNOWN_NON_DEFECTS_TEXT" > "$OUT/known-non-defects.txt"
else
  : > "$OUT/known-non-defects.txt"
fi

# ---------- run.env ----------
{
  echo "OUT=$OUT"; echo "REPO_ROOT=$ROOT"; echo "BASE=$BASE"; echo "HEAD=$HEAD_SHA"
  echo "SCOPE=$SCOPE"; echo "BE=$BE"; echo "FE=$FE"; echo "GRAPH=$GRAPH"
  echo "CHANGED=$CHANGED"; echo "FILES=$FILES"; echo "EMPTY=$EMPTY"; echo "DIRTY=$DIRTY"; echo "LARGE_DIFF=$LARGE_DIFF"
  echo "IMPACTED_CANDIDATES=$IMPACTED_CANDIDATES"; echo "IMPACTED_TRUNCATED=$IMPACTED_TRUNCATED"
  echo "PACK_PRESENT=$PACK_PRESENT"; echo "PACK_STALE=$STALE"; echo "PACK_INVALID=$PACK_INVALID"
  echo "LEDGER_PRESENT=$LEDGER_PRESENT"; echo "LEDGER_STALE=$LEDGER_STALE"; echo "BASE_NOTE=$BASE_NOTE"
  echo "BRIEF_DEGRADED=$BRIEF_DEGRADED"
} > "$OUT/run.env"
cat "$OUT/run.env"; echo "--- brief.txt ---"; cat "$BRIEF"
[ "$DIRTY" = 1 ] && echo "note: uncommitted changes are not in this diff." >&2
exit 0
