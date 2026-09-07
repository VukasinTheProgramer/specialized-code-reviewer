# PR review domain pack (test fixture — citation past EOF) — week 3

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

### dead-code.past-eof

label:        dead-code
statement:    A README section stays consistent with what it documents.
exemplar:     `README.md:999999`
witnesses:    `LICENSE:1`
              `.gitignore:1`
guard:        the citation resolves and stays within the file
unsafe_when:  the file is deleted or shrinks past the cited line

## Promoted non-defects

## Brief probes

```bash
echo "ok"
```

## Dependencies

None recorded.
