# PR review domain pack (test fixture — bad unknown label) — D5

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
| `performance` | Check `README.md` for stale references |

## Brief probes

```bash
echo "ok"
```

## Dependencies

None recorded.
