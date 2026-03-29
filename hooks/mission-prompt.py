#!/usr/bin/env python3
"""
hooks/mission-prompt.py — UserPromptSubmit hook for Mission Plugin.

Fires on every user prompt submission. Injects brief mission context
so the model stays aware of the active mission.

Reads JSON from stdin (UserPromptSubmit event). Returns JSON with additionalContext.
ALWAYS exits 0. Output is JSON to stdout.

Stdin: {"session_id":"...","cwd":"...","hook_event_name":"UserPromptSubmit","prompt":"user's message"}
"""

import json
import os
import sys

# ── Import engine utilities ──────────────────────────────────────────────────

_HOOK_DIR = os.path.dirname(os.path.abspath(__file__))
if _HOOK_DIR not in sys.path:
    sys.path.insert(0, _HOOK_DIR)
_PROJECT_DIR = os.path.dirname(_HOOK_DIR)
if _PROJECT_DIR not in sys.path:
    sys.path.insert(0, _PROJECT_DIR)

from engine import (  # noqa: E402
    find_state_file,
    get_current_feature,
    load_features,
    load_state,
)


# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════


def main():
    try:
        _main_inner()
    except Exception:
        # NEVER exit non-zero — graceful degradation
        sys.exit(0)


def _main_inner():
    # ── Step 1: Read JSON from stdin ─────────────────────────────────────────
    try:
        raw = sys.stdin.read()
        _event = json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, ValueError):
        _event = {}

    # ── Step 2: Find state file → not found → exit 0 ────────────────────────
    state_path = find_state_file()
    if state_path is None:
        sys.exit(0)

    # ── Step 3: Load state → not active → exit 0 ────────────────────────────
    state = load_state(state_path)
    active = state.get("active", False)
    if active is not True and str(active).lower() != "true":
        sys.exit(0)

    mission_dir = os.path.dirname(state_path)

    # ── Step 4: Load features and current feature ────────────────────────────
    features_path = os.path.join(mission_dir, "features.json")
    features = load_features(features_path)
    current_feature = get_current_feature(features)

    # ── Step 5: Build brief context ──────────────────────────────────────────
    phase = state.get("phase", "unknown")
    round_n = state.get("round", 1)

    feature_str = "none"
    if current_feature and isinstance(current_feature, dict):
        fid = current_feature.get("id", "")
        if fid:
            feature_str = fid

    additional_context = (
        f"[MISSION ACTIVE] Phase: {phase} | Round: {round_n} | Feature: {feature_str}\n"
        "The user sent a message. Handle it within the mission context, then continue the mission loop."
    )

    # ── Step 6: Output JSON response ─────────────────────────────────────────
    response = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": additional_context,
        }
    }
    print(json.dumps(response))
    sys.exit(0)


if __name__ == "__main__":
    main()
