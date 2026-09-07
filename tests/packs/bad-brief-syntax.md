# PR review domain pack (test fixture — bad brief syntax) — D3

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

### dead-code.stale-reference

label:        dead-code
statement:    A README section stays consistent with what it documents.
exemplar:     `README.md:1`
witnesses:    `LICENSE:1`
              `.gitignore:1`
guard:        the citation resolves and stays within the file
unsafe_when:  the file is deleted or shrinks past the cited line

## Promoted non-defects

## Brief probes

```bash
if [ 1 -eq 1 ]
  echo "missing then"
```

## Dependencies

None recorded.
