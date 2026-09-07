# PR review domain pack (test fixture — unknown/typo'd field name) — week 3

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

### dead-code.typo-field

label:        dead-code
statement:    A README section stays consistent with what it documents.
exemplar:     `README.md:1`
witnesses:    `LICENSE:1`
              `.gitignore:1`
gaurd:        the citation resolves and stays within the file
unsafe_when:  the file is deleted or shrinks past the cited line

## Promoted non-defects

## Brief probes

```bash
echo "ok"
```

## Dependencies

None recorded.
