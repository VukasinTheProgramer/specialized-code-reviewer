# Domain pack format contract

`model/pr-review-domain.md` (and any pack a foreign repo drops
in via `PR_REVIEW_PACK`) has always been read against these six rules —
`build-artifacts.sh`'s `awk`/`grep` extraction assumed every one of them
without ever writing them down. `validate-pack.sh` enforces all six; its
error messages cite the section below by number. Author against this file,
not against what the parser happens to tolerate today.

## §1 — Section headings, exact match

The pack has exactly five sections, each introduced by one of these
headings, byte-for-byte:

```
## Stack scope prefixes
## Wiring files
## Label probes
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

## §3 — Label probes: one label cell, one probe cell

Each row of the `## Label probes` table has exactly two cells:

```
| `label` | Probes |
|---|---|
| `auth` | `Backend/app/dependencies.py:40` requires a bearer token on every non-public router |
```

A literal `|` inside the probe cell — quoting a shell pipeline, a regex
alternation — splits the row into more than two cells and is read as a
malformed row, not as a probe containing a pipe character. There is no
escape for this yet; the format itself doesn't have one (see
`future-improvements/week-3-label-probes-schema.md`). Rephrase the probe to
avoid a bare `|`, or drop it into `## Wiring files`/prose elsewhere if it
can't be phrased without one.

## §4 — Label probes: closed label list

The first cell of every `## Label probes` row must be exactly one of these
15 labels — no others, no invented ones:

```
auth, ownership, security, data-exposure, db, concurrency,
logic, validation, control-flow, state, contract,
layering, duplication, dead-code, a11y
```

A label outside this list isn't an error either — it's dropped from every
`probes-*.txt` with a warning on stderr, and the row's citation never
reaches any verifier. If a real pattern doesn't fit one of the 15, it isn't
a probe row's business; see `future-improvements/week-3-label-taxonomy.md`
for extending the list itself.

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
