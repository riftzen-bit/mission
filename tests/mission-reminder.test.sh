#!/usr/bin/env bash
# tests/mission-reminder.test.sh — Tests for hooks/mission-reminder.py (Python v1.0)
# Run: bash tests/mission-reminder.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
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

# Helper: create features.json
create_features() {
  local status="${1:-in-progress}"
  local feature_id="${2:-F-001}"
  local description="${3:-Implement auth module}"
  mkdir -p "$TEST_DIR/.mission"
  cat > "$TEST_DIR/.mission/features.json" <<FEATEOF
{
  "features": [
    {
      "id": "$feature_id",
      "description": "$description",
      "status": "$status"
    }
  ]
}
FEATEOF
}

# Helper: create features.json with multiple features
create_multi_features() {
  mkdir -p "$TEST_DIR/.mission"
  cat > "$TEST_DIR/.mission/features.json" <<FEATEOF
{
  "features": [
    {
      "id": "F-001",
      "description": "Setup project",
      "status": "completed"
    },
    {
      "id": "F-002",
      "description": "Implement API routes",
      "status": "in-progress"
    },
    {
      "id": "F-003",
      "description": "Add tests",
      "status": "pending"
    }
  ]
}
FEATEOF
}

# Helper: run mission-reminder.py in test dir context and capture output + exit code
run_hook() {
  local tool_name="$1"
  cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-reminder.py" "$tool_name" 2>&1
  return 0
}

# Helper: run hook with no args
run_hook_no_args() {
  cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-reminder.py" 2>&1
  return 0
}

assert_output_contains() {
  local desc="$1"
  local expected="$2"
  local tool="${3:-Read}"
  TOTAL=$((TOTAL + 1))
  local output
  output=$(run_hook "$tool") || true
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
  local rejected="$2"
  local tool="${3:-Read}"
  TOTAL=$((TOTAL + 1))
  local output
  output=$(run_hook "$tool") || true
  if echo "$output" | grep -qF "$rejected"; then
    echo "FAIL: $desc — output should NOT contain: $rejected"
    echo "  actual output: $output"
    FAILED=$((FAILED + 1))
  else
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  fi
}

assert_silent_exit() {
  local desc="$1"
  local tool="${2:-Read}"
  TOTAL=$((TOTAL + 1))
  local output
  output=$(run_hook "$tool") || true
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
  local tool="${2:-Read}"
  TOTAL=$((TOTAL + 1))
  local exit_code=0
  cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-reminder.py" "$tool" >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected exit 0 but got exit $exit_code"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== Mission Reminder Hook Tests (Python v1.0) ==="
echo ""

# ─────────────────────────────────────────────
# TEST GROUP 1: Silent exits — no args, no state, inactive
# ─────────────────────────────────────────────
echo "--- Silent exits ---"

# No args
TOTAL=$((TOTAL + 1))
output=$(run_hook_no_args) || true
if [ -z "$output" ]; then
  echo "PASS: No args → silent exit 0"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: No args → expected silent exit but got: $output"
  FAILED=$((FAILED + 1))
fi

# No args → exit 0
TOTAL=$((TOTAL + 1))
exit_code=0
cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-reminder.py" >/dev/null 2>&1 || exit_code=$?
if [ "$exit_code" -eq 0 ]; then
  echo "PASS: No args → exit code 0"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: No args → expected exit 0 but got $exit_code"
  FAILED=$((FAILED + 1))
fi

# No state file
rm -rf "$TEST_DIR/.mission"
assert_silent_exit "No state file → silent exit 0"
assert_exit_zero "No state file → exit code 0"

# Inactive mission
create_state "false" "orchestrator" "1"
assert_silent_exit "active=false → silent exit 0"
assert_exit_zero "active=false → exit code 0"

# active as string "false"
mkdir -p "$TEST_DIR/.mission"
echo '{"active": "false", "phase": "orchestrator", "task": "t", "round": 1}' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "active='false' (string) → silent exit 0"

# ─────────────────────────────────────────────
# TEST GROUP 2: Orchestrator phase — no plan, no features
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator: no plan, no features (research phase) ---"

create_state "true" "orchestrator" "1" "build auth system" "researching options"
rm -f "$TEST_DIR/.mission/plan.md"
rm -f "$TEST_DIR/.mission/features.json"

assert_output_contains "Orch no-plan: contains MISSION SKILL ACTIVE" "[MISSION SKILL ACTIVE"
assert_output_contains "Orch no-plan: contains DO NOT DEVIATE" "DO NOT DEVIATE"
assert_output_contains "Orch no-plan: contains Phase: ORCHESTRATOR" "Phase: ORCHESTRATOR"
assert_output_contains "Orch no-plan: contains Round: 1" "Round: 1"
assert_output_contains "Orch no-plan: contains task" "build auth system"
assert_output_contains "Orch no-plan: contains features.json directive" "features.json"
assert_output_contains "Orch no-plan: contains dispatch directive" "dispatching Workers"
assert_output_contains "Orch no-plan: contains Current Action" "researching options"

# ─────────────────────────────────────────────
# TEST GROUP 3: Orchestrator phase — plan exists
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator: plan exists (dispatch/loop phase) ---"

create_state "true" "orchestrator" "2" "fix login bug" "dispatching workers"
echo "# Plan" > "$TEST_DIR/.mission/plan.md"
rm -f "$TEST_DIR/.mission/features.json"

assert_output_contains "Orch plan: contains MISSION SKILL ACTIVE" "[MISSION SKILL ACTIVE"
assert_output_contains "Orch plan: contains DO NOT DEVIATE" "DO NOT DEVIATE"
assert_output_contains "Orch plan: contains Phase: ORCHESTRATOR" "Phase: ORCHESTRATOR"
assert_output_contains "Orch plan: contains Round: 2" "Round: 2"
assert_output_contains "Orch plan: contains task" "fix login bug"
assert_output_contains "Orch plan: contains mission loop directive" "mission loop"
assert_output_contains "Orch plan: contains dispatch keyword" "dispatch"
assert_output_contains "Orch plan: contains Current Action" "dispatching workers"

# ─────────────────────────────────────────────
# TEST GROUP 4: Orchestrator — features.json exists (no plan)
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator: features exists (dispatch phase) ---"

create_state "true" "orchestrator" "1" "implement API"
rm -f "$TEST_DIR/.mission/plan.md"
create_features "in-progress" "F-001" "Implement auth module"

assert_output_contains "Orch features: contains mission loop" "mission loop"
assert_output_contains "Orch features: shows current feature" "F-001"
assert_output_contains "Orch features: shows feature description" "Implement auth module"

# ─────────────────────────────────────────────
# TEST GROUP 5: Worker phase
# ─────────────────────────────────────────────
echo ""
echo "--- Worker phase ---"

create_state "true" "worker" "3" "build API routes"
create_features "in-progress" "F-002" "Implement API routes"

assert_output_contains "Worker: contains MISSION SKILL ACTIVE" "[MISSION SKILL ACTIVE]"
assert_output_contains "Worker: contains Phase: WORKER" "Phase: WORKER"
assert_output_contains "Worker: contains Round: 3" "Round: 3"
assert_output_contains "Worker: contains task" "build API routes"
assert_output_contains "Worker: contains Feature with id" "F-002"
assert_output_contains "Worker: contains feature description" "Implement API routes"
assert_output_contains "Worker: contains handoff directive" "handoff"
assert_output_contains "Worker: contains test file restriction" "DO NOT write test files"

# ─────────────────────────────────────────────
# TEST GROUP 6: Validator phase
# ─────────────────────────────────────────────
echo ""
echo "--- Validator phase ---"

create_state "true" "validator" "2" "validate auth"
create_features "in-progress" "F-001" "Auth module"

assert_output_contains "Validator: contains MISSION SKILL ACTIVE" "[MISSION SKILL ACTIVE]"
assert_output_contains "Validator: contains Phase: VALIDATOR" "Phase: VALIDATOR"
assert_output_contains "Validator: contains Round: 2" "Round: 2"
assert_output_contains "Validator: contains task" "validate auth"
assert_output_contains "Validator: contains Feature with id" "F-001"
assert_output_contains "Validator: contains feature description" "Auth module"
assert_output_contains "Validator: contains test directive" "Write tests"
assert_output_contains "Validator: contains reports directive" ".mission/reports/"
assert_output_contains "Validator: contains source file restriction" "DO NOT modify source files"

# ─────────────────────────────────────────────
# TEST GROUP 7: Role content separation
# ─────────────────────────────────────────────
echo ""
echo "--- Role content separation ---"

# Orchestrator should have dispatch/loop, NOT handoff/test files
create_state "true" "orchestrator" "1" "task1"
echo "# Plan" > "$TEST_DIR/.mission/plan.md"
rm -f "$TEST_DIR/.mission/features.json"

assert_output_contains "Orch separation: has dispatch" "dispatch"
assert_output_not_contains "Orch separation: no handoff" "handoff"
assert_output_not_contains "Orch separation: no test files" "DO NOT write test files"
assert_output_not_contains "Orch separation: no Write tests" "Write tests"
assert_output_not_contains "Orch separation: no source files" "DO NOT modify source files"

# Worker should have handoff, NOT dispatch/loop/validate
create_state "true" "worker" "1" "task1"
create_features "in-progress" "F-001" "feature1"

assert_output_contains "Worker separation: has handoff" "handoff"
assert_output_contains "Worker separation: has test file restriction" "DO NOT write test files"
assert_output_not_contains "Worker separation: no dispatch" "dispatch Workers"
assert_output_not_contains "Worker separation: no mission loop" "mission loop"
assert_output_not_contains "Worker separation: no Write tests" "Write tests"
assert_output_not_contains "Worker separation: no source file restriction" "DO NOT modify source files"

# Validator should have validate/test, NOT dispatch/handoff
create_state "true" "validator" "1" "task1"
create_features "in-progress" "F-001" "feature1"

assert_output_contains "Validator separation: has Write tests" "Write tests"
assert_output_contains "Validator separation: has source restriction" "DO NOT modify source files"
assert_output_not_contains "Validator separation: no dispatch" "dispatch Workers"
assert_output_not_contains "Validator separation: no handoff" "handoff"
assert_output_not_contains "Validator separation: no test file restriction" "DO NOT write test files"

# ─────────────────────────────────────────────
# TEST GROUP 8: Compaction recovery — all roles include key fields
# ─────────────────────────────────────────────
echo ""
echo "--- Compaction recovery fields ---"

# Orchestrator
create_state "true" "orchestrator" "5" "complex migration" "reviewing results"
echo "# Plan" > "$TEST_DIR/.mission/plan.md"
create_features "in-progress" "F-010" "Database migration"

assert_output_contains "Orch recovery: has phase" "Phase: ORCHESTRATOR"
assert_output_contains "Orch recovery: has round" "Round: 5"
assert_output_contains "Orch recovery: has task" "complex migration"
assert_output_contains "Orch recovery: has feature" "F-010"
assert_output_contains "Orch recovery: has action" "reviewing results"

# Worker
create_state "true" "worker" "3" "implement feature" ""
create_features "in-progress" "F-005" "Worker feature"

assert_output_contains "Worker recovery: has phase" "Phase: WORKER"
assert_output_contains "Worker recovery: has round" "Round: 3"
assert_output_contains "Worker recovery: has task" "implement feature"
assert_output_contains "Worker recovery: has feature" "F-005"

# Validator
create_state "true" "validator" "4" "validate output" ""
create_features "in-progress" "F-007" "Validator feature"

assert_output_contains "Validator recovery: has phase" "Phase: VALIDATOR"
assert_output_contains "Validator recovery: has round" "Round: 4"
assert_output_contains "Validator recovery: has task" "validate output"
assert_output_contains "Validator recovery: has feature" "F-007"

# ─────────────────────────────────────────────
# TEST GROUP 9: Feature-aware — shows in-progress feature
# ─────────────────────────────────────────────
echo ""
echo "--- Feature-aware ---"

# Multiple features — only in-progress shown
create_state "true" "worker" "1" "task"
create_multi_features

assert_output_contains "Multi-features: shows in-progress feature" "F-002"
assert_output_contains "Multi-features: shows in-progress description" "Implement API routes"
assert_output_not_contains "Multi-features: does not show completed feature" "F-001"
assert_output_not_contains "Multi-features: does not show pending feature" "F-003"

# No in-progress feature → shows "none"
create_state "true" "worker" "1" "task"
create_features "completed" "F-001" "Done feature"

assert_output_contains "No in-progress: shows none" "none"

# No features.json at all
create_state "true" "worker" "1" "task"
rm -f "$TEST_DIR/.mission/features.json"

assert_output_contains "No features.json: shows none" "none"

# ─────────────────────────────────────────────
# TEST GROUP 10: Fires for ALL tools
# ─────────────────────────────────────────────
echo ""
echo "--- Fires for all tools ---"

create_state "true" "orchestrator" "1" "task"
rm -f "$TEST_DIR/.mission/plan.md"
rm -f "$TEST_DIR/.mission/features.json"

for tool in Read Write Edit Bash Agent Grep Glob MultiEdit; do
  assert_output_contains "Fires for $tool" "[MISSION SKILL ACTIVE" "$tool"
done

# ─────────────────────────────────────────────
# TEST GROUP 11: Always exits 0 (never blocks)
# ─────────────────────────────────────────────
echo ""
echo "--- Always exits 0 ---"

create_state "true" "orchestrator" "1"
assert_exit_zero "Active orchestrator → exit 0"

create_state "true" "worker" "1"
assert_exit_zero "Active worker → exit 0"

create_state "true" "validator" "1"
assert_exit_zero "Active validator → exit 0"

create_state "false" "worker" "1"
assert_exit_zero "Inactive → exit 0"

rm -rf "$TEST_DIR/.mission"
assert_exit_zero "No state → exit 0"

# ─────────────────────────────────────────────
# TEST GROUP 12: Unknown phase → silent exit
# ─────────────────────────────────────────────
echo ""
echo "--- Unknown phase ---"

create_state "true" "complete" "3"
assert_silent_exit "Complete phase → silent exit 0"
assert_exit_zero "Complete phase → exit code 0"

create_state "true" "hacking" "1"
assert_silent_exit "Unknown phase 'hacking' → silent exit 0"
assert_exit_zero "Unknown phase 'hacking' → exit code 0"

# Write empty-phase state manually (create_state defaults "" to "orchestrator")
mkdir -p "$TEST_DIR/.mission"
echo '{"active": true, "phase": "", "task": "test", "round": 1}' > "$TEST_DIR/.mission/state.json"
rm -f "$TEST_DIR/.mission/plan.md" "$TEST_DIR/.mission/features.json"
assert_silent_exit "Empty phase → silent exit 0"

# ─────────────────────────────────────────────
# TEST GROUP 13: Graceful degradation — malformed state/features
# ─────────────────────────────────────────────
echo ""
echo "--- Graceful degradation ---"

# Missing phase field
mkdir -p "$TEST_DIR/.mission"
echo '{"active": true, "task": "test", "round": 1}' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Missing phase field → silent exit"
assert_exit_zero "Missing phase field → exit 0"

# Missing active field
mkdir -p "$TEST_DIR/.mission"
echo '{"phase": "orchestrator", "task": "test", "round": 1}' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Missing active field → silent exit"
assert_exit_zero "Missing active field → exit 0"

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

# Malformed features.json (still shows output, just no feature)
create_state "true" "worker" "1" "task"
mkdir -p "$TEST_DIR/.mission"
echo 'bad json' > "$TEST_DIR/.mission/features.json"
assert_output_contains "Malformed features.json: still outputs reminder" "[MISSION SKILL ACTIVE]"
assert_exit_zero "Malformed features.json → exit 0"

# features.json with wrong structure
create_state "true" "worker" "1" "task"
echo '{"features": "not an array"}' > "$TEST_DIR/.mission/features.json"
assert_output_contains "Wrong features structure: still outputs" "[MISSION SKILL ACTIVE]"
assert_exit_zero "Wrong features structure → exit 0"

# State with missing task/round — uses defaults
create_state "true" "orchestrator" "1" "test"
# Overwrite with minimal state
echo '{"active": true, "phase": "worker"}' > "$TEST_DIR/.mission/state.json"
rm -f "$TEST_DIR/.mission/features.json"
assert_output_contains "Missing task/round: uses defaults" "Round: 1"
assert_output_contains "Missing task/round: default task" "unknown"

# ─────────────────────────────────────────────
# TEST GROUP 14: Subdirectory behavior
# ─────────────────────────────────────────────
echo ""
echo "--- Subdirectory search ---"

create_state "true" "orchestrator" "2" "subdir task"
echo "# Plan" > "$TEST_DIR/.mission/plan.md"
rm -f "$TEST_DIR/.mission/features.json"
mkdir -p "$TEST_DIR/src/components/deep"
TOTAL=$((TOTAL + 1))
output=$(cd "$TEST_DIR/src/components/deep" && python3 "$PROJECT_DIR/hooks/mission-reminder.py" "Read" 2>&1) || true
if echo "$output" | grep -qF "[MISSION SKILL ACTIVE"; then
  echo "PASS: Subdir search → finds state.json from nested dir"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Subdir search → should find state.json from nested dir"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# Subdirectory with worker phase → still outputs (Python version outputs for all phases)
create_state "true" "worker" "1" "worker task"
create_features "in-progress" "F-001" "Some feature"
mkdir -p "$TEST_DIR/src/lib"
TOTAL=$((TOTAL + 1))
output=$(cd "$TEST_DIR/src/lib" && python3 "$PROJECT_DIR/hooks/mission-reminder.py" "Write" 2>&1) || true
if echo "$output" | grep -qF "[MISSION SKILL ACTIVE]"; then
  echo "PASS: Subdir worker phase → outputs reminder"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Subdir worker phase → should output reminder"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# ─────────────────────────────────────────────
# TEST GROUP 15: Plan vs features interaction
# ─────────────────────────────────────────────
echo ""
echo "--- Plan vs features interaction ---"

# Both plan and features exist → dispatch/loop
create_state "true" "orchestrator" "1" "task"
echo "# Plan" > "$TEST_DIR/.mission/plan.md"
create_features "in-progress" "F-001" "Auth"
assert_output_contains "Both plan+features: mission loop" "mission loop"

# Only plan exists, no features → dispatch/loop
create_state "true" "orchestrator" "1" "task"
echo "# Plan" > "$TEST_DIR/.mission/plan.md"
rm -f "$TEST_DIR/.mission/features.json"
assert_output_contains "Only plan: mission loop" "mission loop"

# Only features exist, no plan → dispatch/loop
create_state "true" "orchestrator" "1" "task"
rm -f "$TEST_DIR/.mission/plan.md"
create_features "in-progress" "F-001" "Auth"
assert_output_contains "Only features: mission loop" "mission loop"

# Neither plan nor features → research phase
create_state "true" "orchestrator" "1" "task"
rm -f "$TEST_DIR/.mission/plan.md"
rm -f "$TEST_DIR/.mission/features.json"
assert_output_contains "Neither plan nor features: features.json directive" "features.json"

# ─────────────────────────────────────────────
# TEST GROUP 16: Orchestrator no-action field
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator current action ---"

# With currentAction
create_state "true" "orchestrator" "1" "task" "dispatching worker-1"
echo "# Plan" > "$TEST_DIR/.mission/plan.md"
rm -f "$TEST_DIR/.mission/features.json"
assert_output_contains "Orch with action: shows action" "dispatching worker-1"

# Without currentAction (empty)
create_state "true" "orchestrator" "1" "task" ""
echo "# Plan" > "$TEST_DIR/.mission/plan.md"
rm -f "$TEST_DIR/.mission/features.json"
assert_output_not_contains "Orch no action: no Current Action field" "Current Action"

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
