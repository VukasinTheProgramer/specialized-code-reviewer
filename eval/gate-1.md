# eval/gate-1.md — decided 2026-09-08, end of week 5

Full numbers, per-label table, and everything that got worse:
`eval/week-5-report.md`. This file holds only the gate decision itself.

```
BASELINE (this week's, replacing week 2's invalidated one)
           Arm A (control, today's pipeline, empty pack)
           5 runs · 9 findings · 7 accepted (77.8%) · 1.4 accepted/run

TREATMENT  Arm B (model, today's pipeline, real 10-record pack)
           5 runs · 11 findings · 11 accepted (100%) · 2.2 accepted/run

CONTINUE   accepted-per-run >= 2.8   (2x this week's baseline, re-derived
           against arm A rather than week 2's now-invalid number --
           arm A is what the two-arm design built specifically to replace
           week 2's confounded comparison)
       AND acceptance rate  >= 50%
       AND no label that had 2+ accepted in control drops to 0 in model

STOP       accepted-per-run < 0.1x baseline   OR acceptance < 30%

BETWEEN    one more corpus of 3 branches, then decide.
           no second extension.
```

## Which clause decided it

- accepted-per-run: model's 2.2 does **not** clear 2.8 (2x arm A's 1.4).
  Misses by 0.6 — the single clause this gate turned on.
- acceptance rate: 100% clears 50% clean.
- label-drop: `duplication` (2→4) and `validation` (3→6) both held; the
  only clause from week 2 that stayed vacuous until this week has real
  teeth now, and it passed.
- Nowhere close to STOP's floor either way — not a live consideration.

## Decision, dated 2026-09-08

**BETWEEN.** One more corpus of 3 branches, on today's pipeline, same
two-arm design, same blind verdicting discipline. No second extension —
if that corpus doesn't clear 2.8 accepted/run either, the answer is STOP
under this same reading, not another BETWEEN.

Chosen reading, explicitly: re-derive the "2x baseline" against arm A
(this week's real, less-thin control) rather than take gate-0.md's
literal `0.4` at face value. Week 2's own number was already flagged as
too thin to trust standing alone (N=2); leaning on a number the file
itself distrusts, when a sturdier same-week alternative exists, would
have been the weaker read. The literal-number reading would have said
CONTINUE outright — noted in `eval/week-5-report.md`, not silently
dropped, in case this decision needs to be reopened against that
alternative later.

## What the next 3 branches need

Same corpus construction discipline as `eval/corpus.md`'s existing 5 (or
better — this is also the natural moment to reach for the deferred blind,
non-self-referential corpus, since the deviation-overlap metric already
came back N/A this week for exactly the reason a self-referential corpus
predicts). Same two arms, same blind sheet, same verdict rule, unchanged.
Whatever the combined 8-run number says, decide then — literally,
without a second BETWEEN available.

## Final decision, dated 2026-09-08 (after the BETWEEN extension)

Extension run against a genuinely blind, non-self-referential corpus
(Boskov sajt — full detail `eval/corpus-blind.md`,
`eval/gate-1-extension-report.md`). Combined 8-run result: control 1.125
accepted/run (81.8% acceptance), model 1.625 (100%). Re-derived 2x
baseline against combined control is 2.25 — model's 1.625 still falls
short, by a slightly wider margin than the original single-corpus miss.
Neither of gate-0.md's thresholds cleanly fires with BETWEEN now spent:
not a clean CONTINUE by the strict 2x reading, nowhere near STOP's own
floor either — model has never underperformed control across all 8
combined runs, and caught a real bug (a duplication its own generated
pack predicted almost verbatim) that control missed.

**CONTINUE.** Decided by the user, explicitly, on the "never worse,
sometimes uniquely better" reading over the strict 2x-bar reading —
both were live options, surfaced without a default in
`eval/gate-1-extension-report.md`, and this is the one chosen. Phase 2
(week 6: classify each changed unit) starts from here.
