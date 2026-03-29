#!/usr/bin/env bash
# tests/mission-stop.test.sh — Tests for hooks/mission-stop.py and hooks/mission-subagent-stop.py
# Run: bash tests/mission-stop.test.sh

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
  local persistence="${5:-relentless}"
  mkdir -p "$TEST_DIR/.mission"
  cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": $active,
  "phase": "$phase",
  "task": "$task",
  "round": $round,
  "persistence": "$persistence"
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

# ─────────────────────────────────────────────
# Helper: run stop hooks with stdin JSON
# ─────────────────────────────────────────────
run_stop_hook() {
  local stdin_json="$1"
  echo "$stdin_json" | (cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-stop.py") 2>&1
  return 0
}

run_subagent_stop_hook() {
  local stdin_json="$1"
  echo "$stdin_json" | (cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-subagent-stop.py") 2>&1
  return 0
}

# Run with empty stdin (no pipe at all — /dev/null)
run_stop_hook_empty() {
  (cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-stop.py") < /dev/null 2>&1
  return 0
}

run_subagent_stop_hook_empty() {
  (cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-subagent-stop.py") < /dev/null 2>&1
  return 0
}

# Default stdin JSON for stop hooks
DEFAULT_STDIN='{"session_id":"test","cwd":"/tmp","hook_event_name":"Stop","stop_hook_active":false}'
ACTIVE_STDIN='{"session_id":"test","cwd":"/tmp","hook_event_name":"Stop","stop_hook_active":true}'
SUBAGENT_STDIN='{"session_id":"test","cwd":"/tmp","hook_event_name":"SubagentStop","stop_hook_active":false}'
SUBAGENT_ACTIVE_STDIN='{"session_id":"test","cwd":"/tmp","hook_event_name":"SubagentStop","stop_hook_active":true}'

# ─────────────────────────────────────────────
# Assertion helpers
# ─────────────────────────────────────────────
assert_allows_stop() {
  local desc="$1"
  local output="$2"
  TOTAL=$((TOTAL + 1))
  if [ -z "$output" ]; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected no output (allow stop) but got: $output"
    FAILED=$((FAILED + 1))
  fi
}

assert_blocks_stop() {
  local desc="$1"
  local output="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qF '"decision": "block"'; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected block decision but got: $output"
    FAILED=$((FAILED + 1))
  fi
}

assert_output_contains() {
  local desc="$1"
  local output="$2"
  local expected="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qF "$expected"; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected output to contain: $expected"
    echo "  actual: $output"
    FAILED=$((FAILED + 1))
  fi
}

assert_output_not_contains() {
  local desc="$1"
  local output="$2"
  local unexpected="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qF "$unexpected"; then
    echo "FAIL: $desc — output should NOT contain: $unexpected"
    echo "  actual: $output"
    FAILED=$((FAILED + 1))
  else
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  fi
}

assert_exit_zero() {
  local desc="$1"
  local stdin_json="$2"
  local hook="${3:-stop}"
  TOTAL=$((TOTAL + 1))
  local exit_code=0
  if [ "$hook" = "stop" ]; then
    echo "$stdin_json" | (cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-stop.py") >/dev/null 2>&1 || exit_code=$?
  else
    echo "$stdin_json" | (cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-subagent-stop.py") >/dev/null 2>&1 || exit_code=$?
  fi
  if [ "$exit_code" -eq 0 ]; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected exit 0 but got exit $exit_code"
    FAILED=$((FAILED + 1))
  fi
}

assert_valid_json() {
  local desc="$1"
  local output="$2"
  TOTAL=$((TOTAL + 1))
  if [ -z "$output" ]; then
    echo "PASS: $desc (empty output = allow = valid)"
    PASSED=$((PASSED + 1))
    return
  fi
  if echo "$output" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — output is not valid JSON: $output"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== Mission Stop & SubagentStop Hook Tests ==="
echo ""

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 1: No state file → allow stop
# ═════════════════════════════════════════════════════════════════════════════
echo "--- [1] No state file → allow stop ---"

rm -rf "$TEST_DIR/.mission"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_allows_stop "Stop: No state file → allow" "$output"

output=$(run_subagent_stop_hook "$SUBAGENT_STDIN") || true
assert_allows_stop "SubagentStop: No state file → allow" "$output"

assert_exit_zero "Stop: No state file → exit 0" "$DEFAULT_STDIN" "stop"
assert_exit_zero "SubagentStop: No state file → exit 0" "$SUBAGENT_STDIN" "subagent"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 2: Inactive mission → allow stop
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [2] Inactive mission → allow stop ---"

create_state "false" "orchestrator"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_allows_stop "Stop: active=false → allow" "$output"

output=$(run_subagent_stop_hook "$SUBAGENT_STDIN") || true
assert_allows_stop "SubagentStop: active=false → allow" "$output"

assert_exit_zero "Stop: active=false → exit 0" "$DEFAULT_STDIN" "stop"
assert_exit_zero "SubagentStop: active=false → exit 0" "$SUBAGENT_STDIN" "subagent"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 3: stop_hook_active=true → allow stop (prevent infinite loop)
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [3] stop_hook_active=true → allow (prevent infinite loop) ---"

create_state "true" "orchestrator" "1" "test task"
output=$(run_stop_hook "$ACTIVE_STDIN") || true
assert_allows_stop "Stop: stop_hook_active=true → allow" "$output"

create_state "true" "worker" "2"
output=$(run_stop_hook "$ACTIVE_STDIN") || true
assert_allows_stop "Stop: worker + stop_hook_active=true → allow" "$output"

create_state "true" "validator" "3"
output=$(run_stop_hook "$ACTIVE_STDIN") || true
assert_allows_stop "Stop: validator + stop_hook_active=true → allow" "$output"

create_state "true" "worker" "1"
output=$(run_subagent_stop_hook "$SUBAGENT_ACTIVE_STDIN") || true
assert_allows_stop "SubagentStop: stop_hook_active=true → allow" "$output"

create_state "true" "validator" "1"
output=$(run_subagent_stop_hook "$SUBAGENT_ACTIVE_STDIN") || true
assert_allows_stop "SubagentStop: validator + stop_hook_active=true → allow" "$output"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 4: Active mission, phase=orchestrator → BLOCK (Stop hook)
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [4] Active mission, phase=orchestrator → BLOCK (Stop) ---"

create_state "true" "orchestrator" "1" "build auth system" "relentless"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: orchestrator → block" "$output"
assert_output_contains "Stop: orchestrator → reason has phase" "$output" "Phase: orchestrator"
assert_output_contains "Stop: orchestrator → reason has round" "$output" "Round: 1"
assert_output_contains "Stop: orchestrator → reason has task" "$output" "build auth system"
assert_output_contains "Stop: orchestrator → reason has DO NOT STOP" "$output" "DO NOT STOP"
assert_output_contains "Stop: orchestrator → reason has continue instruction" "$output" "continue the mission loop"
assert_valid_json "Stop: orchestrator → valid JSON" "$output"
assert_exit_zero "Stop: orchestrator → exit 0" "$DEFAULT_STDIN" "stop"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 5: Active mission, phase=worker → BLOCK (Stop hook)
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [5] Active mission, phase=worker → BLOCK (Stop) ---"

create_state "true" "worker" "2" "implement API" "relentless"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: worker → block" "$output"
assert_output_contains "Stop: worker → reason has phase" "$output" "Phase: worker"
assert_output_contains "Stop: worker → reason has round" "$output" "Round: 2"
assert_output_contains "Stop: worker → reason has task" "$output" "implement API"
assert_valid_json "Stop: worker → valid JSON" "$output"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 6: Active mission, phase=validator → BLOCK (Stop hook)
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [6] Active mission, phase=validator → BLOCK (Stop) ---"

create_state "true" "validator" "3" "verify all features"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: validator → block" "$output"
assert_output_contains "Stop: validator → reason has phase" "$output" "Phase: validator"
assert_output_contains "Stop: validator → reason has round" "$output" "Round: 3"
assert_valid_json "Stop: validator → valid JSON" "$output"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 7: Active mission, phase=complete → allow stop
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [7] Active mission, phase=complete → allow ---"

create_state "true" "complete" "5" "done task"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_allows_stop "Stop: phase=complete → allow" "$output"
assert_exit_zero "Stop: phase=complete → exit 0" "$DEFAULT_STDIN" "stop"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 8: Malformed stdin → allow (no crash)
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [8] Malformed stdin → allow (no crash) ---"

create_state "true" "orchestrator" "1"

output=$(run_stop_hook "not valid json at all!!!") || true
assert_blocks_stop "Stop: malformed JSON stdin → still blocks (stdin parse fails gracefully)" "$output"

output=$(run_stop_hook '{"broken": }') || true
assert_blocks_stop "Stop: broken JSON → still blocks (no stop_hook_active)" "$output"

output=$(run_stop_hook '[1,2,3]') || true
assert_blocks_stop "Stop: array stdin → still blocks (not a dict)" "$output"

assert_exit_zero "Stop: malformed stdin → exit 0" "not json" "stop"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 9: Empty stdin → allow / graceful
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [9] Empty stdin → graceful handling ---"

create_state "true" "worker" "1"
output=$(run_stop_hook_empty) || true
assert_blocks_stop "Stop: empty stdin + active worker → block (no stop_hook_active)" "$output"

rm -rf "$TEST_DIR/.mission"
output=$(run_stop_hook_empty) || true
assert_allows_stop "Stop: empty stdin + no state → allow" "$output"

create_state "true" "validator" "1"
output=$(run_subagent_stop_hook_empty) || true
assert_blocks_stop "SubagentStop: empty stdin + active validator → block" "$output"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 10: Feature-aware output
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [10] Feature-aware output ---"

create_state "true" "orchestrator" "1" "build features"
create_features "feat-auth" "Implement authentication" "in-progress"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: with feature → block" "$output"
assert_output_contains "Stop: feature ID in reason" "$output" "feat-auth"

create_state "true" "worker" "2" "implement feature"
create_features "feat-api" "Build REST API" "in-progress"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_output_contains "Stop: worker feature ID" "$output" "feat-api"

# No in-progress feature → no feature in output
create_state "true" "orchestrator" "1" "test task"
create_features "feat-done" "Completed feature" "completed"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: no in-progress feature → still blocks" "$output"
assert_output_not_contains "Stop: no in-progress → no Feature:" "$output" "Feature: feat-done"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 11: SubagentStop — phase=worker → BLOCK
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [11] SubagentStop: phase=worker → BLOCK ---"

create_state "true" "worker" "2" "implement feature"
create_features "feat-api" "Build API" "in-progress"
output=$(run_subagent_stop_hook "$SUBAGENT_STDIN") || true
assert_blocks_stop "SubagentStop: worker → block" "$output"
assert_output_contains "SubagentStop: worker → SUBAGENT MUST CONTINUE" "$output" "SUBAGENT MUST CONTINUE"
assert_output_contains "SubagentStop: worker → phase in reason" "$output" "Phase: worker"
assert_output_contains "SubagentStop: worker → feature in reason" "$output" "feat-api"
assert_output_contains "SubagentStop: worker → structured handoff" "$output" "structured handoff"
assert_valid_json "SubagentStop: worker → valid JSON" "$output"
assert_exit_zero "SubagentStop: worker → exit 0" "$SUBAGENT_STDIN" "subagent"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 12: SubagentStop — phase=validator → BLOCK
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [12] SubagentStop: phase=validator → BLOCK ---"

create_state "true" "validator" "3" "verify everything"
create_features "feat-ui" "Frontend UI" "in-progress"
output=$(run_subagent_stop_hook "$SUBAGENT_STDIN") || true
assert_blocks_stop "SubagentStop: validator → block" "$output"
assert_output_contains "SubagentStop: validator → SUBAGENT MUST CONTINUE" "$output" "SUBAGENT MUST CONTINUE"
assert_output_contains "SubagentStop: validator → phase in reason" "$output" "Phase: validator"
assert_output_contains "SubagentStop: validator → feature in reason" "$output" "feat-ui"
assert_valid_json "SubagentStop: validator → valid JSON" "$output"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 13: SubagentStop — phase=orchestrator → allow
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [13] SubagentStop: phase=orchestrator → allow ---"

create_state "true" "orchestrator" "1" "plan work"
output=$(run_subagent_stop_hook "$SUBAGENT_STDIN") || true
assert_allows_stop "SubagentStop: orchestrator → allow" "$output"
assert_exit_zero "SubagentStop: orchestrator → exit 0" "$SUBAGENT_STDIN" "subagent"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 14: SubagentStop — phase=complete → allow
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [14] SubagentStop: phase=complete → allow ---"

create_state "true" "complete" "5"
output=$(run_subagent_stop_hook "$SUBAGENT_STDIN") || true
assert_allows_stop "SubagentStop: complete → allow" "$output"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 15: Edge cases — missing fields in state
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [15] Edge cases — missing fields ---"

# Missing phase
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "task": "test task",
  "round": 1
}
STATEEOF
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: missing phase → still blocks (phase=unknown)" "$output"
assert_exit_zero "Stop: missing phase → exit 0" "$DEFAULT_STDIN" "stop"

# Missing round
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "phase": "worker",
  "task": "test task"
}
STATEEOF
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: missing round → still blocks" "$output"
assert_output_contains "Stop: missing round → defaults to 1" "$output" "Round: 1"

# Missing task
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "phase": "orchestrator",
  "round": 2
}
STATEEOF
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: missing task → still blocks" "$output"
assert_output_contains "Stop: missing task → defaults to unknown" "$output" "unknown"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 16: Edge cases — malformed state.json
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [16] Malformed state.json → allow ---"

# Empty JSON object
mkdir -p "$TEST_DIR/.mission"
echo '{}' > "$TEST_DIR/.mission/state.json"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_allows_stop "Stop: empty JSON {} → allow" "$output"

# Malformed JSON
mkdir -p "$TEST_DIR/.mission"
echo 'not json at all' > "$TEST_DIR/.mission/state.json"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_allows_stop "Stop: malformed state.json → allow" "$output"

# Empty file
mkdir -p "$TEST_DIR/.mission"
echo -n '' > "$TEST_DIR/.mission/state.json"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_allows_stop "Stop: empty state.json → allow" "$output"

# Array instead of object
mkdir -p "$TEST_DIR/.mission"
echo '[1,2,3]' > "$TEST_DIR/.mission/state.json"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_allows_stop "Stop: array state.json → allow" "$output"

assert_exit_zero "Stop: malformed state → exit 0" "$DEFAULT_STDIN" "stop"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 17: active as string "true" — string coercion
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [17] active as string 'true' ---"

mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": "true",
  "phase": "worker",
  "round": 1,
  "task": "string active"
}
STATEEOF
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: active='true' string → block" "$output"

output=$(run_subagent_stop_hook "$SUBAGENT_STDIN") || true
assert_blocks_stop "SubagentStop: active='true' string → block" "$output"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 18: Subdirectory search
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [18] Subdirectory search ---"

create_state "true" "orchestrator" "2" "test task"
mkdir -p "$TEST_DIR/src/deep/nested"
output=$(echo "$DEFAULT_STDIN" | (cd "$TEST_DIR/src/deep/nested" && python3 "$PROJECT_DIR/hooks/mission-stop.py") 2>&1) || true
assert_blocks_stop "Stop: from subdirectory → finds state and blocks" "$output"
assert_output_contains "Stop: from subdirectory → correct phase" "$output" "Phase: orchestrator"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 19: Malformed features.json — graceful degradation
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [19] Malformed features.json ---"

create_state "true" "orchestrator" "1" "test task"

# Broken features.json
mkdir -p "$TEST_DIR/.mission"
echo 'broken json {{{' > "$TEST_DIR/.mission/features.json"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: malformed features → still blocks" "$output"
assert_exit_zero "Stop: malformed features → exit 0" "$DEFAULT_STDIN" "stop"

# Empty features.json
echo '' > "$TEST_DIR/.mission/features.json"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: empty features → still blocks" "$output"

# No features.json at all
rm -f "$TEST_DIR/.mission/features.json"
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: missing features.json → still blocks" "$output"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 20: SubagentStop — unknown phase → allow
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [20] SubagentStop: unknown phase → allow ---"

mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "phase": "custom_unknown",
  "round": 1
}
STATEEOF
output=$(run_subagent_stop_hook "$SUBAGENT_STDIN") || true
assert_allows_stop "SubagentStop: unknown phase → allow" "$output"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 21: Stop hook — unknown/empty phase → block
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [21] Stop: unknown/empty phase → block ---"

mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "phase": "custom_phase",
  "round": 4,
  "task": "custom work"
}
STATEEOF
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: unknown phase → block (safety)" "$output"
assert_output_contains "Stop: unknown phase → shows phase" "$output" "custom_phase"

# Empty phase
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "phase": "",
  "round": 1,
  "task": "test"
}
STATEEOF
output=$(run_stop_hook "$DEFAULT_STDIN") || true
assert_blocks_stop "Stop: empty phase → block (safety)" "$output"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 22: SubagentStop with no feature
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [22] SubagentStop: no feature context ---"

create_state "true" "worker" "1" "task"
rm -f "$TEST_DIR/.mission/features.json"
output=$(run_subagent_stop_hook "$SUBAGENT_STDIN") || true
assert_blocks_stop "SubagentStop: no features.json → still blocks" "$output"
assert_output_not_contains "SubagentStop: no feature → no Feature:" "$output" "Feature:"

# ═════════════════════════════════════════════════════════════════════════════
# TEST GROUP 23: Always exits 0 — both hooks
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- [23] Always exits 0 ---"

create_state "true" "orchestrator" "1"
assert_exit_zero "Stop: active orchestrator → exit 0" "$DEFAULT_STDIN" "stop"
assert_exit_zero "SubagentStop: active orchestrator → exit 0" "$SUBAGENT_STDIN" "subagent"

create_state "true" "worker" "1"
assert_exit_zero "Stop: active worker → exit 0" "$DEFAULT_STDIN" "stop"
assert_exit_zero "SubagentStop: active worker → exit 0" "$SUBAGENT_STDIN" "subagent"

create_state "true" "validator" "1"
assert_exit_zero "Stop: active validator → exit 0" "$DEFAULT_STDIN" "stop"
assert_exit_zero "SubagentStop: active validator → exit 0" "$SUBAGENT_STDIN" "subagent"

create_state "false"
assert_exit_zero "Stop: inactive → exit 0" "$DEFAULT_STDIN" "stop"
assert_exit_zero "SubagentStop: inactive → exit 0" "$SUBAGENT_STDIN" "subagent"

rm -rf "$TEST_DIR/.mission"
assert_exit_zero "Stop: no state → exit 0" "$DEFAULT_STDIN" "stop"
assert_exit_zero "SubagentStop: no state → exit 0" "$SUBAGENT_STDIN" "subagent"

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
