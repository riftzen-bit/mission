---
description: "Show current Mission Mode progress — phase, round, workers, validator results"
---

# Mission Status

Reads `.mission/state.json` and displays real-time mission progress.

## Implementation

1. Check if `.mission/state.json` exists
   - If not: output "No active mission. Use /enter-mission to start one."
2. Read and parse state.json
3. Display:

```
[MISSION STATUS]
Task: <task description>
Phase: <ORCHESTRATOR|WORKER|VALIDATOR> (round <N>)
Active since: <startedAt in local time>
Duration: <elapsed minutes>

Models: Orchestrator=<model> | Worker=<model> | Validator=<model>

Workers:
  <status icon> worker-1: <task description>
  <status icon> worker-2: <task description>

Latest Validator Report: <path or "pending">
  <brief summary if exists>
```

Status icons: `✓` completed, `⟳` in_progress, `○` pending
