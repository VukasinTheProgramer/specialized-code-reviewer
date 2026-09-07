#!/usr/bin/env python3
"""Parse the '## Label probes' section of a domain pack — week 3's record
format (model/FORMAT.md) — and render each record into $OUT/probes-<slice>.txt.

Multi-line field values (a `statement` wrapped across lines, a `witnesses`
list one citation per line) are why this isn't `awk`: Decision 1 in
todays-work/week3/monday.md set ~30 lines of parsing as the point to switch
to python3 over hand-rolling it, and multi-line continuation crosses that.

usage: parse_conventions.py <pack-file> render <out-dir> [be] [fe]
  Writes/appends one formatted block per record into <out-dir>/probes-<slice>.txt,
  routed by the record's own `label:` field through the same label->slice map
  build-artifacts.sh has always used. Unknown labels warn on stderr and are
  skipped — never block a review, same doctrine as every other pack degrade.
  `be`/`fe` are the same 0/1 stack-scope flags build-artifacts.sh computes
  (model/FORMAT.md §3's `stack` field): a record with `stack: be` is dropped
  when `be` isn't "1", same for `fe`; a record with no `stack` field always
  renders. Both default to "1" (no gating) when omitted, for callers that
  don't have a stack scope to pass.

usage: parse_conventions.py <pack-file> validate
  Prints every problem found, one `invalid: ...` line each (model/validate-pack.sh
  prints these verbatim and never repairs, same rule as week 1's validator) plus
  one `citation\t<id>\t<field>\t<path>\t<line>\t<end_line>` line per exemplar/witness/
  deviation citation, for the caller to bounds-check on disk (existence + line-count
  checking belongs in one place, not reimplemented per language — model/validate-pack.sh
  does it, this script only extracts what to check). `end_line` repeats `line` for a
  bare `path:line` citation (no range). Always exits 0; the caller decides invalid from
  the presence of `invalid:` lines, same as every other check in model/validate-pack.sh.

usage: parse_conventions.py <pack-file> extract-section "<## Heading>"
  Prints the raw lines of one top-level section (same boundary rule as
  render/validate's own `## Label probes` extraction) — shared so a second
  section (`## Promoted non-defects`, `## Dependencies`, ...) doesn't need
  its own hand-rolled awk scan in build-artifacts.sh.
"""
import re
import sys

LABEL_TO_SLICE = {
    "auth": "access", "ownership": "access", "security": "access", "data-exposure": "access",
    "db": "data", "concurrency": "data",
    "logic": "answer", "validation": "answer", "control-flow": "answer", "state": "answer", "contract": "answer",
    "layering": "structure", "duplication": "structure", "dead-code": "structure", "a11y": "structure",
}
CLOSED_LABELS = set(LABEL_TO_SLICE)
LIST_FIELDS = {"witnesses", "deviations"}
CITATION_FIELDS = ["exemplar", "witnesses", "deviations"]  # exemplar: scalar; other two: list
REQUIRED_FIELDS = ["label", "statement", "exemplar", "witnesses", "guard", "unsafe_when"]
KNOWN_FIELDS = set(REQUIRED_FIELDS) | {"deviations", "stack", "matcher"}
ID_RE = re.compile(r"^[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$")
CITATION_RE = re.compile(r"^`?([A-Za-z0-9_./-]+)(?::(\d+)(?:-(\d+))?)?`?$")
# Column-0 only — an indented continuation line never starts with a bare word
# character before the colon at position 0, so this can't collide with one.
# Broad char class (not just the known field names) on purpose: a typo'd key
# (wrong case, a hyphen for an underscore) must still parse as *a* field —
# caught as unknown by validate() — never silently vanish into the previous
# field's value or get dropped as stray text (the plan's own "a typo'd key
# must fail loudly, not vanish").
FIELD_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*):\s?(.*)$")
HEADING_RE = re.compile(r"^### (.+)$")


def extract_section(text, heading):
    lines = text.splitlines()
    out, in_section = [], False
    for line in lines:
        if line.rstrip() == heading:
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section:
            out.append(line)
    return out


def parse_records(section_lines):
    records = []
    cur = None
    field = None
    for line in section_lines:
        m = HEADING_RE.match(line)
        if m:
            if cur is not None:
                records.append(cur)
            cur = {"id": m.group(1).strip()}
            field = None
            continue
        if cur is None:
            continue  # stray text before the first ### heading — not a record
        m = FIELD_RE.match(line)
        if m:
            field = m.group(1)
            value = m.group(2).strip()
            if field in LIST_FIELDS:
                cur[field] = [value] if value else []
            else:
                cur[field] = value
            continue
        stripped = line.strip()
        if not stripped or field is None:
            continue
        # continuation of the previous field: indented, non-heading line
        if field in LIST_FIELDS:
            cur.setdefault(field, []).append(stripped)
        else:
            cur[field] = (cur.get(field, "") + " " + stripped).strip()
    if cur is not None:
        records.append(cur)
    return records


def strip_ticks(s):
    return s.strip("`")


def render_record(r):
    label = r.get("label", "")
    lines = [f"[{r['id']}] {label}"]
    if r.get("statement"):
        lines.append(f"  {r['statement']}")
    if r.get("exemplar"):
        lines.append(f"  correct:      {strip_ticks(r['exemplar'])}")
    witnesses = r.get("witnesses") or []
    if witnesses:
        lines.append(f"  also:         {', '.join(strip_ticks(w) for w in witnesses)}")
    if r.get("guard"):
        lines.append(f"  guard:        {r['guard']}")
    if r.get("unsafe_when"):
        lines.append(f"  unsafe when:  {r['unsafe_when']}")
    return "\n".join(lines) + "\n"


def validate_records(records, section_lines):
    """Yields ('invalid', message) for a structural problem, or
    ('citation', (id, field, path, line)) for a citation to bounds-check —
    never raises, never repairs, same rule as every other check in
    model/validate-pack.sh."""
    # Decision 2 (todays-work/week3/monday.md): hard-cut to records, no
    # backward compatibility with the old `| label | probe |` table. Without
    # this, a pack still in the old shape parses to zero records and passes
    # as "nothing here" — silently going blank (build-artifacts.sh's
    # renderer sees the same zero records) instead of erroring loudly,
    # exactly the failure mode a hard-cut is supposed to prevent.
    #
    # Specifically an old TABLE ROW (>= 2 `|` on one line), not "any content"
    # — a caption paragraph above the first `### id` (same pattern every
    # other section's own doc caption uses, e.g. "## Stack scope prefixes")
    # is legitimate and already safely ignored by parse_records(), and must
    # not itself read as "still in the old format" (a real false positive
    # this produced once: model/pr-review-domain.md's own caption tripped it).
    looks_like_old_table = any(
        line.strip().startswith("|") and line.strip().endswith("|") and line.count("|") >= 2
        for line in section_lines
    )
    if not records and looks_like_old_table:
        yield "invalid", "Label probes has an old-style `| label | probe |` table row, not `### id` records (model/FORMAT.md §3)"
        return
    seen_ids = {}
    for r in records:
        rid = r.get("id", "(no id)")
        loc = f"record `{rid}`"

        if not ID_RE.match(rid):
            yield "invalid", f"{loc}: id doesn't match the slug grammar `label.short-name`, lowercase, `.`/`-` only (model/FORMAT.md §3): {rid}"
        if rid in seen_ids:
            yield "invalid", f"{loc}: duplicate id, already used by an earlier record in this file (model/FORMAT.md §3)"
        seen_ids[rid] = True

        unknown = [k for k in r if k != "id" and k not in KNOWN_FIELDS]
        for k in unknown:
            yield "invalid", f"{loc}: unknown field `{k}` — not one of the nine defined fields, a typo? (model/FORMAT.md §3)"

        for field in REQUIRED_FIELDS:
            value = r.get(field)
            if not value:  # covers missing, empty string, and empty list alike
                yield "invalid", f"{loc}: missing or empty required field `{field}` (model/FORMAT.md §3)"

        label = r.get("label")
        if label and label not in CLOSED_LABELS:
            yield "invalid", f"{loc}: label `{label}` is not one of the 15 closed labels (model/FORMAT.md §4)"

        witnesses = r.get("witnesses") or []
        if r.get("witnesses") is not None and len(witnesses) < 2:
            yield "invalid", f"{loc}: `witnesses` has {len(witnesses)} entr{'y' if len(witnesses) == 1 else 'ies'}, needs at least 2 — a record with one witness is one piece of code with an opinion attached, not a convention (model/FORMAT.md §3)"

        for field in CITATION_FIELDS:
            raw = r.get(field)
            values = raw if isinstance(raw, list) else ([raw] if raw else [])
            for v in values:
                m = CITATION_RE.match(v.strip())
                if not m:
                    yield "invalid", f"{loc}: `{field}` citation doesn't look like a `path` or `path:line` reference: {v}"
                    continue
                path, line, end_line = m.group(1), m.group(2), m.group(3)
                yield "citation", (rid, field, path, line or "", end_line or line or "")


def main():
    if len(sys.argv) < 3 or sys.argv[2] not in ("render", "validate", "extract-section"):
        sys.stderr.write(__doc__)
        sys.exit(2)
    pack_path, mode = sys.argv[1], sys.argv[2]
    with open(pack_path, encoding="utf-8") as f:
        text = f.read()

    if mode == "extract-section":
        if len(sys.argv) != 4:
            sys.stderr.write(__doc__)
            sys.exit(2)
        for line in extract_section(text, sys.argv[3]):
            print(line)
        return

    section = extract_section(text, "## Label probes")
    records = parse_records(section)

    if mode == "render":
        if len(sys.argv) not in (4, 5, 6):
            sys.stderr.write(__doc__)
            sys.exit(2)
        out_dir = sys.argv[3]
        be = sys.argv[4] if len(sys.argv) >= 5 else "1"
        fe = sys.argv[5] if len(sys.argv) >= 6 else "1"
        handles = {}
        for r in records:
            rid = r.get("id", "(no id)")
            stack = r.get("stack")
            if (stack == "be" and be != "1") or (stack == "fe" and fe != "1"):
                continue
            label = r.get("label", "")
            slice_name = LABEL_TO_SLICE.get(label)
            if slice_name is None:
                sys.stderr.write(
                    f"warning: domain pack record `{rid}` has label `{label}`, "
                    f"not one of the 15 known labels — dropped, not routed to any probes-*.txt\n"
                )
                continue
            if slice_name not in handles:
                handles[slice_name] = open(f"{out_dir}/probes-{slice_name}.txt", "a", encoding="utf-8")
            handles[slice_name].write(render_record(r))
        for h in handles.values():
            h.close()
        return

    # mode == "validate"
    for kind, payload in validate_records(records, section):
        if kind == "invalid":
            print(f"invalid: {payload}")
        else:
            rid, field, path, line, end_line = payload
            print(f"citation\t{rid}\t{field}\t{path}\t{line}\t{end_line}")


if __name__ == "__main__":
    main()
