# Week 5 — gate 1 measurement report

Written 2026-09-08, after un-blinding. Every verdict below was reached
blind (`todays-work/week5/wednesday.md`), against `eval/verdict-rule.md`
verbatim, before this file joined the results to their arm.

## Confounders (Monday's audit, unchanged since)

Nine pipeline commits landed between `v0.2-baseline` and this week,
including the entire week-3 record-format rewrite and a real doctrine
change (two hardcoded, foreign-codebase-citing rules deleted from
`scout.md`). None of it biases arm A vs arm B — both ran on today's
identical pipeline — but it means this week's numbers cannot be read as
"the same reviewer as week 2, plus a model." Full list:
`todays-work/week5/monday.md`.

## The two arms

Both ran on today's pipeline, over the same 5 frozen `eval/corpus.md`
SHAs, via `PR_REVIEW_HEAD` against the newly-fixed `READ_ROOT` replay
worktrees (`e5025d1`, landed before either arm ran — the same historical-
tree-vs-live-tree bug that corrupted 2 of week 2's 5 entries).

- **Arm A (control):** `tests/packs/empty.md` — every section present,
  empty. Confirmed genuinely empty (0-byte probes/wiring) before running.
- **Arm B (model):** `model/pr-review-domain.md`'s real 10 records,
  current as of this week (includes the wording fix from `4c3560d`).

## The six metrics

| Metric | Control | Model | Note |
|---|---|---|---|
| accepted / run | **1.4** (7/5) | **2.2** (11/5) | primary |
| acceptance rate | **77.8%** (7/9) | **100%** (11/11) | primary |
| per-label delta | see below | see below | high — the honest one |
| deviation overlap | **N/A** | **N/A** | see below — structurally inapplicable this run |
| regression set | — | **PASS** | gating |
| findings volume | 9 | 11 | context |

### Per-label delta (accepted findings only)

| Label | Control | Model | Δ | Week-4 records for this label |
|---|---|---|---|---|
| validation | 3 | 6 | **+3** | 3 |
| duplication | 2 | 4 | **+2** | 2 |
| contract | 0 | 1 | **+1** | 2 |
| logic | 1 | 0 | **−1** | 1 |
| control-flow | 1 | 0 | **−1** | 1 |

**Read plainly:** every label that gained (`validation`, `duplication`,
`contract`) is one of this week's more heavily-covered labels (2–3
records each). Both labels that lost ground (`logic`, `control-flow`)
have exactly **one** record each — the thinnest coverage of any
populated label. On a corpus this small (5 runs), that's suggestive, not
proof, but it's the shape the plan's own "per-label delta is the honest
one" callout was written to surface: the gains track where the pack is
actually strong, and the one loss tracks where it's thin, rather than
gains and losses landing at random.

**What got worse, named plainly (not buried):** control's e03-wednesday
run found a real, reproduced `control-flow` defect (`build-artifacts.sh`'s
wiring-fence extraction truncating on a mid-fence `## `-prefixed line) —
model's e03-wednesday run did not surface it at all. Not a regression-set
loss (that case isn't in the regression set) but a real instance of the
model arm missing something the control arm caught on the identical diff.

### Deviation overlap — N/A, structurally

The plan's intent: check how many of week 4's 5 hand-found deviations
(`eval/week-4-deviations.md`) arm B independently re-reports. None of
week 4's deviations are reachable by this corpus: they live in
`harness/build-agents.sh`, `harness/check-generated.sh`, and the
`model/FORMAT.md` vs `generate-domain-pack/SKILL.md` label-list drift —
none of which exist yet, or are touched, in any of the 5 frozen week-2
diffs (`harness/` wasn't created until week 2's core split, and the one
diff that does touch `model/FORMAT.md`, e05-friday, only *creates* it —
doesn't compare it against `generate-domain-pack/SKILL.md`). This isn't
a null result on the model's recall; the corpus and the deviations were
never going to intersect. Real fix: a genuinely blind, non-self-
referential corpus (already deferred, `eval/corpus.md`) is what this
metric actually needs.

### Regression set

The one existing case (`18276dc4-duplication`, base `87a033d`, head
`18276dc4c24f843674dc0f7db4aca9f970551e84`) still found in arm B: **PASS**.
Checked against arm A too (expected FAIL — that case's ground truth was
originally found with a domain pack loaded; arm A structurally has none,
so a divergence there isn't a regression signal).

## Reading `eval/gate-0.md` against these numbers

`eval/gate-0.md`'s thresholds (`accepted-per-run >= 0.4`, `acceptance
>= 50%`) are **absolute numbers derived from week 2's own baseline**
(0.2 accepted/run at N=2) — a baseline this week's confounder audit
already ruled invalid to compare against directly. Two honest readings
of gate 1 exist, and they disagree:

**Reading A — apply gate-0.md's stated absolute numbers literally.**
Model's 2.2 accepted/run clears 0.4; 100% clears 50%; the label-drop
clause is vacuous either way (it was written against week 2's own
runs, where no label ever reached 2 accepted). → **CONTINUE.**

**Reading B — re-derive "2x baseline" using arm A (this week's true
confound-free control) as the baseline the 2x multiplier was always
meant to apply to**, since arm A is this week's actual equivalent of
what week 2's number was originally *for*, and using it is the entire
reason this week ran two arms instead of comparing against week 2's
stale number. Under this reading: 2x of control's 1.4 is 2.8; model's
2.2 does not clear it. Acceptance rate and the label-drop clause both
still pass clean. → **BETWEEN** (one more corpus of 3 branches, no
second extension) — not STOP; nothing here is remotely close to STOP's
own floor (accepted/run < 0.1 or acceptance < 30%).

Both readings agree: this is not a STOP. They disagree on CONTINUE vs.
BETWEEN, and the difference between them is real — not a rounding
question, and not one this report should quietly pick a side on. Gate 1
is a decision the user makes in writing, dated, against thresholds
written before there was a stake in the answer (`eval/gate-0.md`'s own
framing) — surfacing the ambiguity honestly is what that framing
requires, not resolving it here.

## What week 6 needs from this, whichever way gate 1 goes

If it continues: the per-label table above, and the specific fact that
`control-flow` and `logic` — the two thinnest-covered labels — are also
the two that showed no gain, is the first concrete evidence for what a
classifier would need to route *toward* (labels with real coverage) and
*away from* (labels the pack barely touches yet).

If it stops or goes BETWEEN: the same table is the honest starting
point for precision work on the existing verifiers, and the deviation-
overlap gap is a direct argument for building the blind, non-self-
referential corpus before spending more time on this one.
