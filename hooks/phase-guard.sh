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

# ─── Canonicalize path to prevent ../ traversal bypass ───
canonicalize_path() {
  local filepath="$1"
  # Use python to normalize path (resolve .., ., but don't require file to exist)
  python3 -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$filepath" 2>/dev/null || echo "$filepath"
}

block() {
  echo "BLOCK: [MISSION GUARD] Phase \"$PHASE\" — $1" >&2
  exit 1
}

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
        block "Orchestrator cannot write/edit source files. Use Agent tool to dispatch Workers."
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
          block "Workers cannot modify .mission/ files (except worker-logs). Only the Orchestrator manages mission state, plan, and reports."
        fi
        exit 0  # Workers can write/edit everything else (source files)
        ;;
      Bash)
        cmd=$(extract_command "$TOOL_INPUT")
        if [ -n "$cmd" ] && is_test_command "$cmd"; then
          block "Workers cannot run tests. That is the Validator's job. Command: $cmd"
        fi
        exit 0  # Workers can run non-test bash commands
        ;;
      Agent)
        agent_type=$(extract_subagent_type "$TOOL_INPUT")
        if [ -n "$agent_type" ] && is_validator_agent "$agent_type"; then
          block "Workers cannot spawn Validators. Only the Orchestrator dispatches Validators."
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
          block "Validators cannot modify .mission/state.json. Only the Orchestrator manages mission state."
        fi
        if [ -n "$filepath" ] && (is_test_file "$filepath" || is_mission_path "$filepath"); then
          exit 0  # Validators can write test files and .mission/reports/*
        fi
        block "Validators can only write test files (*.test.*, *.spec.*, *_test.*, *_spec.*, __tests__/*) and .mission/reports/*. Blocked: $filepath"
        ;;
      Bash)
        exit 0  # Validators can run any bash (tests, build, lint, etc.)
        ;;
      Agent)
        agent_type=$(extract_subagent_type "$TOOL_INPUT")
        if [ -n "$agent_type" ] && is_worker_agent "$agent_type"; then
          block "Validators cannot spawn Workers. Only the Orchestrator dispatches Workers."
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
