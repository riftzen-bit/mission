# Mission Plugin for Claude Code

A strict 3-role orchestration system with hard enforcement via PreToolUse hooks.

## Install

```bash
claude plugins add /path/to/mission
```

## Quick Start

```
/enter-mission Build a REST API for todo app
```

## Configuration

```
/mission-config orchestrator=opus worker=sonnet validator=opus
```

## How It Works

1. `/enter-mission` activates Mission Mode
2. **Orchestrator** reads codebase, creates plan, dispatches Workers
3. **Workers** implement code (parallel if independent)
4. **Validator** writes tests for ALL functions, runs all checks, generates report
5. If issues found → Orchestrator dispatches Workers to fix → Validator re-verifies
6. Loop until 100% pass → Orchestrator cleans up

Roles are strictly isolated. Only one role type active at a time. Hooks enforce boundaries at the tool-call level.

## Requirements

- Claude Code CLI
- Python 3 (for JSON parsing in phase-guard.sh)
