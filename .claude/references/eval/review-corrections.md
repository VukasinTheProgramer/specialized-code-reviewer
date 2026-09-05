# PR reviewer — corrections ledger

What the reviewer got wrong, and the rule that stops it happening again.

The reviewer does not learn from past fix commits. It learns from being corrected here. Every time a run reports something and a human says *that is not a defect*, the dismissal is written down as a **rule**, not as a one-off veto — otherwise the same false finding returns on the next branch that touches the same code.

This copy ships empty — every entry below is repo-specific, learned from actual runs against actual code, and none of that transfers between repos. Start accumulating entries the first time a run against this repo gets a verdict.

## Why not score against past fix commits

The first design fed the reviewer each historical review-fix commit's parent and scored it on finding what a human had found. It was dropped before implementation, for two reasons that do not go away with a bigger sample.

**The answer key would be this team's own past review quality.** A defect class nobody here has ever caught has no entry in it, so the reviewer scores full marks for missing exactly what the humans missed. The number would measure agreement, not correctness.

**Fix commits carry more than fixes.** A rename, a product decision, a feature built in the same commit — under "the fix changed it and the reviewer did not flag it, therefore missed", all of that imports as a penalty for not reporting work that was intended.

What replaces it is below: the reviewer learns from being corrected, and the number comes from what survives a human read.

**This tally cannot count what the reviewer missed, and does not claim to.** A defect nobody noticed appears in neither the ledger nor the tally. The honest measure of a miss is prospective — running on live pull requests and watching what still reaches production — and that is phase-two work.

Neither this tally nor a regression set (see `.claude/references/eval/regression-set/README.md` if this copy has one) substitutes for the other. This tally measures what the reviewer reports and how much of it survives a human read, per label. A regression set measures whether a *change to the reviewer* loses ground it already held — replaying past accepted findings against their original diffs.

## How an entry is made

After a run, every finding gets one of three verdicts from the person who read it:

| Verdict | Meaning | What it writes here |
|---|---|---|
| **accepted** | Real defect, fixed or filed | Nothing here — but if this copy carries the regression-set tooling, record it there too, so the acceptance also becomes ground truth the reviewer can't quietly regress on later. |
| **dismissed** | Not a defect | A new entry, or a `seen:` tick on an existing one. |
| **mislabelled** | Real, wrong label | An entry under *Label corrections*, naming both labels. |

A dismissal is only complete when it answers two questions: **what makes this safe**, and **what would make it unsafe**. A rule with no second half is a rule that suppresses the real version of the same defect later, which is worse than the false positive it prevents.

## Promotion

An entry seen **twice** stops living here and moves into `.claude/agents/pr-review-scout.md` — as a "not this" clause on the label it kept landing on, or as a line in that file's *Known non-defects* section. This ledger holds the evidence; the agent file holds only the rules that earned their place, because every line there is paid for on every spawn.

Nothing here is ever phrased as "never report `<label>`". Rules name a pattern and its guard, never a label to stop looking at.

**Label corrections promote on first sighting.** The two-sighting bar exists because suppression is dangerous: a non-defect rule stops the reviewer reporting something, and one bad call should not silence a check on its own. A label correction suppresses nothing — it moves a finding from one label to a better one — so it can enter the agent file as soon as it is right.

---

## Known non-defects

---

## Label corrections

---

## Run tally

The number that says whether this is working. One row per real run, appended after the verdicts are given. Acceptance rate per label is what a phase-two decision reads: a label dismissed more often than accepted has a probe problem, and the fix goes in the agent file, not here.

| Date | Branch | Findings | Accepted | Dismissed | Mislabelled | Tokens |
|---|---|---|---|---|---|---|

### Verdict log

One row per finding, appended as verdicts are given. **The tally counts; this log is what makes a per-label rate derivable** — accepted and dismissed totals alone cannot say which label was wrong.

| Run | Finding | Label | Verdict | Note |
|---|---|---|---|---|

### Per-label acceptance

Derived from the verdict log, not maintained by hand. A label dismissed more often than accepted has a probe problem, and the fix goes in the agent file — a probe that keeps pointing at safe code is teaching the reviewer to look in the wrong place.

| Label | Accepted | Dismissed | Mislabelled |
|---|---|---|---|

Every label starts with no findings. **No findings is not a passing grade** — it is no data.
