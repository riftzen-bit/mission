# Mission Plugin for Claude Code

A strict 3-role orchestration system that turns Claude Code into a disciplined engineering team. The **Orchestrator** plans, **Workers** code, and the **Validator** tests — each role isolated by hard hook enforcement at the tool-call level.

## Why Mission?

Claude Code is powerful, but without structure it can skip tests, mix concerns, or lose track of quality. Mission Mode forces a disciplined loop:

```
Plan → Implement → Validate → Fix → Validate → ... → Done
```

No role can do another role's job. Workers can't run tests. Validators can't write source code. The Orchestrator can't touch files outside `.mission/`. All enforced by PreToolUse hooks — not just prompts.

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

1. **Orchestrator** reads your codebase, creates a plan
2. **Workers** implement code in parallel (independent tasks)
3. **Validator** writes tests for every function, runs all checks, generates a report
4. If issues found → Workers fix → Validator re-verifies
5. Loop until 100% pass → cleanup → done

## Commands

| Command | Description |
|---------|-------------|
| `/enter-mission [task]` | Start Mission Mode (or resume if interrupted) |
| `/exit-mission` | Emergency stop — always works, no matter what |
| `/mission-status` | Dashboard: phase, round, workers, issue trend |
| `/mission-config` | View or change model/persistence settings |

## Roles

### Orchestrator
Plans, delegates, reviews. Spawns Workers and Validators via the Agent tool.
- **CAN**: Read any file, write to `.mission/`, spawn agents
- **CANNOT**: Write or edit source code (hooks block it)

### Worker
Implements code exactly as assigned. No more, no less.
- **CAN**: Read/write source files, run build commands
- **CANNOT**: Run tests, write test files, modify `.mission/state.json`, spawn Validators

### Validator
The ruthless quality gate. Writes tests, runs all checks, finds bugs.
- **CAN**: Write test files, write reports, run any command
- **CANNOT**: Modify source files, modify mission state, spawn Workers

## Hook Enforcement

Roles aren't just suggested — they're enforced at the tool-call level by `hooks/phase-guard.sh`:

| Defense | What it blocks |
|---------|---------------|
| Phase Lock | Tool calls that don't match the current phase |
| Completion Guard | Completing without a validator report |
| Cleanup Guard | Deactivating without summary + clean worker-logs |
| Worker Test Block | Workers writing `*.test.*`, `*.spec.*`, `tests/*` |
| Validator Path Lock | Validators writing outside `.mission/reports/*` |
| Anti-Premature Stop | Completing in relentless mode when report says FAIL |
| Symlink Protection | Path traversal via symlinks (`realpath` resolution) |
| Phase Transitions | Invalid transitions (e.g., worker → complete) |

## Persistence Modes

| Mode | Behavior |
|------|----------|
| `relentless` (default) | Never stops until ALL pass or you run `/exit-mission` |
| `standard` | Respects round/time limits |
| `cautious` | Stops at first critical issue |

```
/mission-config persistence=relentless
```

## Auto-Continuation

Mission Mode is designed to run the entire loop in a single response. A `PostToolUse` hook (`mission-continue.sh`) fires after every Agent call, reminding Claude to continue instead of stopping.

If the loop is interrupted (e.g., context limits), the **Resume Protocol** auto-detects the active mission on the next message and resumes from exactly where it stopped. No manual intervention needed.

## Configuration

```
/mission-config orchestrator=opus worker=sonnet validator=opus
/mission-config persistence=relentless
/mission-config progressBanners=true
/mission-config strictPhaseLock=true
```

Global config is stored at `~/.mission/config.json`. Per-mission state lives in `.mission/state.json` (auto-cleaned on completion).

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
- Python 3 (for JSON parsing in hooks)

## License

MIT
