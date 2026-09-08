# Domain pack format contract

`model/pr-review-domain.md` (and any pack a foreign repo drops
in via `PR_REVIEW_PACK`) has always been read against these six rules —
`build-artifacts.sh`'s `awk`/`grep` extraction assumed every one of them
without ever writing them down. `validate-pack.sh` enforces all six; its
error messages cite the section below by number. Author against this file,
not against what the parser happens to tolerate today.

## §1 — Section headings, exact match

The pack has exactly six sections, each introduced by one of these
headings, byte-for-byte:

```
## Stack scope prefixes
## Wiring files
## Label probes
## Promoted non-defects
## Brief probes
## Dependencies
```

A retyped heading (wrong case, an extra space, a rename) doesn't error —
every extraction below is an `awk` scoped to that exact string, so a miss
just degrades the whole section to silently empty. `validate-pack.sh` is
what turns that silence into a named error.

## §2 — Wiring files: fenced, closed before the next heading

The `## Wiring files` section holds one fenced block of plain repo-relative
paths, one per line:

````
## Wiring files

```
Backend/app/dependencies.py
Frontend/src/api/client.ts
```
````

The fence must close (an even, non-zero count of `` ``` `` lines) before the
next `## ` heading. An unclosed fence doesn't stay contained — the real
parser's extraction used to keep reading straight past the heading and into
whatever section followed, stopping only at that section's own fence
(fixed, but the shape is still worth knowing when authoring).

## §3 — Label probes: one record per convention, not one row per label

**v2, week 3.** The old shape was one table row per label — a label got
exactly one probe cell for the whole codebase, no matter how many different
ways it actually shows up. The new shape inverts that: any number of
records, each independently tagged with a `label`. Many records can share a
label; that's the point — `ownership` can carry a record for repository
scoping, a separate one for the admin exception, another for the
background-job path, instead of being crammed into one sentence.

A record is a `### <id>` heading, followed by `key: value` lines. A value
may continue onto the next line(s) by indenting them — a wrapped sentence
for `statement`/`guard`/`unsafe_when`, or one citation per line for
`witnesses`/`deviations`:

```
### ownership.repository-user-scope

label:       ownership
stack:       be
statement:   A repository lookup is scoped to the caller by joining to the
             owning row's user_id, never resolved by public id alone.
exemplar:    `Backend/app/crud/payment_repository.py:88`
witnesses:   `Backend/app/crud/account_repository.py:41`
             `Backend/app/crud/statement_repository.py:63`
guard:       the join to PaymentAccount.user_id in the WHERE clause
unsafe_when: the lookup takes an id straight from the request body and
             re-resolves nothing under the caller's identity
deviations:  `Backend/app/crud/legacy_card_repo.py:31`
```

Fields, and who needs each one:

| Field | Required | What it is |
|---|---|---|
| `id` | yes | The `### ` heading text. A stable slug (`label.short-name`, lowercase, `.`/`-` only) — never renumbered once authored, so a citation or regression case naming it stays valid. |
| `label` | yes | Exactly one of the closed 15 (§4). Routes the record to a slice — replaces row position as the routing key. |
| `statement` | yes | One sentence: what correct looks like. Never what the defect looks like — a probe phrased as a defect shape turns the reviewer into a pattern-matcher for that one shape. |
| `exemplar` | yes | One `path:line` that does it right — what a verifier quotes to close an evidence trace. For a structurally-scoped label (`layering`, `a11y`, `dead-code`) whose convention is a property of a whole file rather than one line, `exemplar` names a representative anchor line and `guard` carries the actual scope — a single line can't prove "this file contains no bash" on its own. |
| `witnesses` | ≥ 2 | Other sites that independently conform. Below two, it's one piece of code with an opinion attached, not a convention — the validator (Wednesday) rejects it. |
| `guard` | yes | The specific mechanism that makes the pattern safe — the join, the quantize, the lock, the alias, the enforcement script. This is what lets a finding say *which protection was dropped*. |
| `unsafe_when` | yes | What would make the same shape a real defect. Mirrors the ledger's two-halves dismissal rule (`eval/review-corrections.md`); without it a record silences the genuine version of its own pattern. |
| `deviations` | no | Known non-conforming sites, already triaged. Empty is normal. |
| `stack` | no | `be` / `fe` / unset. Feeds the existing stack gate — a frontend record never fires on a backend-only diff. |
| `matcher` | no | Week 6's deterministic pre-pass candidate signal: a plain literal substring — never a regex, nothing to escape — tested against a changed file's own added lines. A hit proposes this record as a classification candidate for that file (`file<TAB>id` in `classification-candidates.txt`); the scout still confirms `MATCHES`/`DEVIATES` or rejects it, so a hit is a candidate, never a verdict. No `matcher`, or no hit — the record still exists for the scout's own `label` probes, it just never proposes itself as a candidate this way. Optional; leave unset when no cheap literal signals the pattern (most structural conventions won't have one). |

An unknown field name is a typo, not a new field, and `id` must match the
slug grammar (`label.short-name`, lowercase, `.`/`-` only) and be unique
across the file — `validate-pack.sh` rejects any of these rather than
silently ignoring them. Every `exemplar`/`witnesses`/`deviations` citation
must resolve: the file exists, and a `:line` (or `:line-line2`) is within
the file's actual line count — the same bounds check `build-artifacts.sh`
already runs for staleness, applied here at authoring time instead of
diff-review time.

## §4 — Label probes: closed label list

Every record's `label` field must be exactly one of these 15 — no others,
no invented ones:

```
auth, ownership, security, data-exposure, db, concurrency,
logic, validation, control-flow, state, contract,
layering, duplication, dead-code, a11y
```

A label outside this list isn't an error either — the record is dropped
from every `probes-*.txt` with a warning on stderr, and it never reaches
any verifier. If a real pattern doesn't fit one of the 15, it isn't a
record's business; see `future-improvements/unscoped-label-taxonomy.md` for
extending the list itself.

## §4b — Promoted non-defects: this repo's own, and only this repo's own

Week 3, Thursday. Free-form prose, the same two-halves shape
`eval/review-corrections.md`'s `## Known non-defects` section already
requires — what makes the pattern safe, and what would make it unsafe —
extracted verbatim (no field parsing, no validation of that shape; same as
the ledger's own section). Not validated beyond the heading itself being
present.

```
## Promoted non-defects

- **A router file with no auth dependency is not missing auth.** Auth is
  applied at the aggregate router (`Backend/app/api.py:25`). The
  registration line is where the mistake would be. Unsafe when a route
  hand-rolls its own session/cookie read that skips it.
```

This section exists so a rule that only makes sense on one particular
codebase (a specific aggregate-router file, a specific screen's staleness
pattern) has somewhere repo-specific to live, instead of getting hardcoded
into `core/agents/scout.md` — every agent definition in `core/` is meant to
carry zero repo-specific knowledge (`core/README.md`'s own test: would this
survive a rewrite in a different language, on a different repo). **Never
carry a rule here that you haven't watched come back at least twice** —
that's what "promoted" means; a first-sighting dismissal belongs in the
ledger's `## Known non-defects`, not here. Empty is normal and expected on a
repo with no history yet, exactly like every other section.

## §5 — Brief probes: fenced as bash, syntactically valid

The `## Brief probes` section holds one ```` ```bash ```` fenced block,
`eval`'d verbatim by `build-artifacts.sh` with `added()`/`removed()`/`$OUT`
in scope:

````
## Brief probes

```bash
ROUTERS=$(added | grep -cE '@(app|router)\.(get|post|put|delete|patch)\(')
```
````

Missing the `bash` tag on the fence means the block is never captured at
all — silently, no error. A syntax error inside it aborts the `eval`
mid-block; `bash -n` on the extracted block is the offline version of that
same failure, without needing a diff to trigger it.

## §6 — Citations: backtick-wrapped

Any `path/file.ext` or `path/file.ext:line` reference containing a `/`
outside a fenced code block — in `## Label probes` prose, `##
Dependencies`, anywhere — must be backtick-wrapped:

```
`Backend/app/dependencies.py:40`
```

An unwrapped citation is invisible to `/pr-review`'s own staleness check
(`extract_citations` in `build-artifacts.sh` only greps inside backticks) —
the file could be deleted or the line could drift years out of date and
nothing would ever flag it.
