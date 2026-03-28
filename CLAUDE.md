# Mission Plugin

This plugin provides strict 3-role orchestration for Claude Code sessions.

## Commands

- `/enter-mission [task]` — Enter Mission Mode
- `/exit-mission` — Leave Mission Mode
- `/mission-config` — View/set model defaults
- `/mission-status` — View current mission progress

## Roles

- **Orchestrator** — Plans, delegates, reviews. NEVER writes code.
- **Worker** — Implements code. NEVER plans or validates.
- **Validator** — Verifies, tests, reviews. NEVER writes production code.

## Enforcement

Roles are enforced via PreToolUse hooks. The hook script `hooks/phase-guard.sh` reads `.mission/state.json` and blocks forbidden tool calls per phase.

## Config

Global config: `~/.mission/config.json`
Per-project state: `.mission/state.json`

## State Fields (v0.2.0)

The following fields were added to `.mission/state.json` in v0.2.0:

- **`persistence`** — Mission stopping behavior. Values: `"relentless"` (never stop until done), `"standard"` (respect limits), `"cautious"` (stop at first critical). Default: `"relentless"`.
- **`progressBanners`** — Whether to display progress banners at phase transitions. Default: `true`.
- **`strictPhaseLock`** — Whether to enforce strict phase lock validation. Default: `true`.
- **`currentAction`** — Free-text description of what the Orchestrator is currently doing (e.g., "Dispatching worker-2 to implement auth middleware").
- **`phaseLock`** — Object with `phase`, `lockedAt`, and `lockedBy` fields. Ensures only one role is active at a time. Must always match the top-level `phase` field.
- **`phaseHistory`** — Array of `{phase, startedAt, endedAt}` entries tracking every phase transition with timestamps.
- **`issuesTrend`** — Array of `{round, critical, high, medium, low, total}` entries appended after each validator round for trend analysis.

## Phase Lock

The phase lock mechanism provides a hard guarantee that only one role runs at a time:

1. The Orchestrator writes `phaseLock` to state.json before every phase transition.
2. `phase-guard.sh` reads `phaseLock.phase` and validates that tool calls match the locked phase.
3. If `strictPhaseLock` is enabled and `phase` does not match `phaseLock.phase`, the hook blocks the tool call.
4. Only the Orchestrator can modify `phaseLock` (Workers and Validators are blocked from writing to state.json).
5. Valid transitions: `orchestrator` to `worker`, `worker` to `validator`, `validator` to `orchestrator`, `orchestrator` to `complete`.

## Defense Layers (v0.3.0)

Five hook-enforced defense layers in `hooks/phase-guard.sh`:

1. **Completion Guard** — Blocks `phase: "complete"` without validator report. Relentless mode requires "Verdict: PASS" in report.
2. **Mandatory Cleanup Guard** — Blocks `active: false` + `completedAt` without `summary.md` and with leftover worker-logs.
3. **Worker Test File Block** — Workers cannot write test files.
4. **Validator Path Restriction** — Validators can only write `.mission/reports/*`, not other `.mission/` paths.
5. **Anti-Premature-Completion** — Relentless mode blocks completion when report says FAIL.

`/exit-mission` bypasses all guards using `endedAt` instead of `completedAt`.

## Auto-Continuation (v0.4.0)

A `PostToolUse` hook (`hooks/mission-continue.sh`) fires after every Agent call during an active mission. It injects a `[MISSION ACTIVE]` reminder to prevent the model from stopping mid-loop. If the loop is interrupted, the Resume Protocol in SKILL.md auto-detects the active mission and resumes from the current phase.

## Cleanup Order

The cleanup guard enforces this order:
1. Generate `.mission/summary.md`
2. Clean `.mission/worker-logs/*.md`
3. Then and only then: set `active: false` + `completedAt`
4. Output final summary to user (from memory, before deletion)
5. Delete `.mission/` directory entirely: `rm -rf .mission/`

Step 5 is safe because hooks exit early when `active` is not `"true"` (phase-guard.sh line 49). The directory is not preserved after completion — all state, plans, reports, and logs are removed.
