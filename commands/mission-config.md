---
name: mission-config
description: "View or set Mission Mode configuration — models for orchestrator, worker, validator, persistence, and flags"
---

# Mission Config

Manages global Mission Mode configuration stored at `~/.mission/config.json`.

## Usage

- `/mission-config` — Show current config
- `/mission-config orchestrator=sonnet` — Set Orchestrator model
- `/mission-config worker=haiku` — Set Worker model
- `/mission-config validator=opus` — Set Validator model
- `/mission-config orchestrator=opus worker=sonnet validator=haiku` — Set all 3 role models at once
- `/mission-config effort.worker=max` — Set effort level (dot notation for nested keys)
- `/mission-config maxRounds=5` — Set max rounds before stopping
- `/mission-config maxDurationMinutes=240` — Set max duration in minutes
- `/mission-config persistence=relentless` — Never stop until done
- `/mission-config persistence=cautious` — Stop at first critical issue
- `/mission-config progressBanners=false` — Disable progress banners
- `/mission-config strictPhaseLock=true` — Enable strict phase locking
- `/mission-config reset` — Reset to defaults

## Model Configuration

Models control which Claude model is used for each role during a mission. The orchestrator plans and delegates, the worker implements code, and the validator tests and reviews. Each role can use a different model for cost/quality optimization.

| Role | Config Key | Default | Used For |
|------|-----------|---------|----------|
| Orchestrator | `models.orchestrator` | `opus` | Planning, delegation, review |
| Worker | `models.worker` | `opus` | Code implementation |
| Validator | `models.validator` | `opus` | Testing, quality review |

Models are enforced by the phase-guard hook — if a Worker or Validator agent is dispatched with the wrong model, the hook blocks it and shows the expected model. Missing model fields are auto-injected by the hook.

## Valid Values

- **Models:** `opus`, `sonnet`, `haiku`
- **Effort:** `low`, `medium`, `high`, `max`
- **maxRounds:** integer 1-50
- **maxDurationMinutes:** integer 10-480
- **persistence:** `relentless`, `standard`, `cautious` (default: `relentless`)
- **progressBanners:** `true`, `false` (default: `true`)
- **strictPhaseLock:** `true`, `false` (default: `true`)

## Default Config

```json
{
  "models": {
    "orchestrator": "opus",
    "worker": "opus",
    "validator": "opus"
  },
  "effort": {
    "orchestrator": "high",
    "worker": "high",
    "validator": "high"
  },
  "maxRounds": 10,
  "maxDurationMinutes": 120,
  "persistence": "relentless",
  "progressBanners": true,
  "strictPhaseLock": true
}
```

## Implementation

1. Read `~/.mission/config.json` (create with defaults if not exists)
2. If no arguments: display current config in formatted table
3. If arguments: parse `key=value` pairs, validate, update, write back
4. If `reset`: overwrite with defaults
5. For dot-notation keys (e.g., `effort.worker`): navigate nested object
6. Invalid values → show error message, do not apply

## Config Precedence

- `~/.mission/config.json` — Global defaults (set by `/mission-config`)
- `.mission/state.json` `models` field — Per-mission overrides (if set, takes precedence over global config for model enforcement)
