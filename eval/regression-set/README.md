# PR reviewer — regression set

0.10.1's second measurement source. Where the [corrections ledger](../review-corrections.md)
measures what the reviewer reports and how much survives a human read, this
measures whether a *change to the reviewer* loses ground it already held.

Every finding a human marks **accepted** becomes a case: the parent diff as
input, that finding as ground truth — never a human fix commit, and see the
ledger's "Why not score against past fix commits" for why.

## Growing the set

At no authoring cost — pulled from the run's own persisted output, never
hand-typed:

```bash
bash .claude/skills/pr-review/scripts/add-regression-case.sh <label> <file> <line>
```

Run this right after recording an **accepted** verdict in the ledger. It
reads `.git/pr-review/findings.json` (the fixed path the last `/pr-review`
run persisted), pulls the matching finding verbatim, and writes
`cases/<head-short>-<label>-<line>.json`. Re-running for the same finding is
a no-op — cases are never duplicated.

## Case format

```json
{
  "id": "<head-short>-<label>-<file-with-slashes-as-underscores>-<line>",
  "base": "<sha the review ran against>",
  "head": "<sha reviewed>",
  "added": "2026-09-04",
  "finding": { "label": "logic", "file": "...", "line": 58, "failure_mode": "..." }
}
```

`failure_mode` is kept for a human skimming `FAIL` cases; `evidence` is
dropped — the check below never compares it, and it's the field most likely
to run long.

## Re-running the whole set

Required after any change to the reviewer (SKILL.md, an agent definition, a
label probe) — a change that recovers one finding while losing another is
not progress, and only a full re-run reveals it.

```bash
bash .claude/skills/pr-review/scripts/run-regression-set.sh
```

For each case this rebuilds the artifacts for `base...head` (`build-artifacts.sh`
already supports replaying a fixed historical head via `PR_REVIEW_HEAD`,
without checking anything out). It cannot spawn the four verifier subagents
itself — that's the Workflow step in `/pr-review`'s own pipeline, not
shell-scriptable — so it prints, per case, the artifacts directory and the
two remaining steps: run the Workflow against that directory, then

```bash
bash .claude/skills/pr-review/scripts/check-regression-case.sh <case.json> <findings.json>
```

`check-regression-case.sh` matches on label+file+line only — a reworded
`failure_mode` is not a loss — and refuses to compare a case against a
findings.json built from a different base/head (`NOT COMPARABLE`, exit 2)
rather than silently reporting a false pass or fail.

## Reading the set

At 10+ accumulated cases, per-0.10 AC5, the Structure-slice model, the
description pass and the slice boundaries get decided from counts here and
in the run tally — not from argument.
