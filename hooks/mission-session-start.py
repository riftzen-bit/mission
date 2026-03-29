#!/usr/bin/env python3
"""
hooks/mission-session-start.py — SessionStart hook for Mission Plugin.

Fires when a session starts, resumes, or recovers from compaction.
Injects mission context so the model knows a mission is active and
can auto-resume from the current phase.

Reads JSON from stdin (SessionStart event). Returns JSON with additionalContext.
ALWAYS exits 0. Output is JSON to stdout.

Stdin: {"session_id":"...","cwd":"...","hook_event_name":"SessionStart","source":"startup|resume|clear|compact"}
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
# Feature formatting helper
# ═══════════════════════════════════════════════════════════════════════════════


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
        event = json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, ValueError):
        event = {}

    source = event.get("source", "")

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

    # ── Step 5: Build context ────────────────────────────────────────────────
    phase = state.get("phase", "unknown")
    round_n = state.get("round", 1)
    task = state.get("task", "unknown")
    action = state.get("currentAction", "")
    feature_str = _format_feature(current_feature)

    context_lines = [
        "[MISSION ACTIVE — AUTO-RESUME]",
        f"Phase: {phase} | Round: {round_n} | Task: {task}",
        f"Feature: {feature_str}",
        f"Action: {action}",
        "",
        "A mission is active. Read .mission/state.json and .mission/features.json, "
        "then follow the Resume Protocol. DO NOT start new work — continue from where you left off.",
    ]

    # For compact source — include checkpoint if available
    if source == "compact":
        checkpoint_path = os.path.join(mission_dir, "checkpoint.md")
        if os.path.isfile(checkpoint_path):
            try:
                with open(checkpoint_path, "r", encoding="utf-8") as fh:
                    checkpoint_content = fh.read().strip()
                if checkpoint_content:
                    context_lines.append("")
                    context_lines.append("## Checkpoint (pre-compaction state)")
                    context_lines.append(checkpoint_content)
            except (OSError, IOError):
                pass

    additional_context = "\n".join(context_lines)

    # ── Step 6: Output JSON response ─────────────────────────────────────────
    response = {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": additional_context,
        }
    }
    print(json.dumps(response), flush=True)
    sys.exit(0)


if __name__ == "__main__":
    main()
