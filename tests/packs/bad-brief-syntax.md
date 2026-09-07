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

| `label` | Probes |
|---|---|
| `dead-code` | Check `README.md` for stale references |

## Brief probes

```bash
if [ 1 -eq 1 ]
  echo "missing then"
```

## Dependencies

None recorded.
