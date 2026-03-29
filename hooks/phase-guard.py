#!/usr/bin/env python3
"""
hooks/phase-guard.py — Mission plugin PreToolUse enforcement hook.

Called by hooks.json for Write, Edit, MultiEdit, Agent, and Bash tool calls.
Reads .mission/state.json to determine current phase and blocks
forbidden actions.

Arguments: sys.argv[1] = tool name, sys.argv[2] = tool input (JSON)
Exit 0 = ALLOW, Exit 1 with "BLOCK" message = DENY

Imports shared utilities from engine.py (same directory).
"""

import json
import os
import re
import sys

# ── Import engine utilities ──────────────────────────────────────────────────

_HOOK_DIR = os.path.dirname(os.path.abspath(__file__))
if _HOOK_DIR not in sys.path:
    sys.path.insert(0, _HOOK_DIR)
# Also add project root so `from hooks.engine import ...` works
_PROJECT_DIR = os.path.dirname(_HOOK_DIR)
if _PROJECT_DIR not in sys.path:
    sys.path.insert(0, _PROJECT_DIR)

from engine import (  # noqa: E402
    canonicalize_path,
    extract_tool_input,
    find_state_file,
    is_mission_path,
    is_test_command,
    is_test_file,
    load_config,
    load_state,
    validate_model,
)


# ═══════════════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════════════


def _is_state_json(filepath, mission_dir=None):
    """Return True if *filepath* points to the active .mission/state.json.

    When *mission_dir* is provided, does a full path comparison (anchored).
    Falls back to basename heuristic if mission_dir is not available.
    """
    if mission_dir:
        expected = os.path.join(mission_dir, "state.json")
        try:
            return os.path.normcase(os.path.realpath(filepath)) ==                    os.path.normcase(os.path.realpath(expected))
        except (OSError, ValueError):
            pass
    # Fallback: basename heuristic
    base = os.path.basename(filepath)
    if base != "state.json":
        return False
    parent = os.path.basename(os.path.dirname(filepath))
    return parent == ".mission"


def _is_worker_log(filepath):
    """Return True if *filepath* is under .mission/worker-logs/."""
    norm = filepath.replace(os.sep, "/")
    if norm.startswith(".mission/worker-logs/"):
        return True
    if "/.mission/worker-logs/" in norm:
        return True
    return False


def _is_report_path(filepath):
    """Return True if *filepath* is under .mission/reports/."""
    norm = filepath.replace(os.sep, "/")
    if norm.startswith(".mission/reports/"):
        return True
    if "/.mission/reports/" in norm:
        return True
    return False


def _is_worker_agent(agent_type):
    """Return True if *agent_type* is a worker role."""
    lower = agent_type.lower()
    return "worker" in lower


def _is_validator_agent(agent_type):
    """Return True if *agent_type* is a validator role."""
    lower = agent_type.lower()
    return "validator" in lower


def _extract_content(tool_input_dict):
    """Extract the content being written from a Write/Edit/MultiEdit tool input.

    Write uses "content", Edit uses "new_string" or "new_str",
    MultiEdit uses "edits" array with "new_string"/"new_str" per edit.
    Returns the concatenated content string or empty string.
    """
    # Write tool
    content = tool_input_dict.get("content", "")
    if content:
        return content
    # Edit tool
    content = tool_input_dict.get("new_string", "") or tool_input_dict.get("new_str", "")
    if content:
        return content
    # MultiEdit tool — concatenate all edit new_string values
    edits = tool_input_dict.get("edits", [])
    if isinstance(edits, list) and edits:
        parts = []
        for edit in edits:
            if isinstance(edit, dict):
                part = edit.get("new_string", "") or edit.get("new_str", "") or ""
                if part:
                    parts.append(part)
        return " ".join(parts)
    return ""


def _has_active_false(content):
    """Check if content sets active to false (JSON-aware)."""
    try:
        parsed = json.loads(content)
        if isinstance(parsed, dict) and parsed.get("active") is False:
            return True
    except (json.JSONDecodeError, ValueError):
        pass
    return '"active": false' in content or '"active":false' in content


def _has_completed_at(content):
    """Check if content contains completedAt key (JSON-aware)."""
    try:
        parsed = json.loads(content)
        if isinstance(parsed, dict) and "completedAt" in parsed:
            return True
    except (json.JSONDecodeError, ValueError):
        pass
    return "completedAt" in content


def _has_ended_at(content):
    """Check if content contains endedAt key (JSON-aware)."""
    try:
        parsed = json.loads(content)
        if isinstance(parsed, dict) and "endedAt" in parsed:
            return True
    except (json.JSONDecodeError, ValueError):
        pass
    return "endedAt" in content


def _extract_phase_from_content(content):
    """Try to extract a phase value from a content string.

    First attempts JSON parse, falls back to regex.
    Returns the phase string or empty string.
    """
    if not content:
        return ""
    # Try JSON parse first
    try:
        parsed = json.loads(content)
        if isinstance(parsed, dict):
            return parsed.get("phase", "")
    except (json.JSONDecodeError, ValueError):
        pass
    # Fallback: regex for "phase": "value"
    m = re.search(r'"phase"\s*:\s*"([^"]+)"', content)
    return m.group(1) if m else ""


# ═══════════════════════════════════════════════════════════════════════════════
# Block helper
# ═══════════════════════════════════════════════════════════════════════════════

_PHASE = ""
_PHASE_LOCK_PHASE = ""
_PHASE_LOCK_TIMESTAMP = ""


def _phase_lock_info():
    """Build phase lock info suffix for block messages."""
    if _PHASE_LOCK_PHASE:
        return f" [Lock: {_PHASE_LOCK_PHASE} since {_PHASE_LOCK_TIMESTAMP}]"
    return ""


def block(description, guidance=""):
    """Print BLOCK message to stderr and exit 1."""
    lock_info = _phase_lock_info()
    if guidance:
        msg = f'BLOCK: [MISSION GUARD] Phase "{_PHASE}" — {description}. {guidance}.{lock_info}'
    else:
        msg = f'BLOCK: [MISSION GUARD] Phase "{_PHASE}" — {description}.{lock_info}'
    print(msg, file=sys.stderr, flush=True)
    sys.exit(1)


def allow():
    """Exit 0 — allow the tool call."""
    sys.exit(0)


# ═══════════════════════════════════════════════════════════════════════════════
# Valid phase transitions
# ═══════════════════════════════════════════════════════════════════════════════

_VALID_TRANSITIONS = {
    "orchestrator": {"worker", "validator", "complete"},
    "worker": {"validator"},
    "validator": {"orchestrator"},
}

_KNOWN_PHASES = {"orchestrator", "worker", "validator", "complete"}


# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════


def main():
    global _PHASE, _PHASE_LOCK_PHASE, _PHASE_LOCK_TIMESTAMP

    # ── Step 1: Accept 2 args ────────────────────────────────────────────────
    if len(sys.argv) < 3:
        if len(sys.argv) < 2:
            print("phase-guard.py: missing TOOL_NAME and TOOL_INPUT args", file=sys.stderr, flush=True)
        else:
            print("phase-guard.py: missing TOOL_INPUT arg", file=sys.stderr, flush=True)
        sys.exit(0)  # Don't block on missing args

    tool_name = sys.argv[1]
    tool_input_raw = sys.argv[2]

    # ── Step 2: Find state file ──────────────────────────────────────────────
    state_path = find_state_file()
    if state_path is None:
        sys.exit(0)  # Not in mission mode

    mission_dir = os.path.dirname(state_path)

    # ── Step 3: Load state ───────────────────────────────────────────────────
    state = load_state(state_path)

    active = state.get("active", False)
    if active is not True and str(active).lower() != "true":
        sys.exit(0)

    _PHASE = state.get("phase", "")
    if not _PHASE:
        sys.exit(0)

    persistence = state.get("persistence", "relentless")
    strict_phase_lock = state.get("strictPhaseLock", True)
    phase_lock = state.get("phaseLock", {})
    if not isinstance(phase_lock, dict):
        phase_lock = {}
    _PHASE_LOCK_PHASE = phase_lock.get("phase", "")
    _PHASE_LOCK_TIMESTAMP = phase_lock.get("lockedAt", "")
    current_round = state.get("round", 1)

    # ── Step 4: Phase lock check ─────────────────────────────────────────────
    if strict_phase_lock and _PHASE_LOCK_PHASE:
        if _PHASE_LOCK_PHASE != _PHASE:
            block(
                f'Phase lock conflict — state phase is "{_PHASE}" but phaseLock is "{_PHASE_LOCK_PHASE}"',
                "Resolve by having the Orchestrator update phaseLock to match the current phase",
            )

    # ── Step 5: Extract tool input ───────────────────────────────────────────
    tool_input = extract_tool_input(tool_input_raw)

    # ── Step 6: Get file_path ────────────────────────────────────────────────
    file_path = tool_input.get("file_path", "")

    # ── Step 7: Canonicalize file_path ───────────────────────────────────────
    if file_path:
        file_path = canonicalize_path(file_path)

    # ── Step 8: Model validation for Agent calls in orchestrator phase ───────
    if tool_name == "Agent" and _PHASE == "orchestrator":
        action, msg, modified = validate_model(tool_input, state, load_config())
        if action == "block":
            print(msg, file=sys.stderr, flush=True)
            sys.exit(1)
        elif action == "inject":
            # Print the modified input as JSON for the caller to pick up
            print(json.dumps(modified), flush=True)
            sys.exit(0)
        # action == "allow" → continue


    # ── Step 8b: Round / duration limits for Agent dispatch ─────────────────
    if tool_name == "Agent" and _PHASE == "orchestrator":
        subagent_type = tool_input.get("subagent_type", "")
        if subagent_type in ("mission-worker", "mission-validator"):
            config = load_config()
            max_rounds = state.get("maxRounds", config.get("maxRounds", 10))
            max_duration = state.get("maxDurationMinutes", config.get("maxDurationMinutes", 120))

            round_exceeded = isinstance(max_rounds, (int, float)) and current_round > max_rounds

            duration_exceeded = False
            started_at = state.get("startedAt", "")
            if started_at and isinstance(max_duration, (int, float)):
                try:
                    import datetime
                    start_dt = datetime.datetime.fromisoformat(started_at.replace("Z", "+00:00"))
                    elapsed = (datetime.datetime.now(datetime.timezone.utc) - start_dt).total_seconds() / 60
                    duration_exceeded = elapsed > max_duration
                except (ValueError, TypeError, OverflowError):
                    pass

            if round_exceeded or duration_exceeded:
                parts = []
                if round_exceeded:
                    parts.append(f"round {current_round} exceeds maxRounds {max_rounds}")
                if duration_exceeded:
                    parts.append(f"elapsed time exceeds maxDurationMinutes {max_duration}")
                detail = " and ".join(parts)

                if persistence == "relentless":
                    print(f"WARNING: [MISSION GUARD] {detail} — continuing in relentless mode",
                          file=sys.stderr, flush=True)
                else:
                    block(f"Limit exceeded — {detail}",
                          f"Mission is in {persistence} mode. Use /mission-config to increase limits "
                          "or switch to relentless mode")

    # ── State.json mutation checks (steps 9-13) ─────────────────────────────
    # These apply to Write, Edit, and MultiEdit tools writing to state.json
    is_write_tool = tool_name in ("Write", "Edit", "MultiEdit")

    if is_write_tool and file_path and _is_state_json(file_path, mission_dir):
        content = _extract_content(tool_input)

        # ── Step 9: Exit-mission bypass ──────────────────────────────────────
        # endedAt without completedAt → force-exit, bypass all guards
        # If completedAt is ALSO present, do NOT bypass (still enforce guards)
        # SECURITY: Only the Orchestrator may force-exit the mission.
        if _has_ended_at(content) and not _has_completed_at(content):
            if _PHASE != "orchestrator":
                block(
                    "Only the Orchestrator can force-exit the mission",
                    "Workers and Validators cannot write endedAt to state.json",
                )
            sys.exit(0)

        # ── Step 10: Phase transition check ──────────────────────────────────
        new_phase = _extract_phase_from_content(content)
        if new_phase:
            if new_phase not in _KNOWN_PHASES:
                block(
                    f'Unknown phase value: "{new_phase}"',
                    "Valid phases: orchestrator, worker, validator, complete",
                )
            # Same-phase writes are always allowed
            if new_phase != _PHASE:
                valid_targets = _VALID_TRANSITIONS.get(_PHASE, set())
                if new_phase not in valid_targets:
                    block(
                        f"Invalid phase transition: {_PHASE} -> {new_phase}",
                        "Valid transitions: orchestrator->worker, orchestrator->validator, "
                        "orchestrator->complete, worker->validator, validator->orchestrator",
                    )

        # ── Step 11: Completion guard ────────────────────────────────────────
        if new_phase == "complete":
            report_file = os.path.join(mission_dir, "reports", f"round-{current_round}.md")
            if not os.path.isfile(report_file):
                block(
                    f"Cannot complete mission — no validator report found for round {current_round}",
                    f"A validator must run and produce .mission/reports/round-{current_round}.md "
                    "before the mission can complete",
                )
            if persistence == "relentless":
                try:
                    with open(report_file, "r", encoding="utf-8") as f:
                        report_content = f.read()
                except OSError:
                    report_content = ""
                if not re.search(r"^\s*#*\s*Verdict:\s*PASS\b", report_content, re.IGNORECASE | re.MULTILINE):
                    block(
                        "Relentless mode — cannot complete mission while validator report says FAIL",
                        f"The report at .mission/reports/round-{current_round}.md must contain "
                        "'Verdict: PASS' before completing in relentless mode",
                    )

        # ── Step 12: Cleanup guard ───────────────────────────────────────────
        if _has_active_false(content) and _has_completed_at(content):
            # Check summary.md
            summary_path = os.path.join(mission_dir, "summary.md")
            if not os.path.isfile(summary_path):
                block(
                    "Cannot deactivate — .mission/summary.md not found",
                    "Generate summary before completing",
                )
            # Check worker-logs
            worker_logs_dir = os.path.join(mission_dir, "worker-logs")
            if os.path.isdir(worker_logs_dir):
                md_files = [f for f in os.listdir(worker_logs_dir) if f.endswith(".md")]
                if md_files:
                    block(
                        "Cannot deactivate — worker logs not cleaned up",
                        "Remove .mission/worker-logs/*.md before completing",
                    )

            # ── Defense 5 (relentless): Verify PASS before deactivation ──────
            if persistence == "relentless":
                report_file = os.path.join(mission_dir, "reports", f"round-{current_round}.md")
                if not os.path.isfile(report_file):
                    block(
                        f"Relentless mode — cannot deactivate without validator report for round {current_round}",
                        f"A validator must produce .mission/reports/round-{current_round}.md "
                        "with 'Verdict: PASS' before deactivation",
                    )
                try:
                    with open(report_file, "r", encoding="utf-8") as f:
                        report_content = f.read()
                except OSError:
                    report_content = ""
                if not re.search(r"^\s*#*\s*Verdict:\s*PASS\b", report_content, re.IGNORECASE | re.MULTILINE):
                    block(
                        "Relentless mode — cannot deactivate while validator report says FAIL",
                        f"The report at .mission/reports/round-{current_round}.md must contain "
                        "'Verdict: PASS' before deactivating in relentless mode",
                    )

        # ── Step 13: Anti-premature completion (relentless) ──────────────────
        if persistence == "relentless":
            if _has_active_false(content) and not _has_completed_at(content):
                block(
                    "Relentless mode — cannot deactivate mission without completion",
                    "Mission is in relentless mode. Include a completedAt field to perform "
                    "a legitimate completion, or use /exit-mission to force stop",
                )

    # ═════════════════════════════════════════════════════════════════════════
    # PHASE ENFORCEMENT (Step 14-16)
    # ═════════════════════════════════════════════════════════════════════════

    if _PHASE == "orchestrator":
        _enforce_orchestrator(tool_name, tool_input, file_path)
    elif _PHASE == "worker":
        _enforce_worker(tool_name, tool_input, file_path)
    elif _PHASE == "validator":
        _enforce_validator(tool_name, tool_input, file_path)
    else:
        # Unknown phase → BLOCK all
        block(f'Unknown phase "{_PHASE}" — all tool calls blocked')

    # Default: ALLOW
    sys.exit(0)


# ═══════════════════════════════════════════════════════════════════════════════
# Phase enforcement functions
# ═══════════════════════════════════════════════════════════════════════════════


def _enforce_orchestrator(tool_name, tool_input, file_path):
    """Orchestrator: ALLOW .mission/* writes, BLOCK source writes; ALLOW Agent/Bash."""
    if tool_name in ("Write", "Edit", "MultiEdit"):
        if file_path and is_mission_path(file_path):
            allow()
        if file_path:
            block(
                "Orchestrator cannot write/edit source files",
                "Use the Agent tool to dispatch Workers for code changes",
            )
        # Empty file_path → ALLOW
        allow()

    # Bash → ALLOW
    # Agent → ALLOW
    allow()


def _enforce_worker(tool_name, tool_input, file_path):
    """Worker: ALLOW source writes + worker-logs; BLOCK .mission/*, test files, test commands."""
    if tool_name in ("Write", "Edit", "MultiEdit"):
        if file_path and is_mission_path(file_path):
            if _is_worker_log(file_path):
                allow()
            block(
                "Workers cannot modify .mission/ files (except worker-logs)",
                "Only the Orchestrator manages mission state, plan, and reports",
            )
        if file_path and is_test_file(file_path):
            block(
                "Workers cannot write test files — testing is the Validator's exclusive responsibility",
                "Complete your implementation and let the Validator handle tests",
            )
        # Source files or empty path → ALLOW
        allow()

    if tool_name == "Bash":
        cmd = tool_input.get("command", "")
        if cmd and is_test_command(cmd):
            block(
                f"Workers cannot run tests — attempted: {cmd}",
                "Testing is the Validator's job. Complete your implementation first",
            )
        allow()

    if tool_name == "Agent":
        agent_type = tool_input.get("subagent_type", "")
        if agent_type and _is_validator_agent(agent_type):
            block(
                "Workers cannot spawn Validators",
                "Only the Orchestrator dispatches Validators after all Workers complete",
            )
        allow()

    # Other tools → ALLOW
    allow()


def _enforce_validator(tool_name, tool_input, file_path):
    """Validator: ALLOW test files + reports; BLOCK source files, .mission/* (except reports)."""
    if tool_name in ("Write", "Edit", "MultiEdit"):
        # Block state.json explicitly
        if file_path and _is_state_json(file_path):
            block(
                "Validators cannot modify .mission/state.json",
                "Only the Orchestrator manages mission state. Write your findings to .mission/reports/ instead",
            )
        # .mission/ paths: only reports allowed
        if file_path and is_mission_path(file_path):
            if _is_report_path(file_path):
                allow()
            block(
                f"Validators can only write .mission/reports/* — blocked: {file_path}",
                "Other .mission/ paths are managed by the Orchestrator",
            )
        # Test files → ALLOW
        if file_path and is_test_file(file_path):
            allow()
        # Source files → BLOCK
        if file_path:
            block(
                f"Validators can only write test files and .mission/reports/* — blocked: {file_path}",
                "Allowed patterns: *.test.*, *.spec.*, *_test.*, *_spec.*, tests/*, __tests__/*, "
                "spec/*, .mission/reports/*",
            )
        # Empty file_path → ALLOW
        allow()

    if tool_name == "Bash":
        allow()

    if tool_name == "Agent":
        agent_type = tool_input.get("subagent_type", "")
        if agent_type and _is_worker_agent(agent_type):
            block(
                "Validators cannot spawn Workers",
                "Only the Orchestrator dispatches Workers. Report issues in .mission/reports/ "
                "for the Orchestrator to act on",
            )
        allow()

    # Other tools → ALLOW
    allow()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # On unhandled crash (e.g. RecursionError), allow the tool call
        # rather than blocking with a traceback
        sys.exit(0)
