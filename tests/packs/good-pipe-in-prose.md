# PR review domain pack (test fixture — pipe characters in Label probes prose, not an old table row)

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

A caption mentioning a shell pipeline like `cmd1 | cmd2 | cmd3` must not read as an old-style `| label | probe |` table row — this section is otherwise a valid, empty set of records.

## Promoted non-defects

## Brief probes

```bash
echo "ok"
```

## Dependencies

None recorded.
