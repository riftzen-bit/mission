#!/usr/bin/env bash
# tests/mission-continue.test.sh — Tests for hooks/mission-continue.sh (v0.5.0)
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
  local task="${4:-test task}"
  local action="${5:-planning}"
  local persistence="${6:-relentless}"
  mkdir -p "$TEST_DIR/.mission"
  cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": $active,
  "phase": "$phase",
  "task": "$task",
  "round": $round,
  "currentAction": "$action",
  "persistence": "$persistence",
  "workers": []
}
STATEEOF
}

# Helper: create state with workers
create_state_with_workers() {
  local active="$1"
  local phase="${2:-orchestrator}"
  local round="${3:-1}"
  local w_completed="${4:-0}"
  local w_total="${5:-2}"
  mkdir -p "$TEST_DIR/.mission"

  local workers="["
  for ((i=1; i<=w_total; i++)); do
    if [ "$i" -le "$w_completed" ]; then
      workers="$workers{\"name\":\"worker-$i\",\"status\":\"completed\"}"
    else
      workers="$workers{\"name\":\"worker-$i\",\"status\":\"in_progress\"}"
    fi
    if [ "$i" -lt "$w_total" ]; then
      workers="$workers,"
    fi
  done
  workers="$workers]"

  cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": $active,
  "phase": "$phase",
  "task": "test task",
  "round": $round,
  "currentAction": "dispatching",
  "persistence": "relentless",
  "workers": $workers
}
STATEEOF
}

# Helper: run mission-continue.sh with tool name in test dir
run_hook() {
  local tool_name="${1:-unknown}"
  local output
  local exit_code
  output=$(cd "$TEST_DIR" && bash "$HOOK_SCRIPT" "$tool_name" 2>&1) || exit_code=$?
  exit_code=${exit_code:-0}
  echo "$output"
  return $exit_code
}

assert_output_contains() {
  local desc="$1"
  local tool_name="$2"
  local expected="$3"
  TOTAL=$((TOTAL + 1))
  local output
  local exit_code
  output=$(run_hook "$tool_name" 2>&1) || exit_code=$?
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

assert_output_not_contains() {
  local desc="$1"
  local tool_name="$2"
  local unexpected="$3"
  TOTAL=$((TOTAL + 1))
  local output
  local exit_code
  output=$(run_hook "$tool_name" 2>&1) || exit_code=$?
  exit_code=${exit_code:-0}
  if echo "$output" | grep -qF "$unexpected"; then
    echo "FAIL: $desc — output should NOT contain: $unexpected"
    echo "  actual output: $output"
    FAILED=$((FAILED + 1))
  else
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  fi
}

assert_silent_exit() {
  local desc="$1"
  local tool_name="${2:-unknown}"
  TOTAL=$((TOTAL + 1))
  local output
  local exit_code
  output=$(run_hook "$tool_name" 2>&1) || exit_code=$?
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
  local tool_name="${2:-unknown}"
  TOTAL=$((TOTAL + 1))
  local output
  local exit_code
  output=$(run_hook "$tool_name" 2>&1) || exit_code=$?
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

echo "=== Mission Continue Hook Tests (v0.5.0) ==="
echo ""

# ─────────────────────────────────────────────
# TEST GROUP: No state file
# ─────────────────────────────────────────────
echo "--- No state file ---"

rm -rf "$TEST_DIR/.mission"
assert_silent_exit "No state file → silent exit 0" "Agent"
assert_exit_zero "No state file → exit code 0" "Read"

# ─────────────────────────────────────────────
# TEST GROUP: Inactive mission
# ─────────────────────────────────────────────
echo ""
echo "--- Inactive mission ---"

create_state "false" "orchestrator" "1"
assert_silent_exit "active=false, Agent → silent exit 0" "Agent"
assert_silent_exit "active=false, Read → silent exit 0" "Read"
assert_exit_zero "active=false → exit code 0" "Write"

# ─────────────────────────────────────────────
# TEST GROUP: Worker phase — silent for non-Agent, brief for Agent
# ─────────────────────────────────────────────
echo ""
echo "--- Worker phase ---"

create_state "true" "worker" "2"
assert_silent_exit "Worker + Read → silent" "Read"
assert_silent_exit "Worker + Write → silent" "Write"
assert_silent_exit "Worker + Grep → silent" "Grep"
assert_silent_exit "Worker + Bash → silent" "Bash"
assert_output_contains "Worker + Agent → brief reminder" "Agent" "[MISSION ACTIVE]"
assert_output_contains "Worker + Agent → contains phase" "Agent" "Phase: worker"
assert_output_contains "Worker + Agent → contains round" "Agent" "Round: 2"
assert_output_contains "Worker + Agent → contains continue" "Agent" "Continue your assigned task"

# ─────────────────────────────────────────────
# TEST GROUP: Validator phase — same as worker
# ─────────────────────────────────────────────
echo ""
echo "--- Validator phase ---"

create_state "true" "validator" "3"
assert_silent_exit "Validator + Read → silent" "Read"
assert_silent_exit "Validator + Write → silent" "Write"
assert_silent_exit "Validator + Glob → silent" "Glob"
assert_output_contains "Validator + Agent → brief reminder" "Agent" "[MISSION ACTIVE]"
assert_output_contains "Validator + Agent → contains phase" "Agent" "Phase: validator"
assert_output_contains "Validator + Agent → contains round 3" "Agent" "Round: 3"

# ─────────────────────────────────────────────
# TEST GROUP: Orchestrator + Agent → STRONGEST reminder
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator + Agent (strongest) ---"

create_state "true" "orchestrator" "1" "build auth system" "dispatching workers" "relentless"
assert_output_contains "Orch+Agent → MANDATORY CONTINUATION" "Agent" "MANDATORY CONTINUATION"
assert_output_contains "Orch+Agent → Phase ORCHESTRATOR" "Agent" "Phase: ORCHESTRATOR"
assert_output_contains "Orch+Agent → Round: 1" "Agent" "Round: 1"
assert_output_contains "Orch+Agent → Persistence RELENTLESS" "Agent" "RELENTLESS"
assert_output_contains "Orch+Agent → contains task" "Agent" "build auth system"
assert_output_contains "Orch+Agent → DO NOT STOP" "Agent" "DO NOT STOP"
assert_output_contains "Orch+Agent → next steps guidance" "Agent" "NEXT STEPS"
assert_output_contains "Orch+Agent → mentions validator" "Agent" "validator"
assert_output_contains "Orch+Agent → mentions state.json" "Agent" "state.json"

# ─────────────────────────────────────────────
# TEST GROUP: Orchestrator + Read/Grep/Glob → medium reminder
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator + Read/Grep/Glob (medium) ---"

create_state "true" "orchestrator" "2" "fix login bug"
assert_output_contains "Orch+Read → MISSION ACTIVE" "Read" "[MISSION ACTIVE]"
assert_output_contains "Orch+Read → contains task" "Read" "fix login bug"
assert_output_contains "Orch+Read → mentions mission skill" "Read" "mission skill"
assert_output_not_contains "Orch+Read → NOT strongest" "Read" "MANDATORY CONTINUATION"

assert_output_contains "Orch+Grep → MISSION ACTIVE" "Grep" "[MISSION ACTIVE]"
assert_output_contains "Orch+Glob → MISSION ACTIVE" "Glob" "[MISSION ACTIVE]"

# ─────────────────────────────────────────────
# TEST GROUP: Orchestrator + Write/Edit → medium reminder
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator + Write/Edit (medium) ---"

create_state "true" "orchestrator" "1" "test task" "writing plan"
assert_output_contains "Orch+Write → MISSION ACTIVE" "Write" "[MISSION ACTIVE]"
assert_output_contains "Orch+Write → mentions loop" "Write" "mission loop"
assert_output_contains "Orch+Edit → MISSION ACTIVE" "Edit" "[MISSION ACTIVE]"
assert_output_not_contains "Orch+Write → NOT strongest" "Write" "MANDATORY CONTINUATION"

# ─────────────────────────────────────────────
# TEST GROUP: Orchestrator + Bash → medium reminder
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator + Bash (medium) ---"

create_state "true" "orchestrator" "1"
assert_output_contains "Orch+Bash → MISSION ACTIVE" "Bash" "[MISSION ACTIVE]"
assert_output_contains "Orch+Bash → mentions loop" "Bash" "mission loop"
assert_output_not_contains "Orch+Bash → NOT strongest" "Bash" "MANDATORY CONTINUATION"

# ─────────────────────────────────────────────
# TEST GROUP: Orchestrator + unknown tool → light reminder
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator + unknown tool (light) ---"

create_state "true" "orchestrator" "1"
assert_output_contains "Orch+unknown → MISSION ACTIVE" "TaskCreate" "[MISSION ACTIVE]"
assert_output_contains "Orch+unknown → mentions skill" "TaskCreate" "skill"

# ─────────────────────────────────────────────
# TEST GROUP: Worker count in Agent reminder
# ─────────────────────────────────────────────
echo ""
echo "--- Worker count in Agent reminder ---"

create_state_with_workers "true" "orchestrator" "1" "1" "3"
assert_output_contains "Workers 1/3 → shows count" "Agent" "Workers: 1/3"

create_state_with_workers "true" "orchestrator" "2" "2" "2"
assert_output_contains "Workers 2/2 → shows count" "Agent" "Workers: 2/2"

# ─────────────────────────────────────────────
# TEST GROUP: Always exits 0
# ─────────────────────────────────────────────
echo ""
echo "--- Always exits 0 (never blocks) ---"

create_state "true" "orchestrator" "1"
assert_exit_zero "Active orchestrator + Agent → exit 0" "Agent"
assert_exit_zero "Active orchestrator + Read → exit 0" "Read"

create_state "true" "worker" "1"
assert_exit_zero "Active worker + Read → exit 0" "Read"

create_state "false" "orchestrator" "1"
assert_exit_zero "Inactive + Agent → exit 0" "Agent"

rm -rf "$TEST_DIR/.mission"
assert_exit_zero "No state file + Agent → exit 0" "Agent"

# ─────────────────────────────────────────────
# TEST GROUP: Edge cases in state.json
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
assert_silent_exit "Missing phase → silent for Read" "Read"
# Missing phase + Agent → brief reminder (unknown phase enters non-orchestrator branch, Agent triggers output)
assert_output_contains "Missing phase + Agent → brief reminder" "Agent" "[MISSION ACTIVE]"

# Missing round in worker phase + Agent
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "phase": "worker",
  "task": "test task"
}
STATEEOF
assert_output_contains "Worker missing round → defaults to 1" "Agent" "Round: 1"

# Empty JSON object
mkdir -p "$TEST_DIR/.mission"
echo '{}' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Empty JSON → silent" "Agent"
assert_exit_zero "Empty JSON → exit 0" "Agent"

# Malformed JSON
mkdir -p "$TEST_DIR/.mission"
echo 'not json at all' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Malformed JSON → silent" "Agent"
assert_exit_zero "Malformed JSON → exit 0" "Agent"

# Empty file
mkdir -p "$TEST_DIR/.mission"
echo -n '' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Empty file → silent" "Read"
assert_exit_zero "Empty file → exit 0" "Read"

# ─────────────────────────────────────────────
# TEST GROUP: Subdirectory behavior
# ─────────────────────────────────────────────
echo ""
echo "--- Subdirectory search ---"

create_state "true" "orchestrator" "2" "test task"
mkdir -p "$TEST_DIR/src/components/deep"
TOTAL=$((TOTAL + 1))
output=$(cd "$TEST_DIR/src/components/deep" && bash "$HOOK_SCRIPT" "Agent" 2>&1) || true
if echo "$output" | grep -qF "MANDATORY CONTINUATION"; then
  echo "PASS: Subdir orchestrator + Agent → strongest reminder"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Subdir orchestrator + Agent → should get strongest reminder"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

create_state "true" "worker" "1"
mkdir -p "$TEST_DIR/src/lib"
TOTAL=$((TOTAL + 1))
output=$(cd "$TEST_DIR/src/lib" && bash "$HOOK_SCRIPT" "Read" 2>&1) || true
if [ -z "$output" ]; then
  echo "PASS: Subdir worker + Read → silent"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Subdir worker + Read → should be silent"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# ─────────────────────────────────────────────
# TEST GROUP: No tool name argument → defaults to "unknown"
# ─────────────────────────────────────────────
echo ""
echo "--- No tool name argument ---"

create_state "true" "orchestrator" "1"
TOTAL=$((TOTAL + 1))
output=$(cd "$TEST_DIR" && bash "$HOOK_SCRIPT" 2>&1) || true
exit_code=$?
if echo "$output" | grep -qF "[MISSION ACTIVE]"; then
  echo "PASS: No tool name → still outputs reminder (light)"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: No tool name → should output light reminder"
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
