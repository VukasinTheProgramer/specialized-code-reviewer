# Verdict rule — written 2026-09-07, before any corpus run's findings exist

Written now so the bar can't flex to match whatever the runs happen to
produce. Verdicting happens Thursday, a day after these runs — not today.

## Accepted

**"I would change the code because of this" — not "this is technically
true."** The second standard accepts every pedantic-but-harmless
observation; the first is the actual bar a real reviewer holds a real PR
to. Concretely: the finding names a file, line, and concrete trigger; I can
independently re-derive the same failure by reading the cited code myself
(not by trusting the finding's own narration of it); and knowing about it,
I'd want it fixed before merging — not "worth a comment," not "nice to
know," actually blocking.

## Dismissed

The finding's failure_mode doesn't hold up against the actual code — the
trigger it names can't happen, the guard it says is missing already exists
elsewhere, or the "wrong outcome" it describes isn't actually wrong. Also
dismissed: correct-but-so-narrow-nobody-would-act-on-it (the letter of
"accepted" without its spirit — a real gap that's genuinely not worth a
line of code to close). A dismissal is not a verdict on the *label* — see
mislabelled below for that.

## Mislabelled

The underlying observation is real and would be accepted under a
*different* label than the one the finding carries — e.g. a `dead-code`
finding that's actually a `duplication` finding, or an `auth` finding that's
really `ownership`. Verdict the substance as accepted-if-correctly-labelled,
and record which label it should have carried; this is a data point about
label precision, not a pass on the defect itself.

## Process

- Every finding gets exactly one verdict — no partial credit, no "sort of."
- Every verdict gets a one-line reason. A verdict I can't justify in one
  sentence is a verdict on vibes, not evidence — per the plan, that's the
  whole point of writing this down first.
- Use `/explain-bug <n>` to read the full evidence trace before verdicting
  — never judge from the one-line summary alone; that line is the part
  most likely to sound right while resting on evidence that doesn't hold.
- A dismissal that reveals a *general* safe pattern (not just "wrong this
  one time") becomes a dismissal rule in `eval/review-corrections.md`'s
  Known non-defects section, with both halves: what makes the pattern
  safe, and what would make it unsafe. A rule with only the first half
  just suppresses the real version of the same defect later.
