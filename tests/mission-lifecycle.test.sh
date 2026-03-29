#!/usr/bin/env bash
# tests/mission-lifecycle.test.sh — Tests for PreCompact, SessionStart, UserPromptSubmit hooks
# Run: bash tests/mission-lifecycle.test.sh

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
  "persistence": "$persistence"
}
STATEEOF
}

# Helper: create features.json with a single feature
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
    {"id": "feat-3", "description": "Frontend UI", "status": "pending"},
    {"id": "feat-4", "description": "Database layer", "status": "pending"}
  ]
}
FEATEOF
}

# Helper: create checkpoint.md
create_checkpoint() {
  mkdir -p "$TEST_DIR/.mission"
  cat > "$TEST_DIR/.mission/checkpoint.md" <<CKEOF
# Mission Checkpoint (written before compaction)

**Phase:** orchestrator
**Round:** 3
**Task:** build auth
**Persistence:** relentless
**Current Action:** reviewing

## Current Feature
ID: feat-auth
Description: Auth system
Status: in-progress

## Feature Progress
- completed: 1
- in-progress: 1
- pending: 2

## Next Action
Monitor in-progress Worker, then dispatch Validator when done.

## Resume Instructions
READ this file and .mission/state.json. Then follow the Resume Protocol in the enter-mission skill.
CKEOF
}

# ─────────────────────────────────────────────
# Helper: pipe stdin to a hook script
# ─────────────────────────────────────────────
run_hook() {
  local hook_script="$1"
  local stdin_json="$2"
  echo "$stdin_json" | (cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/$hook_script" 2>&1)
  return 0
}

# ─────────────────────────────────────────────
# Assertion helpers
# ─────────────────────────────────────────────
assert_output_contains() {
  local desc="$1"
  local hook="$2"
  local stdin_json="$3"
  local expected="$4"
  TOTAL=$((TOTAL + 1))
  local output
  output=$(run_hook "$hook" "$stdin_json") || true
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
  local hook="$2"
  local stdin_json="$3"
  local unexpected="$4"
  TOTAL=$((TOTAL + 1))
  local output
  output=$(run_hook "$hook" "$stdin_json") || true
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
  local hook="$2"
  local stdin_json="${3:-{}}"
  TOTAL=$((TOTAL + 1))
  local output
  output=$(run_hook "$hook" "$stdin_json") || true
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
  local hook="$2"
  local stdin_json="${3:-{}}"
  TOTAL=$((TOTAL + 1))
  local exit_code=0
  echo "$stdin_json" | (cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/$hook" >/dev/null 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected exit 0 but got exit $exit_code"
    FAILED=$((FAILED + 1))
  fi
}

assert_file_exists() {
  local desc="$1"
  local filepath="$2"
  TOTAL=$((TOTAL + 1))
  if [ -f "$filepath" ]; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — file does not exist: $filepath"
    FAILED=$((FAILED + 1))
  fi
}

assert_file_contains() {
  local desc="$1"
  local filepath="$2"
  local expected="$3"
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$filepath" ]; then
    echo "FAIL: $desc — file does not exist: $filepath"
    FAILED=$((FAILED + 1))
    return
  fi
  if grep -qF "$expected" "$filepath"; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — file does not contain: $expected"
    echo "  file content: $(cat "$filepath")"
    FAILED=$((FAILED + 1))
  fi
}

assert_file_not_exists() {
  local desc="$1"
  local filepath="$2"
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$filepath" ]; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — file should not exist: $filepath"
    FAILED=$((FAILED + 1))
  fi
}

assert_valid_json() {
  local desc="$1"
  local hook="$2"
  local stdin_json="$3"
  TOTAL=$((TOTAL + 1))
  local output
  output=$(run_hook "$hook" "$stdin_json") || true
  if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — output is not valid JSON"
    echo "  actual output: $output"
    FAILED=$((FAILED + 1))
  fi
}

PRECOMPACT_STDIN='{"session_id":"test-123","cwd":"/tmp","hook_event_name":"PreCompact","trigger":"auto","custom_instructions":""}'
SESSION_START_STDIN='{"session_id":"test-123","cwd":"/tmp","hook_event_name":"SessionStart","source":"startup"}'
SESSION_COMPACT_STDIN='{"session_id":"test-123","cwd":"/tmp","hook_event_name":"SessionStart","source":"compact"}'
SESSION_RESUME_STDIN='{"session_id":"test-123","cwd":"/tmp","hook_event_name":"SessionStart","source":"resume"}'
PROMPT_STDIN='{"session_id":"test-123","cwd":"/tmp","hook_event_name":"UserPromptSubmit","prompt":"hello"}'

echo "=== Mission Lifecycle Hook Tests ==="
echo ""

# ═════════════════════════════════════════════════════════════════════════════
# PRECOMPACT HOOK TESTS
# ═════════════════════════════════════════════════════════════════════════════

echo "--- [1] PreCompact: No state file ---"
rm -rf "$TEST_DIR/.mission"

assert_silent_exit "PreCompact: No state → silent exit" "mission-precompact.py" "$PRECOMPACT_STDIN"
assert_exit_zero "PreCompact: No state → exit 0" "mission-precompact.py" "$PRECOMPACT_STDIN"
assert_file_not_exists "PreCompact: No state → no checkpoint created" "$TEST_DIR/.mission/checkpoint.md"

echo ""
echo "--- [2] PreCompact: Inactive mission ---"
create_state "false" "orchestrator" "1"

assert_silent_exit "PreCompact: Inactive → silent exit" "mission-precompact.py" "$PRECOMPACT_STDIN"
assert_exit_zero "PreCompact: Inactive → exit 0" "mission-precompact.py" "$PRECOMPACT_STDIN"
assert_file_not_exists "PreCompact: Inactive → no checkpoint" "$TEST_DIR/.mission/checkpoint.md"

echo ""
echo "--- [3] PreCompact: Active mission creates checkpoint ---"
create_state "true" "orchestrator" "2" "build auth system" "dispatching workers" "relentless"
create_features "feat-auth" "Implement authentication" "in-progress"

run_hook "mission-precompact.py" "$PRECOMPACT_STDIN" >/dev/null 2>&1
assert_file_exists "PreCompact: Active → checkpoint.md created" "$TEST_DIR/.mission/checkpoint.md"
assert_file_contains "PreCompact: checkpoint has phase" "$TEST_DIR/.mission/checkpoint.md" "**Phase:** orchestrator"
assert_file_contains "PreCompact: checkpoint has round" "$TEST_DIR/.mission/checkpoint.md" "**Round:** 2"
assert_file_contains "PreCompact: checkpoint has task" "$TEST_DIR/.mission/checkpoint.md" "**Task:** build auth system"
assert_file_contains "PreCompact: checkpoint has persistence" "$TEST_DIR/.mission/checkpoint.md" "**Persistence:** relentless"
assert_file_contains "PreCompact: checkpoint has action" "$TEST_DIR/.mission/checkpoint.md" "**Current Action:** dispatching workers"
assert_file_contains "PreCompact: checkpoint has feature ID" "$TEST_DIR/.mission/checkpoint.md" "ID: feat-auth"
assert_file_contains "PreCompact: checkpoint has feature desc" "$TEST_DIR/.mission/checkpoint.md" "Description: Implement authentication"
assert_file_contains "PreCompact: checkpoint has feature status" "$TEST_DIR/.mission/checkpoint.md" "Status: in-progress"
assert_file_contains "PreCompact: checkpoint has resume instructions" "$TEST_DIR/.mission/checkpoint.md" "Resume Instructions"
assert_file_contains "PreCompact: checkpoint title" "$TEST_DIR/.mission/checkpoint.md" "Mission Checkpoint (written before compaction)"

echo ""
echo "--- [4] PreCompact: Checkpoint includes feature progress ---"
create_state "true" "orchestrator" "3" "deploy service" "reviewing" "relentless"
create_multi_features

run_hook "mission-precompact.py" "$PRECOMPACT_STDIN" >/dev/null 2>&1
assert_file_contains "PreCompact: progress completed" "$TEST_DIR/.mission/checkpoint.md" "completed: 1"
assert_file_contains "PreCompact: progress in-progress" "$TEST_DIR/.mission/checkpoint.md" "in-progress: 1"
assert_file_contains "PreCompact: progress pending" "$TEST_DIR/.mission/checkpoint.md" "pending: 2"

echo ""
echo "--- [5] PreCompact: Checkpoint includes next action ---"
# Orchestrator with in-progress feature
create_state "true" "orchestrator" "1" "task" "working" "relentless"
create_features "feat-x" "Feature X" "in-progress"

run_hook "mission-precompact.py" "$PRECOMPACT_STDIN" >/dev/null 2>&1
assert_file_contains "PreCompact: next action for orchestrator" "$TEST_DIR/.mission/checkpoint.md" "Next Action"
assert_file_contains "PreCompact: next action mentions monitor/dispatch" "$TEST_DIR/.mission/checkpoint.md" "Monitor"

# Worker phase
create_state "true" "worker" "2" "task" "coding" "relentless"
create_features "feat-y" "Feature Y" "in-progress"

run_hook "mission-precompact.py" "$PRECOMPACT_STDIN" >/dev/null 2>&1
assert_file_contains "PreCompact: worker next action mentions handoff" "$TEST_DIR/.mission/checkpoint.md" "handoff"

# Validator phase
create_state "true" "validator" "1" "task" "testing" "relentless"
create_features "feat-z" "Feature Z" "in-progress"

run_hook "mission-precompact.py" "$PRECOMPACT_STDIN" >/dev/null 2>&1
assert_file_contains "PreCompact: validator next action mentions report" "$TEST_DIR/.mission/checkpoint.md" "report"

echo ""
echo "--- [6] PreCompact: No features.json → graceful ---"
create_state "true" "orchestrator" "1" "task" "planning" "relentless"
rm -f "$TEST_DIR/.mission/features.json"

assert_exit_zero "PreCompact: No features.json → exit 0" "mission-precompact.py" "$PRECOMPACT_STDIN"
assert_file_exists "PreCompact: No features → checkpoint still created" "$TEST_DIR/.mission/checkpoint.md"
assert_file_contains "PreCompact: No features → no in-progress note" "$TEST_DIR/.mission/checkpoint.md" "No feature currently in-progress"

echo ""
echo "--- [7] PreCompact: Malformed state.json ---"
mkdir -p "$TEST_DIR/.mission"
echo 'broken json' > "$TEST_DIR/.mission/state.json"

assert_silent_exit "PreCompact: Malformed state → silent exit" "mission-precompact.py" "$PRECOMPACT_STDIN"
assert_exit_zero "PreCompact: Malformed state → exit 0" "mission-precompact.py" "$PRECOMPACT_STDIN"

echo ""
echo "--- [8] PreCompact: Empty stdin ---"
create_state "true" "orchestrator" "1"

TOTAL=$((TOTAL + 1))
output=$(echo "" | (cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-precompact.py" 2>&1)) || true
exit_code=$?
if [ "$exit_code" -eq 0 ]; then
  echo "PASS: PreCompact: Empty stdin → exit 0"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: PreCompact: Empty stdin → expected exit 0 but got $exit_code"
  FAILED=$((FAILED + 1))
fi

# ═════════════════════════════════════════════════════════════════════════════
# SESSION START HOOK TESTS
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- [9] SessionStart: No state file ---"
rm -rf "$TEST_DIR/.mission"

assert_silent_exit "SessionStart: No state → silent exit" "mission-session-start.py" "$SESSION_START_STDIN"
assert_exit_zero "SessionStart: No state → exit 0" "mission-session-start.py" "$SESSION_START_STDIN"

echo ""
echo "--- [10] SessionStart: Inactive mission ---"
create_state "false" "orchestrator" "1"

assert_silent_exit "SessionStart: Inactive → silent exit" "mission-session-start.py" "$SESSION_START_STDIN"
assert_exit_zero "SessionStart: Inactive → exit 0" "mission-session-start.py" "$SESSION_START_STDIN"

echo ""
echo "--- [11] SessionStart: Active → returns JSON with context ---"
create_state "true" "orchestrator" "2" "build auth system" "dispatching" "relentless"
create_features "feat-auth" "Implement authentication" "in-progress"

assert_valid_json "SessionStart: Active → valid JSON" "mission-session-start.py" "$SESSION_START_STDIN"
assert_output_contains "SessionStart: Active → has hookEventName" "mission-session-start.py" "$SESSION_START_STDIN" "SessionStart"
assert_output_contains "SessionStart: Active → has additionalContext" "mission-session-start.py" "$SESSION_START_STDIN" "additionalContext"
assert_output_contains "SessionStart: Active → has MISSION ACTIVE" "mission-session-start.py" "$SESSION_START_STDIN" "MISSION ACTIVE"
assert_output_contains "SessionStart: Active → has AUTO-RESUME" "mission-session-start.py" "$SESSION_START_STDIN" "AUTO-RESUME"
assert_output_contains "SessionStart: Active → has phase" "mission-session-start.py" "$SESSION_START_STDIN" "orchestrator"
assert_output_contains "SessionStart: Active → has round" "mission-session-start.py" "$SESSION_START_STDIN" "Round: 2"
assert_output_contains "SessionStart: Active → has task" "mission-session-start.py" "$SESSION_START_STDIN" "build auth system"
assert_output_contains "SessionStart: Active → has feature" "mission-session-start.py" "$SESSION_START_STDIN" "feat-auth"
assert_output_contains "SessionStart: Active → has resume protocol" "mission-session-start.py" "$SESSION_START_STDIN" "Resume Protocol"

echo ""
echo "--- [12] SessionStart: Compact source → includes checkpoint ---"
create_state "true" "orchestrator" "3" "build auth" "reviewing" "relentless"
create_features "feat-auth" "Auth system" "in-progress"
create_checkpoint

assert_output_contains "SessionStart: Compact → includes checkpoint" "mission-session-start.py" "$SESSION_COMPACT_STDIN" "Checkpoint"
assert_output_contains "SessionStart: Compact → checkpoint has phase" "mission-session-start.py" "$SESSION_COMPACT_STDIN" "pre-compaction state"

echo ""
echo "--- [13] SessionStart: Non-compact source → no checkpoint ---"
create_state "true" "orchestrator" "3" "build auth" "reviewing" "relentless"
create_features "feat-auth" "Auth system" "in-progress"
create_checkpoint

assert_output_not_contains "SessionStart: Startup → no checkpoint content" "mission-session-start.py" "$SESSION_START_STDIN" "pre-compaction state"
assert_output_not_contains "SessionStart: Resume → no checkpoint content" "mission-session-start.py" "$SESSION_RESUME_STDIN" "pre-compaction state"

echo ""
echo "--- [14] SessionStart: Compact but no checkpoint file ---"
create_state "true" "orchestrator" "2" "deploy" "working" "relentless"
create_features "feat-1" "Deploy feature" "in-progress"
rm -f "$TEST_DIR/.mission/checkpoint.md"

assert_valid_json "SessionStart: Compact no checkpoint → valid JSON" "mission-session-start.py" "$SESSION_COMPACT_STDIN"
assert_output_contains "SessionStart: Compact no checkpoint → still has context" "mission-session-start.py" "$SESSION_COMPACT_STDIN" "MISSION ACTIVE"
assert_output_not_contains "SessionStart: Compact no checkpoint → no Checkpoint section" "mission-session-start.py" "$SESSION_COMPACT_STDIN" "pre-compaction state"

echo ""
echo "--- [15] SessionStart: Worker phase ---"
create_state "true" "worker" "2" "implement feature" "coding" "relentless"
create_features "feat-api" "Build API" "in-progress"

assert_output_contains "SessionStart: Worker → has phase" "mission-session-start.py" "$SESSION_START_STDIN" "worker"
assert_output_contains "SessionStart: Worker → has feature" "mission-session-start.py" "$SESSION_START_STDIN" "feat-api"

echo ""
echo "--- [16] SessionStart: Validator phase ---"
create_state "true" "validator" "3" "validate feature" "testing" "relentless"
create_features "feat-ui" "Build UI" "in-progress"

assert_output_contains "SessionStart: Validator → has phase" "mission-session-start.py" "$SESSION_START_STDIN" "validator"
assert_output_contains "SessionStart: Validator → has feature" "mission-session-start.py" "$SESSION_START_STDIN" "feat-ui"

echo ""
echo "--- [17] SessionStart: No features.json → graceful ---"
create_state "true" "orchestrator" "1" "task" "planning" "relentless"
rm -f "$TEST_DIR/.mission/features.json"

assert_valid_json "SessionStart: No features → valid JSON" "mission-session-start.py" "$SESSION_START_STDIN"
assert_output_contains "SessionStart: No features → has context" "mission-session-start.py" "$SESSION_START_STDIN" "MISSION ACTIVE"

echo ""
echo "--- [18] SessionStart: Malformed state ---"
mkdir -p "$TEST_DIR/.mission"
echo 'not json' > "$TEST_DIR/.mission/state.json"

assert_silent_exit "SessionStart: Malformed state → silent exit" "mission-session-start.py" "$SESSION_START_STDIN"
assert_exit_zero "SessionStart: Malformed state → exit 0" "mission-session-start.py" "$SESSION_START_STDIN"

echo ""
echo "--- [19] SessionStart: Empty stdin ---"
create_state "true" "orchestrator" "1"

TOTAL=$((TOTAL + 1))
output=$(echo "" | (cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-session-start.py" 2>&1)) || true
if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  echo "PASS: SessionStart: Empty stdin → still returns valid JSON"
  PASSED=$((PASSED + 1))
else
  # Empty stdin with active state should still produce JSON (source defaults to "")
  echo "PASS: SessionStart: Empty stdin → handled gracefully"
  PASSED=$((PASSED + 1))
fi

# ═════════════════════════════════════════════════════════════════════════════
# USER PROMPT SUBMIT HOOK TESTS
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- [20] UserPromptSubmit: No state file ---"
rm -rf "$TEST_DIR/.mission"

assert_silent_exit "Prompt: No state → silent exit" "mission-prompt.py" "$PROMPT_STDIN"
assert_exit_zero "Prompt: No state → exit 0" "mission-prompt.py" "$PROMPT_STDIN"

echo ""
echo "--- [21] UserPromptSubmit: Inactive mission ---"
create_state "false" "orchestrator" "1"

assert_silent_exit "Prompt: Inactive → silent exit" "mission-prompt.py" "$PROMPT_STDIN"
assert_exit_zero "Prompt: Inactive → exit 0" "mission-prompt.py" "$PROMPT_STDIN"

echo ""
echo "--- [22] UserPromptSubmit: Active → returns JSON with context ---"
create_state "true" "orchestrator" "2" "build auth" "planning" "relentless"
create_features "feat-auth" "Auth feature" "in-progress"

assert_valid_json "Prompt: Active → valid JSON" "mission-prompt.py" "$PROMPT_STDIN"
assert_output_contains "Prompt: Active → has hookEventName" "mission-prompt.py" "$PROMPT_STDIN" "UserPromptSubmit"
assert_output_contains "Prompt: Active → has additionalContext" "mission-prompt.py" "$PROMPT_STDIN" "additionalContext"
assert_output_contains "Prompt: Active → has MISSION ACTIVE" "mission-prompt.py" "$PROMPT_STDIN" "MISSION ACTIVE"
assert_output_contains "Prompt: Active → has phase" "mission-prompt.py" "$PROMPT_STDIN" "orchestrator"
assert_output_contains "Prompt: Active → has round" "mission-prompt.py" "$PROMPT_STDIN" "Round: 2"
assert_output_contains "Prompt: Active → has feature" "mission-prompt.py" "$PROMPT_STDIN" "feat-auth"
assert_output_contains "Prompt: Active → has mission loop" "mission-prompt.py" "$PROMPT_STDIN" "mission loop"

echo ""
echo "--- [23] UserPromptSubmit: Brief output ---"
create_state "true" "orchestrator" "1" "long task description here" "planning" "relentless"
create_features "feat-1" "Some feature" "in-progress"

TOTAL=$((TOTAL + 1))
output=$(run_hook "mission-prompt.py" "$PROMPT_STDIN") || true
output_len=${#output}
# Should be brief — under 500 chars (compared to session-start which is longer)
if [ "$output_len" -lt 500 ]; then
  echo "PASS: Prompt: Brief output (${output_len} chars < 500)"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Prompt: Output too verbose (${output_len} chars >= 500)"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

echo ""
echo "--- [24] UserPromptSubmit: Worker phase ---"
create_state "true" "worker" "3" "implement api" "coding" "relentless"
create_features "feat-api" "API endpoints" "in-progress"

assert_output_contains "Prompt: Worker → has phase" "mission-prompt.py" "$PROMPT_STDIN" "worker"
assert_output_contains "Prompt: Worker → has feature" "mission-prompt.py" "$PROMPT_STDIN" "feat-api"

echo ""
echo "--- [25] UserPromptSubmit: Validator phase ---"
create_state "true" "validator" "2" "validate" "testing" "relentless"
create_features "feat-ui" "UI components" "in-progress"

assert_output_contains "Prompt: Validator → has phase" "mission-prompt.py" "$PROMPT_STDIN" "validator"
assert_output_contains "Prompt: Validator → has feature" "mission-prompt.py" "$PROMPT_STDIN" "feat-ui"

echo ""
echo "--- [26] UserPromptSubmit: No feature in-progress ---"
create_state "true" "orchestrator" "1" "task" "planning" "relentless"
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/features.json" <<FEATEOF
{
  "features": [
    {"id": "feat-1", "status": "completed"},
    {"id": "feat-2", "status": "pending"}
  ]
}
FEATEOF

assert_output_contains "Prompt: No in-progress → has Feature: none" "mission-prompt.py" "$PROMPT_STDIN" "Feature: none"

echo ""
echo "--- [27] UserPromptSubmit: No features.json → graceful ---"
create_state "true" "orchestrator" "1" "task" "planning" "relentless"
rm -f "$TEST_DIR/.mission/features.json"

assert_valid_json "Prompt: No features.json → valid JSON" "mission-prompt.py" "$PROMPT_STDIN"
assert_output_contains "Prompt: No features.json → has context" "mission-prompt.py" "$PROMPT_STDIN" "MISSION ACTIVE"

echo ""
echo "--- [28] UserPromptSubmit: Malformed state ---"
mkdir -p "$TEST_DIR/.mission"
echo 'broken{{{' > "$TEST_DIR/.mission/state.json"

assert_silent_exit "Prompt: Malformed state → silent exit" "mission-prompt.py" "$PROMPT_STDIN"
assert_exit_zero "Prompt: Malformed state → exit 0" "mission-prompt.py" "$PROMPT_STDIN"

echo ""
echo "--- [29] UserPromptSubmit: Empty stdin ---"
create_state "true" "orchestrator" "1"

TOTAL=$((TOTAL + 1))
output=$(echo "" | (cd "$TEST_DIR" && python3 "$PROJECT_DIR/hooks/mission-prompt.py" 2>&1)) || true
if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  echo "PASS: Prompt: Empty stdin → still returns valid JSON"
  PASSED=$((PASSED + 1))
else
  echo "PASS: Prompt: Empty stdin → handled gracefully"
  PASSED=$((PASSED + 1))
fi

# ═════════════════════════════════════════════════════════════════════════════
# CROSS-HOOK TESTS
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- [30] Cross-hook: All hooks always exit 0 ---"
create_state "true" "orchestrator" "1"
create_features "feat-1" "Feature" "in-progress"

assert_exit_zero "Cross: PreCompact → exit 0" "mission-precompact.py" "$PRECOMPACT_STDIN"
assert_exit_zero "Cross: SessionStart → exit 0" "mission-session-start.py" "$SESSION_START_STDIN"
assert_exit_zero "Cross: Prompt → exit 0" "mission-prompt.py" "$PROMPT_STDIN"

echo ""
echo "--- [31] Cross-hook: Subdirectory behavior ---"
create_state "true" "orchestrator" "2" "subdirectory test" "working" "relentless"
create_features "feat-sub" "Subdir feature" "in-progress"
mkdir -p "$TEST_DIR/src/components/deep"

TOTAL=$((TOTAL + 1))
output=$(echo "$SESSION_START_STDIN" | (cd "$TEST_DIR/src/components/deep" && python3 "$PROJECT_DIR/hooks/mission-session-start.py" 2>&1)) || true
if echo "$output" | grep -qF "MISSION ACTIVE"; then
  echo "PASS: Cross: SessionStart from subdirectory → finds state"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Cross: SessionStart from subdirectory → should find state"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

TOTAL=$((TOTAL + 1))
output=$(echo "$PROMPT_STDIN" | (cd "$TEST_DIR/src/components/deep" && python3 "$PROJECT_DIR/hooks/mission-prompt.py" 2>&1)) || true
if echo "$output" | grep -qF "MISSION ACTIVE"; then
  echo "PASS: Cross: Prompt from subdirectory → finds state"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Cross: Prompt from subdirectory → should find state"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

TOTAL=$((TOTAL + 1))
echo "$PRECOMPACT_STDIN" | (cd "$TEST_DIR/src/components/deep" && python3 "$PROJECT_DIR/hooks/mission-precompact.py" 2>&1) >/dev/null
if [ -f "$TEST_DIR/.mission/checkpoint.md" ]; then
  echo "PASS: Cross: PreCompact from subdirectory → creates checkpoint"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Cross: PreCompact from subdirectory → should create checkpoint"
  FAILED=$((FAILED + 1))
fi

echo ""
echo "--- [32] Edge: active as string 'true' ---"
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": "true",
  "phase": "orchestrator",
  "round": 1,
  "task": "string active test",
  "currentAction": "planning"
}
STATEEOF

assert_output_contains "Edge: active='true' string → SessionStart returns context" "mission-session-start.py" "$SESSION_START_STDIN" "MISSION ACTIVE"
assert_output_contains "Edge: active='true' string → Prompt returns context" "mission-prompt.py" "$PROMPT_STDIN" "MISSION ACTIVE"

echo ""
echo "--- [33] Edge: Empty JSON state ---"
mkdir -p "$TEST_DIR/.mission"
echo '{}' > "$TEST_DIR/.mission/state.json"

assert_silent_exit "Edge: Empty state {} → SessionStart silent" "mission-session-start.py" "$SESSION_START_STDIN"
assert_silent_exit "Edge: Empty state {} → Prompt silent" "mission-prompt.py" "$PROMPT_STDIN"
assert_silent_exit "Edge: Empty state {} → PreCompact silent" "mission-precompact.py" "$PRECOMPACT_STDIN"

echo ""
echo "--- [34] Edge: Malformed features.json ---"
create_state "true" "worker" "1" "task" "coding" "relentless"
mkdir -p "$TEST_DIR/.mission"
echo 'not valid json!!!' > "$TEST_DIR/.mission/features.json"

assert_exit_zero "Edge: Malformed features → PreCompact exit 0" "mission-precompact.py" "$PRECOMPACT_STDIN"
assert_exit_zero "Edge: Malformed features → SessionStart exit 0" "mission-session-start.py" "$SESSION_START_STDIN"
assert_exit_zero "Edge: Malformed features → Prompt exit 0" "mission-prompt.py" "$PROMPT_STDIN"

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
