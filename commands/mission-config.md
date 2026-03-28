---
description: "View or set Mission Mode model defaults — persists globally in ~/.mission/config.json"
---

# Mission Config

Manages global Mission Mode configuration stored at `~/.mission/config.json`.

## Usage

- `/mission-config` — Show current config
- `/mission-config orchestrator=sonnet` — Set Orchestrator model
- `/mission-config worker=haiku validator=sonnet` — Set multiple roles
- `/mission-config effort.worker=max` — Set effort level (dot notation for nested keys)
- `/mission-config maxRounds=5` — Set max rounds before stopping
- `/mission-config maxDurationMinutes=240` — Set max duration in minutes
- `/mission-config persistence=relentless` — Never stop until done
- `/mission-config persistence=cautious` — Stop at first critical issue
- `/mission-config progressBanners=false` — Disable progress banners
- `/mission-config progressBanners=true` — Enable progress banners
- `/mission-config strictPhaseLock=true` — Enable strict phase locking
- `/mission-config strictPhaseLock=false` — Disable strict phase locking
- `/mission-config reset` — Reset to defaults

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
  "models": {"orchestrator": "opus", "worker": "opus", "validator": "opus"},
  "effort": {"orchestrator": "high", "worker": "high", "validator": "high"},
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
