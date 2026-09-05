---
name: explain-bug
description: Explain one numbered finding from the last /pr-review run — the full failure mode, the evidence trace with the real code at each step, and the pattern in this codebase it should have followed. Reads the findings file the review persisted; never re-runs the review and never edits anything. Use when a report line needs to be understood or checked.
---

Expand one finding from the last review. Explains only; never edits.

## Usage

```
/explain-bug 4          # one finding
/explain-bug 2 5        # several
/explain-bug            # list the index
```

## Step 1 — Load the findings file

```bash
F=".git/pr-review/findings.json"
[ -f "$F" ] || { echo "No findings file. Run /pr-review first."; exit 0; }
```

Written by `/pr-review` step 5.4. It holds the merged, sorted findings with the `n` each carries in the report, plus the base, the head SHA and which slices ran.

**Never reconstruct it.** If it is absent the answer is to run the review, not to re-derive a finding from the diff — a finding that no verifier proved is not a finding, and inventing one here would launder a guess through a command whose whole promise is that the claim was already checked.

## Step 2 — Check the numbers still mean what they meant

```bash
git rev-parse HEAD          # against the "head" field in findings.json
```

Different SHA → say so before explaining anything:

```
Note: findings were recorded against 8aa2a9f, HEAD is now c31d0e2.
Line numbers below may have moved. Re-run /pr-review to renumber.
```

Then continue. The finding is still worth reading; its line numbers are the part that rots. A dirty working tree is the same warning for the same reason.

`n` out of range → say how many findings the file holds and stop. Never round to the nearest one.

## Step 3 — With no argument, print the index

The report again, from the file, so a number can be picked without scrolling back:

```
1. [ownership] Backend/app/crud/card_repository.py:61
2. [logic]     Frontend/src/pages/user/components/TransactionsTable.jsx:88
```

## Step 4 — Explain the finding

Four parts, in this order. Everything in the first two comes from the file; only the last two are yours.

### 4.1 What was found

The header and the **whole** `failure_mode`, not the one-line summary the report showed:

```
Bug 1 · [ownership] · Backend/app/crud/card_repository.py:61

A user authenticated as A sends B's card public_id to GET /api/v1/cards/{id};
the query resolves it without an ownership predicate and returns B's card.
```

Verbatim. This is the verifier's claim, and rewording it here quietly replaces a proven statement with a fresh unproven one.

### 4.2 The trace, with the code at each step

For each entry in `evidence`, in order: print the step as the verifier wrote it, then `Read` that file at that line and show the actual code.

```
Step 1 — card_repository.py:59
    stmt = select(Card).where(Card.public_id == public_id)
  The lookup resolves the public_id alone.

Step 2 — card_service_impl.py:44
    card = await self.repo.get_by_public_id(public_id)
  The service passes the id straight from the request and re-checks nothing.

Step 3 — card_router.py:31
    return await service.get_card(public_id)
  The route returns whatever came back.
```

**Read the files. Do not paraphrase code from memory or from the patch.** The point of this command is that the reader sees the real lines without opening five files themselves, and a quoted line that does not match the file is worse than no quote.

If a step's line number no longer holds the code the step describes, say that plainly and show what is there now. That is a stale finding, and the reader needs to know before acting on it.

**No `evidence` array on the finding** → say so: *"This finding was reported without a trace, which its spawn should not have done."* Do not build one. An unevidenced finding is a bug in the agent definition, and covering for it here is what stops anyone from fixing it there.

### 4.3 Why it is wrong

Two or three sentences. What the code does, what it should do, and the concrete consequence — the wrong number, the wrong row, the crash, the leaked field. Ground it in the trace above rather than in the label's general description.

### 4.4 The pattern it should have followed

Name the place in this codebase that already does it correctly, with a path and a line, and show that code.

**Domain pack first.** If `.claude/references/pr-review-domain.md` exists, read its `## Label probes` row for this finding's label — that table carries this repo's own cited files, lines and functions (the repository that filters through `PaymentAccount.user_id`, the `_set_auth_cookies` helper, `.quantize(Decimal("0.01"), ROUND_HALF_UP)`, the `invalidateQueries` in `useCards.js`). Read it and quote it.

**No domain pack, or the row is empty.** Fall back to `.claude/agents/pr-review-scout.md`'s label table — it carries only generic, uncited guidance per label, not a citation to quote. Read it for what the label is looking for, then find the sibling in this codebase yourself and cite it directly.

**Before quoting it, check it operates on the same storage layer as the buggy code — a shared label is not a shared substrate.** A label groups defects by *symptom* (concurrency, ownership, db, whatever), not by what the fixing code has to call. A locking primitive that works against one datastore does not transfer to a different one just because both bugs got the same label — a row lock is not a remedy for a race in an in-memory cache, a queue, or any store that does not support that primitive. Read both call sites: what does the buggy code actually call to persist, read, or synchronize state — which client, which API, which store — and what does the cited pattern call for the same purpose. If those are different mechanisms, the pattern does not compile onto this bug, no matter how well the label matches.

If no such sibling exists — including because the only labeled example is for the wrong substrate — say so instead of citing it anyway. A cited pattern that cannot apply is worse than no citation: it reads authoritative and sends the reader toward a fix that won't work.

## What this skill does not do

- **No edits, no patches, no fix diffs.** Explaining is separate work from fixing, the same way reviewing is. A reader who wants the fix asks for it as its own task, with the finding as the input.
- **No new findings.** Something wrong spotted while reading the files here is not a finding — it has been through no verifier. Mention it as an aside if it matters, clearly marked as unverified, and never number it.
- **No re-review, no spawns.** Every fact needed is already in `findings.json` and in the files it points at.
- **No verdict.** Not "this is critical", not "safe to merge". The review had no severity ladder and neither does this.
