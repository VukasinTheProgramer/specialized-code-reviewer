# Week 4 deviations harvest

Every deviation found while authoring `model/pr-review-domain.md`'s Label
probes records — collected here per the plan's Thursday task, not fixed
(records are data this week, not a backlog). Three uses: free findings,
a sanity check on the records themselves, and a partial answer key for
Monday's week-5 re-run.

| # | File:line | Deviates from | Real bug? |
|---|---|---|---|
| 1 | `harness/build-agents.sh:12` | `validation.git-root-guard` | **No — tested, not assumed.** `set -eu`'s own errexit aborts the script on the failing `git rev-parse --show-toplevel` inside the assignment, before `ROOT` is ever used empty — confirmed by running it outside a git repo (`fatal: not a git repository...`, exit 128, script never reaches `cd`). Corrects Monday's commit message, which called this "arguably a latent bug" without testing it. |
| 2 | `harness/check-generated.sh:8` | `validation.git-root-guard` | **No**, same mechanism and same correction as #1 — also `set -eu`. |
| 3 | `harness/build-agents.sh:1` (whole file) | `contract.script-header-documents-interface` | **Minor, not urgent.** No `usage:`/exit-codes header block. Lower-value here than on the skill scripts — this file has no external caller besides `check-generated.sh` and CI, and its own comment block already documents *when* to run it. Worth a two-line header addition someday; not a functional defect. |
| 4 | `harness/check-generated.sh:1` (whole file) | `contract.script-header-documents-interface` | Same as #3. |
| 5 | `model/FORMAT.md` §4 vs `.claude/skills/generate-domain-pack/SKILL.md` step 3 | No Label probes record — this is a pack-format-level finding, not a code-under-review one, so no exemplar exists to hold it up against | **Yes, real.** The closed 15-label list is hand-retyped in both places and has already drifted: same 15 names, different order (`layering`'s position moved between the two copies). Nothing tests that they match. If the closed set itself ever changes, only whichever copy someone remembers to update reflects it — the other goes silently stale. Same duplication class as the `pack-heading-check.sh` fix `duplication.shared-matching-logic-sourced-not-copied` documents; this one just hasn't been fixed yet. Candidate for `future-improvements/`, not touched this week. |

## What this says about the records themselves

Two real deviations (#1, #2) turned out, on actual testing, not to be bugs
— the pattern they deviate from is still correct as a general rule, but
citing them as evidence of danger was wrong until tested. Left them in
`validation.git-root-guard`'s `deviations:` field regardless — deviating
from the letter of the convention is still a fact about those two files,
independent of whether it happens to be safe today for an unrelated
reason (`set -e`). If `-e` is ever dropped from either script, the
guard's absence stops being free.

One real, unfixed structural bug (#5) surfaced by the act of writing
records, not by reviewing a diff — exactly the kind of free finding this
week's method is supposed to produce.
