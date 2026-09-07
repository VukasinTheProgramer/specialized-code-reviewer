# PR review domain pack (test fixture — bad pipe in cell) — D2

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

| `label` | Probes |
|---|---|
| `dead-code` | grep -r "a|b" file | wc -l |

## Brief probes

```bash
echo "ok"
```

## Dependencies

None recorded.
