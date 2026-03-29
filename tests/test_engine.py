"""
tests/test_engine.py — Pytest suite for hooks/engine.py

50+ test cases using tmp_path fixture and @pytest.mark.parametrize.
"""

import json
import os
import sys

import pytest

# Ensure the project root is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from hooks.engine import (
    _deep_merge,
    canonicalize_path,
    extract_tool_input,
    find_state_file,
    get_current_feature,
    get_next_feature,
    is_mission_path,
    is_test_command,
    is_test_file,
    load_config,
    load_features,
    load_state,
    validate_model,
    validate_status_transition,
)


# ═══════════════════════════════════════════════════════════════════════════════
# load_state
# ═══════════════════════════════════════════════════════════════════════════════


class TestLoadState:
    """Tests for load_state()."""

    def test_valid_state(self, tmp_path):
        state = {
            "active": True,
            "phase": "worker",
            "persistence": "relentless",
            "round": 2,
            "task": "Implement auth",
        }
        sf = tmp_path / ".mission" / "state.json"
        sf.parent.mkdir(parents=True)
        sf.write_text(json.dumps(state))
        result = load_state(str(sf))
        assert result["active"] is True
        assert result["phase"] == "worker"
        assert result["round"] == 2

    def test_missing_file(self, tmp_path):
        result = load_state(str(tmp_path / "nonexistent.json"))
        assert result == {"active": False}

    def test_malformed_json(self, tmp_path):
        sf = tmp_path / "state.json"
        sf.write_text("{not valid json!!!")
        result = load_state(str(sf))
        assert result == {"active": False}

    def test_json_array_not_dict(self, tmp_path):
        sf = tmp_path / "state.json"
        sf.write_text("[1, 2, 3]")
        result = load_state(str(sf))
        assert result == {"active": False}

    def test_missing_fields_returns_what_exists(self, tmp_path):
        sf = tmp_path / "state.json"
        sf.write_text(json.dumps({"active": True}))
        result = load_state(str(sf))
        assert result["active"] is True
        assert "phase" not in result

    def test_empty_file(self, tmp_path):
        sf = tmp_path / "state.json"
        sf.write_text("")
        result = load_state(str(sf))
        assert result == {"active": False}

    def test_none_path_no_state(self, tmp_path, monkeypatch):
        """load_state(None) uses find_state_file(); if not found → inactive."""
        monkeypatch.chdir(tmp_path)
        result = load_state(None)
        assert result == {"active": False}

    def test_full_state_round_trip(self, tmp_path):
        """Ensure all recognized fields survive the round-trip."""
        state = {
            "active": True,
            "phase": "validator",
            "persistence": "relentless",
            "strictPhaseLock": True,
            "phaseLock": {"phase": "validator", "lockedAt": "2025-01-01T00:00:00Z", "lockedBy": "orchestrator"},
            "round": 3,
            "task": "Fix auth bug",
            "workers": [{"id": "w1", "status": "done"}],
            "currentAction": "Validating worker output",
            "models": {"orchestrator": "opus", "worker": "sonnet", "validator": "opus"},
        }
        sf = tmp_path / "state.json"
        sf.write_text(json.dumps(state))
        result = load_state(str(sf))
        assert result == state


# ═══════════════════════════════════════════════════════════════════════════════
# load_config
# ═══════════════════════════════════════════════════════════════════════════════


class TestLoadConfig:
    """Tests for load_config()."""

    def test_valid_config_merge(self, tmp_path):
        cfg = {"models": {"worker": "sonnet"}, "maxRounds": 5}
        cf = tmp_path / "config.json"
        cf.write_text(json.dumps(cfg))
        result = load_config(str(cf))
        # User override
        assert result["models"]["worker"] == "sonnet"
        assert result["maxRounds"] == 5
        # Defaults preserved
        assert result["models"]["orchestrator"] == "opus"
        assert result["models"]["validator"] == "opus"
        assert result["persistence"] == "relentless"
        assert result["progressBanners"] is True
        assert result["strictPhaseLock"] is True
        assert result["maxDurationMinutes"] == 120

    def test_missing_file_returns_defaults(self, tmp_path):
        result = load_config(str(tmp_path / "no-such-config.json"))
        assert result["models"]["orchestrator"] == "opus"
        assert result["maxRounds"] == 10

    def test_malformed_json(self, tmp_path):
        cf = tmp_path / "config.json"
        cf.write_text("{{bad}}")
        result = load_config(str(cf))
        assert result["persistence"] == "relentless"

    def test_json_array_returns_defaults(self, tmp_path):
        cf = tmp_path / "config.json"
        cf.write_text("[1]")
        result = load_config(str(cf))
        assert result == {
            "models": {"orchestrator": "opus", "worker": "opus", "validator": "opus"},
            "persistence": "relentless",
            "progressBanners": True,
            "strictPhaseLock": True,
            "maxRounds": 10,
            "maxDurationMinutes": 120,
        }

    def test_partial_models_merge(self, tmp_path):
        cf = tmp_path / "config.json"
        cf.write_text(json.dumps({"models": {"validator": "haiku"}}))
        result = load_config(str(cf))
        assert result["models"]["validator"] == "haiku"
        assert result["models"]["orchestrator"] == "opus"
        assert result["models"]["worker"] == "opus"


# ═══════════════════════════════════════════════════════════════════════════════
# load_features
# ═══════════════════════════════════════════════════════════════════════════════


class TestLoadFeatures:
    """Tests for load_features()."""

    def test_valid_features(self, tmp_path):
        features = {"features": [{"id": "f1", "status": "pending"}]}
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps(features))
        result = load_features(str(ff))
        assert len(result["features"]) == 1

    def test_empty_features_list(self, tmp_path):
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps({"features": []}))
        result = load_features(str(ff))
        assert result["features"] == []

    def test_missing_file(self, tmp_path):
        result = load_features(str(tmp_path / "nope.json"))
        assert result == {"features": []}

    def test_malformed_json(self, tmp_path):
        ff = tmp_path / "features.json"
        ff.write_text("not json")
        result = load_features(str(ff))
        assert result == {"features": []}

    def test_json_array_returns_default(self, tmp_path):
        ff = tmp_path / "features.json"
        ff.write_text("[1,2]")
        result = load_features(str(ff))
        assert result == {"features": []}


# ═══════════════════════════════════════════════════════════════════════════════
# canonicalize_path
# ═══════════════════════════════════════════════════════════════════════════════


class TestCanonicalizePath:
    """Tests for canonicalize_path()."""

    def test_traversal_resolve(self):
        result = canonicalize_path("src/../.mission/state.json")
        assert ".." not in result
        assert result.endswith(os.path.join(".mission", "state.json"))

    def test_symlink_resolve(self, tmp_path):
        real = tmp_path / "real.txt"
        real.write_text("hello")
        link = tmp_path / "link.txt"
        link.symlink_to(real)
        result = canonicalize_path(str(link))
        assert result == str(real.resolve())

    def test_nonexistent_path(self):
        result = canonicalize_path("/does/not/exist/foo.txt")
        assert result == os.path.normpath("/does/not/exist/foo.txt")

    def test_unicode_path(self, tmp_path):
        udir = tmp_path / "dữ_liệu"
        udir.mkdir()
        result = canonicalize_path(str(udir))
        assert "dữ_liệu" in result

    def test_dot_segments(self):
        result = canonicalize_path("./a/./b/../c")
        assert result == os.path.normpath("a/c")


# ═══════════════════════════════════════════════════════════════════════════════
# find_state_file
# ═══════════════════════════════════════════════════════════════════════════════


class TestFindStateFile:
    """Tests for find_state_file()."""

    def test_found_in_cwd(self, tmp_path):
        mission_dir = tmp_path / ".mission"
        mission_dir.mkdir()
        sf = mission_dir / "state.json"
        sf.write_text("{}")
        result = find_state_file(str(tmp_path))
        assert result == str(sf)

    def test_found_in_parent(self, tmp_path):
        mission_dir = tmp_path / ".mission"
        mission_dir.mkdir()
        sf = mission_dir / "state.json"
        sf.write_text("{}")
        child = tmp_path / "src" / "deep"
        child.mkdir(parents=True)
        result = find_state_file(str(child))
        assert result == str(sf)

    def test_not_found(self, tmp_path):
        child = tmp_path / "empty" / "child"
        child.mkdir(parents=True)
        result = find_state_file(str(child))
        assert result is None


# ═══════════════════════════════════════════════════════════════════════════════
# is_mission_path
# ═══════════════════════════════════════════════════════════════════════════════


class TestIsMissionPath:
    """Tests for is_mission_path()."""

    @pytest.mark.parametrize(
        "path_str",
        [
            ".mission/state.json",
            ".mission/plan.md",
            ".mission/reports/round-1.md",
            "/home/user/project/.mission/state.json",
            "/home/user/project/.mission/worker-logs/w1.md",
        ],
    )
    def test_true_cases(self, path_str):
        assert is_mission_path(path_str) is True

    @pytest.mark.parametrize(
        "path_str",
        [
            ".mission-fake/state.json",
            "src/mission/index.ts",
            "mission/state.json",
            "test/.mission-alt/foo",
        ],
    )
    def test_false_cases(self, path_str):
        assert is_mission_path(path_str) is False

    def test_absolute_mission_path(self, tmp_path):
        mission_dir = tmp_path / ".mission"
        mission_dir.mkdir()
        sf = mission_dir / "state.json"
        sf.write_text("{}")
        assert is_mission_path(str(sf)) is True

    def test_dotmission_alone(self):
        assert is_mission_path(".mission") is True


# ═══════════════════════════════════════════════════════════════════════════════
# is_test_file
# ═══════════════════════════════════════════════════════════════════════════════


class TestIsTestFile:
    """Tests for is_test_file()."""

    @pytest.mark.parametrize(
        "path_str",
        [
            "auth.test.ts",
            "auth.spec.js",
            "auth_test.py",
            "auth_spec.rb",
            "test_auth.py",
            "tests/test_auth.py",
            "src/tests/integration.py",
            "__tests__/Button.jsx",
            "spec/models/user_spec.rb",
            "src/__tests__/helpers.js",
        ],
    )
    def test_true_patterns(self, path_str):
        assert is_test_file(path_str) is True

    @pytest.mark.parametrize(
        "path_str",
        [
            "test-fixtures/data.json",
            "src/testUtils.ts",
            "contest/entry.py",
            "src/utils.ts",
            "attest/verify.py",
            "latest/report.md",
            "protest/main.py",
        ],
    )
    def test_false_patterns(self, path_str):
        assert is_test_file(path_str) is False


# ═══════════════════════════════════════════════════════════════════════════════
# is_test_command
# ═══════════════════════════════════════════════════════════════════════════════


class TestIsTestCommand:
    """Tests for is_test_command()."""

    @pytest.mark.parametrize(
        "cmd",
        [
            "npm test",
            "npx jest",
            "npx vitest run",
            "npx mocha --reporter spec",
            "yarn test",
            "pnpm test",
            "pytest",
            "pytest -xvs tests/",
            "python -m pytest",
            "python3 -m pytest tests/ -v",
            "go test ./...",
            "cargo test",
            "make test",
            "gradle test",
            "mvn test",
            "bundle exec rspec",
            "phpunit",
        ],
    )
    def test_direct_runners(self, cmd):
        assert is_test_command(cmd) is True

    @pytest.mark.parametrize(
        "cmd",
        [
            'sh -c "npm test"',
            "bash -c 'pytest -xvs'",
            "sh -c 'npx jest --coverage'",
        ],
    )
    def test_wrapped_commands(self, cmd):
        assert is_test_command(cmd) is True

    @pytest.mark.parametrize(
        "cmd",
        [
            "cd src && npm test",
            "cd /project && pytest",
            "cd app && npx jest",
        ],
    )
    def test_chained_commands(self, cmd):
        assert is_test_command(cmd) is True

    @pytest.mark.parametrize(
        "cmd",
        [
            "npm run test:unit",
            "npm run test:integration",
            "yarn test:e2e",
            "pnpm test:smoke",
        ],
    )
    def test_npm_run_test_variants(self, cmd):
        assert is_test_command(cmd) is True

    @pytest.mark.parametrize(
        "cmd",
        [
            "env CI=true npm test",
            "CI=true pytest",
            "NODE_ENV=test npx jest",
        ],
    )
    def test_env_prefixed(self, cmd):
        assert is_test_command(cmd) is True

    @pytest.mark.parametrize(
        "cmd",
        [
            "npm install",
            "npm run build",
            "npm run build-test-utils",
            "node scripts/generate-test-data.js",
            "echo test",
            "cat tests/data.json",
            "ls tests/",
            "",
            "   ",
        ],
    )
    def test_false_positives(self, cmd):
        assert is_test_command(cmd) is False

    def test_none_input(self):
        assert is_test_command(None) is False

    def test_integer_input(self):
        assert is_test_command(123) is False


# ═══════════════════════════════════════════════════════════════════════════════
# extract_tool_input
# ═══════════════════════════════════════════════════════════════════════════════


class TestExtractToolInput:
    """Tests for extract_tool_input()."""

    def test_valid_json(self):
        result = extract_tool_input('{"file_path": "src/index.ts"}')
        assert result == {"file_path": "src/index.ts"}

    def test_malformed_json(self):
        assert extract_tool_input("{bad") == {}

    def test_empty_string(self):
        assert extract_tool_input("") == {}

    def test_none(self):
        assert extract_tool_input(None) == {}

    def test_json_array_returns_empty(self):
        assert extract_tool_input("[1,2]") == {}

    def test_json_number_returns_empty(self):
        assert extract_tool_input("42") == {}


# ═══════════════════════════════════════════════════════════════════════════════
# validate_model
# ═══════════════════════════════════════════════════════════════════════════════


class TestValidateModel:
    """Tests for validate_model()."""

    def _make_state(self, **kwargs):
        base = {"active": True, "phase": "orchestrator"}
        base.update(kwargs)
        return base

    def _make_config(self, **kwargs):
        base = {
            "models": {"orchestrator": "opus", "worker": "opus", "validator": "opus"},
        }
        base.update(kwargs)
        return base

    def test_correct_model_allow(self):
        tool_input = {"subagent_type": "mission-worker", "model": "opus"}
        action, msg, modified = validate_model(
            tool_input, self._make_state(), self._make_config()
        )
        assert action == "allow"
        assert msg is None
        assert modified is None

    def test_wrong_model_block(self):
        tool_input = {"subagent_type": "mission-worker", "model": "haiku"}
        action, msg, modified = validate_model(
            tool_input, self._make_state(), self._make_config()
        )
        assert action == "block"
        assert "BLOCK" in msg
        assert "MISSION GUARD" in msg
        assert modified is None

    def test_missing_model_inject(self):
        tool_input = {"subagent_type": "mission-worker"}
        action, msg, modified = validate_model(
            tool_input, self._make_state(), self._make_config()
        )
        assert action == "inject"
        assert msg is None
        assert modified["model"] == "opus"
        assert modified["subagent_type"] == "mission-worker"

    def test_non_mission_agent_bypass(self):
        tool_input = {"subagent_type": "code-reviewer", "model": "haiku"}
        action, msg, modified = validate_model(
            tool_input, self._make_state(), self._make_config()
        )
        assert action == "allow"

    def test_no_subagent_type(self):
        tool_input = {"model": "opus"}
        action, msg, modified = validate_model(
            tool_input, self._make_state(), self._make_config()
        )
        assert action == "allow"

    def test_case_insensitive_match(self):
        tool_input = {"subagent_type": "mission-worker", "model": "OPUS"}
        action, msg, modified = validate_model(
            tool_input, self._make_state(), self._make_config()
        )
        assert action == "allow"

    def test_trimmed_match(self):
        tool_input = {"subagent_type": "mission-worker", "model": "  opus  "}
        action, msg, modified = validate_model(
            tool_input, self._make_state(), self._make_config()
        )
        assert action == "allow"

    def test_state_overrides_config(self):
        """State models take precedence over config models."""
        tool_input = {"subagent_type": "mission-worker", "model": "sonnet"}
        state = self._make_state(models={"worker": "sonnet"})
        config = self._make_config()  # config says opus
        action, msg, modified = validate_model(tool_input, state, config)
        assert action == "allow"

    def test_state_overrides_config_block(self):
        """Wrong model per state (even though config would allow it)."""
        tool_input = {"subagent_type": "mission-worker", "model": "opus"}
        state = self._make_state(models={"worker": "sonnet"})
        config = self._make_config()  # config says opus
        action, msg, modified = validate_model(tool_input, state, config)
        assert action == "block"

    def test_validator_model(self):
        tool_input = {"subagent_type": "mission-validator", "model": "opus"}
        action, msg, modified = validate_model(
            tool_input, self._make_state(), self._make_config()
        )
        assert action == "allow"

    def test_validator_wrong_model(self):
        tool_input = {"subagent_type": "mission-validator", "model": "haiku"}
        action, msg, modified = validate_model(
            tool_input, self._make_state(), self._make_config()
        )
        assert action == "block"

    def test_empty_model_string_inject(self):
        tool_input = {"subagent_type": "mission-worker", "model": ""}
        action, msg, modified = validate_model(
            tool_input, self._make_state(), self._make_config()
        )
        assert action == "inject"
        assert modified["model"] == "opus"

    def test_whitespace_model_inject(self):
        tool_input = {"subagent_type": "mission-worker", "model": "   "}
        action, msg, modified = validate_model(
            tool_input, self._make_state(), self._make_config()
        )
        assert action == "inject"
        assert modified["model"] == "opus"

    def test_non_dict_input(self):
        action, msg, modified = validate_model("not a dict", {}, {})
        assert action == "allow"


# ═══════════════════════════════════════════════════════════════════════════════
# get_current_feature
# ═══════════════════════════════════════════════════════════════════════════════


class TestGetCurrentFeature:
    """Tests for get_current_feature()."""

    def test_has_in_progress(self):
        features = {
            "features": [
                {"id": "f1", "status": "completed"},
                {"id": "f2", "status": "in-progress"},
                {"id": "f3", "status": "pending"},
            ]
        }
        result = get_current_feature(features)
        assert result["id"] == "f2"

    def test_no_in_progress(self):
        features = {
            "features": [
                {"id": "f1", "status": "completed"},
                {"id": "f2", "status": "pending"},
            ]
        }
        assert get_current_feature(features) is None

    def test_multiple_in_progress_first_wins(self):
        features = {
            "features": [
                {"id": "f1", "status": "in-progress"},
                {"id": "f2", "status": "in-progress"},
            ]
        }
        result = get_current_feature(features)
        assert result["id"] == "f1"

    def test_empty_features(self):
        assert get_current_feature({"features": []}) is None

    def test_non_dict_input(self):
        assert get_current_feature("bad") is None

    def test_missing_features_key(self):
        assert get_current_feature({"other": []}) is None


# ═══════════════════════════════════════════════════════════════════════════════
# get_next_feature
# ═══════════════════════════════════════════════════════════════════════════════


class TestGetNextFeature:
    """Tests for get_next_feature()."""

    def test_simple_pending_no_deps(self):
        features = {
            "features": [
                {"id": "f1", "status": "pending", "dependencies": []},
            ]
        }
        result = get_next_feature(features)
        assert result["id"] == "f1"

    def test_dependency_blocking(self):
        features = {
            "features": [
                {"id": "f1", "status": "pending", "dependencies": ["f0"]},
            ]
        }
        assert get_next_feature(features) is None

    def test_dependency_met(self):
        features = {
            "features": [
                {"id": "f1", "status": "completed"},
                {"id": "f2", "status": "pending", "dependencies": ["f1"]},
            ]
        }
        result = get_next_feature(features)
        assert result["id"] == "f2"

    def test_all_blocked(self):
        features = {
            "features": [
                {"id": "f1", "status": "pending", "dependencies": ["f0"]},
                {"id": "f2", "status": "pending", "dependencies": ["f1"]},
            ]
        }
        assert get_next_feature(features) is None

    def test_all_completed(self):
        features = {
            "features": [
                {"id": "f1", "status": "completed"},
                {"id": "f2", "status": "completed"},
            ]
        }
        assert get_next_feature(features) is None

    def test_skips_in_progress(self):
        features = {
            "features": [
                {"id": "f1", "status": "in-progress"},
                {"id": "f2", "status": "pending", "dependencies": []},
            ]
        }
        result = get_next_feature(features)
        assert result["id"] == "f2"

    def test_empty_features(self):
        assert get_next_feature({"features": []}) is None

    def test_non_dict_input(self):
        assert get_next_feature("bad") is None

    def test_multiple_deps_all_met(self):
        features = {
            "features": [
                {"id": "f1", "status": "completed"},
                {"id": "f2", "status": "completed"},
                {"id": "f3", "status": "pending", "dependencies": ["f1", "f2"]},
            ]
        }
        result = get_next_feature(features)
        assert result["id"] == "f3"

    def test_multiple_deps_partial_met(self):
        features = {
            "features": [
                {"id": "f1", "status": "completed"},
                {"id": "f2", "status": "pending", "dependencies": []},
                {"id": "f3", "status": "pending", "dependencies": ["f1", "f2"]},
            ]
        }
        result = get_next_feature(features)
        # f2 is pending (no deps) so it's returned; f3 is blocked because f2 not completed
        assert result["id"] == "f2"


# ═══════════════════════════════════════════════════════════════════════════════
# _deep_merge (internal helper, but critical to test)
# ═══════════════════════════════════════════════════════════════════════════════


class TestDeepMerge:
    """Tests for _deep_merge()."""

    def test_flat_merge(self):
        assert _deep_merge({"a": 1}, {"b": 2}) == {"a": 1, "b": 2}

    def test_override(self):
        assert _deep_merge({"a": 1}, {"a": 2}) == {"a": 2}

    def test_nested_merge(self):
        base = {"models": {"a": 1, "b": 2}}
        override = {"models": {"b": 3, "c": 4}}
        result = _deep_merge(base, override)
        assert result == {"models": {"a": 1, "b": 3, "c": 4}}

    def test_base_not_mutated(self):
        base = {"a": {"x": 1}}
        _deep_merge(base, {"a": {"y": 2}})
        assert base == {"a": {"x": 1}}


# ═══════════════════════════════════════════════════════════════════════════════
# validate_status_transition
# ═══════════════════════════════════════════════════════════════════════════════


class TestValidateStatusTransition:
    """Tests for validate_status_transition()."""

    # ── Valid transitions ─────────────────────────────────────────────────────

    @pytest.mark.parametrize(
        "old_status,new_status",
        [
            ("pending", "in-progress"),
            ("in-progress", "completed"),
            ("in-progress", "failed"),
        ],
    )
    def test_valid_transitions(self, old_status, new_status):
        assert validate_status_transition(old_status, new_status) is True

    # ── Invalid transitions ───────────────────────────────────────────────────

    @pytest.mark.parametrize(
        "old_status,new_status",
        [
            ("pending", "completed"),    # Can't skip in-progress
            ("pending", "failed"),       # Can't fail before starting
            ("completed", "in-progress"),  # Can't go back
            ("completed", "pending"),    # Can't go back
            ("completed", "failed"),     # Can't fail after completing
            ("failed", "in-progress"),   # Can't restart failed
            ("failed", "pending"),       # Can't go back
            ("failed", "completed"),     # Can't complete after failing
        ],
    )
    def test_invalid_transitions(self, old_status, new_status):
        assert validate_status_transition(old_status, new_status) is False

    # ── Edge cases ────────────────────────────────────────────────────────────

    def test_same_status_is_invalid(self):
        """Transitioning to same status is not valid."""
        assert validate_status_transition("pending", "pending") is False
        assert validate_status_transition("in-progress", "in-progress") is False
        assert validate_status_transition("completed", "completed") is False
        assert validate_status_transition("failed", "failed") is False

    def test_unknown_old_status(self):
        assert validate_status_transition("unknown", "in-progress") is False

    def test_unknown_new_status(self):
        assert validate_status_transition("pending", "unknown") is False

    def test_empty_string_status(self):
        assert validate_status_transition("", "in-progress") is False
        assert validate_status_transition("pending", "") is False

    def test_none_status(self):
        assert validate_status_transition(None, "in-progress") is False
        assert validate_status_transition("pending", None) is False

    def test_non_string_status(self):
        assert validate_status_transition(123, "in-progress") is False
        assert validate_status_transition("pending", 456) is False


# ═══════════════════════════════════════════════════════════════════════════════
# load_features — additional edge cases
# ═══════════════════════════════════════════════════════════════════════════════


class TestLoadFeaturesEdgeCases:
    """Additional edge-case tests for load_features()."""

    def test_missing_optional_fields(self, tmp_path):
        """Features with missing assignee, dependencies, handoff don't crash."""
        features = {
            "features": [
                {
                    "id": "f1",
                    "description": "Minimal feature",
                    "status": "pending",
                }
            ]
        }
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps(features))
        result = load_features(str(ff))
        assert len(result["features"]) == 1
        f = result["features"][0]
        assert f["id"] == "f1"
        # Missing keys should just be absent, not error
        assert f.get("assignee") is None
        assert f.get("dependencies") is None
        assert f.get("handoff") is None

    def test_null_optional_fields(self, tmp_path):
        """Features with null assignee, dependencies, handoff handled."""
        features = {
            "features": [
                {
                    "id": "f1",
                    "description": "Feature",
                    "status": "pending",
                    "assignee": None,
                    "dependencies": [],
                    "handoff": None,
                }
            ]
        }
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps(features))
        result = load_features(str(ff))
        assert len(result["features"]) == 1
        assert result["features"][0]["assignee"] is None
        assert result["features"][0]["dependencies"] == []
        assert result["features"][0]["handoff"] is None

    def test_partial_write_truncated(self, tmp_path):
        """Truncated JSON (partial write) returns empty features."""
        ff = tmp_path / "features.json"
        ff.write_text('{"features": [{"id": "f1", "stat')  # truncated
        result = load_features(str(ff))
        assert result == {"features": []}

    def test_duplicate_ids_first_wins_get_current(self, tmp_path):
        """Duplicate IDs: get_current_feature returns first occurrence."""
        features = {
            "features": [
                {"id": "dup", "description": "First", "status": "in-progress"},
                {"id": "dup", "description": "Second", "status": "in-progress"},
            ]
        }
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps(features))
        data = load_features(str(ff))
        result = get_current_feature(data)
        assert result["description"] == "First"

    def test_duplicate_ids_first_wins_get_next(self, tmp_path):
        """Duplicate pending IDs: get_next_feature returns first occurrence."""
        features = {
            "features": [
                {"id": "dup", "description": "First", "status": "pending", "dependencies": []},
                {"id": "dup", "description": "Second", "status": "pending", "dependencies": []},
            ]
        }
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps(features))
        data = load_features(str(ff))
        result = get_next_feature(data)
        assert result["description"] == "First"

    def test_features_not_list(self, tmp_path):
        """features key is not a list → treated as empty."""
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps({"features": "not a list"}))
        data = load_features(str(ff))
        assert get_current_feature(data) is None
        assert get_next_feature(data) is None

    def test_non_dict_feature_entries(self, tmp_path):
        """Non-dict entries in features list are skipped gracefully."""
        features = {
            "features": [
                "not a dict",
                42,
                None,
                {"id": "real", "status": "in-progress"},
            ]
        }
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps(features))
        data = load_features(str(ff))
        result = get_current_feature(data)
        assert result["id"] == "real"

    def test_large_features_list_performance(self, tmp_path):
        """50 features should parse in under 50ms."""
        import time

        features = {
            "features": [
                {
                    "id": f"feature-{i}",
                    "description": f"Feature number {i}",
                    "status": "pending" if i > 1 else "completed",
                    "dependencies": [f"feature-{i - 1}"] if i > 1 else [],
                    "assignee": f"worker-{i % 3}",
                    "handoff": None,
                }
                for i in range(50)
            ]
        }
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps(features))

        start = time.perf_counter()
        data = load_features(str(ff))
        current = get_current_feature(data)
        next_f = get_next_feature(data)
        elapsed_ms = (time.perf_counter() - start) * 1000

        assert elapsed_ms < 50, f"Features parsing took {elapsed_ms:.1f}ms (> 50ms)"
        # feature-0 and feature-1 are completed (i <= 1)
        # feature-2 is pending with dep on feature-1 (completed), so it's next
        assert next_f["id"] == "feature-2"
        assert current is None  # no in-progress feature

    def test_all_completed_returns_none(self, tmp_path):
        """All features completed → no current, no next."""
        features = {
            "features": [
                {"id": "f1", "status": "completed"},
                {"id": "f2", "status": "completed"},
                {"id": "f3", "status": "completed"},
            ]
        }
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps(features))
        data = load_features(str(ff))
        assert get_current_feature(data) is None
        assert get_next_feature(data) is None

    def test_failed_feature_skipped_by_next(self, tmp_path):
        """Failed features are skipped by get_next_feature()."""
        features = {
            "features": [
                {"id": "f1", "status": "failed"},
                {"id": "f2", "status": "pending", "dependencies": []},
            ]
        }
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps(features))
        data = load_features(str(ff))
        result = get_next_feature(data)
        assert result["id"] == "f2"

    def test_dependency_on_failed_feature_blocks(self, tmp_path):
        """Feature depending on a failed feature is blocked (not completed)."""
        features = {
            "features": [
                {"id": "f1", "status": "failed"},
                {"id": "f2", "status": "pending", "dependencies": ["f1"]},
            ]
        }
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps(features))
        data = load_features(str(ff))
        result = get_next_feature(data)
        # f2 is blocked because f1 is failed (not completed)
        assert result is None

    def test_full_schema_round_trip(self, tmp_path):
        """All schema fields preserved through load."""
        features = {
            "features": [
                {
                    "id": "f1",
                    "description": "Auth module",
                    "assignee": "worker-1",
                    "status": "in-progress",
                    "dependencies": [],
                    "handoff": {"summary": "WIP", "filesChanged": ["auth.py"]},
                }
            ]
        }
        ff = tmp_path / "features.json"
        ff.write_text(json.dumps(features))
        data = load_features(str(ff))
        f = data["features"][0]
        assert f["id"] == "f1"
        assert f["assignee"] == "worker-1"
        assert f["handoff"]["summary"] == "WIP"
        assert f["handoff"]["filesChanged"] == ["auth.py"]

    def test_load_features_with_find_state(self, tmp_path, monkeypatch):
        """load_features(None) uses find_state_file() to locate features."""
        mission_dir = tmp_path / ".mission"
        mission_dir.mkdir()
        sf = mission_dir / "state.json"
        sf.write_text(json.dumps({"active": True, "phase": "worker"}))
        ff = mission_dir / "features.json"
        ff.write_text(json.dumps({"features": [{"id": "auto", "status": "pending"}]}))
        monkeypatch.chdir(tmp_path)
        result = load_features(None)
        assert len(result["features"]) == 1
        assert result["features"][0]["id"] == "auto"

    def test_load_features_none_no_state(self, tmp_path, monkeypatch):
        """load_features(None) with no state file returns empty."""
        monkeypatch.chdir(tmp_path)
        result = load_features(None)
        assert result == {"features": []}
