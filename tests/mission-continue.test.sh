#!/usr/bin/env bash
# tests/mission-continue.test.sh — Tests for hooks/mission-continue.sh
# Run: bash tests/mission-continue.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$PROJECT_DIR/hooks/mission-continue.sh"
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
  mkdir -p "$TEST_DIR/.mission"
  cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": $active,
  "phase": "$phase",
  "task": "test task",
  "round": $round
}
STATEEOF
}

# Helper: run mission-continue.sh in test dir context and capture output + exit code
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

echo "=== Mission Continue Hook Tests ==="
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
# TEST GROUP: Active mission — continuation reminder
# ─────────────────────────────────────────────
echo ""
echo "--- Active mission: continuation reminder ---"

create_state "true" "orchestrator" "1"
assert_output_contains "Active orchestrator phase → contains [MISSION ACTIVE]" "[MISSION ACTIVE]"

create_state "true" "orchestrator" "1"
assert_output_contains "Active orchestrator phase → contains Phase: orchestrator" "Phase: orchestrator"

create_state "true" "orchestrator" "1"
assert_output_contains "Active orchestrator phase → contains Round: 1" "Round: 1"

create_state "true" "worker" "2"
assert_output_contains "Active worker phase round 2 → contains Phase: worker" "Phase: worker"

create_state "true" "worker" "2"
assert_output_contains "Active worker phase round 2 → contains Round: 2" "Round: 2"

create_state "true" "validator" "3"
assert_output_contains "Active validator phase round 3 → contains Phase: validator" "Phase: validator"

create_state "true" "validator" "3"
assert_output_contains "Active validator phase round 3 → contains Round: 3" "Round: 3"

# Verify the full continuation instruction is present
create_state "true" "orchestrator" "1"
assert_output_contains "Continuation instruction present" "Do NOT end your response"

create_state "true" "orchestrator" "1"
assert_output_contains "Action instruction present" "Continue the mission loop"

# ─────────────────────────────────────────────
# TEST GROUP: Always exits 0
# ─────────────────────────────────────────────
echo ""
echo "--- Always exits 0 (never blocks) ---"

create_state "true" "orchestrator" "1"
assert_exit_zero "Active mission → exit 0"

create_state "false" "worker" "1"
assert_exit_zero "Inactive mission → exit 0"

rm -rf "$TEST_DIR/.mission"
assert_exit_zero "No state file → exit 0"

# ─────────────────────────────────────────────
# TEST GROUP: Edge cases in state.json
# ─────────────────────────────────────────────
echo ""
echo "--- Edge cases ---"

# Missing phase field — should default to "unknown"
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "task": "test task",
  "round": 1
}
STATEEOF
assert_output_contains "Missing phase → defaults to unknown" "Phase: unknown"
assert_exit_zero "Missing phase → exit 0"

# Missing round field — should default to 1
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "phase": "worker",
  "task": "test task"
}
STATEEOF
assert_output_contains "Missing round → defaults to 1" "Round: 1"

# Missing active field — should default to false (silent exit)
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "phase": "worker",
  "task": "test task",
  "round": 1
}
STATEEOF
assert_silent_exit "Missing active field → defaults to false, silent exit"

# Empty JSON object
mkdir -p "$TEST_DIR/.mission"
echo '{}' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Empty JSON object → defaults to active=false, silent exit"
assert_exit_zero "Empty JSON object → exit 0"

# Malformed JSON — python3 fails, fallback to "false", silent exit
mkdir -p "$TEST_DIR/.mission"
echo 'this is not json' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Malformed JSON → python3 error caught, silent exit"
assert_exit_zero "Malformed JSON → exit 0"

# Empty file
mkdir -p "$TEST_DIR/.mission"
echo -n '' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Empty file → python3 error caught, silent exit"
assert_exit_zero "Empty file → exit 0"

# Large round number
create_state "true" "validator" "99"
assert_output_contains "Large round number → Round: 99" "Round: 99"

# Phase with special characters (should just pass through)
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "phase": "complete",
  "task": "test task",
  "round": 5
}
STATEEOF
assert_output_contains "Complete phase → Phase: complete" "Phase: complete"

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

# Verify output starts with [MISSION ACTIVE]
TOTAL=$((TOTAL + 1))
if echo "$output" | grep -q '^\[MISSION ACTIVE\]'; then
  echo "PASS: Output starts with [MISSION ACTIVE]"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Output should start with [MISSION ACTIVE]"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# ─────────────────────────────────────────────
# TEST GROUP: Subdirectory behavior (find_state_file walks upward)
# ─────────────────────────────────────────────
echo ""
echo "--- Subdirectory search ---"

create_state "true" "worker" "2"
mkdir -p "$TEST_DIR/src/components/deep"
TOTAL=$((TOTAL + 1))
output=$(cd "$TEST_DIR/src/components/deep" && bash "$HOOK_SCRIPT" 2>&1) || true
if echo "$output" | grep -qF "[MISSION ACTIVE]"; then
  echo "PASS: Subdir search → finds state.json from nested dir"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Subdir search → should find state.json from nested dir"
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
