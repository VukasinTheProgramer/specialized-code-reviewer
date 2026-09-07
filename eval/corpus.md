# Baseline corpus — week 2

Frozen by SHA, never by branch name — replayable identically regardless of
what branches move later. Run via `build-artifacts.sh <base> ` with
`PR_REVIEW_HEAD=<head>` (no checkout needed).

Corpus choice: this repo's own history is the only real history that exists
(a fresh project — see `todays-work/` week 2 notes for the discussion). Used
this week's five real work days rather than synthetic branches. Trade-off,
stated up front: self-referential — the reviewer reviews its own pipeline
scripts, which both the reviewer's author and I already know well, cutting
against the "judge blind" spirit this exercise wants. No genuine tiny
(3-5 line) fix exists in this history either. Accepted anyway, per the
2026-09-07 decision, over pulling in an unrelated repo.

| id | base | head | what it does | expectation (written before running) |
|---|---|---|---|---|
| e01-monday | `87a033d` | `18276dc` | Failing-corpus test fixtures (7 markdown packs) + `tests/run.sh` spec + a `validate-pack.sh` skeleton (one check implemented: heading match). | Mostly new test-fixture data, not logic. Expect little to nothing; if anything fires, it's against the skeleton's own heading-check code, not the fixtures. |
| e02-tuesday | `18276dc` | `43f3f8e` | Five more `validate-pack.sh` checks: wiring-fence parity, label field-count, closed-label membership, brief bash-fence+`bash -n`, citation backtick-wrapping. Real awk/bash logic, folds in one trivial `.gitignore` commit. | The logic-heaviest entry so far — genuine candidate for a real finding if an awk edge case (field-splitting, fence-counting) was missed. |
| e03-wednesday | `43f3f8e` | `a42f5e6` | Wires the validator into `build-artifacts.sh` (`PACK_INVALID` gate, folded into the existing `STALE` flag), fixes D1 (wiring-extraction heading-reset) and D3 (brief-probes stderr capture → `BRIEF_DEGRADED`), updates `SKILL.md`. Largest of the five (119 lines, 4 files). | Largest and most structurally significant diff of the five — best single candidate to surface something real, if anything does. |
| e04-thursday | `a42f5e6` | `270c8e9` | Pure prose fix to `generate-domain-pack/SKILL.md` — D7 (`--force`), D8 (`<BASE>` arg), folds the validator into step 3, fixes a wrong claim about `PACK_STALE`. Single file, zero executable code touched. | Docs-only — the "mostly config or docs" slot. Expect a clean run; there's no logic here to be wrong. |
| e05-friday | `270c8e9` | `2887944` | Adds `model/FORMAT.md` (new doc), updates `validate-pack.sh`'s error messages to cite it by section (string literals only, no logic change), adds two README troubleshooting rows. | Mostly docs with a cosmetic string-literal touch to already-tested code. Expect clean or near-clean. |

## Not this corpus

A genuinely blind, non-self-referential corpus (a different repo's real
feature branches) — deferred, not rejected; see the 2026-09-07 decision.
