# PR review domain pack (test fixture — round trip) — week 3, Friday

Three records, one per a different slice, each field carrying a marker
distinct to that record — proves a record's fields reach the right
`probes-<slice>.txt` unmangled, and nowhere else.

## Stack scope prefixes

| Prefix | Stack |
|---|---|
| `.claude/skills/` | backend |

## Wiring files

```
.claude/skills/pr-review/scripts/build-artifacts.sh
README.md
```

## Label probes

### auth.roundtrip-marker-a

label:        auth
statement:    Record A statement carries MARKER_A_STATEMENT and nothing else's.
exemplar:     `README.md:1`
witnesses:    `LICENSE:1`
              `.gitignore:1`
guard:        Record A guard carries MARKER_A_GUARD.
unsafe_when:  Record A unsafe_when carries MARKER_A_UNSAFE.

### db.roundtrip-marker-b

label:        db
statement:    Record B statement carries MARKER_B_STATEMENT and nothing else's.
exemplar:     `LICENSE:1`
witnesses:    `LICENSE:1`
              `.gitignore:1`
guard:        Record B guard carries MARKER_B_GUARD.
unsafe_when:  Record B unsafe_when carries MARKER_B_UNSAFE.

### a11y.roundtrip-marker-c

label:        a11y
statement:    Record C statement carries MARKER_C_STATEMENT and nothing else's.
exemplar:     `.gitignore:1`
witnesses:    `LICENSE:1`
              `.gitignore:1`
guard:        Record C guard carries MARKER_C_GUARD.
unsafe_when:  Record C unsafe_when carries MARKER_C_UNSAFE.

## Promoted non-defects

## Brief probes

```bash
echo "ok"
```

## Dependencies

None recorded.
