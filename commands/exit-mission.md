---
name: exit-mission
description: "Exit Mission Mode — emergency stop that always works, bypasses all guards"
---

# Exit Mission

**Emergency stop — ALWAYS works.** No persistence setting, no phase lock, and no unresolved issue count can prevent `/exit-mission` from deactivating the mission. The user is always in control.

## What Happens

1. Read `.mission/state.json`
2. Set `"active": false` and record `"endedAt"` timestamp
3. Display cleanup status and mission summary
4. Delete `.mission/` directory entirely: `rm -rf .mission/`
5. Hooks auto-deactivate (phase-guard checks `active` field)

## endedAt vs completedAt — The Bypass Mechanism

`/exit-mission` writes `"active": false` with an **`endedAt`** field (NOT `completedAt`). This distinction is critical:

- **`completedAt`** = legitimate completion → triggers cleanup guard checks (summary.md required, worker-logs must be clean)
- **`endedAt`** = force exit → **bypasses ALL cleanup guards** (no cleanup required for emergency stops)

The phase-guard hook only enforces cleanup when `completedAt` is present. `/exit-mission` uses `endedAt` instead, so it always works regardless of mission state.

## Relentless Mode Warning

If the mission is in relentless mode (`persistence: "relentless"`), display a warning before exiting:

```
⚠ Mission is in RELENTLESS mode with <N> unresolved issues.
  Are you sure you want to stop?
  The mission will NOT auto-resume — all mission state will be removed on exit.
```

Force exit regardless by running `/exit-mission` again or confirming.

## Cleanup Status Display

When `/exit-mission` runs, display cleanup readiness before deactivating:

```
Cleanup Status:
  summary.md:    ✓ exists / ✗ missing
  worker-logs:   ✓ clean (0 files) / ✗ dirty (N files remaining)
  latest report: ✓ round-N.md / ✗ none
```

If cleanup is incomplete and the mission completed normally (not force-stopped), warn the user.

## Summary Output

Before deleting `.mission/`, output a summary from memory:
- Task description
- Number of rounds completed
- Features progress from `features.json` (X/Y completed)
- Files created and modified
- Test results
- Duration

## Safety

After deactivation, `.mission/` is deleted via `rm -rf .mission/`. This is safe because hooks exit early when `active` is not `"true"`. No mission state is preserved after exit.
