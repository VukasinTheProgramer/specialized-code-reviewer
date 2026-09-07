# PR review domain pack (test fixture — brief probes runtime error, not caught by bash -n)

## Stack scope prefixes

| Prefix | Stack |
|---|---|
| `.claude/skills/` | backend |

## Wiring files

```
README.md
```

## Label probes

| `label` | Probes |
|---|---|
| `dead-code` | Check `README.md` for stale references |

## Brief probes

```bash
echo "ROUTERS=$(nonexistent_command_xyz)"
```

## Dependencies

None recorded.
