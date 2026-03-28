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
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Task: <task description>
Phase: <ORCHESTRATOR|WORKER|VALIDATOR> (round <N>)
Persistence: <RELENTLESS|STANDARD|CAUTIOUS>
Active since: <startedAt in local time>
Duration: <elapsed minutes>
Current action: <currentAction from state>

Models: Orchestrator=<model> | Worker=<model> | Validator=<model>

Phase Lock: <phase> (since <lockedAt>)

Workers:
  <status icon> worker-1: <task description>
  <status icon> worker-2: <task description>

Phase Timeline:
  ORCHESTRATOR: 0:00 → 1:23
  WORKER:       1:23 → 5:47
  VALIDATOR:    5:47 → 8:12
  ORCHESTRATOR: 8:12 → now

Issue Trend:
  Round 1: ██████ 6 issues (2C 3H 1M 0L)
  Round 2: █      1 issue  (0C 1H 0M 0L)  ▼ improving

Latest Validator Report: <path or "pending">
  <brief summary if exists>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Status icons: `✓` completed, `⟳` in_progress, `○` pending

## Field Details

### Phase Lock
Read `phaseLock` from state.json. Display the locked phase and the timestamp it was locked at. If `strictPhaseLock` is enabled, note this in the output.

### Phase Timeline
Read `phaseHistory` from state.json. For each entry, display the phase name and the time range (startedAt to endedAt). If `endedAt` is null, display "now" instead. Calculate time offsets relative to the mission's `startedAt` timestamp.

### Issue Trend
Read `issuesTrend` from state.json. For each round entry:
- Display a bar chart using `█` characters (1 block per issue, max 20)
- Show the breakdown: `(<critical>C <high>H <medium>M <low>L)`
- Compare with previous round: `▼ improving` (total decreased), `▲ worsening` (total increased), `═ stable` (same)

### Current Action
Read `currentAction` from state.json. This shows what the Orchestrator is doing right now (e.g., "Dispatching worker-2 to implement auth middleware", "Reading validator report for round 3").

### Defense Status
Show which defense layers are active:

```
Defense Layers:
  Completion Guard:    ✓ active
  Cleanup Guard:       ✓ active
  Worker Test Block:   ✓ active
  Validator Restrict:  ✓ active
  Anti-Premature-Stop: ✓ active (relentless) / ○ inactive (standard/cautious)
```

### Cleanup Readiness
Show cleanup status for the orchestrator:

```
Cleanup Readiness:
  summary.md:  ✓ exists / ✗ missing
  worker-logs: ✓ clean / ✗ N files remaining
```
