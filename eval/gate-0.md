# eval/gate-0.md — written 2026-09-07, before week 3 begins

```
BASELINE   5 runs · 2 findings · 1 accepted (50%) · 0.2 accepted/run
           # duplication 1/1 accepted · validation 0/1 accepted
           # 4 additional findings (e02, e05) excluded as corpus-methodology
           # artifacts, not counted either direction -- see caveat below

CONTINUE   accepted-per-run >= 0.4   (2x baseline)
       AND acceptance rate  >= 50%
       AND no label that had 2+ accepted here drops to 0
           # vacuous this round: no label reached 2 accepted yet (N=1
           # total accepted) -- this clause has no teeth until a corpus
           # with more real findings exists to test it against

STOP       accepted-per-run < 0.1   OR acceptance < 30%
           # the model made it no better, or actively worse

BETWEEN    one more corpus of 3 branches, then decide.
           # no second extension. this clause is the whole point.
```

## Caveat: this baseline is low-confidence, and that's worth stating plainly

The corpus is 5 runs but only **2 real findings survived verdicting** — the
other 4 (from `e02-tuesday` and `e05-friday`) were excluded as
corpus-methodology artifacts (the historical diff pair pre-dates this
repo's own `core/`/`harness/` split; the finding was true of the *current*
tree, not the diffed commits — see `eval/runs/README.md`). N=2 is not
enough to trust a percentage on its own; `1 accepted / 2 findings = 50%`
would read very differently as `4/8` or `40/80`. The thresholds above are
set as **multiples/fractions of this specific baseline**, deliberately
loose (2x to continue, not the plan's illustrative +50%) precisely because
the number underneath them is this thin.

This is also the corpus's known trade-off from day one
(`eval/corpus.md`): self-referential (the reviewer reviewing its own
pipeline scripts, code both the reviewer's author and I already knew well)
and mostly composed of diffs I'd already effectively reviewed by writing
them carefully across the week — so a *low* finding count here is partly a
measurement of "how clean was this week's own work," not purely "how good
is the reviewer at finding real defects in typical code." A genuinely
blind corpus (a different repo's real feature branches, deferred per
`eval/corpus.md`) is the fix, not re-running this same corpus for a bigger
N.

## What did work

The two real verdicts are informative in shape even at N=2: the accepted
finding (`duplication`, e01) was independently re-verified and its
predicted failure — the two copies drifting apart — had already happened by
the time it was checked (Thursday), which is about as strong a validation
signal as a single finding can carry. The dismissed finding (`validation`,
e01) revealed a real, reusable safe pattern (declared incremental WIP with
a dated TODO and a co-shipped test asserting the expected fail state) now
captured in `eval/review-corrections.md`'s Known non-defects — that rule
should suppress a class of future false positives on this repo's own
day-by-day incremental commit style, which is worth more than the raw
number suggests.

## Decision, dated

Continuing to week 3. The baseline is thin but nothing in it argues for
stopping, and the corpus's known weaknesses (self-referential, low N) are
a reason to *build a better corpus later* (deferred, tracked in
`eval/corpus.md`), not a reason to treat week 1–2's actual pipeline work as
having failed a test it was never really strong enough to fail.
