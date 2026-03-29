#!/usr/bin/env python3
"""Stop hook — prevents Droid from stopping while mission is active.

Fires on the Stop event (Droid finishing a response). If a mission is
active and the phase is NOT "complete", this hook blocks the stop by
emitting a JSON ``{"decision": "block", "reason": "..."}`` object.

Reads JSON input from stdin (includes ``stop_hook_active`` to prevent
infinite loops). Always exits 0 — crashes / missing state allow the stop.
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
# Helpers
# ═══════════════════════════════════════════════════════════════════════════════


def _read_stdin():
    """Read and parse JSON from stdin. Returns dict or None on failure."""
    try:
        raw = sys.stdin.read()
        if not raw or not raw.strip():
            return None
        data = json.loads(raw)
        if isinstance(data, dict):
            return data
        return None
    except Exception:
        return None


def _feature_id(state_path):
    """Return the current in-progress feature ID, or empty string."""
    try:
        features_path = os.path.join(os.path.dirname(state_path), "features.json")
        features = load_features(features_path)
        feature = get_current_feature(features)
        if feature and isinstance(feature, dict):
            return feature.get("id", "")
    except Exception:
        pass
    return ""


def _block(reason):
    """Print a block decision as JSON and exit 0."""
    print(json.dumps({"decision": "block", "reason": reason}), flush=True)
    sys.exit(0)


# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════


def main():
    try:
        _main_inner()
    except Exception:
        # On any crash → allow stop (exit 0, no output)
        sys.exit(0)


def _main_inner():
    # ── Step 1: Read JSON from stdin ─────────────────────────────────────────
    stdin_data = _read_stdin()

    # ── Step 2: Check stop_hook_active → prevent infinite loop ───────────────
    if stdin_data is not None:
        if stdin_data.get("stop_hook_active") is True:
            sys.exit(0)

    # ── Step 3: Find .mission/state.json ─────────────────────────────────────
    state_path = find_state_file()
    if state_path is None:
        sys.exit(0)

    # ── Step 4: Load state — not active → allow stop ────────────────────────
    state = load_state(state_path)
    active = state.get("active", False)
    if active is not True and str(active).lower() != "true":
        sys.exit(0)

    # ── Step 5: Check phase ──────────────────────────────────────────────────
    phase = state.get("phase", "")
    if phase == "complete":
        # Mission is complete — allow stop
        sys.exit(0)

    # ── Step 6: Active mission, not complete → BLOCK ─────────────────────────
    round_n = state.get("round", 1)
    task = state.get("task", "unknown")
    feat_id = _feature_id(state_path)

    reason_parts = [
        f"[MISSION ACTIVE — DO NOT STOP] Phase: {phase or 'unknown'} | Round: {round_n} | Task: {task}"
    ]
    if feat_id:
        reason_parts[0] += f" | Feature: {feat_id}"
    reason_parts.append(
        "You MUST continue the mission loop. Read .mission/state.json and take the next action."
    )

    _block(". ".join(reason_parts))


if __name__ == "__main__":
    main()
