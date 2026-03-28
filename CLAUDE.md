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
