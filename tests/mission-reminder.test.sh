#!/usr/bin/env bash
# tests/mission-reminder.test.sh — Tests for hooks/mission-reminder.sh
# Run: bash tests/mission-reminder.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$PROJECT_DIR/hooks/mission-reminder.sh"
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
  local active="$1"
  local phase="${2:-orchestrator}"
  local round="${3:-1}"
  local task="${4:-test task}"
  local action="${5:-}"
  mkdir -p "$TEST_DIR/.mission"
  cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": $active,
  "phase": "$phase",
  "task": "$task",
  "round": $round,
  "currentAction": "$action"
}
STATEEOF
}

# Helper: run mission-reminder.sh in test dir context and capture output + exit code
run_hook() {
  local output
  local exit_code
  output=$(cd "$TEST_DIR" && bash "$HOOK_SCRIPT" 2>&1) || exit_code=$?
  exit_code=${exit_code:-0}
  echo "$output"
  return $exit_code
}

assert_output_contains() {
  local desc="$1"
  local expected="$2"
  TOTAL=$((TOTAL + 1))
  local output
  local exit_code
  output=$(run_hook 2>&1) || exit_code=$?
  exit_code=${exit_code:-0}
  if [ "$exit_code" -ne 0 ]; then
    echo "FAIL: $desc — script exited with code $exit_code"
    echo "  output: $output"
    FAILED=$((FAILED + 1))
    return
  fi
  if echo "$output" | grep -qF "$expected"; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected output to contain: $expected"
    echo "  actual output: $output"
    FAILED=$((FAILED + 1))
  fi
}

assert_silent_exit() {
  local desc="$1"
  TOTAL=$((TOTAL + 1))
  local output
  local exit_code
  output=$(run_hook 2>&1) || exit_code=$?
  exit_code=${exit_code:-0}
  if [ "$exit_code" -ne 0 ]; then
    echo "FAIL: $desc — script exited with code $exit_code"
    echo "  output: $output"
    FAILED=$((FAILED + 1))
    return
  fi
  if [ -z "$output" ]; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected no output but got: $output"
    FAILED=$((FAILED + 1))
  fi
}

assert_exit_zero() {
  local desc="$1"
  TOTAL=$((TOTAL + 1))
  local output
  local exit_code
  output=$(run_hook 2>&1) || exit_code=$?
  exit_code=${exit_code:-0}
  if [ "$exit_code" -eq 0 ]; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected exit 0 but got exit $exit_code"
    echo "  output: $output"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== Mission Reminder Hook Tests ==="
echo ""

# ─────────────────────────────────────────────
# TEST GROUP: No state file
# ─────────────────────────────────────────────
echo "--- No state file ---"

rm -rf "$TEST_DIR/.mission"
assert_silent_exit "No state file → silent exit 0"
assert_exit_zero "No state file → exit code 0"

# ─────────────────────────────────────────────
# TEST GROUP: Inactive mission
# ─────────────────────────────────────────────
echo ""
echo "--- Inactive mission ---"

create_state "false" "orchestrator" "1"
assert_silent_exit "active=false → silent exit 0"
assert_exit_zero "active=false → exit code 0"

# ─────────────────────────────────────────────
# TEST GROUP: Non-orchestrator phases → silent
# ─────────────────────────────────────────────
echo ""
echo "--- Non-orchestrator phases (should be silent) ---"

create_state "true" "worker" "1"
assert_silent_exit "Worker phase → silent exit 0"
assert_exit_zero "Worker phase → exit code 0"

create_state "true" "validator" "2"
assert_silent_exit "Validator phase → silent exit 0"
assert_exit_zero "Validator phase → exit code 0"

create_state "true" "complete" "3"
assert_silent_exit "Complete phase → silent exit 0"

# ─────────────────────────────────────────────
# TEST GROUP: Orchestrator active — reminder output
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator active: reminder output ---"

create_state "true" "orchestrator" "1" "build auth system"
assert_output_contains "Active orchestrator → contains MISSION SKILL ACTIVE" "[MISSION SKILL ACTIVE"
assert_output_contains "Active orchestrator → contains DO NOT DEVIATE" "DO NOT DEVIATE"
assert_output_contains "Active orchestrator → contains Phase: ORCHESTRATOR" "Phase: ORCHESTRATOR"
assert_output_contains "Active orchestrator → contains Round: 1" "Round: 1"
assert_output_contains "Active orchestrator → contains task description" "build auth system"

create_state "true" "orchestrator" "3" "fix login bug"
assert_output_contains "Round 3 → contains Round: 3" "Round: 3"
assert_output_contains "Round 3 → contains task" "fix login bug"

# ─────────────────────────────────────────────
# TEST GROUP: Plan existence changes reminder
# ─────────────────────────────────────────────
echo ""
echo "--- Plan existence affects reminder ---"

create_state "true" "orchestrator" "1" "test task" "researching"
rm -f "$TEST_DIR/.mission/plan.md"
assert_output_contains "No plan → mentions writing plan.md" "plan.md"

# Create plan file
create_state "true" "orchestrator" "1" "test task" "dispatching workers"
echo "# Plan" > "$TEST_DIR/.mission/plan.md"
assert_output_contains "Plan exists → mentions mission loop" "mission loop"
assert_output_contains "Plan exists → mentions dispatch" "dispatch"

# ─────────────────────────────────────────────
# TEST GROUP: Always exits 0 (never blocks)
# ─────────────────────────────────────────────
echo ""
echo "--- Always exits 0 (never blocks) ---"

create_state "true" "orchestrator" "1"
assert_exit_zero "Active orchestrator → exit 0"

create_state "false" "worker" "1"
assert_exit_zero "Inactive worker → exit 0"

rm -rf "$TEST_DIR/.mission"
assert_exit_zero "No state file → exit 0"

# ─────────────────────────────────────────────
# TEST GROUP: Edge cases
# ─────────────────────────────────────────────
echo ""
echo "--- Edge cases ---"

# Missing phase field — grep returns empty → not orchestrator → silent
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "task": "test task",
  "round": 1
}
STATEEOF
assert_silent_exit "Missing phase field → silent exit (not orchestrator)"

# Missing active field — defaults to not active → silent
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "phase": "orchestrator",
  "task": "test task",
  "round": 1
}
STATEEOF
assert_silent_exit "Missing active field → silent exit"

# Empty JSON object
mkdir -p "$TEST_DIR/.mission"
echo '{}' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Empty JSON → silent exit"
assert_exit_zero "Empty JSON → exit 0"

# Malformed JSON
mkdir -p "$TEST_DIR/.mission"
echo 'this is not json' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Malformed JSON → silent exit"
assert_exit_zero "Malformed JSON → exit 0"

# Empty file
mkdir -p "$TEST_DIR/.mission"
echo -n '' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Empty file → silent exit"
assert_exit_zero "Empty file → exit 0"

# ─────────────────────────────────────────────
# TEST GROUP: Output format
# ─────────────────────────────────────────────
echo ""
echo "--- Output format ---"

create_state "true" "orchestrator" "1"
TOTAL=$((TOTAL + 1))
output=$(run_hook 2>&1)
# Verify it is exactly one line
line_count=$(echo "$output" | wc -l)
if [ "$line_count" -eq 1 ]; then
  echo "PASS: Output is exactly one line"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Output should be one line, got $line_count lines"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# Verify output starts with [MISSION SKILL ACTIVE
TOTAL=$((TOTAL + 1))
if echo "$output" | grep -q '^\[MISSION SKILL ACTIVE'; then
  echo "PASS: Output starts with [MISSION SKILL ACTIVE"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Output should start with [MISSION SKILL ACTIVE"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# ─────────────────────────────────────────────
# TEST GROUP: Subdirectory behavior
# ─────────────────────────────────────────────
echo ""
echo "--- Subdirectory search ---"

create_state "true" "orchestrator" "2"
mkdir -p "$TEST_DIR/src/components/deep"
TOTAL=$((TOTAL + 1))
output=$(cd "$TEST_DIR/src/components/deep" && bash "$HOOK_SCRIPT" 2>&1) || true
if echo "$output" | grep -qF "[MISSION SKILL ACTIVE"; then
  echo "PASS: Subdir search → finds state.json from nested dir"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Subdir search → should find state.json from nested dir"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# Subdirectory with worker phase → still silent
create_state "true" "worker" "1"
mkdir -p "$TEST_DIR/src/lib"
TOTAL=$((TOTAL + 1))
output=$(cd "$TEST_DIR/src/lib" && bash "$HOOK_SCRIPT" 2>&1) || true
if [ -z "$output" ]; then
  echo "PASS: Subdir worker phase → silent"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Subdir worker phase → should be silent"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

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
