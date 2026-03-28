#!/usr/bin/env bash
# tests/phase-guard.test.sh — Tests for hooks/phase-guard.sh
# Run: bash tests/phase-guard.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD_SCRIPT="$PROJECT_DIR/hooks/phase-guard.sh"
TEST_DIR=$(mktemp -d)
PASSED=0
FAILED=0
TOTAL=0

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Helper: create .mission/state.json in test dir
create_state() {
  local phase="$1"
  local active="${2:-true}"
  mkdir -p "$TEST_DIR/.mission"
  cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": $active,
  "phase": "$phase",
  "task": "test task",
  "round": 1
}
STATEEOF
}

# Helper: run phase-guard and capture exit code + output
run_guard() {
  local tool_name="$1"
  local tool_input="$2"
  local output
  local exit_code
  output=$(cd "$TEST_DIR" && TOOL_NAME="$tool_name" TOOL_INPUT="$tool_input" bash "$GUARD_SCRIPT" "$tool_name" "$tool_input" 2>&1) || exit_code=$?
  exit_code=${exit_code:-0}
  echo "$output"
  return $exit_code
}

assert_blocked() {
  local desc="$1"
  shift
  TOTAL=$((TOTAL + 1))
  local output
  if output=$(run_guard "$@" 2>&1); then
    echo "FAIL: $desc — expected BLOCK but got ALLOW"
    echo "  output: $output"
    FAILED=$((FAILED + 1))
  else
    if echo "$output" | grep -q "BLOCK"; then
      echo "PASS: $desc"
      PASSED=$((PASSED + 1))
    else
      echo "FAIL: $desc — exit non-zero but no BLOCK message"
      echo "  output: $output"
      FAILED=$((FAILED + 1))
    fi
  fi
}

assert_allowed() {
  local desc="$1"
  shift
  TOTAL=$((TOTAL + 1))
  local output
  if output=$(run_guard "$@" 2>&1); then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected ALLOW but got BLOCK"
    echo "  output: $output"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== Phase Guard Tests ==="
echo ""

# ─────────────────────────────────────────────
# TEST GROUP: No mission active
# ─────────────────────────────────────────────
echo "--- No mission active ---"

rm -rf "$TEST_DIR/.mission"
assert_allowed "No state file → Write allowed" "Write" '{"file_path":"/tmp/foo.ts"}'
assert_allowed "No state file → Edit allowed" "Edit" '{"file_path":"/tmp/foo.ts"}'
assert_allowed "No state file → Bash allowed" "Bash" '{"command":"npm test"}'
assert_allowed "No state file → Agent allowed" "Agent" '{"subagent_type":"validator"}'

create_state "orchestrator" "false"
assert_allowed "active=false → Write allowed" "Write" '{"file_path":"/tmp/foo.ts"}'

# ─────────────────────────────────────────────
# TEST GROUP: Orchestrator phase
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator phase ---"

create_state "orchestrator"
assert_allowed "Orch: Write to .mission/plan.md" "Write" '{"file_path":".mission/plan.md"}'
assert_allowed "Orch: Write to .mission/state.json" "Write" '{"file_path":".mission/state.json"}'
assert_blocked "Orch: Write to src/index.ts" "Write" '{"file_path":"src/index.ts"}'
assert_blocked "Orch: Write to app.py" "Write" '{"file_path":"app.py"}'
assert_allowed "Orch: Edit .mission/plan.md" "Edit" '{"file_path":".mission/plan.md"}'
assert_blocked "Orch: Edit src/index.ts" "Edit" '{"file_path":"src/index.ts"}'
assert_allowed "Orch: Bash git log" "Bash" '{"command":"git log --oneline -10"}'
assert_allowed "Orch: Bash ls" "Bash" '{"command":"ls -la"}'
assert_allowed "Orch: Agent worker" "Agent" '{"subagent_type":"mission-worker"}'
assert_allowed "Orch: Agent validator" "Agent" '{"subagent_type":"mission-validator"}'
assert_allowed "Orch: Agent explore" "Agent" '{"subagent_type":"Explore"}'

# ─────────────────────────────────────────────
# TEST GROUP: Worker phase
# ─────────────────────────────────────────────
echo ""
echo "--- Worker phase ---"

create_state "worker"
assert_allowed "Worker: Write src/index.ts" "Write" '{"file_path":"src/index.ts"}'
assert_allowed "Worker: Write new file" "Write" '{"file_path":"src/routes/api.ts"}'
assert_blocked "Worker: Write .mission/state.json" "Write" '{"file_path":".mission/state.json"}'
assert_allowed "Worker: Write .mission/worker-logs/worker-1.md" "Write" '{"file_path":".mission/worker-logs/worker-1.md"}'
assert_allowed "Worker: Edit src/index.ts" "Edit" '{"file_path":"src/index.ts"}'
assert_blocked "Worker: Edit .mission/state.json" "Edit" '{"file_path":".mission/state.json"}'
assert_blocked "Worker: Bash npm test" "Bash" '{"command":"npm test"}'
assert_blocked "Worker: Bash npx jest" "Bash" '{"command":"npx jest --coverage"}'
assert_blocked "Worker: Bash pytest" "Bash" '{"command":"pytest tests/"}'
assert_blocked "Worker: Bash go test" "Bash" '{"command":"go test ./..."}'
assert_blocked "Worker: Bash cargo test" "Bash" '{"command":"cargo test"}'
assert_blocked "Worker: Bash make test" "Bash" '{"command":"make test"}'
assert_blocked "Worker: Bash python -m pytest" "Bash" '{"command":"python -m pytest"}'
assert_blocked "Worker: Bash npx vitest" "Bash" '{"command":"npx vitest run"}'
assert_blocked "Worker: Bash yarn test" "Bash" '{"command":"yarn test"}'
assert_blocked "Worker: Bash pnpm test" "Bash" '{"command":"pnpm test"}'
assert_blocked "Worker: Bash bundle exec rspec" "Bash" '{"command":"bundle exec rspec"}'
assert_blocked "Worker: Bash phpunit" "Bash" '{"command":"phpunit tests/"}'
assert_blocked "Worker: Bash gradle test" "Bash" '{"command":"gradle test"}'
assert_blocked "Worker: Bash mvn test" "Bash" '{"command":"mvn test"}'
assert_allowed "Worker: Bash npm install" "Bash" '{"command":"npm install express"}'
assert_allowed "Worker: Bash npm run build" "Bash" '{"command":"npm run build"}'
assert_allowed "Worker: Bash mkdir test-fixtures" "Bash" '{"command":"mkdir test-fixtures"}'
assert_allowed "Worker: Bash tsc" "Bash" '{"command":"tsc --noEmit"}'
assert_blocked "Worker: Agent validator" "Agent" '{"subagent_type":"mission-validator"}'
assert_allowed "Worker: Agent sub-worker" "Agent" '{"subagent_type":"mission-worker"}'
assert_allowed "Worker: Agent explore" "Agent" '{"subagent_type":"Explore"}'

# ─────────────────────────────────────────────
# TEST GROUP: Validator phase
# ─────────────────────────────────────────────
echo ""
echo "--- Validator phase ---"

create_state "validator"
assert_allowed "Validator: Write src/index.test.ts" "Write" '{"file_path":"src/index.test.ts"}'
assert_allowed "Validator: Write src/app.spec.ts" "Write" '{"file_path":"src/app.spec.ts"}'
assert_allowed "Validator: Write tests/test_main.py" "Write" '{"file_path":"tests/test_main.py"}'
assert_allowed "Validator: Write main_test.go" "Write" '{"file_path":"main_test.go"}'
assert_allowed "Validator: Write __tests__/app.js" "Write" '{"file_path":"__tests__/app.js"}'
assert_allowed "Validator: Write .mission/reports/round-1.md" "Write" '{"file_path":".mission/reports/round-1.md"}'
assert_blocked "Validator: Write src/index.ts" "Write" '{"file_path":"src/index.ts"}'
assert_blocked "Validator: Write app.py" "Write" '{"file_path":"app.py"}'
assert_blocked "Validator: Write main.go" "Write" '{"file_path":"main.go"}'
assert_allowed "Validator: Edit src/index.test.ts" "Edit" '{"file_path":"src/index.test.ts"}'
assert_allowed "Validator: Edit src/app.spec.ts" "Edit" '{"file_path":"src/app.spec.ts"}'
assert_blocked "Validator: Edit src/index.ts" "Edit" '{"file_path":"src/index.ts"}'
assert_allowed "Validator: Bash npm test" "Bash" '{"command":"npm test"}'
assert_allowed "Validator: Bash npx jest" "Bash" '{"command":"npx jest --coverage"}'
assert_allowed "Validator: Bash tsc" "Bash" '{"command":"tsc --noEmit"}'
assert_blocked "Validator: Agent worker" "Agent" '{"subagent_type":"mission-worker"}'
assert_allowed "Validator: Agent sub-validator" "Agent" '{"subagent_type":"mission-validator"}'
assert_allowed "Validator: Agent explore" "Agent" '{"subagent_type":"Explore"}'

# ─────────────────────────────────────────────
# TEST GROUP: Edge cases
# ─────────────────────────────────────────────
echo ""
echo "--- Edge cases ---"

create_state "orchestrator"
assert_allowed "Orch: Write .mission/summary.md" "Write" '{"file_path":".mission/summary.md"}'
assert_blocked "Orch: Write .mission-fake/hack.ts" "Write" '{"file_path":".mission-fake/hack.ts"}'

create_state "worker"
assert_allowed "Worker: Write to path with test in dir name" "Write" '{"file_path":"test-fixtures/data.json"}'
assert_blocked "Worker: Bash npx jest (with args)" "Bash" '{"command":"npx jest --watchAll"}'

create_state "validator"
assert_allowed "Validator: Write nested test file" "Write" '{"file_path":"src/utils/__tests__/helper.test.ts"}'
assert_allowed "Validator: Write _spec.rb file" "Write" '{"file_path":"spec/models/user_spec.rb"}'
assert_blocked "Validator: Write package.json" "Write" '{"file_path":"package.json"}'

# ─────────────────────────────────────────────
# TEST GROUP: Path traversal attacks
# ─────────────────────────────────────────────
echo ""
echo "--- Path traversal attacks ---"

create_state "worker"
assert_blocked "Worker: Write .mission/state.json via traversal" "Write" '{"file_path":"src/../.mission/state.json"}'
assert_blocked "Worker: Edit .mission/state.json via traversal" "Edit" '{"file_path":"foo/bar/../../.mission/state.json"}'

create_state "orchestrator"
assert_blocked "Orch: Write source via .mission/../src traversal" "Write" '{"file_path":".mission/../src/index.ts"}'

create_state "validator"
assert_blocked "Validator: Write source via traversal" "Write" '{"file_path":"tests/../src/index.ts"}'
assert_allowed "Validator: Write test file via normalized path" "Write" '{"file_path":"src/../tests/test_main.py"}'

# ─────────────────────────────────────────────
# TEST GROUP: Bug fixes regression
# ─────────────────────────────────────────────
echo ""
echo "--- Bug fixes regression ---"

# Bug 2: python3 -m pytest test coverage
create_state "worker"
assert_blocked "Worker: Bash python3 -m pytest" "Bash" '{"command":"python3 -m pytest tests/"}'

# Bug 3: spec/ directory for Validator
create_state "validator"
assert_allowed "Validator: Write spec/support/helpers.rb (spec dir)" "Write" '{"file_path":"spec/support/helpers.rb"}'
assert_allowed "Validator: Write spec/factories/user.rb (spec dir)" "Write" '{"file_path":"spec/factories/user.rb"}'

# Bug 4: Absolute paths
create_state "orchestrator"
assert_allowed "Orch: Write absolute .mission/plan.md" "Write" '{"file_path":"/home/user/project/.mission/plan.md"}'
assert_blocked "Orch: Write absolute source file" "Write" '{"file_path":"/home/user/project/src/index.ts"}'

create_state "worker"
assert_blocked "Worker: Write absolute .mission/state.json" "Write" '{"file_path":"/home/user/project/.mission/state.json"}'
assert_blocked "Worker: Write absolute .mission/plan.md" "Write" '{"file_path":"/home/user/project/.mission/plan.md"}'
assert_allowed "Worker: Write absolute source file" "Write" '{"file_path":"/home/user/project/src/index.ts"}'
assert_allowed "Worker: Write absolute worker-log" "Write" '{"file_path":"/home/user/project/.mission/worker-logs/worker-1.md"}'

# Bug 6: Worker blocked from .mission/plan.md and .mission/reports
create_state "worker"
assert_blocked "Worker: Write .mission/plan.md" "Write" '{"file_path":".mission/plan.md"}'
assert_blocked "Worker: Write .mission/reports/round-1.md" "Write" '{"file_path":".mission/reports/round-1.md"}'
assert_blocked "Worker: Write .mission/summary.md" "Write" '{"file_path":".mission/summary.md"}'
assert_allowed "Worker: Write .mission/worker-logs/worker-1.md" "Write" '{"file_path":".mission/worker-logs/worker-1.md"}'
assert_blocked "Worker: Edit .mission/plan.md" "Edit" '{"file_path":".mission/plan.md"}'

# Bug 9: Validator blocked from .mission/state.json
create_state "validator"
assert_blocked "Validator: Write .mission/state.json" "Write" '{"file_path":".mission/state.json"}'
assert_blocked "Validator: Edit .mission/state.json" "Edit" '{"file_path":".mission/state.json"}'
assert_allowed "Validator: Write .mission/reports/round-1.md" "Write" '{"file_path":".mission/reports/round-1.md"}'

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo "=== Results ==="
echo "PASSED: $PASSED / $TOTAL"
echo "FAILED: $FAILED / $TOTAL"

if [ "$FAILED" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
