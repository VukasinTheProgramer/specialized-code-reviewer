# Report format — Step 5.5 and 5.6

The exact render. Every value comes from the object the Workflow returned (persisted as
`findings.json`); nothing here is composed at render time. Section numbers match `SKILL.md`.

### 5.5 Render

```
1. [ownership] Backend/app/crud/card_repository.py:61
   Any authenticated user reaches another user's card row by sending its public_id.

2. [logic] Frontend/src/pages/user/components/TransactionsTable.jsx:88
   Amount arrives from the API as a string and toFixed reintroduces float error.
```

Summary line is the **first sentence of `failure_mode`, verbatim** — never rewritten. Evidence trace is deferred (not dropped) to `/explain-bug <n>`; a finding without an `evidence` array is stored without one, never reconstructed.

**The numbered findings are the whole body of the report.** There is no dismissal section: a verifier either proved a defect or dropped it silently, so nothing arrives here describing something that was ruled out. Never add such a section, and never describe a finding as ruled out.

Close every report with what ran:

```
4 findings.  /explain-bug <n> for the trace and the reasoning.
Slices run: Access, Data, Answer, Structure — 4 spawns, scope backend.
Hypotheses: 12 raised, 11 routed, 3 proven, 1 also found by sweep, 0 left unread.
Scout context: graph off this run (no graphify-out/graph.json yet) — related resolved via grep.
```

`routed` (hypotheses that actually reached a verifier, after the router dropped any outside every slice or outside this repo's stack) is the denominator for precision — read it as `proven ÷ routed`, never `proven ÷ raised`, since `raised` still counts hypotheses no verifier ever saw.

When `dropped_unreachable` is non-zero, add one more closing line:

```
3 candidates dropped as unreachable (closing file not named).
```

When `dropped_invalid_line` is non-zero (§5.3b), add one more closing line:

```
1 finding dropped — line number does not exist in the file at HEAD.
```

When `hypotheses.dropped` is non-zero, add one more closing line:

```
2 hypotheses dropped before reaching a verifier — label outside the closed 15, or outside this repo's stack.
```

`raised` minus `routed` already implies this number, but only to a reader who
knows to subtract. Name it: a non-zero count on a run whose scope should own
those labels is the signature of a scout emitting a label that does not exist
(a typo, or a reference block in its prompt misread as a 16th label), and that
is a lost hypothesis, not a filtered one.

When `degraded` is non-empty, name it right after `verified_clean`/`failed`, never silently folded into either:

```
Degraded: Data — 3 findings returned, none renderable (missing fields). db and concurrency were not reliably reviewed.
```

When `slice_mismatch` is non-empty, name the labels a verifier's own echo didn't cover:

```
Warning: Answer echoed its slice without state — treat state as unreviewed this run.
```

### 5.6 A clean report names what was checked

```
No findings.

Verified clean: Access, Data, Answer, Structure — 4 spawns, scope frontend.
Hypotheses: 7 raised, 7 routed, 0 proven, 0 also found by sweep, 0 left unread.
Scout context: graph off this run (no graphify-out/graph.json yet) — related resolved via grep.
```

A failed spawn is always named separately, never silent:

```
Verified clean: Access, Answer, Structure — 3 spawns.
Failed:         Data — returned nothing parseable. db and
                concurrency were not reviewed on this branch.
```

