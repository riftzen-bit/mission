---
description: "Exit Mission Mode — deactivate mission, save state, output summary"
---

# Exit Mission

1. Read `.mission/state.json`
2. Set `"active": false` and record `"endedAt"` timestamp
3. Output a summary of the mission:
   - Task description
   - Number of rounds completed
   - Files created and modified
   - Test results
   - Duration
4. Hooks auto-deactivate (phase-guard checks `active` field)

The `.mission/` directory is preserved so you can review the plan, reports, and summary later.
