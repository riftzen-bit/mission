#!/usr/bin/env bash
# hooks/mission-continue.sh — Mission plugin PostToolUse continuation hook
#
# Runs after Agent calls complete. If a mission is active, outputs a
# continuation reminder so the model keeps the mission loop going.
#
# Exit 0 always (never block).

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

# Read active, phase, round — pass STATE_FILE as argv[1] to avoid shell injection
ACTIVE=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get("active",False)).lower())' "$STATE_FILE" 2>/dev/null || echo "false")

if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

PHASE=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("phase","unknown"))' "$STATE_FILE" 2>/dev/null || echo "unknown")
ROUND=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("round",1))' "$STATE_FILE" 2>/dev/null || echo "1")

echo "[MISSION ACTIVE] Phase: $PHASE | Round: $ROUND — Do NOT end your response. Continue the mission loop: take the next action immediately."
