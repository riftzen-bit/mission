"""
hooks/engine.py — Shared Python engine for Mission Plugin hooks.

Provides common utilities for state loading, path canonicalization,
file/command classification, and model validation.

Stdlib only (json, os, sys, pathlib, re). Python 3.8+ compatible.
"""

import json
import os
import re


# ─── Default configuration ───────────────────────────────────────────────────

_DEFAULT_CONFIG = {
    "models": {
        "orchestrator": "opus",
        "worker": "opus",
        "validator": "opus",
    },
    "persistence": "relentless",
    "progressBanners": True,
    "strictPhaseLock": True,
    "maxRounds": 10,
    "maxDurationMinutes": 120,
}


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _deep_merge(base, override):
    """Recursively merge *override* into a copy of *base*."""
    merged = dict(base)
    for key, val in override.items():
        if (
            key in merged
            and isinstance(merged[key], dict)
            and isinstance(val, dict)
        ):
            merged[key] = _deep_merge(merged[key], val)
        else:
            merged[key] = val
    return merged


# ─── State / Config / Features loaders ────────────────────────────────────────

def load_state(state_path=None):
    """Parse .mission/state.json and return a dict.

    Missing or malformed file returns ``{"active": False}``.
    """
    if state_path is None:
        state_path = find_state_file()
    if state_path is None:
        return {"active": False}
    try:
        with open(state_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            return {"active": False}
        return data
    except (OSError, json.JSONDecodeError, ValueError):
        return {"active": False}


def load_config(config_path=None):
    """Read ~/.mission/config.json and deep-merge with defaults.

    Missing or malformed file returns the full default config.
    """
    if config_path is None:
        config_path = os.path.join(os.path.expanduser("~"), ".mission", "config.json")
    try:
        with open(config_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            return dict(_DEFAULT_CONFIG)
        return _deep_merge(_DEFAULT_CONFIG, data)
    except (OSError, json.JSONDecodeError, ValueError):
        return dict(_DEFAULT_CONFIG)


def load_features(features_path=None):
    """Read .mission/features.json.

    Falls back to ``.bak`` copy if the primary file is missing or corrupt.
    Returns ``{"features": []}`` if both fail.
    """
    if features_path is None:
        state_file = find_state_file()
        if state_file is None:
            return {"features": []}
        features_path = os.path.join(os.path.dirname(state_file), "features.json")

    # Try primary file first
    data = _try_load_json(features_path)
    if data is not None:
        return data

    # Primary failed — try .bak
    bak_path = features_path + ".bak"
    data = _try_load_json(bak_path)
    if data is not None:
        return data

    return {"features": []}


def _try_load_json(path):
    """Try to load a JSON dict from *path*. Returns dict or None."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            return data
        return None
    except (OSError, json.JSONDecodeError, ValueError):
        return None


# ─── Atomic write ────────────────────────────────────────────────────────────

def atomic_write(path, content):
    """Write *content* to *path* atomically via a temp file + os.replace().

    On POSIX, ``os.replace()`` is atomic. On Windows it is near-atomic.
    If the write or replace fails, the original file is untouched.
    """
    tmp_path = path + ".tmp"
    try:
        with open(tmp_path, "w", encoding="utf-8") as fh:
            fh.write(content)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_path, path)
    except OSError:
        # Clean up temp file on failure; original file untouched
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        raise


def write_features(features_path, data):
    """Write features dict to *features_path* atomically, keeping a .bak copy.

    Creates a ``.bak`` backup of the existing file before overwriting.
    """
    content = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    # Backup existing file
    if os.path.isfile(features_path):
        bak_path = features_path + ".bak"
        try:
            with open(features_path, "r", encoding="utf-8") as fh:
                bak_content = fh.read()
            atomic_write(bak_path, bak_content)
        except OSError:
            pass  # Best-effort backup
    atomic_write(features_path, content)


# ─── Path utilities ───────────────────────────────────────────────────────────

def canonicalize_path(path_str):
    """Resolve symlinks for existing paths, normalize for others. Handle Unicode."""
    if os.path.exists(path_str) or os.path.islink(path_str):
        return os.path.realpath(path_str)
    return os.path.normpath(path_str)


def find_state_file(start_dir=None):
    """Walk upward from *start_dir* looking for .mission/state.json.

    Returns the absolute path or ``None``.
    """
    if start_dir is None:
        start_dir = os.getcwd()
    current = os.path.abspath(start_dir)
    while True:
        candidate = os.path.join(current, ".mission", "state.json")
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(current)
        if parent == current:
            break
        current = parent
    return None


def is_mission_path(path_str):
    """Return True if *path_str* resolves to inside a .mission/ directory.

    False for .mission-fake/, src/mission/, etc.
    """
    canon = canonicalize_path(path_str)
    # Normalize separators to /
    canon = canon.replace(os.sep, "/")

    # Check for /.mission/ segment or path starting with .mission/
    if "/.mission/" in canon or canon.endswith("/.mission"):
        return True
    # Relative paths starting with .mission/
    if canon == ".mission" or canon.startswith(".mission/"):
        return True
    return False


# ─── File / command classification ────────────────────────────────────────────

_TEST_FILE_EXTENSIONS = r"\.(?:py|js|ts|jsx|tsx|rb|go|rs|java|kt|cpp|c|cs|swift|sh)$"

_TEST_FILE_BASENAME_PATTERNS = re.compile(
    r"(?:"
    r".*\.test\..+"       # *.test.*
    r"|.*\.spec\..+"      # *.spec.*
    r"|.*_test\..+"       # *_test.*
    r"|.*_spec\..+"       # *_spec.*
    r"|test_.*" + _TEST_FILE_EXTENSIONS  # test_*.py, test_*.js, etc. (not test_data.json)
    + r")$"
)

_TEST_DIR_PATTERNS = re.compile(
    r"(?:^|/)(?:tests|__tests__|spec)/"
)


def is_test_file(path_str):
    """Return True if *path_str* looks like a test file.

    True patterns:
        *.test.*, *.spec.*, *_test.*, *_spec.*, test_*,
        tests/*, __tests__/*, spec/*

    False patterns:
        test-fixtures/data.json, src/testUtils.ts, contest/entry.py
    """
    # Normalize separators
    normalized = path_str.replace(os.sep, "/")
    basename = os.path.basename(normalized)

    # Basename patterns
    if _TEST_FILE_BASENAME_PATTERNS.match(basename):
        return True

    # Directory patterns — tests/, __tests__/, spec/
    if _TEST_DIR_PATTERNS.search(normalized):
        return True
    # Also check if path starts with tests/, __tests__/, spec/ (no leading /)
    if (
        normalized.startswith("tests/")
        or normalized.startswith("__tests__/")
        or normalized.startswith("spec/")
    ):
        return True

    return False


# Direct test runners
_DIRECT_TEST_RUNNERS = [
    "npm test",
    "npx jest",
    "npx vitest",
    "npx mocha",
    "yarn test",
    "pnpm test",
    "pytest",
    "python -m pytest",
    "python3 -m pytest",
    "go test",
    "cargo test",
    "make test",
    "gradle test",
    "mvn test",
    "bundle exec rspec",
    "phpunit",
]

# Patterns for npm/yarn/pnpm run test:*
_NPM_RUN_TEST_RE = re.compile(
    r"(?:npm|yarn|pnpm)\s+(?:run\s+)?test(?::\S+)?"
)


def is_test_command(cmd):
    """Return True if *cmd* is a test-runner invocation.

    Handles direct runners, wrapped commands (sh -c, bash -c),
    chained commands (&&, ;), env prefixes, and npm run test:* variants.
    """
    if not cmd or not isinstance(cmd, str):
        return False

    stripped = cmd.strip()
    if not stripped:
        return False

    # Check for wrapped commands: sh -c "...", bash -c '...'
    # Extract inner command
    inner = _unwrap_shell(stripped)
    if inner != stripped:
        return is_test_command(inner)

    # Strip env-style prefixes: env VAR=val ..., VAR=val ...
    cleaned = _strip_env_prefix(stripped)

    # Handle chained commands: cmd1 && cmd2, cmd1 ; cmd2
    # Also handle: cd dir && cmd
    parts = re.split(r"\s*&&\s*|\s*;\s*", cleaned)
    for part in parts:
        part = part.strip()
        if not part:
            continue
        # Skip cd commands
        if part.startswith("cd "):
            continue
        if _is_direct_test(part):
            return True

    return False


def _unwrap_shell(cmd):
    """Extract inner command from sh -c '...' or bash -c '...' wrappers."""
    m = re.match(
        r"""^(?:sh|bash)\s+-c\s+(['"])(.*)\1\s*$""",
        cmd,
    )
    if m:
        return m.group(2).strip()
    # Also handle without quotes (less common but possible)
    m = re.match(
        r"^(?:sh|bash)\s+-c\s+(.+)$",
        cmd,
    )
    if m:
        return m.group(1).strip()
    return cmd


def _strip_env_prefix(cmd):
    """Strip leading env VAR=val or VAR=val prefixes."""
    # env command: env VAR=val ... actual_command
    m = re.match(r"^env\s+((?:\S+=\S+\s+)*)(.+)$", cmd)
    if m:
        return m.group(2).strip()
    # Direct VAR=val prefix: VAR=val actual_command
    result = cmd
    while True:
        m = re.match(r"^[A-Za-z_][A-Za-z0-9_]*=\S+\s+(.+)$", result)
        if m:
            result = m.group(1).strip()
        else:
            break
    return result


def _is_direct_test(cmd):
    """Check if *cmd* is a direct test runner invocation."""
    for runner in _DIRECT_TEST_RUNNERS:
        if cmd == runner or cmd.startswith(runner + " ") or cmd.startswith(runner + "\t"):
            return True
    # npm/yarn/pnpm run test:* variants
    if _NPM_RUN_TEST_RE.match(cmd):
        return True
    return False


# ─── Tool input helpers ───────────────────────────────────────────────────────

def extract_tool_input(raw_json):
    """Parse a JSON string to dict. Malformed/empty returns ``{}``."""
    if not raw_json:
        return {}
    try:
        result = json.loads(raw_json)
        if isinstance(result, dict):
            return result
        return {}
    except (json.JSONDecodeError, TypeError, ValueError):
        return {}


# ─── Model validation ────────────────────────────────────────────────────────

def validate_model(tool_input, state, config):
    """Validate and potentially inject the correct model for mission agents.

    Returns ``(action, message, modified_input)`` where *action* is one of:
    - ``"allow"``  — model matches or not a mission agent; message and modified are None.
    - ``"block"``  — wrong model specified; message contains the block reason.
    - ``"inject"`` — model missing; modified_input has the correct model set.
    """
    if not isinstance(tool_input, dict):
        return ("allow", None, None)

    subagent_type = tool_input.get("subagent_type", "")
    if not subagent_type:
        return ("allow", None, None)

    # Determine role from subagent_type
    role = None
    if subagent_type == "mission-worker":
        role = "worker"
    elif subagent_type == "mission-validator":
        role = "validator"
    else:
        # Non-mission agent types → allow
        return ("allow", None, None)

    # Determine expected model: state overrides config
    state_models = state.get("models", {}) if isinstance(state, dict) else {}
    config_models = config.get("models", {}) if isinstance(config, dict) else {}
    expected_model = state_models.get(role) or config_models.get(role, "opus")

    current_model = tool_input.get("model", "")

    if not current_model or not current_model.strip():
        # Missing model → inject
        modified = dict(tool_input)
        modified["model"] = expected_model
        return ("inject", None, modified)

    # Compare case-insensitive, trimmed
    if current_model.strip().lower() == expected_model.strip().lower():
        return ("allow", None, None)

    # Wrong model → block
    msg = (
        f"BLOCK: [MISSION GUARD] Model mismatch for {subagent_type} — "
        f"expected \"{expected_model}\" but got \"{current_model.strip()}\""
    )
    return ("block", msg, None)


# ─── Feature tracking ────────────────────────────────────────────────────────

# Valid status transitions (old_status → set of allowed new_statuses)
_VALID_STATUS_TRANSITIONS = {
    "pending": {"in-progress"},
    "in-progress": {"completed", "failed"},
}


def validate_status_transition(old_status, new_status):
    """Return True if transitioning from *old_status* to *new_status* is valid.

    Valid transitions:
      pending → in-progress
      in-progress → completed
      in-progress → failed

    All other transitions (including same-status) return False.
    Non-string inputs return False.
    """
    if not isinstance(old_status, str) or not isinstance(new_status, str):
        return False
    allowed = _VALID_STATUS_TRANSITIONS.get(old_status)
    if allowed is None:
        return False
    return new_status in allowed


def get_current_feature(features):
    """Return the first feature with status ``"in-progress"``, or None."""
    if not isinstance(features, dict):
        return None
    feature_list = features.get("features", [])
    if not isinstance(feature_list, list):
        return None
    for feature in feature_list:
        if isinstance(feature, dict) and feature.get("status") == "in-progress":
            return feature
    return None


def get_next_feature(features):
    """Return the first pending feature whose dependencies are all completed.

    Returns None if no feature is available.
    """
    if not isinstance(features, dict):
        return None
    feature_list = features.get("features", [])
    if not isinstance(feature_list, list):
        return None

    # Build a set of completed feature IDs/names
    completed = set()
    for feature in feature_list:
        if isinstance(feature, dict) and feature.get("status") == "completed":
            fid = feature.get("id") or feature.get("name", "")
            if fid:
                completed.add(fid)

    for feature in feature_list:
        if not isinstance(feature, dict):
            continue
        if feature.get("status") != "pending":
            continue
        deps = feature.get("dependencies", [])
        if not isinstance(deps, list):
            continue
        if all(dep in completed for dep in deps):
            return feature

    return None
