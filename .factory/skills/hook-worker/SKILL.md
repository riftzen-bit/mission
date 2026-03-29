---
name: hook-worker
description: Implements Python hook scripts and their bash test suites for the Mission Plugin
---

# Hook Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Features that involve creating or modifying:
- Python hook scripts (hooks/engine.py, hooks/phase-guard.py, hooks/mission-continue.py, hooks/mission-reminder.py)
- hooks.json configuration
- Bash test suites for hooks (tests/phase-guard.test.sh, tests/mission-continue.test.sh, tests/mission-reminder.test.sh)
- Python unit tests (tests/test_engine.py)

## Required Skills

None — direct file editing and test execution.

## Work Procedure

### 1. Understand Context
- Read `.factory/library/architecture.md` for system overview
- Read `AGENTS.md` for coding conventions (Python 3.8+, stdlib only, BLOCK message format)
- Read the existing v0.5.0 bash hooks to understand current behavior patterns
- Read existing test files to understand the bash test harness (assert_blocked/assert_allowed)

### 2. Write Tests FIRST (TDD — Red Phase)
- For Python modules (engine.py): Write pytest tests in `tests/test_engine.py`
  - Minimum 5 test cases per function, 3 edge cases
  - Cover: happy path, missing files, malformed JSON, edge cases, performance
  - Use `tmp_path` fixture for temporary directories
  - Use parametrize for comprehensive input coverage
- For hook scripts: Write bash integration tests
  - Use the existing test harness pattern (assert_blocked, assert_allowed helpers)
  - Create mock state.json and features.json in temp directories
  - Test both BLOCK and ALLOW scenarios
  - Test edge cases: missing files, malformed JSON, empty input, Unicode paths
- Run tests to confirm they FAIL (red phase)

### 3. Implement (Green Phase)
- Write the Python code to make tests pass
- Follow conventions from AGENTS.md:
  - Python 3.8+ compatible
  - stdlib only (json, os, sys, pathlib, time)
  - Graceful error handling (no unhandled exceptions)
  - BLOCK format: `BLOCK: [MISSION GUARD] Phase "<phase>" — <description>`
- For phase-guard.py: Preserve ALL v0.5.0 defenses while adding v1.0 features
- For hooks.json: Use thin bash wrappers that call python3

### 4. Verify (Refactor Phase)
- Run ALL test suites (not just the ones you wrote):
  ```bash
  bash tests/phase-guard.test.sh
  bash tests/mission-continue.test.sh
  bash tests/mission-reminder.test.sh
  python3 -m pytest tests/test_engine.py -v
  ```
- Check performance: `time python3 hooks/phase-guard.py Write '{"file_path":"x.ts"}'` < 50ms
- Verify no regressions in existing tests
- Check that BLOCK messages follow consistent format

### 5. Manual Verification
- Run hooks manually against real-looking scenarios:
  - Create a mock .mission/state.json and invoke each hook
  - Verify output format matches expected patterns
  - Test the hooks.json configuration by checking bash wrappers work

## Example Handoff

```json
{
  "salientSummary": "Implemented hooks/engine.py with 12 functions (load_state, load_config, load_features, canonicalize_path, find_state_file, is_mission_path, is_test_file, is_test_command, extract_tool_input, validate_model, get_current_feature, get_next_feature). All functions handle missing/malformed input gracefully. Wrote 65 pytest tests in tests/test_engine.py covering all functions with edge cases. All pass. Performance: load_state < 5ms.",
  "whatWasImplemented": "hooks/engine.py — shared Python module for all hooks. 12 functions using stdlib only. Single-call state parsing replaces 6 separate python3 invocations. Config loading with defaults merge. Path canonicalization with symlink resolution. Test file/command detection including wrapped commands. Model validation with state.json override.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {"command": "python3 -m pytest tests/test_engine.py -v", "exitCode": 0, "observation": "65 passed in 0.4s"},
      {"command": "python3 -c 'import time; t=time.perf_counter(); from hooks.engine import load_state; print(f\"{(time.perf_counter()-t)*1000:.1f}ms\")'", "exitCode": 0, "observation": "4.2ms"}
    ],
    "interactiveChecks": [
      {"action": "Created mock state.json with phase=worker and invoked engine functions", "observed": "All fields parsed correctly, is_test_file detects all patterns, wrapped commands detected"},
      {"action": "Tested load_state with malformed JSON", "observed": "Returns {active: False} sentinel, no exception"}
    ]
  },
  "tests": {
    "added": [
      {"file": "tests/test_engine.py", "cases": [
        {"name": "test_load_state_all_fields", "verifies": "Returns dict with all required fields"},
        {"name": "test_load_state_missing_file", "verifies": "Returns inactive sentinel on missing file"},
        {"name": "test_load_state_malformed_json", "verifies": "Returns inactive sentinel on bad JSON"},
        {"name": "test_is_test_command_wrapped", "verifies": "Detects sh -c 'npm test' patterns"},
        {"name": "test_validate_model_case_insensitive", "verifies": "Opus matches opus after normalization"}
      ]}
    ]
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- Feature depends on a hook function that doesn't exist yet in engine.py
- The v0.5.0 bash hook has behavior not documented in the feature description
- Test framework (assert_blocked/assert_allowed) doesn't work as expected
- Python 3 not available or has unexpected version limitations
- Performance target (< 50ms) cannot be met with stdlib-only approach
