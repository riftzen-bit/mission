# Architecture — Mission Plugin v1.0

## Overview

The Mission Plugin enforces a 3-role orchestration pattern for Claude Code sessions via hook-based enforcement. It turns a single Claude Code session into a disciplined team: **Orchestrator** (plans), **Workers** (implement), **Validator** (tests).

## Component Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Claude Code Session                                      │
│                                                          │
│  ┌─────────────┐    ┌──────────────┐   ┌─────────────┐ │
│  │ Orchestrator │───▶│ Agent Tool   │──▶│ Workers     │ │
│  │ (main)       │    │ (dispatch)   │   │ (subagents) │ │
│  └──────┬───────┘    └──────────────┘   └─────────────┘ │
│         │                                                │
│         ▼            ┌──────────────┐   ┌─────────────┐ │
│  ┌─────────────┐    │ Agent Tool   │──▶│ Validator   │ │
│  │ State Mgmt   │    │ (dispatch)   │   │ (subagent)  │ │
│  │ .mission/    │    └──────────────┘   └─────────────┘ │
│  └─────────────┘                                         │
└────────────────────┬────────────────────────────────────┘
                     │ Hook Layer (intercepts ALL tool calls)
┌────────────────────┴────────────────────────────────────┐
│ PreToolUse Hooks                                         │
│  ├─ phase-guard.py   (ENFORCE: block forbidden actions)  │
│  └─ mission-reminder.py (INJECT: anti-drift context)     │
│                                                          │
│ PostToolUse Hooks                                        │
│  └─ mission-continue.py (INJECT: continuation reminder)  │
│                                                          │
│ Shared Engine: engine.py                                 │
│  ├─ load_state()        — Single-call state parsing      │
│  ├─ load_config()       — Config with defaults merge     │
│  ├─ load_features()     — Features.json parsing          │
│  ├─ canonicalize_path() — Symlink + traversal resolution │
│  ├─ validate_model()    — Agent model enforcement        │
│  ├─ is_test_file()      — Test file pattern detection    │
│  ├─ is_test_command()   — Test runner detection           │
│  └─ is_mission_path()   — .mission/ path detection       │
└─────────────────────────────────────────────────────────┘
```

## State Management

### Runtime State: `.mission/state.json`
Single source of truth during an active mission. Created on `/enter-mission`, deleted on completion/exit.

Key fields: `active`, `phase`, `round`, `task`, `models`, `persistence`, `workers`, `phaseLock`, `currentAction`, `phaseHistory`, `issuesTrend`.

### Feature Tracking: `.mission/features.json`
Ordered list of features with statuses. Replaces free-form plan.md. Workers are dispatched per-feature, and hooks inject current feature context into reminders.

Schema: `{features: [{id, description, assignee, status, dependencies, handoff}]}`

### Global Config: `~/.mission/config.json`
User preferences persisted across missions. Models, persistence mode, flags.

## Hook Enforcement Flow

```
Tool Call → PreToolUse → [phase-guard.py] → BLOCK or ALLOW
                       → [mission-reminder.py] → inject context
         → Tool Executes
         → PostToolUse → [mission-continue.py] → inject continuation
```

### Phase Guard Decision Tree
1. No state file → ALLOW
2. Not active → ALLOW
3. Phase lock conflict → BLOCK
4. Model enforcement (Agent calls, orchestrator only) → BLOCK/INJECT/ALLOW
5. Phase-specific enforcement (orchestrator/worker/validator/complete)
6. Unknown phase → BLOCK

### Context Preservation Layers
1. **PreToolUse reminder**: Fresh context BEFORE every tool call
2. **PostToolUse continuation**: Next-step instructions AFTER every tool call
3. **Strength gradient**: STRONGEST (Agent) > MEDIUM (Read/Write) > LIGHT (Grep/Glob)
4. **All-role coverage**: Orchestrator, worker, AND validator get reminders
5. **Feature-aware**: Reminders include current feature ID/description
6. **Compaction recovery**: Enough state in each injection to resume after compaction

## Data Flow

```
/enter-mission → Read config → Create .mission/ → Init state.json + features.json
  → Orchestrator researches codebase
  → Creates features in features.json
  → Dispatches Worker per feature (Agent tool, model from config)
    → Worker implements feature
    → Worker writes structured handoff to features.json
  → Dispatches Validator (Agent tool, model from config)
    → Validator tests per-feature
    → Writes report to .mission/reports/round-N.md
  → If issues: loop (dispatch fix workers → validate again)
  → All pass: cleanup → rm -rf .mission/
```

## Security Boundaries

| Role | Can Write | Cannot Write | Cannot Execute |
|------|-----------|-------------|----------------|
| Orchestrator | `.mission/*` | Source files | — |
| Worker | Source files, `.mission/worker-logs/*` | Test files, `.mission/state.json` | Test commands |
| Validator | Test files, `.mission/reports/*` | Source files, `.mission/state.json` | — |

All enforced by `phase-guard.py` via path canonicalization (symlink + traversal resolution).
