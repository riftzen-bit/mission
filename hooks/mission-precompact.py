#!/usr/bin/env python3
"""
hooks/mission-precompact.py — PreCompact hook for Mission Plugin.

Fires BEFORE context compaction. Writes a checkpoint file so the mission
can be resumed after compaction wipes the context window.

Reads JSON from stdin (PreCompact event). Writes .mission/checkpoint.md.
ALWAYS exits 0 — PreCompact hooks cannot block compaction.

Stdin: {"session_id":"...","cwd":"...","hook_event_name":"PreCompact","trigger":"auto|manual","custom_instructions":""}
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
    get_next_feature,
    load_features,
    load_state,
)


# ═══════════════════════════════════════════════════════════════════════════════
# Feature progress helpers
# ═══════════════════════════════════════════════════════════════════════════════


def _feature_progress(features):
    """Return dict with completed, in-progress, pending, failed counts."""
    counts = {"completed": 0, "in-progress": 0, "pending": 0, "failed": 0}
    feature_list = features.get("features", [])
    if not isinstance(feature_list, list):
        return counts
    for f in feature_list:
        if not isinstance(f, dict):
            continue
        status = f.get("status", "pending")
        if status in counts:
            counts[status] += 1
        else:
            counts["pending"] += 1
    return counts


def _next_action(phase, feature, features):
    """Determine what should happen next based on phase and feature state."""
    if phase == "orchestrator":
        progress = _feature_progress(features)
        if progress["in-progress"] > 0:
            return "Monitor in-progress Worker, then dispatch Validator when done."
        if progress["failed"] > 0 and progress["pending"] == 0 and progress["in-progress"] == 0:
            return "Some features failed. Re-scope or retry failed features before completing."
        if progress["pending"] > 0:
            return "Dispatch Worker for next pending feature."
        total = sum(progress.values())
        if progress["completed"] == total and total > 0:
            return "All features completed. Dispatch Validator for final check, then run completion gate."
        return "Review features.json and dispatch next Worker or Validator."
    elif phase == "worker":
        if feature:
            return f"Continue implementing feature '{feature.get('id', 'unknown')}'. Produce structured handoff when done."
        return "Complete assigned feature and produce structured handoff."
    elif phase == "validator":
        if feature:
            return f"Continue validating feature '{feature.get('id', 'unknown')}'. Write report when done."
        return "Validate all completed features and write report to .mission/reports/."
    return "Resume the mission loop from the current phase."


# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════


def main():
    try:
        _main_inner()
    except Exception:
        # NEVER exit non-zero — PreCompact hooks must not fail
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

    # ── Step 4: Load features ────────────────────────────────────────────────
    features_path = os.path.join(mission_dir, "features.json")
    features = load_features(features_path)
    current_feature = get_current_feature(features)

    # ── Step 5: Build checkpoint content ─────────────────────────────────────
    phase = state.get("phase", "unknown")
    round_n = state.get("round", 1)
    task = state.get("task", "unknown")
    persistence = state.get("persistence", "relentless")
    action = state.get("currentAction", "")

    progress = _feature_progress(features)

    lines = [
        "# Mission Checkpoint (written before compaction)",
        "",
        f"**Phase:** {phase}",
        f"**Round:** {round_n}",
        f"**Task:** {task}",
        f"**Persistence:** {persistence}",
        f"**Current Action:** {action}",
    ]

    # Current feature section
    lines.append("")
    lines.append("## Current Feature")
    if current_feature and isinstance(current_feature, dict):
        lines.append(f"ID: {current_feature.get('id', 'none')}")
        lines.append(f"Description: {current_feature.get('description', 'none')}")
        lines.append(f"Status: {current_feature.get('status', 'unknown')}")
    else:
        lines.append("No feature currently in-progress.")

    # Feature progress section
    lines.append("")
    lines.append("## Feature Progress")
    lines.append(f"- completed: {progress['completed']}")
    lines.append(f"- in-progress: {progress['in-progress']}")
    lines.append(f"- pending: {progress['pending']}")
    lines.append(f"- failed: {progress['failed']}")

    # Failed features with reasons (if any)
    feature_list = features.get("features", [])
    failed_features = [
        f for f in feature_list
        if isinstance(f, dict) and f.get("status") == "failed"
    ]
    if failed_features:
        lines.append("")
        lines.append("## Failed Features")
        for ff in failed_features:
            fid = ff.get("id", "unknown")
            reason = ff.get("failureReason", "no reason recorded")
            lines.append(f"- {fid}: {reason}")

    # Next action section
    lines.append("")
    lines.append("## Next Action")
    lines.append(_next_action(phase, current_feature, features))

    # Resume instructions
    lines.append("")
    lines.append("## Resume Instructions")
    lines.append(
        "READ this file and .mission/state.json. Then follow the Resume Protocol in the enter-mission skill."
    )

    checkpoint_content = "\n".join(lines) + "\n"

    # ── Step 6: Write checkpoint.md ──────────────────────────────────────────
    checkpoint_path = os.path.join(mission_dir, "checkpoint.md")
    try:
        with open(checkpoint_path, "w", encoding="utf-8") as fh:
            fh.write(checkpoint_content)
    except OSError as e:
        print(f"mission-precompact: failed to write checkpoint: {e}", file=sys.stderr, flush=True)

    # Exit 0 — PreCompact hooks can't block compaction
    sys.exit(0)


if __name__ == "__main__":
    main()
