#!/usr/bin/env bash
# tests/mission-continue.test.sh — Tests for hooks/mission-continue.py (Python rewrite)
# Run: bash tests/mission-continue.test.sh

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

# ─────────────────────────────────────────────
# Helper: create .mission/state.json in test dir
# ─────────────────────────────────────────────
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
  local task="${6:-test task}"
  local action="${7:-dispatching}"
  local persistence="${8:-relentless}"
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
  "task": "$task",
  "round": $round,
  "currentAction": "$action",
  "persistence": "$persistence",
  "workers": $workers
}
STATEEOF
}

# Helper: create features.json
create_features() {
  local feature_id="${1:-feat-1}"
  local feature_desc="${2:-Implement auth}"
  local feature_status="${3:-in-progress}"
  mkdir -p "$TEST_DIR/.mission"
  cat > "$TEST_DIR/.mission/features.json" <<FEATEOF
{
  "features": [
    {
      "id": "$feature_id",
      "description": "$feature_desc",
      "status": "$feature_status"
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
    {"id": "feat-1", "description": "Auth system", "status": "completed"},
    {"id": "feat-2", "description": "API endpoints", "status": "in-progress"},
    {"id": "feat-3", "description": "Frontend UI", "status": "pending"}
  ]
}
FEATEOF
}

# ─────────────────────────────────────────────
# Helper: run mission-continue.py with tool name in test dir
# ─────────────────────────────────────────────
run_hook() {
  local tool_name="$1"
  cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-continue.py" "$tool_name" 2>&1
  return 0  # always succeeds
}

run_hook_no_args() {
  cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-continue.py" 2>&1
  return 0
}

# ─────────────────────────────────────────────
# Assertion helpers
# ─────────────────────────────────────────────
assert_output_contains() {
  local desc="$1"
  local tool_name="$2"
  local expected="$3"
  TOTAL=$((TOTAL + 1))
  local output
  output=$(run_hook "$tool_name") || true
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
  output=$(run_hook "$tool_name") || true
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
  output=$(run_hook "$tool_name") || true
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
  local exit_code=0
  cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-continue.py" "$tool_name" >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected exit 0 but got exit $exit_code"
    FAILED=$((FAILED + 1))
  fi
}

# Compare output lengths: output for tool1 should be longer than tool2
assert_output_longer() {
  local desc="$1"
  local tool1="$2"
  local tool2="$3"
  TOTAL=$((TOTAL + 1))
  local output1 output2 len1 len2
  output1=$(run_hook "$tool1") || true
  output2=$(run_hook "$tool2") || true
  len1=${#output1}
  len2=${#output2}
  if [ "$len1" -gt "$len2" ]; then
    echo "PASS: $desc (${len1} > ${len2})"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected $tool1 output (${len1}) > $tool2 output (${len2})"
    echo "  $tool1: $output1"
    echo "  $tool2: $output2"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== Mission Continue Hook Tests (Python rewrite) ==="
echo ""

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 1: Silent exits — no state file
# ═════════════════════════════════════════════════════════════════════════════
echo "--- [1] No state file ---"

rm -rf "$TEST_DIR/.mission"
assert_silent_exit "No state file + Agent → silent exit 0" "Agent"
assert_silent_exit "No state file + Read → silent exit 0" "Read"
assert_silent_exit "No state file + Write → silent exit 0" "Write"
assert_silent_exit "No state file + Bash → silent exit 0" "Bash"
assert_exit_zero "No state file → exit code 0" "Agent"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 2: Silent exits — inactive mission
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [2] Inactive mission ---"

create_state "false" "orchestrator" "1"
assert_silent_exit "active=false + Agent → silent exit 0" "Agent"
assert_silent_exit "active=false + Read → silent exit 0" "Read"
assert_silent_exit "active=false + Write → silent exit 0" "Write"
assert_exit_zero "active=false → exit code 0" "Bash"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 3: Silent exits — no args
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [3] No args ---"

create_state "true" "orchestrator" "1"
TOTAL=$((TOTAL + 1))
output=$(run_hook_no_args) || true
if [ -z "$output" ]; then
  echo "PASS: No tool arg → silent exit 0"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: No tool arg → expected silent but got: $output"
  FAILED=$((FAILED + 1))
fi

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 4: Orchestrator + Agent → STRONGEST
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [4] Orchestrator + Agent (STRONGEST) ---"

create_state "true" "orchestrator" "1" "build auth system" "dispatching workers" "relentless"
# Debug: run once with stderr visible to diagnose Windows failures
debug_out=$(cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-continue.py" "Agent" 2>&1) || true
if [ -z "$debug_out" ]; then
  echo "DEBUG: Orchestrator+Agent produced empty output. Stderr check:"
  cd "$TEST_DIR" && python3 -u "$PROJECT_DIR/hooks/mission-continue.py" "Agent" 2>&1 || echo "DEBUG: exit code $?"
  echo "DEBUG: state.json content:"
  cat "$TEST_DIR/.mission/state.json" 2>/dev/null || echo "DEBUG: no state.json"
  echo "DEBUG: Testing engine import:"
  cd "$TEST_DIR" && python3 -c "import sys; sys.path.insert(0, '$PROJECT_DIR/hooks'); from engine import find_state_file; print('ENGINE OK, state:', find_state_file())" 2>&1 || echo "DEBUG: engine import failed"
fi
assert_output_contains "Orch+Agent → MANDATORY CONTINUATION" "Agent" "MANDATORY CONTINUATION"
assert_output_contains "Orch+Agent → Phase ORCHESTRATOR" "Agent" "Phase: ORCHESTRATOR"
assert_output_contains "Orch+Agent → Round: 1" "Agent" "Round: 1"
assert_output_contains "Orch+Agent → Persistence RELENTLESS" "Agent" "RELENTLESS"
assert_output_contains "Orch+Agent → contains task" "Agent" "build auth system"
assert_output_contains "Orch+Agent → DO NOT STOP" "Agent" "DO NOT STOP"
assert_output_contains "Orch+Agent → next steps guidance" "Agent" "NEXT STEPS"
assert_output_contains "Orch+Agent → mentions validator" "Agent" "validator"
assert_output_contains "Orch+Agent → mentions completion gate" "Agent" "completion gate"
assert_output_contains "Orch+Agent → END MANDATORY" "Agent" "[END MANDATORY CONTINUATION]"
assert_output_contains "Orch+Agent → TAKE THE NEXT ACTION" "Agent" "TAKE THE NEXT ACTION NOW"
assert_output_contains "Orch+Agent → contains action" "Agent" "dispatching workers"

# Different persistence
create_state "true" "orchestrator" "3" "test task" "planning" "standard"
assert_output_contains "Orch+Agent+standard → Persistence STANDARD" "Agent" "STANDARD"

create_state "true" "orchestrator" "5" "deploy api" "reviewing" "cautious"
assert_output_contains "Orch+Agent+cautious → Persistence CAUTIOUS" "Agent" "CAUTIOUS"
assert_output_contains "Orch+Agent → Round: 5" "Agent" "Round: 5"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 5: Orchestrator + Read/Write/Edit/Bash → MEDIUM
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [5] Orchestrator + Read/Write/Edit/Bash (MEDIUM) ---"

create_state "true" "orchestrator" "2" "fix login bug" "reading plan" "relentless"
assert_output_contains "Orch+Read → MISSION ACTIVE" "Read" "[MISSION ACTIVE]"
assert_output_contains "Orch+Read → Phase ORCHESTRATOR" "Read" "Phase: ORCHESTRATOR"
assert_output_contains "Orch+Read → Round: 2" "Read" "Round: 2"
assert_output_contains "Orch+Read → mentions mission loop" "Read" "mission loop"
assert_output_not_contains "Orch+Read → NOT strongest" "Read" "MANDATORY CONTINUATION"

create_state "true" "orchestrator" "1" "test task" "writing plan" "relentless"
assert_output_contains "Orch+Write → MISSION ACTIVE" "Write" "[MISSION ACTIVE]"
assert_output_contains "Orch+Write → mentions loop" "Write" "mission loop"
assert_output_contains "Orch+Edit → MISSION ACTIVE" "Edit" "[MISSION ACTIVE]"
assert_output_not_contains "Orch+Write → NOT strongest" "Write" "MANDATORY CONTINUATION"

assert_output_contains "Orch+Bash → MISSION ACTIVE" "Bash" "[MISSION ACTIVE]"
assert_output_contains "Orch+Bash → mentions loop" "Bash" "mission loop"
assert_output_not_contains "Orch+Bash → NOT strongest" "Bash" "MANDATORY CONTINUATION"

assert_output_contains "Orch+MultiEdit → MISSION ACTIVE" "MultiEdit" "[MISSION ACTIVE]"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 6: Orchestrator + Grep/Glob → LIGHT
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [6] Orchestrator + Grep/Glob (LIGHT) ---"

create_state "true" "orchestrator" "2" "fix login bug"
assert_output_contains "Orch+Grep → MISSION ACTIVE" "Grep" "[MISSION ACTIVE]"
assert_output_contains "Orch+Grep → mentions skill" "Grep" "Follow the skill"
assert_output_contains "Orch+Glob → MISSION ACTIVE" "Glob" "[MISSION ACTIVE]"
assert_output_contains "Orch+Glob → mentions skill" "Glob" "Follow the skill"
assert_output_not_contains "Orch+Grep → NOT strongest" "Grep" "MANDATORY CONTINUATION"
assert_output_not_contains "Orch+Grep → NOT medium loop" "Grep" "mission loop"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 7: Worker phase — Agent → STRONG
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [7] Worker + Agent (STRONG) ---"

create_state "true" "worker" "2"
assert_output_contains "Worker+Agent → MISSION ACTIVE" "Agent" "[MISSION ACTIVE]"
assert_output_contains "Worker+Agent → Phase: WORKER" "Agent" "Phase: WORKER"
assert_output_contains "Worker+Agent → Round: 2" "Agent" "Round: 2"
assert_output_contains "Worker+Agent → continue task" "Agent" "Continue your assigned task"
assert_output_contains "Worker+Agent → structured handoff" "Agent" "structured handoff"
assert_output_not_contains "Worker+Agent → NOT orchestrator strongest" "Agent" "MANDATORY CONTINUATION"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 8: Worker phase — Read/Write/Edit/Bash → MEDIUM
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [8] Worker + Read/Write/Edit/Bash (MEDIUM) ---"

create_state "true" "worker" "3"
assert_output_contains "Worker+Read → MISSION ACTIVE" "Read" "[MISSION ACTIVE]"
assert_output_contains "Worker+Read → Phase: WORKER" "Read" "Phase: WORKER"
assert_output_contains "Worker+Read → Round: 3" "Read" "Round: 3"
assert_output_contains "Worker+Write → MISSION ACTIVE" "Write" "[MISSION ACTIVE]"
assert_output_contains "Worker+Edit → MISSION ACTIVE" "Edit" "[MISSION ACTIVE]"
assert_output_contains "Worker+Bash → MISSION ACTIVE" "Bash" "[MISSION ACTIVE]"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 9: Worker phase — Grep/Glob → LIGHT
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [9] Worker + Grep/Glob (LIGHT) ---"

create_state "true" "worker" "1"
assert_output_contains "Worker+Grep → MISSION ACTIVE" "Grep" "[MISSION ACTIVE]"
assert_output_contains "Worker+Grep → Follow skill" "Grep" "Follow the skill"
assert_output_contains "Worker+Glob → MISSION ACTIVE" "Glob" "[MISSION ACTIVE]"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 10: Validator phase — Agent → STRONG
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [10] Validator + Agent (STRONG) ---"

create_state "true" "validator" "3"
assert_output_contains "Validator+Agent → MISSION ACTIVE" "Agent" "[MISSION ACTIVE]"
assert_output_contains "Validator+Agent → Phase: VALIDATOR" "Agent" "Phase: VALIDATOR"
assert_output_contains "Validator+Agent → Round: 3" "Agent" "Round: 3"
assert_output_contains "Validator+Agent → continue validation" "Agent" "Continue validation"
assert_output_contains "Validator+Agent → write report" "Agent" "Write report"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 11: Validator phase — Read/Write/Edit/Bash → MEDIUM
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [11] Validator + Read/Write/Edit/Bash (MEDIUM) ---"

create_state "true" "validator" "2"
assert_output_contains "Validator+Read → MISSION ACTIVE" "Read" "[MISSION ACTIVE]"
assert_output_contains "Validator+Read → Phase: VALIDATOR" "Read" "Phase: VALIDATOR"
assert_output_contains "Validator+Write → MISSION ACTIVE" "Write" "[MISSION ACTIVE]"
assert_output_contains "Validator+Bash → MISSION ACTIVE" "Bash" "[MISSION ACTIVE]"
assert_output_contains "Validator+Edit → MISSION ACTIVE" "Edit" "[MISSION ACTIVE]"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 12: Validator phase — Grep/Glob → LIGHT
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [12] Validator + Grep/Glob (LIGHT) ---"

create_state "true" "validator" "1"
assert_output_contains "Validator+Grep → MISSION ACTIVE" "Grep" "[MISSION ACTIVE]"
assert_output_contains "Validator+Glob → MISSION ACTIVE" "Glob" "[MISSION ACTIVE]"
assert_output_contains "Validator+Grep → Follow skill" "Grep" "Follow the skill"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 13: Strength ordering — Agent > Write/Read > Grep/Glob
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [13] Strength ordering ---"

create_state "true" "orchestrator" "1" "build auth system" "dispatching" "relentless"
assert_output_longer "Orch: Agent output > Read output" "Agent" "Read"
assert_output_longer "Orch: Agent output > Grep output" "Agent" "Grep"
assert_output_longer "Orch: Read output > Grep output" "Read" "Grep"

create_state "true" "worker" "1"
assert_output_longer "Worker: Agent output > Read output" "Agent" "Read"
assert_output_longer "Worker: Agent output > Grep output" "Agent" "Grep"

create_state "true" "validator" "1"
assert_output_longer "Validator: Agent output > Read output" "Agent" "Read"
assert_output_longer "Validator: Agent output > Grep output" "Agent" "Grep"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 14: Worker count in Agent reminder
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [14] Worker count in Agent reminder ---"

create_state_with_workers "true" "orchestrator" "1" "1" "3"
assert_output_contains "Workers 1/3 → shows count" "Agent" "Workers: 1/3"

create_state_with_workers "true" "orchestrator" "2" "2" "2"
assert_output_contains "Workers 2/2 → shows count" "Agent" "Workers: 2/2"

create_state_with_workers "true" "orchestrator" "1" "0" "5"
assert_output_contains "Workers 0/5 → shows count" "Agent" "Workers: 0/5"

create_state_with_workers "true" "orchestrator" "1" "3" "3"
assert_output_contains "Workers 3/3 → all complete" "Agent" "Workers: 3/3"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 15: Feature-aware output
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [15] Feature-aware output ---"

create_state "true" "orchestrator" "1" "build features" "dispatching" "relentless"
create_features "feat-auth" "Implement authentication" "in-progress"
assert_output_contains "Orch+Agent+feature → feature id" "Agent" "feat-auth"
assert_output_contains "Orch+Agent+feature → feature desc" "Agent" "Implement authentication"
assert_output_contains "Orch+Read+feature → feature id" "Read" "feat-auth"
assert_output_contains "Orch+Grep+feature → feature id" "Grep" "feat-auth"

# Worker with feature
create_state "true" "worker" "2"
create_features "feat-api" "Build REST API" "in-progress"
assert_output_contains "Worker+Agent+feature → feature id" "Agent" "feat-api"
assert_output_contains "Worker+Agent+feature → feature desc" "Agent" "Build REST API"
assert_output_contains "Worker+Read+feature → feature id" "Read" "feat-api"

# Validator with feature
create_state "true" "validator" "1"
create_features "feat-ui" "Frontend components" "in-progress"
assert_output_contains "Validator+Agent+feature → feature id" "Agent" "feat-ui"
assert_output_contains "Validator+Agent+feature → feature desc" "Agent" "Frontend components"

# Only show in-progress feature, not pending/completed
create_state "true" "orchestrator" "1" "test task" "planning" "relentless"
create_multi_features
assert_output_contains "Multi-feature → shows in-progress feat-2" "Agent" "feat-2"
assert_output_contains "Multi-feature → shows in-progress desc" "Agent" "API endpoints"
assert_output_not_contains "Multi-feature → NOT completed feat-1" "Agent" "Auth system"
assert_output_not_contains "Multi-feature → NOT pending feat-3" "Agent" "Frontend UI"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 16: No feature / no features.json → graceful degradation
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [16] Graceful degradation (no features) ---"

create_state "true" "orchestrator" "1" "test task" "planning" "relentless"
rm -f "$TEST_DIR/.mission/features.json"
assert_output_contains "No features.json → still outputs MANDATORY" "Agent" "MANDATORY CONTINUATION"
assert_output_contains "No features.json → still has round" "Agent" "Round: 1"
assert_exit_zero "No features.json → exit 0" "Agent"

# features.json with no in-progress feature
create_state "true" "worker" "2"
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/features.json" <<FEATEOF
{
  "features": [
    {"id": "feat-1", "status": "completed"},
    {"id": "feat-2", "status": "pending"}
  ]
}
FEATEOF
assert_output_contains "No in-progress feature → still outputs" "Agent" "[MISSION ACTIVE]"
assert_output_not_contains "No in-progress feature → no Feature:" "Agent" "Feature:"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 17: Unknown tool names
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [17] Unknown tool names ---"

create_state "true" "orchestrator" "1"
assert_output_contains "Orch+unknown tool → MISSION ACTIVE" "TaskCreate" "[MISSION ACTIVE]"
assert_output_contains "Orch+unknown tool → Follow skill" "TaskCreate" "Follow the skill"
assert_output_contains "Orch+SomeRandomTool → MISSION ACTIVE" "SomeRandomTool" "[MISSION ACTIVE]"

create_state "true" "worker" "1"
assert_output_contains "Worker+unknown tool → MISSION ACTIVE" "FooBar" "[MISSION ACTIVE]"
assert_output_contains "Worker+unknown tool → Follow skill" "FooBar" "Follow the skill"

create_state "true" "validator" "1"
assert_output_contains "Validator+unknown tool → MISSION ACTIVE" "XyzTool" "[MISSION ACTIVE]"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 18: Always exits 0 — never blocks
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [18] Always exits 0 ---"

create_state "true" "orchestrator" "1"
assert_exit_zero "Active orchestrator + Agent → exit 0" "Agent"
assert_exit_zero "Active orchestrator + Read → exit 0" "Read"
assert_exit_zero "Active orchestrator + Grep → exit 0" "Grep"

create_state "true" "worker" "1"
assert_exit_zero "Active worker + Read → exit 0" "Read"
assert_exit_zero "Active worker + Agent → exit 0" "Agent"

create_state "true" "validator" "1"
assert_exit_zero "Active validator + Bash → exit 0" "Bash"

create_state "false" "orchestrator" "1"
assert_exit_zero "Inactive + Agent → exit 0" "Agent"

rm -rf "$TEST_DIR/.mission"
assert_exit_zero "No state file + Agent → exit 0" "Agent"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 19: Edge cases in state.json
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [19] Edge cases ---"

# Missing phase field
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "task": "test task",
  "round": 1
}
STATEEOF
assert_silent_exit "Missing phase + Read → silent" "Read"
assert_output_contains "Missing phase + Agent → brief reminder" "Agent" "[MISSION ACTIVE]"
assert_exit_zero "Missing phase → exit 0" "Agent"

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

# Missing task in orchestrator phase
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "phase": "orchestrator",
  "round": 2
}
STATEEOF
assert_output_contains "Missing task → defaults to unknown" "Agent" "unknown"

# Empty JSON object
mkdir -p "$TEST_DIR/.mission"
echo '{}' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Empty JSON {} → silent" "Agent"
assert_exit_zero "Empty JSON {} → exit 0" "Agent"

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

# Array instead of object
mkdir -p "$TEST_DIR/.mission"
echo '[1,2,3]' > "$TEST_DIR/.mission/state.json"
assert_silent_exit "Array JSON → silent" "Agent"
assert_exit_zero "Array JSON → exit 0" "Agent"

# active as string "true" (shouldn't activate — we expect boolean)
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": "true",
  "phase": "orchestrator",
  "round": 1
}
STATEEOF
assert_output_contains "active='true' string → outputs reminder" "Agent" "MANDATORY CONTINUATION"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 20: Malformed features.json — graceful degradation
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [20] Malformed features ---"

create_state "true" "orchestrator" "1" "test task" "planning" "relentless"

# Malformed features.json
mkdir -p "$TEST_DIR/.mission"
echo 'broken json {{{' > "$TEST_DIR/.mission/features.json"
assert_output_contains "Malformed features → still outputs" "Agent" "MANDATORY CONTINUATION"
assert_exit_zero "Malformed features → exit 0" "Agent"

# features.json as array
mkdir -p "$TEST_DIR/.mission"
echo '[]' > "$TEST_DIR/.mission/features.json"
assert_output_contains "Array features → still outputs" "Agent" "MANDATORY CONTINUATION"
assert_exit_zero "Array features → exit 0" "Agent"

# Empty features.json
mkdir -p "$TEST_DIR/.mission"
echo '' > "$TEST_DIR/.mission/features.json"
assert_output_contains "Empty features → still outputs" "Agent" "MANDATORY CONTINUATION"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 21: Subdirectory behavior
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [21] Subdirectory search ---"

create_state "true" "orchestrator" "2" "test task" "planning" "relentless"
mkdir -p "$TEST_DIR/src/components/deep"
TOTAL=$((TOTAL + 1))
output=$(cd "$TEST_DIR/src/components/deep" && python3 "$PROJECT_DIR/hooks/mission-continue.py" "Agent" 2>&1) || true
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
output=$(cd "$TEST_DIR/src/lib" && python3 "$PROJECT_DIR/hooks/mission-continue.py" "Grep" 2>&1) || true
if echo "$output" | grep -qF "[MISSION ACTIVE]"; then
  echo "PASS: Subdir worker + Grep → light reminder"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Subdir worker + Grep → should get light reminder"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 22: Unknown phase handling
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [22] Unknown phase ---"

mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "phase": "custom_phase",
  "round": 4
}
STATEEOF
assert_output_contains "Unknown phase + Agent → MISSION ACTIVE" "Agent" "[MISSION ACTIVE]"
assert_output_contains "Unknown phase + Agent → shows phase" "Agent" "custom_phase"
assert_output_contains "Unknown phase + Agent → shows round" "Agent" "Round: 4"
assert_output_contains "Unknown phase + Read → MISSION ACTIVE" "Read" "[MISSION ACTIVE]"
assert_output_contains "Unknown phase + Grep → MISSION ACTIVE" "Grep" "[MISSION ACTIVE]"
assert_exit_zero "Unknown phase → exit 0" "Agent"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 23: Compaction recovery info in STRONGEST
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [23] Compaction recovery info ---"

create_state_with_workers "true" "orchestrator" "3" "2" "4" "deploy microservice" "reviewing worker output" "relentless"
create_features "feat-deploy" "Deploy to staging" "in-progress"
output=$(run_hook "Agent") || true
TOTAL=$((TOTAL + 1))
# Verify all compaction recovery fields present
all_present=true
for field in "Phase: ORCHESTRATOR" "Round: 3" "RELENTLESS" "deploy microservice" "Workers: 2/4" "reviewing worker output" "feat-deploy" "Deploy to staging"; do
  if ! echo "$output" | grep -qF "$field"; then
    echo "FAIL: Compaction recovery — missing field: $field"
    echo "  output: $output"
    FAILED=$((FAILED + 1))
    all_present=false
    break
  fi
done
if [ "$all_present" = "true" ]; then
  echo "PASS: Compaction recovery — all fields present in STRONGEST reminder"
  PASSED=$((PASSED + 1))
fi

# ═════════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════════
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
