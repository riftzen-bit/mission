---
name: enter-mission
description: "Enter Mission Mode — strict 3-role orchestration (Orchestrator, Worker, Validator)"
---

# Enter Mission

Invoke the `enter-mission` skill to activate Mission Mode. Pass the task as an argument or omit to be asked.

## Usage

- `/enter-mission Build a REST API for todo app`
- `/enter-mission Fix the authentication bug in login flow`
- `/enter-mission` (will ask what you want to build)

## What Happens

1. Reads `~/.mission/config.json` for model and persistence settings
2. Creates `.mission/` directory with `state.json` (runtime state) and `features.json` (structured tracking)
3. Creates `.mission/mission-brief.md` as a human-readable mission overview
4. Activates the Orchestrator phase — the enter-mission skill takes over

## Auto-Resume

If `.mission/state.json` already exists with `"active": true`, the skill auto-resumes from the last phase using `features.json` to determine progress. No data is lost — the resume protocol state machine determines the next action based on:

- Current phase and round from `state.json`
- Feature statuses from `features.json` (pending, in-progress, completed, failed)

Only if you explicitly invoke `/enter-mission` with a NEW task argument while a mission is active will you be asked whether to resume or start fresh.

## The Mission Loop

```
Orchestrator → create features.json → dispatch Workers per feature → Validator → (fix → validate)* → done
```

All in one response turn. The enter-mission skill enforces mandatory continuation — the mission runs until all features pass or you use `/exit-mission`.

## Hook Enforcement

Three Python hooks enforce role separation at the tool-call level:

- **`phase-guard.py`** (PreToolUse) — Blocks forbidden actions per phase
- **`mission-reminder.py`** (PreToolUse) — Injects anti-drift context before every tool call
- **`mission-continue.py`** (PostToolUse) — Injects continuation reminder after every tool call

## Related Commands

- `/exit-mission` — Emergency stop (always works)
- `/mission-status` — View mission progress dashboard
- `/mission-config` — Configure models and persistence
