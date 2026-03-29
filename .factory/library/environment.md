# Environment

## Dependencies
- **Python 3.x** — Required for all hooks (engine.py, phase-guard.py, mission-continue.py, mission-reminder.py)
- **Bash** — Required for thin hook wrappers and test scripts
- **No external Python packages** — Uses only stdlib: `json`, `os`, `sys`, `pathlib`, `time`

## File Locations
- Plugin root: `/home/paul/Projects/mission/`
- Global config: `~/.mission/config.json`
- Runtime state: `.mission/` (in project root, created per-mission, cleaned on completion)

## Hook System
- Hooks registered in `hooks/hooks.json`
- Claude Code calls hooks with `$TOOL_NAME` and `$TOOL_INPUT` env vars
- PreToolUse hooks can BLOCK (exit non-zero) or ALLOW (exit 0)
- PostToolUse hooks are informational only (always exit 0)
- `${CLAUDE_PLUGIN_ROOT}` env var points to plugin root directory

## Testing
- Test framework: Custom bash test harness (assert_blocked / assert_allowed helpers)
- Python tests: pytest for engine.py unit tests
- CI: GitHub Actions on Linux, macOS, Windows
- All tests run via `bash tests/<name>.test.sh` or `python3 -m pytest tests/`
