#!/usr/bin/env bash
# hooks/mission-continue.sh — Mission plugin PostToolUse continuation hook (v0.5.0)
#
# Fires after ALL major tool calls during an active mission.
# Injects phase-appropriate continuation reminders to prevent the model
# from stopping mid-loop or forgetting the skill workflow.
#
# Reminder strength by tool type:
#   Agent  → STRONGEST (orchestrator must continue loop immediately)
#   Read/Grep/Glob → MEDIUM (prevent research drift)
#   Write/Edit/Bash → MEDIUM (continue after execution)
#   Other → LIGHT
#
# Only full reminders for orchestrator phase. Workers/validators get
# minimal reminders (only after Agent calls) to avoid confusion.
#
# Exit 0 always (never block).

set -euo pipefail

TOOL_NAME="${1:-unknown}"

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

# Fast grep check: skip if not active
ACTIVE=$(grep -oP '"active"\s*:\s*\K[a-z]+' "$STATE_FILE" 2>/dev/null | head -1 || echo "false")
if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

# Fast phase check: route by phase
PHASE=$(grep -oP '"phase"\s*:\s*"\K[^"]+' "$STATE_FILE" 2>/dev/null | head -1 || echo "unknown")

# Workers and validators: minimal reminder only after Agent calls
if [ "$PHASE" != "orchestrator" ]; then
  if [ "$TOOL_NAME" = "Agent" ]; then
    ROUND=$(grep -oP '"round"\s*:\s*\K[0-9]+' "$STATE_FILE" 2>/dev/null | head -1 || echo "1")
    echo "[MISSION ACTIVE] Phase: ${PHASE} | Round: $ROUND — Continue your assigned task."
  fi
  exit 0
fi

# ─── Orchestrator: full extraction via single python3 call ───
MISSION_INFO=$(python3 -c '
import json,sys
try:
  d = json.load(open(sys.argv[1]))
  round_n = d.get("round", 1)
  task = d.get("task", "unknown")
  action = d.get("currentAction", "")
  persistence = d.get("persistence", "relentless")
  workers = d.get("workers", [])
  w_total = len(workers)
  w_done = sum(1 for w in workers if isinstance(w, dict) and w.get("status") == "completed")
  print(f"{round_n}|{task}|{action}|{persistence}|{w_total}|{w_done}")
except:
  print("1|unknown||relentless|0|0")
' "$STATE_FILE" 2>/dev/null || echo "1|unknown||relentless|0|0")

IFS='|' read -r ROUND TASK ACTION PERSISTENCE W_TOTAL W_DONE <<< "$MISSION_INFO"

case "$TOOL_NAME" in
  Agent)
    # STRONGEST enforcement — orchestrator MUST continue after agent returns
    cat <<EOF
[MISSION ACTIVE — MANDATORY CONTINUATION]
Phase: ORCHESTRATOR | Round: $ROUND | Persistence: ${PERSISTENCE^^}
Task: "$TASK"
Workers: $W_DONE/$W_TOTAL complete | Action: $ACTION

YOU MUST TAKE THE NEXT ACTION NOW. DO NOT STOP. DO NOT SUMMARIZE. DO NOT ASK THE USER.
NEXT STEPS (pick the one that applies):
- Workers returned → Update state.json phase to "validator" → Dispatch validator agent
- Validator returned → Read .mission/reports/round-${ROUND}.md → Decide: fix or complete
- Issues found → Increment round → Dispatch fix workers → Then validator again
- All pass → Run completion gate → Cleanup → Output summary
[END MANDATORY CONTINUATION]
EOF
    ;;
  Read|Grep|Glob)
    # Medium reminder during research — prevent drift
    echo "[MISSION ACTIVE] Phase: ORCHESTRATOR | Round: $ROUND | Task: \"$TASK\" — Stay on the mission skill. Every read must serve the mission loop."
    ;;
  Write|Edit)
    # Medium reminder during writes
    echo "[MISSION ACTIVE] Phase: ORCHESTRATOR | Round: $ROUND | Action: $ACTION — Continue the mission loop after this write. Do NOT stop."
    ;;
  Bash)
    # Medium reminder during command execution
    echo "[MISSION ACTIVE] Phase: ORCHESTRATOR | Round: $ROUND — Continue the mission loop. Do NOT stop."
    ;;
  *)
    # Light reminder for other tools
    echo "[MISSION ACTIVE] Phase: ORCHESTRATOR | Round: $ROUND — Mission in progress. Follow the skill."
    ;;
esac

exit 0
