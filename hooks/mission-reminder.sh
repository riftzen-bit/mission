#!/usr/bin/env bash
# hooks/mission-reminder.sh — PreToolUse mission context injection (v0.5.0)
#
# Fires before ALL major tool calls during an active mission.
# Injects a skill-adherence reminder into the model's context via stdout.
# This prevents the model from "forgetting" the mission skill after
# extensive research (many Read/Grep/Glob calls).
#
# NEVER blocks — always exits 0. Output goes to stdout as additional context.
#
# Performance:
#   - No .mission/ dir → exits in <1ms (stat check only)
#   - Not active or not orchestrator → exits via grep (~2ms, no python3)
#   - Orchestrator active → single python3 call for field extraction (~50ms)

set -euo pipefail

# ─── Find .mission/state.json ───
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

# No state file → not in mission mode → silent exit
if [ -z "$STATE_FILE" ]; then
  exit 0
fi

MISSION_DIR=$(dirname "$STATE_FILE")

# Fast grep check: skip python3 if not active
if ! grep -q '"active"' "$STATE_FILE" 2>/dev/null; then
  exit 0
fi

# Fast phase check via grep: only remind orchestrator
# Workers and validators have focused prompts — reminders would confuse them
PHASE=$(grep -oP '"phase"\s*:\s*"\K[^"]+' "$STATE_FILE" 2>/dev/null | head -1 || echo "")
if [ "$PHASE" != "orchestrator" ]; then
  exit 0
fi

# Verify actually active (grep "active" above matches the key name, not value)
ACTIVE=$(grep -oP '"active"\s*:\s*\K[a-z]+' "$STATE_FILE" 2>/dev/null | head -1 || echo "false")
if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

# Full extraction for orchestrator reminder (single python3 call)
MISSION_INFO=$(python3 -c '
import json,sys
try:
  d = json.load(open(sys.argv[1]))
  round_n = d.get("round", 1)
  task = d.get("task", "unknown")
  action = d.get("currentAction", "")
  print(f"{round_n}|{task}|{action}")
except:
  print("1|unknown|")
' "$STATE_FILE" 2>/dev/null || echo "1|unknown|")

IFS='|' read -r ROUND TASK ACTION <<< "$MISSION_INFO"

# Adjust reminder based on whether plan exists
if [ ! -f "$MISSION_DIR/plan.md" ]; then
  echo "[MISSION SKILL ACTIVE — DO NOT DEVIATE] Phase: ORCHESTRATOR | Round: $ROUND | Task: \"$TASK\" — You are under the enter-mission skill. Your research MUST lead to writing .mission/plan.md, then dispatching Workers. Do NOT forget the skill. Do NOT act outside the mission loop."
else
  echo "[MISSION SKILL ACTIVE — DO NOT DEVIATE] Phase: ORCHESTRATOR | Round: $ROUND | Task: \"$TASK\" | Action: $ACTION — Plan exists. Follow the mission loop: dispatch Workers → validate → fix → complete. Do NOT deviate. Do NOT stop mid-loop."
fi

exit 0
