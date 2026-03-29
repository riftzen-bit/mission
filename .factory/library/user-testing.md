# User Testing

## Validation Surface
- **Surface type**: CLI (hook scripts invoked via command line)
- **No browser/API surface** — purely script execution
- **Testing tool**: bash + python3 direct execution

## Testing Approach
All assertions verified by:
1. Creating mock `.mission/state.json` and `.mission/features.json` in temp directories
2. Running hook scripts with specific tool name and tool input arguments
3. Checking exit codes (0 = ALLOW, non-zero = BLOCK) and stdout content
4. Content-check assertions verified by grepping file contents

## Validation Concurrency
- **Max concurrent validators**: 5 (no resource-heavy processes — just script execution)
- Machine: 16 CPU, 61GB RAM — well within budget
- Each test invocation: ~50ms, ~10MB memory

## Known Constraints
- Hook scripts depend on Python 3 being available in PATH
- Tests must create isolated temp directories to avoid state leakage
- Symlink tests require OS support (may be limited on some Windows configs)

## Flow Validator Guidance: CLI

### Content-Check Assertions (VAL-AGENT-*, VAL-SKILL-*)
These assertions verify the CONTENT of markdown files using grep/rg pattern matching.
- **Repo root**: `/home/paul/Projects/mission`
- **Agent files**: `agents/orchestrator.md`, `agents/worker.md`, `agents/validator.md`
- **Skill file**: `skills/enter-mission/SKILL.md`
- **Command files**: `commands/enter-mission.md`, `commands/exit-mission.md`, `commands/mission-config.md`, `commands/mission-status.md`
- Use `rg` (ripgrep) for pattern matching — it's pre-installed
- For count checks (e.g., "≥ 3 occurrences"), use `rg -c` or `rg --count`
- Case-insensitive matching where appropriate with `-i`
- Each assertion specifies exact expected content — match against the validation contract

### CLI Execution Assertions (VAL-FEAT-*)
These test the hook Python scripts with mock state/features.json files.
- **Hook scripts**: `hooks/engine.py`, `hooks/phase-guard.py`, `hooks/mission-continue.py`, `hooks/mission-reminder.py`
- **Python path**: `python3` (available in PATH)
- Create temp directories per test to isolate state
- State file: `.mission/state.json` in temp dir
- Features file: `.mission/features.json` in temp dir (or project root features.json depending on hook)
- Run hooks from temp dir as CWD so they find `.mission/state.json`
- Exit codes: 0 = ALLOW/success, non-zero = BLOCK
- Always clean up temp dirs after tests

### Isolation Rules
- Each subagent works in its own temp directory for CLI execution tests
- Content-check subagents only READ repo files — no modifications
- No shared mutable state between subagents
- All subagents can read the repo root simultaneously without conflict
