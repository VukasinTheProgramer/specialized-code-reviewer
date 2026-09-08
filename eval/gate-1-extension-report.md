# Gate 1 BETWEEN extension — combined result

Written 2026-09-08. Per `eval/gate-1.md`'s BETWEEN decision: one more
corpus of 3 branches, no second extension. Full corpus detail:
`eval/corpus-blind.md`. Blind verdicting done the same way as week 5
(`eval/runs/wblind-sheet.json`, key opened only after all 4 findings
verdicted) — every finding independently reproduced against the actual
historical commit before verdicting, not trusted from its own narration.

## The new corpus's own numbers (3 runs, genuinely blind — Boskov sajt,
never reviewed by me before this run)

| Metric | Control | Model |
|---|---|---|
| findings | 2 | 2 |
| accepted | 2 | 2 |
| accepted/run | 0.667 | 0.667 |
| acceptance rate | 100% | 100% |

**Tied, not a win for either arm.** Both arms found the same real
initials-duplication bug independently. Each arm also found one thing
the other missed: control caught a genuinely serious bug (a hardcoded
Web3Forms placeholder API key — the contact form silently fails on
every real submission as shipped); model caught a real duplication bug
its own generated pack's `contract.site-info-single-source` record
predicted almost exactly (`unsafe_when: a component inlines a
phone/email/address string literal instead of importing site`) — a
clean piece of causal evidence the pack is doing *something*, even
though it didn't add up to a higher aggregate number this time.
`b02` and `b03` (the two smaller diffs) produced zero findings in
either arm — nothing to find, honestly reported, not padded.

## Combined with the original 5-run corpus (`eval/week-5-report.md`)

| Metric | Control (8 runs) | Model (8 runs) |
|---|---|---|
| findings | 11 | 13 |
| accepted | 9 | 13 |
| accepted/run | **1.125** | **1.625** |
| acceptance rate | 81.8% | 100% |

Re-deriving the "2x baseline" bar against this combined control number
(the same reading `eval/gate-1.md` chose the first time): 2× 1.125 =
**2.25**. Model's combined 1.625 does not clear it — the gap is
slightly *wider* than the original single-corpus miss (0.625 vs. 0.6),
not narrower. The extension corpus did not resolve the ambiguity in
model's favor.

Checked the other side too: nowhere close to STOP's own floor
(accepted-per-run < 0.1× baseline, or acceptance < 30%) under any
reading. Model's acceptance rate stayed at 100% across both corpora
combined, and its accepted/run, while short of 2×, is comfortably
*above* control's own number every single time measured — it has never
once underperformed control in this project's history so far.

## The actual dilemma, surfaced plainly

`eval/gate-1.md`'s BETWEEN clause says "no second extension" — meaning
the only two moves left on the table are CONTINUE or STOP. Neither of
gate-0.md's own thresholds cleanly fires:

- The strict 2× reading (the one this project has consistently
  preferred) says **not CONTINUE** — model still falls short of 2×
  control, now by a slightly larger margin than before.
- STOP's own floor is nowhere near triggered — model has never
  underperformed control on any of the 8 combined runs, and its
  acceptance rate is perfect throughout.

This is a real gap in the plan's own three-way framework: it doesn't
name what to do when the extension corpus neither closes the CONTINUE
gap nor gets anywhere near STOP. **Not resolving this here** — same
reasoning as the original gate-1 CONTINUE-vs-BETWEEN call: this decides
whether phase 2 starts, and it should be made by the person who has to
live with it, not defaulted to silently.

**My honest read, not a decision:** the 2× multiplier was calibrated to
guard against noise in a thin sample: it's a *should clearly be
better*, not *never worse*, bar. Model has never been worse than
control across 8 combined runs and produced one clean, pack-caused
catch this round — that's a real, if modest, positive signal, just not
the 2× the original bar demanded. A defensible case exists either way:
CONTINUE on the strength of "never worse, sometimes uniquely better,"
or STOP on the strength of "the bar was written in advance for a
reason, and it wasn't cleared even after the one extension the plan
allowed."
