#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# REAL-WORLD MISSION LIFECYCLE SIMULATION
# Simulates exactly how Claude Code invokes each hook during a mission
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SIM_DIR=$(mktemp -d)
PASS=0; FAIL=0; TOTAL=0

cleanup() { rm -rf "$SIM_DIR"; }
trap cleanup EXIT

ok()   { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo "  FAIL: $1"; echo "    GOT: $2"; }

check_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then ok "$desc (exit=$actual)"
  else fail "$desc -- expected exit $expected" "exit $actual"; fi
}

check_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then ok "$desc"
  else fail "$desc -- missing: $needle" "${haystack:0:200}"; fi
}

check_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then fail "$desc -- should NOT contain: $needle" "${haystack:0:200}"
  else ok "$desc"; fi
}

echo "=== REAL-WORLD MISSION LIFECYCLE SIMULATION ==="
echo ""
echo "--- PHASE 1: No Mission Active -- all hooks inert ---"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"src/main.py","content":"hello"}' 2>&1) || ec=$?
check_exit "phase-guard: no state -> ALLOW" "0" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-reminder.py" "Read" 2>&1) || ec=$?
check_exit "reminder: no state -> exit 0" "0" "$ec"
[ -z "$out" ] && ok "reminder: no output" || fail "reminder: should be silent" "$out"

ec=0; out=$(echo '{}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-stop.py") 2>&1) || ec=$?
check_exit "stop: no state -> allow" "0" "$ec"

ec=0; out=$(echo '{"source":"startup"}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-session-start.py") 2>&1) || ec=$?
check_exit "session-start: no state -> exit 0" "0" "$ec"
[ -z "$out" ] && ok "session-start: no output" || fail "session-start: should be silent" "$out"

echo ""
echo "--- PHASE 2: Mission Init -- Orchestrator creates state ---"

mkdir -p "$SIM_DIR/.mission/reports" "$SIM_DIR/.mission/worker-logs"
cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{
  "active": true,
  "phase": "orchestrator",
  "task": "Build user authentication system",
  "round": 1,
  "persistence": "relentless",
  "strictPhaseLock": false,
  "currentAction": "planning features",
  "models": {"orchestrator": "opus", "worker": "opus", "validator": "opus"}
}
STATE

ec=0; out=$(echo '{"source":"startup"}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-session-start.py") 2>&1) || ec=$?
check_exit "session-start: active -> exit 0" "0" "$ec"
check_contains "session-start: returns JSON with context" "$out" "additionalContext"
check_contains "session-start: has MISSION ACTIVE" "$out" "MISSION ACTIVE"
check_contains "session-start: has AUTO-RESUME" "$out" "AUTO-RESUME"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-reminder.py" "Read" 2>&1) || ec=$?
check_contains "reminder: orch has MISSION SKILL ACTIVE" "$out" "[MISSION SKILL ACTIVE"
check_contains "reminder: orch has features.json directive" "$out" "features.json"

# Orchestrator can write to .mission/
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/features.json","content":"{}"}' 2>&1) || ec=$?
check_exit "phase-guard: orch write .mission/ -> ALLOW" "0" "$ec"

# Orchestrator CANNOT write source files
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/src/auth.py","content":"pass"}' 2>&1) || ec=$?
check_exit "phase-guard: orch write source -> BLOCK" "1" "$ec"
check_contains "phase-guard: orch block msg" "$out" "BLOCK"

echo ""
echo "--- PHASE 3: Orchestrator creates features.json ---"

cat > "$SIM_DIR/.mission/features.json" << 'FEAT'
{
  "features": [
    {"id": "auth-login", "description": "Login endpoint with JWT", "status": "pending", "dependencies": []},
    {"id": "auth-register", "description": "Registration endpoint", "status": "pending", "dependencies": []},
    {"id": "auth-middleware", "description": "JWT middleware guard", "status": "pending", "dependencies": ["auth-login"]}
  ]
}
FEAT

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-reminder.py" "Read" 2>&1) || ec=$?
check_contains "reminder: has mission loop" "$out" "mission loop"
check_not_contains "reminder: no research directive" "$out" "research MUST lead"

echo ""
echo "--- PHASE 4: Orchestrator dispatches Worker (model enforcement) ---"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Agent" '{"subagent_type":"mission-worker","model":"opus","prompt":"implement auth-login"}' 2>&1) || ec=$?
check_exit "model: correct opus -> ALLOW" "0" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Agent" '{"subagent_type":"mission-worker","model":"haiku","prompt":"implement"}' 2>&1) || ec=$?
check_exit "model: wrong haiku -> BLOCK" "1" "$ec"
check_contains "model: block msg has MISSION GUARD" "$out" "MISSION GUARD"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Agent" '{"subagent_type":"mission-worker","prompt":"implement auth-login"}' 2>&1) || ec=$?
check_exit "model: missing -> inject (exit 0)" "0" "$ec"
check_contains "model: injected opus in output" "$out" '"model": "opus"'

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Agent" '{"subagent_type":"code-reviewer","model":"haiku"}' 2>&1) || ec=$?
check_exit "model: non-mission agent -> ALLOW" "0" "$ec"

echo ""
echo "--- PHASE 5: Worker phase -- role enforcement ---"

cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{
  "active": true, "phase": "worker", "task": "Build auth", "round": 1,
  "persistence": "relentless", "strictPhaseLock": false,
  "currentAction": "implementing auth-login"
}
STATE

python3 -c "
import json
with open('$SIM_DIR/.mission/features.json') as f: data = json.load(f)
data['features'][0]['status'] = 'in-progress'
with open('$SIM_DIR/.mission/features.json', 'w') as f: json.dump(data, f, indent=2)
"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/src/auth.py","content":"def login(): pass"}' 2>&1) || ec=$?
check_exit "worker: write source -> ALLOW" "0" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/worker-logs/w1.md","content":"# Handoff"}' 2>&1) || ec=$?
check_exit "worker: write worker-logs -> ALLOW" "0" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{}"}' 2>&1) || ec=$?
check_exit "worker: write state.json -> BLOCK" "1" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/tests/test_auth.py","content":"def test(): pass"}' 2>&1) || ec=$?
check_exit "worker: write test file -> BLOCK" "1" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Bash" '{"command":"pytest tests/"}' 2>&1) || ec=$?
check_exit "worker: run pytest -> BLOCK" "1" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Bash" '{"command":"npm run build"}' 2>&1) || ec=$?
check_exit "worker: run build -> ALLOW" "0" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Agent" '{"subagent_type":"mission-validator"}' 2>&1) || ec=$?
check_exit "worker: spawn validator -> BLOCK" "1" "$ec"

# Data file that looks like test but is NOT code -> ALLOW
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/test_data.json","content":"{}"}' 2>&1) || ec=$?
check_exit "worker: write test_data.json (data) -> ALLOW" "0" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-reminder.py" "Write" 2>&1) || ec=$?
check_contains "reminder: worker has feature id" "$out" "auth-login"
check_contains "reminder: worker has handoff directive" "$out" "handoff"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-continue.py" "Agent" 2>&1) || ec=$?
check_contains "continue: worker+Agent has MISSION ACTIVE" "$out" "[MISSION ACTIVE]"
check_contains "continue: worker+Agent has handoff" "$out" "structured handoff"

ec=0; out=$(echo '{"stop_hook_active":false}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-stop.py") 2>&1) || ec=$?
check_contains "stop: blocks worker" "$out" '"decision": "block"'

ec=0; out=$(echo '{"stop_hook_active":false}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-subagent-stop.py") 2>&1) || ec=$?
check_contains "subagent-stop: blocks worker" "$out" '"decision": "block"'

ec=0; out=$(echo '{"stop_hook_active":true}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-stop.py") 2>&1) || ec=$?
[ -z "$out" ] && ok "stop: stop_hook_active=true -> allow (no output)" || fail "stop: should allow" "$out"

echo ""
echo "--- PHASE 6: Validator phase -- role enforcement ---"

cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{
  "active": true, "phase": "validator", "task": "Build auth", "round": 1,
  "persistence": "relentless", "strictPhaseLock": false
}
STATE

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/tests/test_auth.py","content":"import pytest"}' 2>&1) || ec=$?
check_exit "validator: write test file -> ALLOW" "0" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/reports/round-1.md","content":"## Verdict: PASS"}' 2>&1) || ec=$?
check_exit "validator: write report -> ALLOW" "0" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/src/auth.py","content":"hacked"}' 2>&1) || ec=$?
check_exit "validator: write source -> BLOCK" "1" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{}"}' 2>&1) || ec=$?
check_exit "validator: write state.json -> BLOCK" "1" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/plan.md","content":"# Plan"}' 2>&1) || ec=$?
check_exit "validator: write plan.md -> BLOCK" "1" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Agent" '{"subagent_type":"mission-worker"}' 2>&1) || ec=$?
check_exit "validator: spawn worker -> BLOCK" "1" "$ec"

ec=0; out=$(echo '{"stop_hook_active":false}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-subagent-stop.py") 2>&1) || ec=$?
check_contains "subagent-stop: blocks validator" "$out" '"decision": "block"'

echo ""
echo "--- PHASE 7: Completion gate -- relentless mode ---"

cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{
  "active": true, "phase": "orchestrator", "task": "Build auth", "round": 1,
  "persistence": "relentless", "strictPhaseLock": false
}
STATE

# No report -> BLOCK
rm -f "$SIM_DIR/.mission/reports/round-1.md"
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"phase\":\"complete\",\"active\":true,\"round\":1,\"persistence\":\"relentless\"}"}' 2>&1) || ec=$?
check_exit "completion: no report -> BLOCK" "1" "$ec"

# Report with FAIL -> BLOCK
printf "# Round 1 Report\n\n## Verdict: FAIL\n\n3 critical issues." > "$SIM_DIR/.mission/reports/round-1.md"
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"phase\":\"complete\",\"active\":true,\"round\":1,\"persistence\":\"relentless\"}"}' 2>&1) || ec=$?
check_exit "completion: FAIL report -> BLOCK" "1" "$ec"

# CRITICAL FIX: Report "Verdict: FAIL" with word PASS elsewhere -> BLOCK
printf "# Round 1\n\n## Verdict: FAIL\n\nPrevious round had PASS but regression found." > "$SIM_DIR/.mission/reports/round-1.md"
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"phase\":\"complete\",\"active\":true,\"round\":1,\"persistence\":\"relentless\"}"}' 2>&1) || ec=$?
check_exit "CRITICAL FIX: verdict FAIL+PASS text -> BLOCK" "1" "$ec"

# Report with PASS -> ALLOW
printf "# Round 1 Report\n\n## Verdict: PASS\n\nAll tests pass." > "$SIM_DIR/.mission/reports/round-1.md"
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"phase\":\"complete\",\"active\":true,\"round\":1,\"persistence\":\"relentless\"}"}' 2>&1) || ec=$?
check_exit "completion: PASS report -> ALLOW" "0" "$ec"

echo ""
echo "--- PHASE 8: Cleanup guard ---"

# No summary -> BLOCK
rm -f "$SIM_DIR/.mission/summary.md"
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"active\":false,\"completedAt\":\"2026-03-29\",\"phase\":\"orchestrator\",\"round\":1,\"persistence\":\"relentless\"}"}' 2>&1) || ec=$?
check_exit "cleanup: no summary -> BLOCK" "1" "$ec"

# Summary + worker-logs -> BLOCK
echo "# Summary" > "$SIM_DIR/.mission/summary.md"
echo "log" > "$SIM_DIR/.mission/worker-logs/w1.md"
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"active\":false,\"completedAt\":\"2026-03-29\",\"phase\":\"orchestrator\",\"round\":1,\"persistence\":\"relentless\"}"}' 2>&1) || ec=$?
check_exit "cleanup: logs remain -> BLOCK" "1" "$ec"

# Clean -> ALLOW
rm "$SIM_DIR/.mission/worker-logs/w1.md"
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"active\":false,\"completedAt\":\"2026-03-29\",\"phase\":\"orchestrator\",\"round\":1,\"persistence\":\"relentless\"}"}' 2>&1) || ec=$?
check_exit "cleanup: clean state -> ALLOW" "0" "$ec"

echo ""
echo "--- PHASE 9: CRITICAL FIX -- exit-mission bypass ---"

cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{"active": true, "phase": "worker", "task": "Build auth", "round": 1, "persistence": "relentless", "strictPhaseLock": false}
STATE

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"endedAt\":\"2026-03-29T00:00:00Z\"}"}' 2>&1) || ec=$?
check_exit "CRITICAL: worker endedAt -> BLOCK" "1" "$ec"
check_contains "CRITICAL: msg mentions Orchestrator" "$out" "Orchestrator"

cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{"active": true, "phase": "orchestrator", "task": "Build auth", "round": 1, "persistence": "relentless"}
STATE
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"endedAt\":\"2026-03-29T00:00:00Z\"}"}' 2>&1) || ec=$?
check_exit "CRITICAL: orchestrator endedAt -> ALLOW" "0" "$ec"

echo ""
echo "--- PHASE 10: CRITICAL FIX -- MultiEdit content extraction ---"

cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{"active": true, "phase": "orchestrator", "task": "Build auth", "round": 1, "persistence": "relentless"}
STATE
rm -f "$SIM_DIR/.mission/summary.md"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "MultiEdit" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","edits":[{"old_string":"active","new_string":"{\"active\": false, \"completedAt\": \"2026-03-29\"}"}]}' 2>&1) || ec=$?
check_exit "CRITICAL: MultiEdit completedAt -> BLOCK (cleanup)" "1" "$ec"
check_contains "CRITICAL: MultiEdit block mentions summary" "$out" "summary.md"

echo ""
echo "--- PHASE 11: PreCompact checkpoint ---"

cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{"active": true, "phase": "orchestrator", "task": "Build auth", "round": 2, "persistence": "relentless", "currentAction": "reviewing validator report"}
STATE

python3 -c "
import json
with open('$SIM_DIR/.mission/features.json') as f: data = json.load(f)
data['features'][0]['status'] = 'completed'
data['features'][1]['status'] = 'in-progress'
with open('$SIM_DIR/.mission/features.json', 'w') as f: json.dump(data, f, indent=2)
"

ec=0; out=$(echo '{"trigger":"auto"}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-precompact.py") 2>&1) || ec=$?
check_exit "precompact: exit 0" "0" "$ec"
[ -f "$SIM_DIR/.mission/checkpoint.md" ] && ok "precompact: checkpoint.md created" || fail "precompact: missing checkpoint.md" "not found"

ckpt=$(cat "$SIM_DIR/.mission/checkpoint.md")
check_contains "checkpoint: has phase" "$ckpt" "**Phase:** orchestrator"
check_contains "checkpoint: has round" "$ckpt" "**Round:** 2"
check_contains "checkpoint: has task" "$ckpt" "**Task:** Build auth"
check_contains "checkpoint: has resume" "$ckpt" "Resume Instructions"

echo ""
echo "--- PHASE 12: SessionStart compact recovery ---"

ec=0; out=$(echo '{"source":"compact"}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-session-start.py") 2>&1) || ec=$?
check_contains "session-start compact: has checkpoint" "$out" "Checkpoint"

ec=0; out=$(echo '{"source":"startup"}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-session-start.py") 2>&1) || ec=$?
check_not_contains "session-start startup: no checkpoint" "$out" "pre-compaction state"

echo ""
echo "--- PHASE 13: UserPromptSubmit ---"

ec=0; out=$(echo '{"prompt":"continue"}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-prompt.py") 2>&1) || ec=$?
check_exit "prompt: exit 0" "0" "$ec"
check_contains "prompt: valid JSON" "$out" "additionalContext"
check_contains "prompt: has MISSION ACTIVE" "$out" "MISSION ACTIVE"

echo ""
echo "--- PHASE 14: Phase lock enforcement ---"

cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{
  "active": true, "phase": "worker", "task": "Build auth", "round": 1,
  "persistence": "relentless", "strictPhaseLock": true,
  "phaseLock": {"phase": "orchestrator", "lockedAt": "2026-03-29T10:00:00Z"}
}
STATE

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/src/foo.py","content":"x=1"}' 2>&1) || ec=$?
check_exit "phase-lock: mismatch -> BLOCK" "1" "$ec"
check_contains "phase-lock: msg mentions conflict" "$out" "Phase lock conflict"

echo ""
echo "--- PHASE 15: Phase transition validation (orchestrator writes state) ---"

# Valid: orchestrator->worker
cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{"active": true, "phase": "orchestrator", "task": "Build auth", "round": 1, "persistence": "standard", "strictPhaseLock": false}
STATE
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"phase\":\"worker\"}"}' 2>&1) || ec=$?
check_exit "transition: orchestrator->worker -> ALLOW" "0" "$ec"

# Valid: orchestrator->validator
cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{"active": true, "phase": "orchestrator", "task": "Build auth", "round": 1, "persistence": "standard", "strictPhaseLock": false}
STATE
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"phase\":\"validator\"}"}' 2>&1) || ec=$?
check_exit "transition: orchestrator->validator -> ALLOW" "0" "$ec"

# Invalid: orchestrator directly to itself (same-phase = allowed, no transition)
# Invalid: worker->orchestrator (worker can't write state.json at all)
cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{"active": true, "phase": "worker", "task": "Build auth", "round": 1, "persistence": "standard", "strictPhaseLock": false}
STATE
ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/.mission/state.json","content":"{\"phase\":\"orchestrator\"}"}' 2>&1) || ec=$?
check_exit "transition: worker can't write state.json -> BLOCK" "1" "$ec"

echo ""
echo "--- PHASE 16: Failed feature counting ---"

cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{"active": true, "phase": "orchestrator", "task": "Build auth", "round": 2, "persistence": "relentless", "currentAction": "reviewing"}
STATE
cat > "$SIM_DIR/.mission/features.json" << 'FEAT'
{
  "features": [
    {"id": "f1", "status": "completed"},
    {"id": "f2", "status": "failed"},
    {"id": "f3", "status": "failed"}
  ]
}
FEAT

ec=0; out=$(echo '{"trigger":"auto"}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-precompact.py") 2>&1) || ec=$?
ckpt=$(cat "$SIM_DIR/.mission/checkpoint.md")
check_contains "failed count: shows failed: 2" "$ckpt" "failed: 2"
check_contains "failed count: shows completed: 1" "$ckpt" "completed: 1"
check_contains "failed action: mentions re-scope or failed" "$ckpt" "failed"

echo ""
echo "--- PHASE 17: Mission complete -> stop hook allows ---"

cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{"active": true, "phase": "complete", "task": "Build auth", "round": 3}
STATE

ec=0; out=$(echo '{"stop_hook_active":false}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-stop.py") 2>&1) || ec=$?
[ -z "$out" ] && ok "stop: complete phase -> allow" || fail "stop: should allow" "$out"

ec=0; out=$(echo '{"stop_hook_active":false}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-subagent-stop.py") 2>&1) || ec=$?
[ -z "$out" ] && ok "subagent-stop: complete phase -> allow" || fail "subagent-stop: should allow" "$out"

echo ""
echo "--- PHASE 18: Inactive mission -> all hooks inert ---"

cat > "$SIM_DIR/.mission/state.json" << 'STATE'
{"active": false, "phase": "orchestrator", "completedAt": "2026-03-29T12:00:00Z"}
STATE

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/phase-guard.py" "Write" '{"file_path":"'"$SIM_DIR"'/anything.py","content":"x"}' 2>&1) || ec=$?
check_exit "inactive: phase-guard -> ALLOW" "0" "$ec"

ec=0; out=$(cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-reminder.py" "Read" 2>&1) || ec=$?
[ -z "$out" ] && ok "inactive: reminder -> silent" || fail "inactive: reminder should be silent" "$out"

ec=0; out=$(echo '{"stop_hook_active":false}' | (cd "$SIM_DIR" && python3 "$PROJECT_DIR/hooks/mission-stop.py") 2>&1) || ec=$?
[ -z "$out" ] && ok "inactive: stop -> allow" || fail "inactive: stop should allow" "$out"

echo ""
echo "=== Results ==="
echo "PASSED: $PASS / $TOTAL"
echo "FAILED: $FAIL / $TOTAL"
if [ "$FAIL" -gt 0 ]; then echo "SOME SIMULATIONS FAILED"; exit 1
else echo "ALL SIMULATIONS PASSED -- 100% VERIFIED"; exit 0; fi
