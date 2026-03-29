#!/usr/bin/env python3
"""
hooks/mission-continue.py — Mission plugin PostToolUse continuation hook.

Fires after ALL major tool calls during an active mission.
Injects phase-appropriate continuation reminders to prevent the model
from stopping mid-loop or forgetting the skill workflow.

Reminder strength by tool type and phase:
  Orchestrator + Agent  → STRONGEST (mandatory continuation)
  Orchestrator + Read/Write/Edit/Bash → MEDIUM (stay in loop)
  Orchestrator + Grep/Glob → LIGHT (follow the skill)
  Worker/Validator + Agent → STRONG (continue assigned task)
  Worker/Validator + Read/Write/Edit/Bash → MEDIUM
  Worker/Validator + Grep/Glob → LIGHT

Entry: python3 hooks/mission-continue.py <TOOL_NAME>
ALWAYS exits 0 (never blocks). Outputs text injected into context.
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


# ═══════════════════════════════════════════════════════════════════════════════
# Tool classification
# ═══════════════════════════════════════════════════════════════════════════════

_AGENT_TOOLS = {"Agent"}
_MEDIUM_TOOLS = {"Read", "Write", "Edit", "MultiEdit", "Bash"}
_LIGHT_TOOLS = {"Grep", "Glob"}


def _tool_strength(tool_name):
    """Return 'strongest', 'medium', or 'light' based on tool name."""
    if tool_name in _AGENT_TOOLS:
        return "strongest"
    if tool_name in _MEDIUM_TOOLS:
        return "medium"
    if tool_name in _LIGHT_TOOLS:
        return "light"
    return "light"


# ═══════════════════════════════════════════════════════════════════════════════
# Feature context helper
# ═══════════════════════════════════════════════════════════════════════════════


def _feature_context(feature):
    """Build a feature context string from a feature dict, or empty string."""
    if not feature or not isinstance(feature, dict):
        return ""
    fid = feature.get("id", "")
    desc = feature.get("description", "")
    if fid and desc:
        return f"Feature: {fid} — {desc}"
    if fid:
        return f"Feature: {fid}"
    if desc:
        return f"Feature: {desc}"
    return ""


# ═══════════════════════════════════════════════════════════════════════════════
# Worker status helper
# ═══════════════════════════════════════════════════════════════════════════════


def _worker_status(state):
    """Return (completed, total) worker counts from state."""
    workers = state.get("workers", [])
    if not isinstance(workers, list):
        return (0, 0)
    total = len(workers)
    completed = sum(
        1
        for w in workers
        if isinstance(w, dict) and w.get("status") == "completed"
    )
    return (completed, total)


# ═══════════════════════════════════════════════════════════════════════════════
# Reminder generators
# ═══════════════════════════════════════════════════════════════════════════════


def _orchestrator_strongest(state, feature):
    """STRONGEST reminder: orchestrator + Agent."""
    round_n = state.get("round", 1)
    task = state.get("task", "unknown")
    persistence = state.get("persistence", "relentless")
    action = state.get("currentAction", "")
    w_done, w_total = _worker_status(state)
    feat_ctx = _feature_context(feature)

    lines = [
        "[MISSION ACTIVE — MANDATORY CONTINUATION]",
        f"Phase: ORCHESTRATOR | Round: {round_n} | Persistence: {persistence.upper()}",
        f'Task: "{task}"',
        f"Workers: {w_done}/{w_total} complete | Action: {action}",
    ]
    if feat_ctx:
        lines.append(feat_ctx)
    lines.append("")
    lines.append(
        "YOU MUST TAKE THE NEXT ACTION NOW. DO NOT STOP. DO NOT SUMMARIZE. DO NOT ASK THE USER."
    )
    lines.append("NEXT STEPS (pick the one that applies):")
    lines.append(
        '- If workers returned -> transition to validator. Update state.json phase to "validator" -> Dispatch validator agent'
    )
    lines.append(
        f"- If validator returned -> Read .mission/reports/round-{round_n}.md -> Decide: fix or complete"
    )
    lines.append(
        "- Issues found -> Increment round -> Dispatch fix workers -> Then validator again"
    )
    lines.append(
        "- All pass -> Run completion gate -> Cleanup -> Output summary"
    )
    lines.append("DO NOT STOP. TAKE THE NEXT ACTION NOW.")
    lines.append("[END MANDATORY CONTINUATION]")
    return "\n".join(lines)


def _orchestrator_medium(state, feature, tool_name):
    """MEDIUM reminder: orchestrator + Read/Write/Edit/Bash."""
    round_n = state.get("round", 1)
    task = state.get("task", "unknown")
    action = state.get("currentAction", "")
    feat_ctx = _feature_context(feature)
    parts = [f"[MISSION ACTIVE] Phase: ORCHESTRATOR | Round: {round_n}"]
    if feat_ctx:
        parts[0] += f" | {feat_ctx}"
    if tool_name in ("Read", "Grep", "Glob"):
        parts.append(f'Task: "{task}" — Stay on the mission loop. Every read must serve the mission loop.')
    elif tool_name in ("Write", "Edit", "MultiEdit"):
        parts.append(f"Action: {action} — Continue the mission loop after this write. Do NOT stop.")
    elif tool_name == "Bash":
        parts.append("Continue the mission loop. Do NOT stop.")
    else:
        parts.append("Stay on the mission loop.")
    return " ".join(parts)


def _orchestrator_light(state, feature):
    """LIGHT reminder: orchestrator + Grep/Glob/unknown."""
    round_n = state.get("round", 1)
    feat_ctx = _feature_context(feature)
    base = f"[MISSION ACTIVE] Phase: ORCHESTRATOR | Round: {round_n}"
    if feat_ctx:
        base += f" | {feat_ctx}"
    return base + " — Follow the skill."


def _worker_strong(state, feature):
    """STRONG reminder: worker + Agent."""
    round_n = state.get("round", 1)
    feat_ctx = _feature_context(feature)
    parts = [f"[MISSION ACTIVE] Phase: WORKER | Round: {round_n}"]
    if feat_ctx:
        parts[0] += f" | {feat_ctx}"
    parts.append("— Continue your assigned task. Produce structured handoff when done.")
    return " ".join(parts)


def _worker_medium(state, feature):
    """MEDIUM reminder: worker + Read/Write/Edit/Bash."""
    round_n = state.get("round", 1)
    feat_ctx = _feature_context(feature)
    base = f"[MISSION ACTIVE] Phase: WORKER | Round: {round_n}"
    if feat_ctx:
        base += f" | {feat_ctx}"
    return base + " — Continue your assigned task."


def _worker_light(state, feature):
    """LIGHT reminder: worker + Grep/Glob."""
    round_n = state.get("round", 1)
    base = f"[MISSION ACTIVE] Phase: WORKER | Round: {round_n}"
    return base + " — Follow the skill."


def _validator_strong(state, feature):
    """STRONG reminder: validator + Agent."""
    round_n = state.get("round", 1)
    feat_ctx = _feature_context(feature)
    parts = [f"[MISSION ACTIVE] Phase: VALIDATOR | Round: {round_n}"]
    if feat_ctx:
        parts[0] += f" | {feat_ctx}"
    parts.append("— Continue validation. Write report when done.")
    return " ".join(parts)


def _validator_medium(state, feature):
    """MEDIUM reminder: validator + Read/Write/Edit/Bash."""
    round_n = state.get("round", 1)
    feat_ctx = _feature_context(feature)
    base = f"[MISSION ACTIVE] Phase: VALIDATOR | Round: {round_n}"
    if feat_ctx:
        base += f" | {feat_ctx}"
    return base + " — Continue validation."


def _validator_light(state, feature):
    """LIGHT reminder: validator + Grep/Glob."""
    round_n = state.get("round", 1)
    base = f"[MISSION ACTIVE] Phase: VALIDATOR | Round: {round_n}"
    return base + " — Follow the skill."


# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════


def main():
    try:
        _main_inner()
    except Exception:
        # NEVER exit non-zero — this is a PostToolUse hook
        sys.exit(0)


def _main_inner():
    # ── Step 1: Accept 1 arg (TOOL_NAME). No args → exit 0 silently ─────────
    if len(sys.argv) < 2:
        sys.exit(0)
    tool_name = sys.argv[1]

    # ── Step 2: Find state file → not found → exit 0 silently ───────────────
    state_path = find_state_file()
    if state_path is None:
        sys.exit(0)

    # ── Step 3: Load state → not active → exit 0 silently ───────────────────
    state = load_state(state_path)
    active = state.get("active", False)
    if active is not True and str(active).lower() != "true":
        sys.exit(0)

    phase = state.get("phase", "")
    if not phase:
        # Missing phase → treat as unknown; only output for Agent
        if tool_name == "Agent":
            round_n = state.get("round", 1)
            print(f"[MISSION ACTIVE] Phase: unknown | Round: {round_n} — Continue your assigned task.", flush=True)
        sys.exit(0)

    # ── Step 4: Load features ────────────────────────────────────────────────
    features_path = os.path.join(os.path.dirname(state_path), "features.json")
    try:
        features = load_features(features_path)
    except Exception:
        features = {"features": []}

    # ── Step 5: Get current feature ──────────────────────────────────────────
    try:
        feature = get_current_feature(features)
    except Exception:
        feature = None

    # ── Step 6: Output reminder based on PHASE + TOOL_NAME ───────────────────
    strength = _tool_strength(tool_name)

    if phase == "orchestrator":
        if strength == "strongest":
            print(_orchestrator_strongest(state, feature), flush=True)
        elif strength == "medium":
            print(_orchestrator_medium(state, feature, tool_name), flush=True)
        else:
            print(_orchestrator_light(state, feature), flush=True)

    elif phase == "worker":
        if strength == "strongest":
            print(_worker_strong(state, feature), flush=True)
        elif strength == "medium":
            print(_worker_medium(state, feature), flush=True)
        else:
            print(_worker_light(state, feature), flush=True)

    elif phase == "validator":
        if strength == "strongest":
            print(_validator_strong(state, feature), flush=True)
        elif strength == "medium":
            print(_validator_medium(state, feature), flush=True)
        else:
            print(_validator_light(state, feature), flush=True)

    else:
        # Unknown phase → light reminder if active
        round_n = state.get("round", 1)
        if tool_name == "Agent":
            print(f"[MISSION ACTIVE] Phase: {phase} | Round: {round_n} — Continue your assigned task.", flush=True)
        elif strength == "medium":
            print(f"[MISSION ACTIVE] Phase: {phase} | Round: {round_n} — Stay on the mission loop.", flush=True)
        else:
            print(f"[MISSION ACTIVE] Phase: {phase} | Round: {round_n} — Follow the skill.", flush=True)

    sys.exit(0)


if __name__ == "__main__":
    main()
