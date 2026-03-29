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
