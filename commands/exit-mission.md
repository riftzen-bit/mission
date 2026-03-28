---
description: "Exit Mission Mode — deactivate mission, save state, output summary"
---

# Exit Mission

1. Read `.mission/state.json`
2. Set `"active": false` and record `"endedAt"` timestamp
3. Output a summary of the mission (from memory, before deletion):
   - Task description
   - Number of rounds completed
   - Files created and modified
   - Test results
   - Duration
4. Hooks auto-deactivate (phase-guard checks `active` field)
5. Delete `.mission/` directory entirely: `rm -rf .mission/`

## Relentless Mode Warning

If the mission is in relentless mode (`persistence: "relentless"`), display a warning before exiting:

```
⚠ Mission is in RELENTLESS mode with <N> unresolved issues.
  Are you sure you want to stop?
  The mission will NOT auto-resume — all mission state will be removed on exit.
```

Force exit regardless by running `/exit-mission` again or confirming.

## Always Works

`/exit-mission` ALWAYS deactivates the mission regardless of mode. It is the user's emergency brake. No persistence setting, no phase lock, and no unresolved issue count can prevent `/exit-mission` from working. The user is always in control.

## Cleanup Status

When `/exit-mission` runs, display cleanup readiness before deactivating:

```
Cleanup Status:
  summary.md:    ✓ exists / ✗ missing
  worker-logs:   ✓ clean (0 files) / ✗ dirty (N files remaining)
  latest report: ✓ round-N.md / ✗ none
```

If cleanup is incomplete and the mission completed normally (not force-stopped), warn the user.

## Force Exit Bypasses All Guards

`/exit-mission` writes `"active": false` with an `"endedAt"` field (NOT `"completedAt"`). This distinction is important:
- `completedAt` = legitimate completion → triggers cleanup guard checks
- `endedAt` = force exit → bypasses cleanup guard (no cleanup required for emergency stops)

The hook only enforces cleanup when `completedAt` is present. `/exit-mission` uses `endedAt` instead, so it always works. After deactivation, the `.mission/` directory is deleted via `rm -rf .mission/`. This is safe because hooks exit early when `active` is not `"true"`.
