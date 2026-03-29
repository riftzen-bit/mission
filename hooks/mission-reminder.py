#!/usr/bin/env python3
"""
hooks/mission-reminder.py — PreToolUse anti-drift context injection hook.

Fires before ALL tool calls during an active mission.
Injects a role-specific skill-adherence reminder into the model's context
via stdout. Prevents the model from "forgetting" the mission skill after
extensive research or context compaction.

NEVER blocks — always exits 0. Output goes to stdout as additional context.

Arguments: sys.argv[1] = tool name
Exit 0 always.
"""

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


def _format_feature(feature):
    """Format a feature dict into 'id — description' string."""
    if not feature or not isinstance(feature, dict):
        return "none"
    fid = feature.get("id", "")
    desc = feature.get("description", "")
    if fid and desc:
        return f"{fid} — {desc}"
    if fid:
        return str(fid)
    if desc:
        return str(desc)
    return "none"


def main():
    # ── Step 1: Accept 1 arg (TOOL_NAME). No args → exit 0 silently ─────────
    if len(sys.argv) < 2:
        sys.exit(0)

    # tool_name accepted but not used for filtering — fires for ALL tools
    # tool_name = sys.argv[1]

    # ── Step 2: find_state_file() → not found → exit 0 silently ─────────────
    state_path = find_state_file()
    if state_path is None:
        sys.exit(0)

    mission_dir = os.path.dirname(state_path)

    # ── Step 3: load_state() → not active → exit 0 silently ─────────────────
    state = load_state(state_path)

    active = state.get("active", False)
    if active is not True and str(active).lower() != "true":
        sys.exit(0)

    phase = state.get("phase", "")
    if not phase:
        sys.exit(0)

    # ── Step 4: Load features, get current feature ──────────────────────────
    features_path = os.path.join(mission_dir, "features.json")
    features = load_features(features_path)
    current_feature = get_current_feature(features)

    # Common fields for compaction recovery
    round_n = state.get("round", 1)
    task = state.get("task", "unknown")
    current_action = state.get("currentAction", "")
    feature_str = _format_feature(current_feature)

    # ── Step 5: Output role-specific reminder ────────────────────────────────

    if phase == "orchestrator":
        _output_orchestrator(mission_dir, round_n, task, feature_str, current_action, features_path)
    elif phase == "worker":
        _output_worker(round_n, task, feature_str)
    elif phase == "validator":
        _output_validator(round_n, task, feature_str)
    # Unknown phase → exit 0 silently

    sys.exit(0)


def _output_orchestrator(mission_dir, round_n, task, feature_str, current_action, features_path):
    """Orchestrator reminder — varies based on plan/features existence."""
    plan_exists = os.path.isfile(os.path.join(mission_dir, "plan.md"))
    features_exist = os.path.isfile(features_path)

    if not plan_exists and not features_exist:
        # No plan and no features — research phase
        parts = [
            "[MISSION SKILL ACTIVE — DO NOT DEVIATE]",
            f"Phase: ORCHESTRATOR",
            f"Round: {round_n}",
            f'Task: "{task}"',
            f"Current Feature: {feature_str}",
        ]
        if current_action:
            parts.append(f"Current Action: {current_action}")
        parts.append(
            'Directive: "Your research MUST lead to creating .mission/features.json, '
            'then dispatching Workers. DO NOT DEVIATE."'
        )
        print(" | ".join(parts), flush=True)
    else:
        # Plan or features exists — dispatch/loop phase
        parts = [
            "[MISSION SKILL ACTIVE — DO NOT DEVIATE]",
            f"Phase: ORCHESTRATOR",
            f"Round: {round_n}",
            f'Task: "{task}"',
            f"Current Feature: {feature_str}",
        ]
        if current_action:
            parts.append(f"Current Action: {current_action}")
        parts.append(
            'Directive: "Follow the mission loop: dispatch Workers → validate → fix → complete. '
            'DO NOT DEVIATE."'
        )
        print(" | ".join(parts), flush=True)


def _output_worker(round_n, task, feature_str):
    """Worker reminder — focused on feature implementation."""
    parts = [
        "[MISSION SKILL ACTIVE]",
        f"Phase: WORKER",
        f"Round: {round_n}",
        f'Task: "{task}"',
        f"Feature: {feature_str}",
        'Directive: "Complete your assigned feature. Produce structured JSON handoff '
        'when done. DO NOT write test files."',
    ]
    print(" | ".join(parts), flush=True)


def _output_validator(round_n, task, feature_str):
    """Validator reminder — focused on validation and testing."""
    parts = [
        "[MISSION SKILL ACTIVE]",
        f"Phase: VALIDATOR",
        f"Round: {round_n}",
        f'Task: "{task}"',
        f"Feature: {feature_str}",
        'Directive: "Validate the completed feature. Write tests and report to '
        '.mission/reports/. DO NOT modify source files."',
    ]
    print(" | ".join(parts), flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # NEVER exit non-zero — graceful degradation
        sys.exit(0)
