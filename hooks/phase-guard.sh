#!/usr/bin/env bash
# hooks/phase-guard.sh — Mission plugin PreToolUse enforcement
#
# Called by hooks.json for Write, Edit, Agent, and Bash tool calls.
# Reads .mission/state.json to determine current phase and blocks
# forbidden actions.
#
# Arguments: $1 = tool name, $2 = tool input (JSON)
# Exit 0 = ALLOW, Exit 1 with "BLOCK" message = DENY

set -euo pipefail

TOOL_NAME="${1:-}"
TOOL_INPUT="${2:-}"

# ─── Find .mission/state.json ───
# Search from current directory upward (handles subagents in subdirs)
find_state_file() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.mission/state.json" ]; then
      echo "$dir/.mission/state.json"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

STATE_FILE=$(find_state_file 2>/dev/null) || true

# No state file → not in mission mode → allow everything
if [ -z "$STATE_FILE" ]; then
  exit 0
fi

MISSION_DIR=$(dirname "$STATE_FILE")

# Read state — pass STATE_FILE as argv[1] to avoid shell injection via path
ACTIVE=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get("active",False)).lower())' "$STATE_FILE" 2>/dev/null || echo "false")
PHASE=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("phase",""))' "$STATE_FILE" 2>/dev/null || echo "")
PERSISTENCE=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("persistence","relentless"))' "$STATE_FILE" 2>/dev/null || echo "relentless")
STRICT_PHASE_LOCK=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get("strictPhaseLock",True)).lower())' "$STATE_FILE" 2>/dev/null || echo "true")
PHASE_LOCK_PHASE=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); pl=d.get("phaseLock",{}); print(pl.get("phase","") if isinstance(pl,dict) else "")' "$STATE_FILE" 2>/dev/null || echo "")
PHASE_LOCK_TIMESTAMP=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); pl=d.get("phaseLock",{}); print(pl.get("lockedAt","") if isinstance(pl,dict) else "")' "$STATE_FILE" 2>/dev/null || echo "")
ROUND=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("round",1))' "$STATE_FILE" 2>/dev/null || echo "1")

# Not active → allow everything
if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

# No phase set → allow (shouldn't happen but safe default)
if [ -z "$PHASE" ]; then
  exit 0
fi

# ─── Extract file_path from tool input ───
extract_file_path() {
  python3 -c "
import json,sys
try:
  d = json.loads(sys.argv[1])
  print(d.get('file_path',''))
except:
  print('')
" "$1" 2>/dev/null || echo ""
}

# ─── Extract command from Bash tool input ───
extract_command() {
  python3 -c "
import json,sys
try:
  d = json.loads(sys.argv[1])
  print(d.get('command',''))
except:
  print('')
" "$1" 2>/dev/null || echo ""
}

# ─── Extract subagent_type from Agent tool input ───
extract_subagent_type() {
  python3 -c "
import json,sys
try:
  d = json.loads(sys.argv[1])
  print(d.get('subagent_type',''))
except:
  print('')
" "$1" 2>/dev/null || echo ""
}

# ─── Check if path is under .mission/ ───
# After canonicalize_path, paths are either relative (.mission/foo) or absolute (/x/.mission/foo)
is_mission_path() {
  local filepath="$1"
  case "$filepath" in
    .mission/*) return 0 ;;
  esac
  # Match absolute paths: contains /.mission/ segment
  if [[ "$filepath" == *"/.mission/"* ]]; then
    return 0
  fi
  return 1
}

# ─── Check if path is .mission/state.json ───
is_state_json() {
  local filepath="$1"
  local base
  base=$(basename "$filepath")
  if [ "$base" != "state.json" ]; then
    return 1
  fi
  # Check parent dir is .mission
  local parent
  parent=$(basename "$(dirname "$filepath")")
  if [ "$parent" = ".mission" ]; then
    return 0
  fi
  return 1
}

# ─── Check if path is .mission/worker-logs/* ───
is_worker_log() {
  local filepath="$1"
  case "$filepath" in
    .mission/worker-logs/*) return 0 ;;
  esac
  if [[ "$filepath" == *"/.mission/worker-logs/"* ]]; then
    return 0
  fi
  return 1
}

# ─── Check if path is under .mission/reports/ ───
is_report_path() {
  local filepath="$1"
  case "$filepath" in
    .mission/reports/*) return 0 ;;
  esac
  if [[ "$filepath" == *"/.mission/reports/"* ]]; then
    return 0
  fi
  return 1
}

# ─── Check if path is a test file ───
is_test_file() {
  local filepath="$1"
  local basename
  basename=$(basename "$filepath")

  # Match *.test.*, *.spec.*, *_test.*, *_spec.*, test_*
  case "$basename" in
    *.test.*|*.spec.*|*_test.*|*_spec.*|test_*) return 0 ;;
  esac

  # Match tests/* directory
  case "$filepath" in
    tests/*|*/tests/*) return 0 ;;
  esac

  # Match __tests__/* anywhere in path
  case "$filepath" in
    *__tests__/*|*/__tests__/*) return 0 ;;
  esac

  # Match spec/* directory (Ruby rspec convention)
  case "$filepath" in
    spec/*|*/spec/*) return 0 ;;
  esac

  # Match .mission/reports/*
  case "$filepath" in
    .mission/reports/*|*/.mission/reports/*) return 0 ;;
  esac

  return 1
}

# ─── Check if bash command is a test runner ───
is_test_command() {
  local cmd="$1"
  # Strip leading whitespace
  cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//')

  case "$cmd" in
    "npm test"*) return 0 ;;
    "npx jest"*) return 0 ;;
    "npx vitest"*) return 0 ;;
    "npx mocha"*) return 0 ;;
    "yarn test"*) return 0 ;;
    "pnpm test"*) return 0 ;;
    "pytest"*) return 0 ;;
    "python -m pytest"*) return 0 ;;
    "python3 -m pytest"*) return 0 ;;
    "go test"*) return 0 ;;
    "cargo test"*) return 0 ;;
    "make test"*) return 0 ;;
    "gradle test"*) return 0 ;;
    "mvn test"*) return 0 ;;
    "bundle exec rspec"*) return 0 ;;
    "phpunit"*) return 0 ;;
  esac

  return 1
}

# ─── Check if agent is a worker type ───
is_worker_agent() {
  local agent_type="$1"
  case "$agent_type" in
    *worker*|*Worker*|*mission-worker*) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── Check if agent is a validator type ───
is_validator_agent() {
  local agent_type="$1"
  case "$agent_type" in
    *validator*|*Validator*|*mission-validator*) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── Canonicalize path to prevent ../ traversal and symlink bypass ───
canonicalize_path() {
  local filepath="$1"
  # Use realpath to resolve .., ., AND symlinks (including broken symlinks).
  # Falls back to normpath only if the path is not a symlink and does not exist.
  python3 -c '
import os,sys
p = sys.argv[1]
if os.path.exists(p) or os.path.islink(p):
    print(os.path.realpath(p))
else:
    print(os.path.normpath(p))
' "$filepath" 2>/dev/null || echo "$filepath"
}

# ─── Build phase lock info string ───
phase_lock_info() {
  if [ -n "$PHASE_LOCK_PHASE" ]; then
    echo " [Lock: $PHASE_LOCK_PHASE since $PHASE_LOCK_TIMESTAMP]"
  fi
}

block() {
  local description="$1"
  local guidance="${2:-}"
  local lock_info
  lock_info=$(phase_lock_info)
  if [ -n "$guidance" ]; then
    echo "BLOCK: [MISSION GUARD] Phase \"$PHASE\" — $description. $guidance.$lock_info" >&2
  else
    echo "BLOCK: [MISSION GUARD] Phase \"$PHASE\" — $description.$lock_info" >&2
  fi
  exit 1
}

# ═══════════════════════════════════════════════
# PHASE LOCK VALIDATION
# ═══════════════════════════════════════════════

if [ "$STRICT_PHASE_LOCK" = "true" ] && [ -n "$PHASE_LOCK_PHASE" ]; then
  if [ "$PHASE_LOCK_PHASE" != "$PHASE" ]; then
    block "Phase lock conflict — state phase is \"$PHASE\" but phaseLock is \"$PHASE_LOCK_PHASE\"" "Resolve by having the Orchestrator update phaseLock to match the current phase"
  fi
fi

# ═══════════════════════════════════════════════
# RELENTLESS MODE ENFORCEMENT
# ═══════════════════════════════════════════════

# When persistence is "relentless", block writes to state.json that set
# active=false unless the content also contains completedAt (legitimate completion).
if [ "$PERSISTENCE" = "relentless" ]; then
  if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
    filepath=$(extract_file_path "$TOOL_INPUT")
    filepath=$(canonicalize_path "$filepath")
    if [ -n "$filepath" ] && is_state_json "$filepath"; then
      # Extract the content being written (Write uses "content", Edit uses "new_string")
      HAS_DEACTIVATION=$(python3 -c "
import json,sys
try:
  d = json.loads(sys.argv[1])
  content = d.get('content', '') or d.get('new_string', '') or ''
  has_active_false = '\"active\": false' in content or '\"active\":false' in content
  has_completed_at = 'completedAt' in content
  if has_active_false and not has_completed_at:
    print('block')
  else:
    print('allow')
except:
  print('allow')
" "$TOOL_INPUT" 2>/dev/null || echo "allow")
      if [ "$HAS_DEACTIVATION" = "block" ]; then
        block "Relentless mode — cannot deactivate mission without completion" "Mission is in relentless mode. Include a completedAt field to perform a legitimate completion, or use /exit-mission to force stop"
      fi
      # Defense 5: Anti-premature-completion — even with completedAt in relentless mode,
      # verify the validator report exists and says PASS before allowing deactivation
      HAS_COMPLETED_DEACTIVATION_R=$(python3 -c "
import json,sys
try:
  d = json.loads(sys.argv[1])
  content = d.get('content', '') or d.get('new_string', '') or ''
  has_active_false = '\"active\": false' in content or '\"active\":false' in content
  has_completed_at = 'completedAt' in content
  if has_active_false and has_completed_at:
    print('check')
  else:
    print('skip')
except:
  print('skip')
" "$TOOL_INPUT" 2>/dev/null || echo "skip")
      if [ "$HAS_COMPLETED_DEACTIVATION_R" = "check" ]; then
        REPORT_FILE="$MISSION_DIR/reports/round-${ROUND}.md"
        if [ ! -f "$REPORT_FILE" ]; then
          block "Relentless mode — cannot deactivate without validator report for round $ROUND" "A validator must produce .mission/reports/round-${ROUND}.md with 'Verdict: PASS' before deactivation"
        fi
        if ! grep -qi "Verdict:.*PASS" "$REPORT_FILE" 2>/dev/null; then
          block "Relentless mode — cannot deactivate while validator report says FAIL" "The report at .mission/reports/round-${ROUND}.md must contain 'Verdict: PASS' before deactivating in relentless mode"
        fi
      fi
    fi
  fi
fi

# ═══════════════════════════════════════════════
# MANDATORY CLEANUP GUARD
# ═══════════════════════════════════════════════

# When writing to state.json with active=false AND completedAt, enforce cleanup:
# 1. summary.md must exist
# 2. worker-logs/ must have no .md files
# This applies in ALL persistence modes (not just relentless).
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  filepath=$(extract_file_path "$TOOL_INPUT")
  filepath=$(canonicalize_path "$filepath")
  if [ -n "$filepath" ] && is_state_json "$filepath"; then
    HAS_COMPLETED_DEACTIVATION=$(python3 -c "
import json,sys
try:
  d = json.loads(sys.argv[1])
  content = d.get('content', '') or d.get('new_string', '') or ''
  has_active_false = '\"active\": false' in content or '\"active\":false' in content
  has_completed_at = 'completedAt' in content
  if has_active_false and has_completed_at:
    print('check')
  else:
    print('skip')
except:
  print('skip')
" "$TOOL_INPUT" 2>/dev/null || echo "skip")
    if [ "$HAS_COMPLETED_DEACTIVATION" = "check" ]; then
      # Check summary.md exists
      if [ ! -f "$MISSION_DIR/summary.md" ]; then
        block "Cannot deactivate — .mission/summary.md not found" "Generate summary before completing"
      fi
      # Check worker-logs/ has no .md files
      if [ -d "$MISSION_DIR/worker-logs" ]; then
        LEFTOVER_LOGS=$(find "$MISSION_DIR/worker-logs" -name "*.md" -maxdepth 1 2>/dev/null | head -1)
        if [ -n "$LEFTOVER_LOGS" ]; then
          block "Cannot deactivate — worker logs not cleaned up" "Remove .mission/worker-logs/*.md before completing"
        fi
      fi
    fi
  fi
fi

# ═══════════════════════════════════════════════
# PHASE TRANSITION VALIDATION
# ═══════════════════════════════════════════════

# When writing to state.json, validate that the new phase value is a known phase
# and that the transition from the current phase is valid.
# Only the orchestrator can write state.json (enforced below), so this is defense-in-depth.
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  filepath=$(extract_file_path "$TOOL_INPUT")
  filepath=$(canonicalize_path "$filepath")
  if [ -n "$filepath" ] && is_state_json "$filepath"; then
    NEW_PHASE=$(python3 -c "
import json,sys,re
try:
  d = json.loads(sys.argv[1])
  content = d.get('content', '') or d.get('new_string', '') or ''
  # Try JSON parse first
  try:
    parsed = json.loads(content)
    print(parsed.get('phase', ''))
  except:
    # Fallback: regex for '\"phase\": \"<value>\"' or '\"phase\":\"<value>\"'
    m = re.search(r'\"phase\"\s*:\s*\"([^\"]+)\"', content)
    print(m.group(1) if m else '')
except:
  print('')
" "$TOOL_INPUT" 2>/dev/null || echo "")

    if [ -n "$NEW_PHASE" ]; then
      # Validate known phase values
      case "$NEW_PHASE" in
        orchestrator|worker|validator|complete)
          # Known phase — now validate transition path
          VALID_TRANSITION="false"
          case "$PHASE" in
            orchestrator)
              # Orchestrator can transition to worker, validator, or complete
              case "$NEW_PHASE" in
                worker|validator|complete) VALID_TRANSITION="true" ;;
              esac
              ;;
            worker)
              # Worker phase can only transition to validator
              case "$NEW_PHASE" in
                validator) VALID_TRANSITION="true" ;;
              esac
              ;;
            validator)
              # Validator phase can only transition to orchestrator
              case "$NEW_PHASE" in
                orchestrator) VALID_TRANSITION="true" ;;
              esac
              ;;
          esac
          # Same-phase writes are always allowed (e.g., orchestrator updating state while still in orchestrator phase)
          if [ "$NEW_PHASE" = "$PHASE" ]; then
            VALID_TRANSITION="true"
          fi
          if [ "$VALID_TRANSITION" != "true" ]; then
            block "Invalid phase transition: $PHASE -> $NEW_PHASE" "Valid transitions: orchestrator->worker, orchestrator->validator, orchestrator->complete, worker->validator, validator->orchestrator"
          fi
          ;;
        *)
          block "Unknown phase value: \"$NEW_PHASE\"" "Valid phases: orchestrator, worker, validator, complete"
          ;;
      esac
    fi
  fi
fi

# ═══════════════════════════════════════════════
# COMPLETION GUARD
# ═══════════════════════════════════════════════

# When writing to state.json with phase="complete", verify:
# 1. A validator report exists for the current round
# 2. In relentless mode: the report contains "Verdict: PASS"
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  filepath=$(extract_file_path "$TOOL_INPUT")
  filepath=$(canonicalize_path "$filepath")
  if [ -n "$filepath" ] && is_state_json "$filepath"; then
    # Reuse NEW_PHASE from phase transition validation if available, otherwise extract it
    COMPLETION_PHASE=$(python3 -c "
import json,sys,re
try:
  d = json.loads(sys.argv[1])
  content = d.get('content', '') or d.get('new_string', '') or ''
  try:
    parsed = json.loads(content)
    print(parsed.get('phase', ''))
  except:
    m = re.search(r'\"phase\"\s*:\s*\"([^\"]+)\"', content)
    print(m.group(1) if m else '')
except:
  print('')
" "$TOOL_INPUT" 2>/dev/null || echo "")
    if [ "$COMPLETION_PHASE" = "complete" ]; then
      REPORT_FILE="$MISSION_DIR/reports/round-${ROUND}.md"
      if [ ! -f "$REPORT_FILE" ]; then
        block "Cannot complete mission — no validator report found for round $ROUND" "A validator must run and produce .mission/reports/round-${ROUND}.md before the mission can complete"
      fi
      # In relentless mode, also verify the report says PASS
      if [ "$PERSISTENCE" = "relentless" ]; then
        if ! grep -qi "Verdict:.*PASS" "$REPORT_FILE" 2>/dev/null; then
          block "Relentless mode — cannot complete mission while validator report says FAIL" "The report at .mission/reports/round-${ROUND}.md must contain 'Verdict: PASS' before completing in relentless mode"
        fi
      fi
    fi
  fi
fi

# ═══════════════════════════════════════════════
# PHASE ENFORCEMENT
# ═══════════════════════════════════════════════

case "$PHASE" in

  # ─── ORCHESTRATOR PHASE ───
  orchestrator)
    case "$TOOL_NAME" in
      Write|Edit)
        filepath=$(extract_file_path "$TOOL_INPUT")
        filepath=$(canonicalize_path "$filepath")
        if [ -n "$filepath" ] && is_mission_path "$filepath"; then
          exit 0  # Orchestrator can write to .mission/*
        fi
        block "Orchestrator cannot write/edit source files" "Use the Agent tool to dispatch Workers for code changes"
        ;;
      Bash)
        exit 0  # Orchestrator can run any bash command (read-only intent enforced by prompt)
        ;;
      Agent)
        exit 0  # Orchestrator can spawn any agent
        ;;
      *)
        exit 0
        ;;
    esac
    ;;

  # ─── WORKER PHASE ───
  worker)
    case "$TOOL_NAME" in
      Write|Edit)
        filepath=$(extract_file_path "$TOOL_INPUT")
        filepath=$(canonicalize_path "$filepath")
        # Workers can write to .mission/worker-logs/* only
        if [ -n "$filepath" ] && is_mission_path "$filepath"; then
          if is_worker_log "$filepath"; then
            exit 0  # Workers can write their own logs
          fi
          block "Workers cannot modify .mission/ files (except worker-logs)" "Only the Orchestrator manages mission state, plan, and reports"
        fi
        # Workers cannot write test files — testing is the Validator's job
        if [ -n "$filepath" ] && is_test_file "$filepath"; then
          block "Workers cannot write test files — testing is the Validator's exclusive responsibility" "Complete your implementation and let the Validator handle tests"
        fi
        exit 0  # Workers can write/edit everything else (source files)
        ;;
      Bash)
        cmd=$(extract_command "$TOOL_INPUT")
        if [ -n "$cmd" ] && is_test_command "$cmd"; then
          block "Workers cannot run tests — attempted: $cmd" "Testing is the Validator's job. Complete your implementation first"
        fi
        exit 0  # Workers can run non-test bash commands
        ;;
      Agent)
        agent_type=$(extract_subagent_type "$TOOL_INPUT")
        if [ -n "$agent_type" ] && is_validator_agent "$agent_type"; then
          block "Workers cannot spawn Validators" "Only the Orchestrator dispatches Validators after all Workers complete"
        fi
        exit 0  # Workers can spawn sub-workers and other agents
        ;;
      *)
        exit 0
        ;;
    esac
    ;;

  # ─── VALIDATOR PHASE ───
  validator)
    case "$TOOL_NAME" in
      Write|Edit)
        filepath=$(extract_file_path "$TOOL_INPUT")
        filepath=$(canonicalize_path "$filepath")
        # Block state.json explicitly — Validators must not modify mission state
        if [ -n "$filepath" ] && is_state_json "$filepath"; then
          block "Validators cannot modify .mission/state.json" "Only the Orchestrator manages mission state. Write your findings to .mission/reports/ instead"
        fi
        # Validators can only write to .mission/reports/*, not other .mission/ paths
        if [ -n "$filepath" ] && is_mission_path "$filepath"; then
          if is_report_path "$filepath"; then
            exit 0  # Validators can write to .mission/reports/*
          fi
          block "Validators can only write .mission/reports/* — blocked: $filepath" "Other .mission/ paths are managed by the Orchestrator"
        fi
        if [ -n "$filepath" ] && is_test_file "$filepath"; then
          exit 0  # Validators can write test files
        fi
        block "Validators can only write test files and .mission/reports/* — blocked: $filepath" "Allowed patterns: *.test.*, *.spec.*, *_test.*, *_spec.*, tests/*, __tests__/*, spec/*, .mission/reports/*"
        ;;
      Bash)
        exit 0  # Validators can run any bash (tests, build, lint, etc.)
        ;;
      Agent)
        agent_type=$(extract_subagent_type "$TOOL_INPUT")
        if [ -n "$agent_type" ] && is_worker_agent "$agent_type"; then
          block "Validators cannot spawn Workers" "Only the Orchestrator dispatches Workers. Report issues in .mission/reports/ for the Orchestrator to act on"
        fi
        exit 0  # Validators can spawn sub-validators and other agents
        ;;
      *)
        exit 0
        ;;
    esac
    ;;

  # ─── UNKNOWN PHASE → allow (safe default) ───
  *)
    exit 0
    ;;
esac
