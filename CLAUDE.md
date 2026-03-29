# Mission Plugin v1.0

Strict 3-role orchestration for Claude Code sessions. Python hook engine with model enforcement, structured feature tracking via `features.json`, and Factory-grade anti-drift protection.

## Commands

- `/enter-mission [task]` — Enter Mission Mode (auto-resumes if interrupted)
- `/exit-mission` — Emergency stop — always works, bypasses all guards
- `/mission-config` — View/set model defaults for all 3 roles
- `/mission-status` — View mission progress with per-feature status from `features.json`

## Roles

- **Orchestrator** — Plans, delegates, reviews. NEVER writes code. Creates and tracks `features.json`.
- **Worker** — Implements code as assigned per feature. NEVER plans, tests, or validates.
- **Validator** — Verifies per-feature, writes tests, generates structured reports. NEVER writes production code.

## Enforcement

Roles are enforced at the tool-call level by three Python hooks sharing a common engine (`hooks/engine.py`):

- **`hooks/phase-guard.py`** (PreToolUse) — Blocks forbidden tool calls per phase. Covers Write, Edit, MultiEdit, Agent, and Bash tools.
- **`hooks/mission-reminder.py`** (PreToolUse) — Injects role-specific anti-drift reminders before every tool call. Feature-aware from `features.json`.
- **`hooks/mission-continue.py`** (PostToolUse) — Injects continuation reminders after every tool call with strength gradient (STRONGEST for Agent, MEDIUM for Read/Write, LIGHT for Grep/Glob).

All hooks are registered in `hooks/hooks.json` and invoked via `python3` directly. The shared `engine.py` module provides single-call state parsing, path canonicalization, model validation, and feature tracking — all using Python stdlib only.

## Config

Global config: `~/.mission/config.json`
Per-project state: `.mission/state.json`
Feature tracking: `.mission/features.json`
Human-readable overview: `.mission/mission-brief.md`

### State Fields

- **`active`** — Whether the mission is currently running. `true` or `false`.
- **`phase`** — Current phase: `"orchestrator"`, `"worker"`, `"validator"`, or `"complete"`.
- **`task`** — The mission task description.
- **`round`** — Current validation round number.
- **`persistence`** — Stopping behavior: `"relentless"` (default, never stop until done), `"standard"` (respect limits), `"cautious"` (stop at first critical).
- **`progressBanners`** — Show progress banners at phase transitions. Default: `true`.
- **`strictPhaseLock`** — Enforce phase lock validation. Default: `true`.
- **`currentAction`** — What the Orchestrator is currently doing.
- **`features`** — Path to `features.json` (structured tracking, replaces old `plan.md`).
- **`models`** — Per-mission model overrides (takes precedence over global config).
- **`phaseLock`** — Object with `phase`, `lockedAt`, `lockedBy`. Ensures single-role execution.
- **`phaseHistory`** — Array of `{phase, startedAt, endedAt}` entries tracking phase transitions.
- **`issuesTrend`** — Array of `{round, critical, high, medium, low, total}` entries for trend analysis.

## Feature Tracking (features.json)

The Orchestrator creates `.mission/features.json` during initialization. This is the machine-tracked source of truth for all features:

```json
{
  "features": [
    {
      "id": "feature-slug",
      "description": "What needs to be done",
      "assignee": null,
      "status": "pending",
      "dependencies": [],
      "handoff": null
    }
  ]
}
```

**Status lifecycle:** `pending` → `in-progress` → `completed` | `failed`

The Orchestrator dispatches Workers per feature, tracks handoffs in `features.json`, and uses feature statuses as the primary completion gate. All hooks read `features.json` for context injection.

## Model Enforcement

Models for each role are configured via `~/.mission/config.json` (or overridden per-mission in `state.json`):

- `models.orchestrator` — default: `"opus"`
- `models.worker` — default: `"opus"`
- `models.validator` — default: `"opus"`

The phase-guard hook enforces models on Agent dispatch:
- **Correct model** → ALLOW
- **Wrong model** → BLOCK with expected model in message
- **Missing model** → Auto-inject correct model from config

Only mission agents (`mission-worker`, `mission-validator`) are checked. Non-mission agents bypass model enforcement.

## Phase Lock

The phase lock mechanism guarantees single-role execution:

1. The Orchestrator writes `phaseLock` to state.json before every phase transition.
2. `phase-guard.py` validates that `phaseLock.phase` matches the current `phase`.
3. If `strictPhaseLock` is enabled and they don't match, the hook blocks the tool call.
4. Only the Orchestrator can modify `phaseLock` (Workers and Validators are blocked from writing to state.json).
5. Valid transitions: `orchestrator` → `worker`, `orchestrator` → `validator`, `orchestrator` → `complete`, `worker` → `validator`, `validator` → `orchestrator`.

## Defense Layers

Eight hook-enforced defense layers in `hooks/phase-guard.py`:

| # | Defense | What it blocks |
|---|---------|---------------|
| 1 | Completion Guard | `phase: "complete"` without validator report. Relentless requires `Verdict: PASS`. |
| 2 | Cleanup Guard | `active: false` + `completedAt` without `summary.md` or with leftover worker-logs |
| 3 | Worker Test Block | Workers writing `*.test.*`, `*.spec.*`, `*_test.*`, `tests/*`, `__tests__/*` |
| 4 | Validator Path Lock | Validators writing to `.mission/` except `.mission/reports/*` |
| 5 | Anti-Premature-Completion | Completion in relentless mode when report says FAIL |
| 6 | Model Enforcement | Wrong model on Agent dispatch; auto-injects if missing |
| 7 | Phase Lock | Tool calls when `phase ≠ phaseLock.phase` (if `strictPhaseLock` enabled) |
| 8 | Unknown Phase Block | All tool calls when phase is not in valid set |

`/exit-mission` bypasses all guards using `endedAt` instead of `completedAt`.

## Context Preservation

Two anti-drift hooks fire for ALL roles (orchestrator, worker, validator) on every matched tool call:

- **PreToolUse (`mission-reminder.py`)** — Injects `[MISSION SKILL ACTIVE — DO NOT DEVIATE]` with role-specific directives and feature context from `features.json`. Includes compaction recovery state (phase, round, task, current feature, current action).
- **PostToolUse (`mission-continue.py`)** — Injects `[MISSION ACTIVE]` with strength gradient. STRONGEST reminder for Agent calls includes full recovery context sufficient to resume after 20+ tool calls or context compaction.

Both hooks read `features.json` and show only the current in-progress feature. Both handle missing/malformed state gracefully and never exit non-zero.

## Auto-Continuation

The mission loop runs in a single response turn. The `mission-continue.py` PostToolUse hook fires after every tool call, reminding the model to continue. If interrupted, the Resume Protocol in SKILL.md auto-detects the active mission via `state.json` and `features.json` and resumes from the current phase.

## Cleanup Order

The cleanup guard enforces this order:
1. Generate `.mission/summary.md` (includes per-feature summary from `features.json`)
2. Clean `.mission/worker-logs/*.md`
3. Then and only then: set `active: false` + `completedAt`
4. Output final summary to user (from memory, before deletion)
5. Delete `.mission/` directory entirely: `rm -rf .mission/`

Step 5 is safe because hooks exit early when `active` is not `"true"`. The directory (including `state.json`, `features.json`, reports, and logs) is not preserved after completion.
