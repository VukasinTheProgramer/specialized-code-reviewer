# PR review domain pack

Repo-specific knowledge for `/pr-review`. The skill and every agent it spawns
check for this file before falling back to their built-in, stack-agnostic
default. Delete or rename this file to run the reviewer generic on this repo
(useful for testing the fallback path); this copy ships empty — run the
`generate-domain-pack` skill to fill in the six sections below for whatever
repo it's dropped into, or edit them by hand.

Every section below is intentionally empty, with no explanatory prose under
any heading — this file's own overview is the only place that documents what
each section is for, since anything written directly under a `## Heading`
gets read verbatim by an agent, prose included. An empty section behaves
exactly like "no domain pack" for that one check — every fallback downstream
already handles it (verified in the upstream repo this copy was cut from:
`PACK_STALE` does not fire on an empty-but-present section, only on a
missing/renamed `## Heading` or a citation that no longer resolves).

**Stack scope prefixes** computes `SCOPE`/`BE`/`FE` and gates which labels can
fire. **Wiring files** are pinned as readable-without-asking in every
verifier's prompt. **Label probes** hold this repo's own convention records —
any number tagged with a label, not one row per label (`model/FORMAT.md`
§3). **Promoted non-defects** holds this repo's own dismissal rules that
have come back twice (`model/FORMAT.md` §4b) — never a rule copied in from
another codebase. **Brief probes** are the regexes behind `brief.txt`.
**Dependencies** is a fast first-pass check before flagging an import as
newly-added — a curated shortlist, never a substitute for reading the actual
manifest.

## Stack scope prefixes

Path prefixes used by `SKILL.md` §2 to compute `SCOPE` and to gate which
labels can fire (`ownership`/`db` need `backend`; `state`/`a11y` need
`frontend`). Leave this table empty for a single-stack repo — `SCOPE`
resolves `both` — or fill in one row per stack:

| Prefix | Stack |
|---|---|

## Wiring files

Paths pinned as readable-without-asking in every verifier's prompt, alongside its own hypothesis `related` list (`SKILL.md` §3.3):

```
```

## Label probes

Concrete, cited convention records — the "Probes" half of the table in
`pr-review-scout.md` and the "How to verify in this codebase" section of each
`pr-verify-*` agent. Read the label table in `pr-review-scout.md` for the label
names, the slice routing, and the `Use for` column, which stay generic and
live there permanently — only the citation-heavy records below move with the
domain pack. Format: `model/FORMAT.md` §3. No precedent found for a label →
leave it uncovered entirely, never fabricate a record.

## Promoted non-defects

## Brief probes

Regex used by `SKILL.md` §4.1 to assemble `brief.txt`. Content-matching, so
they only ever run against `code.diff` (added lines from this repo's own
stack-scope prefixes, never the whole patch). Leave this block empty to fall
back to the generic presence-only fields (`migrations`, `lockfiles/deps
touched`):

```bash
```

## Dependencies
