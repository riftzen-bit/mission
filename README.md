# Mission Plugin for Claude Code v1.0

A strict 3-role orchestration system that turns Claude Code into a disciplined engineering team. The **Orchestrator** plans, **Workers** code, and the **Validator** tests — each role isolated by hard hook enforcement at the tool-call level. Features structured tracking via `features.json`, model enforcement, and Factory-grade anti-drift protection.

## Why Mission?

Claude Code is powerful, but without structure it can skip tests, mix concerns, or lose track of quality. Mission Mode forces a disciplined loop:

```
Plan → Create features.json → Dispatch Workers per feature → Validate → Fix → Validate → ... → Done
```

No role can do another role's job. Workers can't run tests. Validators can't write source code. The Orchestrator can't touch files outside `.mission/`. All enforced by Python PreToolUse hooks — not just prompts.

## Install

```bash
# From GitHub
/plugin marketplace add riftzen-bit/mission
/plugin install mission

# Or from a local clone
/plugin install /path/to/mission
```

## Quick Start

```
/enter-mission Build a REST API for user authentication
```

That's it. Mission Mode activates and runs the full loop automatically:

1. **Orchestrator** reads your codebase, creates `features.json` with structured feature list
2. **Workers** implement code per feature (parallel for independent features)
3. **Validator** validates per-feature with structured assertion tracking, generates report
4. If issues found → Workers fix → Validator re-verifies
5. Loop until all features pass → cleanup → done

## Commands

| Command | Description |
|---------|-------------|
| `/enter-mission [task]` | Start Mission Mode (or resume if interrupted) |
| `/exit-mission` | Emergency stop — always works, bypasses all guards via `endedAt` |
| `/mission-status` | Dashboard: phase, round, per-feature progress from `features.json` |
| `/mission-config` | View or set models for orchestrator, worker, validator + persistence |

## Roles

### Orchestrator
Plans, delegates, reviews. Spawns Workers and Validators via the Agent tool.
- **CAN**: Read any file, write to `.mission/`, create/update `features.json`, spawn agents
- **CANNOT**: Write or edit source code (hooks block it)

### Worker
Implements code exactly as assigned per feature from `features.json`. Produces structured JSON handoffs.
- **CAN**: Read/write source files, run build commands
- **CANNOT**: Run tests, write test files, modify `.mission/state.json`, spawn Validators

### Validator
The ruthless quality gate. Validates per-feature, writes tests, runs all checks, finds bugs.
- **CAN**: Write test files, write `.mission/reports/*`, run any command
- **CANNOT**: Modify source files, modify mission state, spawn Workers

## Hook Enforcement

Roles are enforced at the tool-call level by a Python hook engine (`hooks/engine.py`) shared across eight hooks:

- **`hooks/phase-guard.py`** (PreToolUse) — Blocks forbidden tool calls per phase
- **`hooks/mission-reminder.py`** (PreToolUse) — Injects role-specific anti-drift reminders with feature context
- **`hooks/mission-continue.py`** (PostToolUse) — Injects continuation reminders with strength gradient
- **`hooks/mission-stop.py`** (Stop) — Blocks session from ending while mission is active
- **`hooks/mission-subagent-stop.py`** (SubagentStop) — Blocks sub-agents from premature stopping
- **`hooks/mission-precompact.py`** (PreCompact) — Saves checkpoint before context compaction
- **`hooks/mission-session-start.py`** (SessionStart) — Auto-injects mission context on session start/resume
- **`hooks/mission-prompt.py`** (UserPromptSubmit) — Injects mission context on every user message

All 8 hooks across 7 event types registered in `hooks/hooks.json` via direct `python3` invocation. Single-process execution per hook (no subprocess chains).

| Defense | What it blocks |
|---------|---------------|
| Phase Lock | Tool calls that don't match the current phase |
| Completion Guard | Completing without a validator report (relentless: requires `Verdict: PASS`) |
| Cleanup Guard | Deactivating without `summary.md` + clean worker-logs |
| Worker Test Block | Workers writing `*.test.*`, `*.spec.*`, `*_test.*`, `tests/*`, `__tests__/*` |
| Validator Path Lock | Validators writing to `.mission/` except `.mission/reports/*` |
| Anti-Premature Stop | Completion in relentless mode when report says FAIL |
| Model Enforcement | Wrong model on Agent dispatch (auto-injects if missing) |
| Unknown Phase Block | All tool calls when phase is not in valid set |
| Symlink Protection | Path traversal via symlinks (`realpath` resolution) |
| Phase Transitions | Invalid transitions (e.g., worker → complete) |
| Stop Guard | Droid stopping while mission active (non-complete phase) |
| SubagentStop Guard | Workers/Validators stopping without handoff/report |

## Feature Tracking

The Orchestrator creates `.mission/features.json` as the structured tracking system:

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

Status lifecycle: `pending` → `in-progress` → `completed` | `failed`

Workers are dispatched per feature. Handoffs are structured JSON (`{filesChanged, summary, testsNeeded}`). Feature statuses are the primary completion gate.

## Persistence Modes

| Mode | Behavior |
|------|----------|
| `relentless` (default) | Never stops until ALL features pass or you run `/exit-mission` |
| `standard` | Respects round/time limits |
| `cautious` | Stops at first critical issue |

```
/mission-config persistence=relentless
```

## Auto-Continuation & Context Preservation

Mission Mode runs the entire loop in a single response. The `mission-continue.py` PostToolUse hook fires after every tool call with a strength gradient:
- **STRONGEST** (Agent + orchestrator) — Full recovery context from `features.json`
- **STRONG** (Agent + worker/validator) — Phase and feature context
- **MEDIUM** (Read/Write/Edit/Bash) — Phase and round
- **LIGHT** (Grep/Glob) — Minimal reminder

The `mission-reminder.py` PreToolUse hook injects role-specific anti-drift reminders for ALL roles (not just orchestrator), ensuring context preservation across 20+ tool calls.

If the loop is interrupted, the **Resume Protocol** reads `state.json` and `features.json` to determine exact progress and resumes from the current phase automatically.

Five additional lifecycle hooks ensure continuity: the **Stop** hook blocks the model from ending its response mid-mission, **SubagentStop** prevents sub-agents from quitting early, **PreCompact** saves a checkpoint before context compaction, **SessionStart** auto-injects recovery context on session start, and **UserPromptSubmit** keeps the model mission-aware on every user message.

## Configuration

```
/mission-config orchestrator=opus worker=sonnet validator=opus
/mission-config persistence=relentless
/mission-config progressBanners=true
/mission-config strictPhaseLock=true
```

Global config is stored at `~/.mission/config.json`. Per-mission state lives in `.mission/state.json` (auto-cleaned on completion). Per-mission model overrides in `state.json` take precedence over global config.

| Option | Default | Description |
|--------|---------|-------------|
| `models.orchestrator` | `opus` | Model for planning and delegation |
| `models.worker` | `opus` | Model for implementation |
| `models.validator` | `opus` | Model for testing and review |
| `maxRounds` | `10` | Soft limit in relentless mode |
| `maxDurationMinutes` | `120` | Soft limit in relentless mode |
| `persistence` | `relentless` | `relentless`, `standard`, or `cautious` |
| `progressBanners` | `true` | Show phase transition banners |
| `strictPhaseLock` | `true` | Enforce phase lock validation |

## Requirements

- Claude Code CLI
- Python 3 (for hook engine — stdlib only, no pip packages)

## License

MIT
