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
# TEST GROUP: Symlink attacks
# ─────────────────────────────────────────────
echo ""
echo "--- Symlink attacks ---"

# Worker: symlink to .mission/state.json → BLOCK
create_state "worker"
ln -sf "$TEST_DIR/.mission/state.json" "$TEST_DIR/innocent-link"
assert_blocked "Worker: Write via symlink to .mission/state.json → BLOCK" "Write" "{\"file_path\":\"$TEST_DIR/innocent-link\"}"
rm -f "$TEST_DIR/innocent-link"

# Worker: symlink to .mission/plan.md → BLOCK
create_state "worker"
ln -sf "$TEST_DIR/.mission/plan.md" "$TEST_DIR/fake-source.ts"
echo "# plan" > "$TEST_DIR/.mission/plan.md"
assert_blocked "Worker: Write via symlink to .mission/plan.md → BLOCK" "Write" "{\"file_path\":\"$TEST_DIR/fake-source.ts\"}"
rm -f "$TEST_DIR/fake-source.ts"

# Validator: symlink to source file → BLOCK
create_state "validator"
echo "source" > "$TEST_DIR/src-file.ts"
ln -sf "$TEST_DIR/src-file.ts" "$TEST_DIR/fake-test.test.ts"
assert_blocked "Validator: Write via symlink to source file (disguised as test) → BLOCK" "Write" "{\"file_path\":\"$TEST_DIR/fake-test.test.ts\"}"
rm -f "$TEST_DIR/fake-test.test.ts" "$TEST_DIR/src-file.ts"

# Worker: symlink to .mission/reports → BLOCK
create_state "worker"
mkdir -p "$TEST_DIR/.mission/reports"
ln -sf "$TEST_DIR/.mission/reports/round-1.md" "$TEST_DIR/my-notes.md"
assert_blocked "Worker: Write via symlink to .mission/reports/ → BLOCK" "Write" "{\"file_path\":\"$TEST_DIR/my-notes.md\"}"
rm -f "$TEST_DIR/my-notes.md"

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
# Helper: create state with extended fields (v2)
# ─────────────────────────────────────────────
# Usage: create_state_v2 <phase> <active> <persistence> <strictPhaseLock> <phaseLockPhase> <phaseLockTimestamp>
create_state_v2() {
  local phase="$1"
  local active="${2:-true}"
  local persistence="${3:-standard}"
  local strict_phase_lock="${4:-false}"
  local phase_lock_phase="${5:-}"
  local phase_lock_timestamp="${6:-2026-03-28T10:05:00Z}"
  mkdir -p "$TEST_DIR/.mission"

  # Build phaseLock block conditionally
  local phase_lock_json="null"
  if [ -n "$phase_lock_phase" ]; then
    phase_lock_json=$(cat <<PEOF
{
    "phase": "$phase_lock_phase",
    "lockedAt": "$phase_lock_timestamp",
    "lockedBy": "orchestrator"
  }
PEOF
)
  fi

  cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": $active,
  "phase": "$phase",
  "task": "test task",
  "round": 1,
  "persistence": "$persistence",
  "strictPhaseLock": $strict_phase_lock,
  "phaseLock": $phase_lock_json
}
STATEEOF
}

# ─────────────────────────────────────────────
# TEST GROUP: Phase Lock Validation
# ─────────────────────────────────────────────
echo ""
echo "--- Phase lock validation ---"

# strictPhaseLock=true, phase matches phaseLock → ALLOW
create_state_v2 "worker" "true" "standard" "true" "worker"
assert_allowed "PhaseLock: strict=true, phase=worker, lock=worker → ALLOW" "Write" '{"file_path":"src/index.ts"}'

# strictPhaseLock=true, phase mismatches phaseLock → BLOCK
create_state_v2 "worker" "true" "standard" "true" "orchestrator"
assert_blocked "PhaseLock: strict=true, phase=worker, lock=orchestrator → BLOCK" "Write" '{"file_path":"src/index.ts"}'

# strictPhaseLock=true, mismatch on validator phase → BLOCK
create_state_v2 "validator" "true" "standard" "true" "worker"
assert_blocked "PhaseLock: strict=true, phase=validator, lock=worker → BLOCK" "Bash" '{"command":"npm test"}'

# strictPhaseLock=false, mismatch → ALLOW (lock not enforced)
create_state_v2 "worker" "true" "standard" "false" "orchestrator"
assert_allowed "PhaseLock: strict=false, phase=worker, lock=orchestrator → ALLOW" "Write" '{"file_path":"src/index.ts"}'

# strictPhaseLock missing but phaseLock has mismatched phase — defaults to strict=true, so BLOCK
# (Issue 2 fix: strictPhaseLock now defaults to true per docs, so missing field = strict enforcement)
mkdir -p "$TEST_DIR/.mission"
cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": true,
  "phase": "worker",
  "task": "test task",
  "round": 1,
  "phaseLock": {
    "phase": "orchestrator",
    "lockedAt": "2026-03-28T10:05:00Z",
    "lockedBy": "orchestrator"
  }
}
STATEEOF
assert_blocked "PhaseLock: no strictPhaseLock field + phaseLock mismatch → BLOCK (default strict=true)" "Write" '{"file_path":"src/index.ts"}'

# strictPhaseLock missing and NO phaseLock field at all → ALLOW (no lock to enforce)
create_state "worker"
assert_allowed "PhaseLock: no strictPhaseLock, no phaseLock → ALLOW (nothing to enforce)" "Write" '{"file_path":"src/index.ts"}'

# Missing phaseLock field entirely → ALLOW (backward compat)
create_state_v2 "worker" "true" "standard" "true" ""
assert_allowed "PhaseLock: strict=true but no phaseLock.phase → ALLOW (backward compat)" "Write" '{"file_path":"src/index.ts"}'

# strictPhaseLock=true, matching orchestrator phase → ALLOW orchestrator write to .mission
create_state_v2 "orchestrator" "true" "standard" "true" "orchestrator"
assert_allowed "PhaseLock: strict=true, orch phase matches lock → ALLOW .mission write" "Write" '{"file_path":".mission/plan.md"}'

# ─────────────────────────────────────────────
# TEST GROUP: Relentless Mode Enforcement
# ─────────────────────────────────────────────
echo ""
echo "--- Relentless mode enforcement ---"

# Relentless: block writing active=false without completedAt to state.json
create_state_v2 "orchestrator" "true" "relentless" "false" ""
assert_blocked "Relentless: Write active=false without completedAt → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"active\": false, \"phase\": \"orchestrator\"}"}'

# Relentless: allow writing active=false WITH completedAt to state.json (with report+summary for cleanup/defense-5 guards)
create_state_v2 "orchestrator" "true" "relentless" "false" ""
mkdir -p "$TEST_DIR/.mission/reports"
cat > "$TEST_DIR/.mission/reports/round-1.md" <<REOF
# Validator Report — Round 1
## Verdict: PASS
REOF
echo "# Mission Summary" > "$TEST_DIR/.mission/summary.md"
mkdir -p "$TEST_DIR/.mission/worker-logs"
assert_allowed "Relentless: Write active=false with completedAt → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"active\": false, \"completedAt\": \"2026-03-28T12:00:00Z\"}"}'

# Relentless: Edit with active=false without completedAt → BLOCK
create_state_v2 "orchestrator" "true" "relentless" "false" ""
assert_blocked "Relentless: Edit active=false without completedAt → BLOCK" "Edit" '{"file_path":".mission/state.json","new_string":"\"active\": false"}'

# Relentless: Edit with active=false AND completedAt → ALLOW (with report+summary for cleanup/defense-5 guards)
create_state_v2 "orchestrator" "true" "relentless" "false" ""
mkdir -p "$TEST_DIR/.mission/reports"
cat > "$TEST_DIR/.mission/reports/round-1.md" <<REOF
# Validator Report — Round 1
## Verdict: PASS
REOF
echo "# Mission Summary" > "$TEST_DIR/.mission/summary.md"
mkdir -p "$TEST_DIR/.mission/worker-logs"
assert_allowed "Relentless: Edit active=false with completedAt → ALLOW" "Edit" '{"file_path":".mission/state.json","new_string":"\"active\": false, \"completedAt\": \"2026-03-28T12:00:00Z\""}'

# Standard mode: allow writing active=false without completedAt (no relentless enforcement)
create_state_v2 "orchestrator" "true" "standard" "false" ""
assert_allowed "Standard: Write active=false without completedAt → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"active\": false}"}'

# Missing persistence field — defaults to "relentless" per docs, so active=false without completedAt is BLOCKED
# (Issue 1 fix: persistence now defaults to "relentless" instead of "standard")
create_state "orchestrator"
assert_blocked "No persistence field: Write active=false without completedAt → BLOCK (default relentless)" "Write" '{"file_path":".mission/state.json","content":"{\"active\": false}"}'

# Relentless: does NOT affect non-state.json writes
create_state_v2 "orchestrator" "true" "relentless" "false" ""
assert_allowed "Relentless: Write to .mission/plan.md (not state.json) → ALLOW" "Write" '{"file_path":".mission/plan.md","content":"updated plan"}'

# Relentless: allow writing to state.json without active=false (normal updates)
create_state_v2 "orchestrator" "true" "relentless" "false" ""
assert_allowed "Relentless: Write phase change (no active=false) → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"worker\", \"active\": true}"}'

# Relentless: compact format active:false also blocked
create_state_v2 "orchestrator" "true" "relentless" "false" ""
assert_blocked "Relentless: Write active:false (no space) without completedAt → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"active\":false}"}'

# Cautious mode: allow deactivation (only relentless blocks)
create_state_v2 "orchestrator" "true" "cautious" "false" ""
assert_allowed "Cautious: Write active=false → ALLOW (only relentless blocks)" "Write" '{"file_path":".mission/state.json","content":"{\"active\": false}"}'

# ─────────────────────────────────────────────
# TEST GROUP: Phase transition validation
# ─────────────────────────────────────────────
echo ""
echo "--- Phase transition validation ---"

# Valid transition: orchestrator → worker
create_state_v2 "orchestrator" "true" "standard" "false" ""
assert_allowed "Transition: orchestrator → worker → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"worker\", \"active\": true}"}'

# Valid transition: orchestrator → validator
create_state_v2 "orchestrator" "true" "standard" "false" ""
assert_allowed "Transition: orchestrator → validator → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"validator\", \"active\": true}"}'

# Valid transition: orchestrator → complete (requires report for completion guard)
create_state_v2 "orchestrator" "true" "standard" "false" ""
mkdir -p "$TEST_DIR/.mission/reports"
cat > "$TEST_DIR/.mission/reports/round-1.md" <<REOF
# Validator Report — Round 1
## Verdict: PASS
REOF
assert_allowed "Transition: orchestrator → complete → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"complete\", \"active\": true}"}'

# Same-phase write: orchestrator → orchestrator (updating state within same phase)
create_state_v2 "orchestrator" "true" "standard" "false" ""
assert_allowed "Transition: orchestrator → orchestrator (same phase) → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"orchestrator\", \"active\": true}"}'

# Invalid: unknown phase value
create_state_v2 "orchestrator" "true" "standard" "false" ""
assert_blocked "Transition: orchestrator → unknown phase 'hacking' → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"hacking\", \"active\": true}"}'

# Invalid transition: worker → complete (only orchestrator can complete)
create_state_v2 "worker" "true" "standard" "false" ""
# Note: worker can't write state.json (blocked by phase enforcement below),
# but the transition check runs first as defense-in-depth
assert_blocked "Transition: worker → complete → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"complete\", \"active\": true}"}'

# Invalid transition: validator → worker
create_state_v2 "validator" "true" "standard" "false" ""
assert_blocked "Transition: validator → worker → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"worker\", \"active\": true}"}'

# Invalid transition: worker → orchestrator
create_state_v2 "worker" "true" "standard" "false" ""
assert_blocked "Transition: worker → orchestrator → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"orchestrator\", \"active\": true}"}'

# Valid transition: worker → validator
create_state_v2 "worker" "true" "standard" "false" ""
# Note: worker can't write state.json (phase enforcement), but transition check itself allows it
assert_blocked "Transition: worker → validator via Write state.json → BLOCK (worker can't write state.json)" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"validator\", \"active\": true}"}'

# Valid transition: validator → orchestrator
create_state_v2 "validator" "true" "standard" "false" ""
# Note: validator can't write state.json either, blocked by phase enforcement
assert_blocked "Transition: validator → orchestrator via Write state.json → BLOCK (validator can't write state.json)" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"orchestrator\", \"active\": true}"}'

# No phase in content → transition check skipped, normal rules apply
create_state_v2 "orchestrator" "true" "standard" "false" ""
assert_allowed "Transition: no phase in content → skip check → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"active\": true, \"round\": 2}"}'

# Edit with phase value via regex fallback (non-JSON content)
create_state_v2 "orchestrator" "true" "standard" "false" ""
assert_allowed "Transition: Edit with phase via regex → orchestrator → worker → ALLOW" "Edit" '{"file_path":".mission/state.json","new_string":"\"phase\": \"worker\""}'

# Edit with unknown phase via regex fallback
create_state_v2 "orchestrator" "true" "standard" "false" ""
assert_blocked "Transition: Edit with unknown phase via regex → BLOCK" "Edit" '{"file_path":".mission/state.json","new_string":"\"phase\": \"badphase\""}'

# ─────────────────────────────────────────────
# TEST GROUP: Improved error messages
# ─────────────────────────────────────────────
echo ""
echo "--- Improved error messages ---"

# Error message includes phase lock info when phaseLock is present
create_state_v2 "worker" "true" "standard" "false" "worker" "2026-03-28T10:05:00Z"
output=$(run_guard "Write" '{"file_path":".mission/state.json"}' 2>&1) || true
TOTAL=$((TOTAL + 1))
if echo "$output" | grep -q '\[Lock: worker since 2026-03-28T10:05:00Z\]'; then
  echo "PASS: Error message includes phase lock info"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Error message missing phase lock info"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# Error message includes guidance text
create_state_v2 "worker" "true" "standard" "false" "" ""
output=$(run_guard "Bash" '{"command":"npm test"}' 2>&1) || true
TOTAL=$((TOTAL + 1))
if echo "$output" | grep -q "Validator's job"; then
  echo "PASS: Error message includes guidance"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Error message missing guidance"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# Error message includes phase name
create_state_v2 "orchestrator" "true" "standard" "false" "" ""
output=$(run_guard "Write" '{"file_path":"src/index.ts"}' 2>&1) || true
TOTAL=$((TOTAL + 1))
if echo "$output" | grep -q 'Phase "orchestrator"'; then
  echo "PASS: Error message includes phase name"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Error message missing phase name"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# Relentless block message includes relentless context
create_state_v2 "orchestrator" "true" "relentless" "false" "" ""
output=$(run_guard "Write" '{"file_path":".mission/state.json","content":"{\"active\": false}"}' 2>&1) || true
TOTAL=$((TOTAL + 1))
if echo "$output" | grep -q "Relentless mode"; then
  echo "PASS: Relentless block message includes mode context"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Relentless block message missing mode context"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# Phase lock conflict message includes both phases
create_state_v2 "worker" "true" "standard" "true" "orchestrator" "2026-03-28T10:05:00Z"
output=$(run_guard "Write" '{"file_path":"src/index.ts"}' 2>&1) || true
TOTAL=$((TOTAL + 1))
if echo "$output" | grep -q 'phaseLock is "orchestrator"' && echo "$output" | grep -q 'phase is "worker"'; then
  echo "PASS: Phase lock conflict message includes both phases"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: Phase lock conflict message missing phase details"
  echo "  output: $output"
  FAILED=$((FAILED + 1))
fi

# ─────────────────────────────────────────────
# Helper: create state with v3 fields (round)
# ─────────────────────────────────────────────
# Usage: create_state_v3 <phase> <active> <persistence> <strictPhaseLock> <phaseLockPhase> <round>
create_state_v3() {
  local phase="$1"
  local active="${2:-true}"
  local persistence="${3:-standard}"
  local strict_phase_lock="${4:-false}"
  local phase_lock_phase="${5:-}"
  local round="${6:-1}"
  mkdir -p "$TEST_DIR/.mission"
  mkdir -p "$TEST_DIR/.mission/reports"

  # Build phaseLock block conditionally
  local phase_lock_json="null"
  if [ -n "$phase_lock_phase" ]; then
    phase_lock_json=$(cat <<PEOF
{
    "phase": "$phase_lock_phase",
    "lockedAt": "2026-03-28T10:05:00Z",
    "lockedBy": "orchestrator"
  }
PEOF
)
  fi

  cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": $active,
  "phase": "$phase",
  "task": "test task",
  "round": $round,
  "persistence": "$persistence",
  "strictPhaseLock": $strict_phase_lock,
  "phaseLock": $phase_lock_json
}
STATEEOF
  # Clean up reports/summary/worker-logs from previous test
  rm -rf "$TEST_DIR/.mission/reports"
  rm -f "$TEST_DIR/.mission/summary.md"
  rm -rf "$TEST_DIR/.mission/worker-logs"
  mkdir -p "$TEST_DIR/.mission/reports"
}

# Helper: create a validator report file
create_report() {
  local round="$1"
  local verdict="${2:-PASS}"
  mkdir -p "$TEST_DIR/.mission/reports"
  cat > "$TEST_DIR/.mission/reports/round-${round}.md" <<REOF
# Validator Report — Round $round
## Verdict: $verdict
REOF
}

# Helper: create summary.md
create_summary() {
  mkdir -p "$TEST_DIR/.mission"
  echo "# Mission Summary" > "$TEST_DIR/.mission/summary.md"
}

# Helper: create a worker log file
create_worker_log() {
  local worker_id="$1"
  mkdir -p "$TEST_DIR/.mission/worker-logs"
  echo "# Worker $worker_id Output" > "$TEST_DIR/.mission/worker-logs/worker-${worker_id}.md"
}

# ─────────────────────────────────────────────
# TEST GROUP: Completion guard
# ─────────────────────────────────────────────
echo ""
echo "--- Completion guard ---"

# Complete without report → BLOCK
create_state_v3 "orchestrator" "true" "standard" "false" "" "1"
assert_blocked "Complete: no report exists → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"complete\", \"active\": true}"}'

# Complete with report (standard mode) → ALLOW
create_state_v3 "orchestrator" "true" "standard" "false" "" "1"
create_report 1 "PASS"
assert_allowed "Complete: report exists (standard) → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"complete\", \"active\": true}"}'

# Complete with FAIL report (standard mode) → ALLOW (standard doesn't check content)
create_state_v3 "orchestrator" "true" "standard" "false" "" "1"
create_report 1 "FAIL"
assert_allowed "Complete: FAIL report (standard) → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"complete\", \"active\": true}"}'

# Complete with PASS report (relentless) → ALLOW
create_state_v3 "orchestrator" "true" "relentless" "false" "" "1"
create_report 1 "PASS"
assert_allowed "Complete: PASS report (relentless) → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"complete\", \"active\": true}"}'

# Complete with FAIL report (relentless) → BLOCK
create_state_v3 "orchestrator" "true" "relentless" "false" "" "1"
create_report 1 "FAIL"
assert_blocked "Complete: FAIL report (relentless) → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"complete\", \"active\": true}"}'

# Complete with empty report (relentless) → BLOCK (no Verdict: PASS found)
create_state_v3 "orchestrator" "true" "relentless" "false" "" "1"
mkdir -p "$TEST_DIR/.mission/reports"
echo "" > "$TEST_DIR/.mission/reports/round-1.md"
assert_blocked "Complete: empty report (relentless) → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"complete\", \"active\": true}"}'

# Complete round 2 with report for round 2 → ALLOW
create_state_v3 "orchestrator" "true" "standard" "false" "" "2"
create_report 2 "PASS"
assert_allowed "Complete: round 2 with round-2 report → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"complete\", \"active\": true}"}'

# Complete round 2 but only round 1 report exists → BLOCK
create_state_v3 "orchestrator" "true" "standard" "false" "" "2"
create_report 1 "PASS"
assert_blocked "Complete: round 2 but only round-1 report → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"phase\": \"complete\", \"active\": true}"}'

# ─────────────────────────────────────────────
# TEST GROUP: Mandatory cleanup guard
# ─────────────────────────────────────────────
echo ""
echo "--- Mandatory cleanup guard ---"

# Deactivate without summary.md → BLOCK
create_state_v3 "orchestrator" "true" "standard" "false" "" "1"
create_report 1 "PASS"
mkdir -p "$TEST_DIR/.mission/worker-logs"
assert_blocked "Cleanup: no summary.md → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"active\": false, \"completedAt\": \"2026-03-28T12:00:00Z\", \"phase\": \"complete\"}"}'

# Deactivate with summary but leftover worker-logs → BLOCK
create_state_v3 "orchestrator" "true" "standard" "false" "" "1"
create_report 1 "PASS"
create_summary
create_worker_log 1
assert_blocked "Cleanup: summary exists but worker-logs not cleaned → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"active\": false, \"completedAt\": \"2026-03-28T12:00:00Z\", \"phase\": \"complete\"}"}'

# Deactivate with summary and empty worker-logs → ALLOW
create_state_v3 "orchestrator" "true" "standard" "false" "" "1"
create_report 1 "PASS"
create_summary
mkdir -p "$TEST_DIR/.mission/worker-logs"
assert_allowed "Cleanup: summary exists, worker-logs clean → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"active\": false, \"completedAt\": \"2026-03-28T12:00:00Z\", \"phase\": \"complete\"}"}'

# Cleanup applies in relentless mode too (no summary)
create_state_v3 "orchestrator" "true" "relentless" "false" "" "1"
create_report 1 "PASS"
mkdir -p "$TEST_DIR/.mission/worker-logs"
assert_blocked "Cleanup: relentless mode, no summary → BLOCK" "Write" '{"file_path":".mission/state.json","content":"{\"active\": false, \"completedAt\": \"2026-03-28T12:00:00Z\", \"phase\": \"complete\"}"}'

# Cleanup with everything correct in relentless mode
create_state_v3 "orchestrator" "true" "relentless" "false" "" "1"
create_report 1 "PASS"
create_summary
mkdir -p "$TEST_DIR/.mission/worker-logs"
assert_allowed "Cleanup: relentless, summary + clean logs → ALLOW" "Write" '{"file_path":".mission/state.json","content":"{\"active\": false, \"completedAt\": \"2026-03-28T12:00:00Z\", \"phase\": \"complete\"}"}'

# Cleanup check does NOT apply to force-exit (active=false without completedAt)
# In standard mode, active=false without completedAt is allowed (no cleanup needed for force-exit)
# Note: force-exit sets active=false without phase change, so no completion guard trigger
create_state_v3 "orchestrator" "true" "standard" "false" "" "1"
assert_allowed "Cleanup: force-exit (no completedAt) in standard → ALLOW (no cleanup needed)" "Write" '{"file_path":".mission/state.json","content":"{\"active\": false, \"phase\": \"orchestrator\"}"}'

# ─────────────────────────────────────────────
# TEST GROUP: Worker test file block
# ─────────────────────────────────────────────
echo ""
echo "--- Worker test file block ---"

create_state "worker"
assert_blocked "Worker: Write src/index.test.ts → BLOCK" "Write" '{"file_path":"src/index.test.ts"}'
assert_blocked "Worker: Write src/app.spec.ts → BLOCK" "Write" '{"file_path":"src/app.spec.ts"}'
assert_blocked "Worker: Write tests/test_main.py → BLOCK" "Write" '{"file_path":"tests/test_main.py"}'
assert_blocked "Worker: Write __tests__/app.js → BLOCK" "Write" '{"file_path":"__tests__/app.js"}'
assert_blocked "Worker: Write main_test.go → BLOCK" "Write" '{"file_path":"main_test.go"}'
assert_blocked "Worker: Edit src/index.test.ts → BLOCK" "Edit" '{"file_path":"src/index.test.ts"}'
assert_allowed "Worker: Write src/index.ts (not test) → ALLOW" "Write" '{"file_path":"src/index.ts"}'
assert_allowed "Worker: Write .mission/worker-logs/worker-1.md (not blocked by test guard) → ALLOW" "Write" '{"file_path":".mission/worker-logs/worker-1.md"}'

# ─────────────────────────────────────────────
# TEST GROUP: Validator .mission/ restriction
# ─────────────────────────────────────────────
echo ""
echo "--- Validator .mission/ restriction ---"

create_state "validator"
assert_allowed "Validator: Write .mission/reports/round-1.md → ALLOW" "Write" '{"file_path":".mission/reports/round-1.md"}'
assert_allowed "Validator: Write .mission/reports/round-5.md → ALLOW" "Write" '{"file_path":".mission/reports/round-5.md"}'
assert_blocked "Validator: Write .mission/plan.md → BLOCK" "Write" '{"file_path":".mission/plan.md"}'
assert_blocked "Validator: Write .mission/summary.md → BLOCK" "Write" '{"file_path":".mission/summary.md"}'
assert_blocked "Validator: Write .mission/worker-logs/worker-1.md → BLOCK" "Write" '{"file_path":".mission/worker-logs/worker-1.md"}'
assert_blocked "Validator: Edit .mission/plan.md → BLOCK" "Edit" '{"file_path":".mission/plan.md"}'
assert_allowed "Validator: Edit .mission/reports/round-1.md → ALLOW" "Edit" '{"file_path":".mission/reports/round-1.md"}'

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
