# Mission Plugin Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Claude Code plugin with 3-role orchestration (Orchestrator, Worker, Validator) and hard enforcement via PreToolUse hooks.

**Architecture:** Pure markdown plugin (skills, agents, commands) with one bash script (`phase-guard.sh`) for hook enforcement. No Node.js runtime. State managed via JSON files. Global config at `~/.mission/config.json`, per-project state at `.mission/state.json`.

**Tech Stack:** Bash (hooks), Markdown + YAML frontmatter (agents/skills/commands), JSON (config/state)

**Spec:** `docs/superpowers/specs/2026-03-28-mission-plugin-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `.claude-plugin/plugin.json` | Create | Plugin manifest |
| `.claude-plugin/marketplace.json` | Create | Marketplace registry |
| `package.json` | Create | Version metadata |
| `hooks/hooks.json` | Create | Hook registration for PreToolUse |
| `hooks/phase-guard.sh` | Create | **Core** — bash enforcement script |
| `tests/phase-guard.test.sh` | Create | Tests for phase-guard.sh |
| `agents/orchestrator.md` | Create | Orchestrator role prompt |
| `agents/worker.md` | Create | Worker role prompt |
| `agents/validator.md` | Create | Validator role prompt |
| `skills/enter-mission/SKILL.md` | Create | Main skill — transforms session into Orchestrator |
| `commands/enter-mission.md` | Create | /enter-mission command |
| `commands/exit-mission.md` | Create | /exit-mission command |
| `commands/mission-config.md` | Create | /mission-config command |
| `commands/mission-status.md` | Create | /mission-status command |
| `CLAUDE.md` | Create | Plugin-level guidance |
| `AGENTS.md` | Create | Agent catalog |
| `README.md` | Create | Plugin documentation |

---

## Chunk 1: Plugin Scaffold

### Task 1: Plugin Manifest Files

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `package.json`

- [ ] **Step 1: Create `.claude-plugin/plugin.json`**

```json
{
  "name": "mission",
  "version": "0.1.0",
  "description": "Strict 3-role orchestration plugin for Claude Code — Orchestrator plans, Workers code, Validators verify. Hard enforcement via hooks.",
  "author": {
    "name": "Paul"
  },
  "license": "MIT",
  "keywords": ["claude-code", "orchestration", "mission", "agents", "hooks", "tdd"],
  "agents": [
    "./agents/orchestrator.md",
    "./agents/worker.md",
    "./agents/validator.md"
  ],
  "commands": ["./commands/"],
  "skills": ["./skills/"]
}
```

- [ ] **Step 2: Create `.claude-plugin/marketplace.json`**

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "mission",
  "description": "Strict 3-role orchestration plugin — Orchestrator, Worker, Validator with hard hook enforcement",
  "owner": {
    "name": "Paul"
  },
  "plugins": [
    {
      "name": "mission",
      "source": "./",
      "description": "3-role orchestration with strict isolation and PreToolUse hooks enforcement",
      "version": "0.1.0",
      "category": "workflow",
      "tags": ["orchestration", "agents", "hooks", "tdd", "validation"],
      "license": "MIT"
    }
  ]
}
```

- [ ] **Step 3: Create `package.json`**

```json
{
  "name": "mission-plugin",
  "version": "0.1.0",
  "description": "Mission — strict 3-role orchestration plugin for Claude Code",
  "license": "MIT",
  "private": true
}
```

- [ ] **Step 4: Commit scaffold**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json package.json
git commit -m "chore: add plugin manifest and package.json"
```

---

### Task 2: Plugin Documentation Files

**Files:**
- Create: `CLAUDE.md`
- Create: `AGENTS.md`
- Create: `README.md`

- [ ] **Step 1: Create `CLAUDE.md`**

```markdown
# Mission Plugin

This plugin provides strict 3-role orchestration for Claude Code sessions.

## Commands

- `/enter-mission [task]` — Enter Mission Mode
- `/exit-mission` — Leave Mission Mode
- `/mission-config` — View/set model defaults
- `/mission-status` — View current mission progress

## Roles

- **Orchestrator** — Plans, delegates, reviews. NEVER writes code.
- **Worker** — Implements code. NEVER plans or validates.
- **Validator** — Verifies, tests, reviews. NEVER writes production code.

## Enforcement

Roles are enforced via PreToolUse hooks. The hook script `hooks/phase-guard.sh` reads `.mission/state.json` and blocks forbidden tool calls per phase.

## Config

Global config: `~/.mission/config.json`
Per-project state: `.mission/state.json`
```

- [ ] **Step 2: Create `AGENTS.md`**

```markdown
# Mission Agents

## mission-orchestrator

Plans, delegates, and reviews. Spawns Workers and Validators via the Agent tool. Cannot write or edit any file outside `.mission/`. Enforced by hooks.

**Model:** Configurable (default: opus)
**Tools:** Read, Grep, Glob, Bash, Agent, Write/Edit (`.mission/*` only)

## mission-worker

Implements code as specified by the Orchestrator. Must read all relevant files before writing. Cannot run tests, spawn Validators, or modify `.mission/state.json`.

**Model:** Configurable (default: opus)
**Tools:** Read, Grep, Glob, Bash (no test commands), Write, Edit, Agent (sub-workers only)

## mission-validator

Verifies all Worker output. MUST create test cases for every function regardless of size. Cannot modify source files — only test files and `.mission/reports/*`. Cannot spawn Workers.

**Model:** Configurable (default: opus)
**Tools:** Read, Grep, Glob, Bash, Write/Edit (test files and reports only), Agent (sub-validators only)
```

- [ ] **Step 3: Create `README.md`**

```markdown
# Mission Plugin for Claude Code

A strict 3-role orchestration system with hard enforcement via PreToolUse hooks.

## Install

```bash
claude plugins add /path/to/mission
```

## Quick Start

```
/enter-mission Build a REST API for todo app
```

## Configuration

```
/mission-config orchestrator=opus worker=sonnet validator=opus
```

## How It Works

1. `/enter-mission` activates Mission Mode
2. **Orchestrator** reads codebase, creates plan, dispatches Workers
3. **Workers** implement code (parallel if independent)
4. **Validator** writes tests for ALL functions, runs all checks, generates report
5. If issues found → Orchestrator dispatches Workers to fix → Validator re-verifies
6. Loop until 100% pass → Orchestrator cleans up

Roles are strictly isolated. Only one role type active at a time. Hooks enforce boundaries at the tool-call level.
```

- [ ] **Step 4: Commit docs**

```bash
git add CLAUDE.md AGENTS.md README.md
git commit -m "docs: add CLAUDE.md, AGENTS.md, and README.md"
```

---

## Chunk 2: Phase Guard Hook (Core)

This is the most critical piece — the bash script that enforces role isolation.

### Task 3: Write Phase Guard Tests

**Files:**
- Create: `tests/phase-guard.test.sh`

- [ ] **Step 1: Create test harness**

```bash
#!/usr/bin/env bash
# tests/phase-guard.test.sh — Tests for hooks/phase-guard.sh
# Run: bash tests/phase-guard.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD_SCRIPT="$PROJECT_DIR/hooks/phase-guard.sh"
TEST_DIR=$(mktemp -d)
PASSED=0
FAILED=0
TOTAL=0

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Helper: create .mission/state.json in test dir
create_state() {
  local phase="$1"
  local active="${2:-true}"
  mkdir -p "$TEST_DIR/.mission"
  cat > "$TEST_DIR/.mission/state.json" <<STATEEOF
{
  "active": $active,
  "phase": "$phase",
  "task": "test task",
  "round": 1
}
STATEEOF
}

# Helper: run phase-guard and capture exit code + output
run_guard() {
  local tool_name="$1"
  local tool_input="$2"
  local output
  local exit_code
  output=$(cd "$TEST_DIR" && TOOL_NAME="$tool_name" TOOL_INPUT="$tool_input" bash "$GUARD_SCRIPT" "$tool_name" "$tool_input" 2>&1) || exit_code=$?
  exit_code=${exit_code:-0}
  echo "$output"
  return $exit_code
}

assert_blocked() {
  local desc="$1"
  shift
  TOTAL=$((TOTAL + 1))
  local output
  if output=$(run_guard "$@" 2>&1); then
    echo "FAIL: $desc — expected BLOCK but got ALLOW"
    echo "  output: $output"
    FAILED=$((FAILED + 1))
  else
    if echo "$output" | grep -q "BLOCK"; then
      echo "PASS: $desc"
      PASSED=$((PASSED + 1))
    else
      echo "FAIL: $desc — exit non-zero but no BLOCK message"
      echo "  output: $output"
      FAILED=$((FAILED + 1))
    fi
  fi
}

assert_allowed() {
  local desc="$1"
  shift
  TOTAL=$((TOTAL + 1))
  local output
  if output=$(run_guard "$@" 2>&1); then
    echo "PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc — expected ALLOW but got BLOCK"
    echo "  output: $output"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== Phase Guard Tests ==="
echo ""

# ─────────────────────────────────────────────
# TEST GROUP: No mission active
# ─────────────────────────────────────────────
echo "--- No mission active ---"

rm -rf "$TEST_DIR/.mission"
assert_allowed "No state file → Write allowed" "Write" '{"file_path":"/tmp/foo.ts"}'
assert_allowed "No state file → Edit allowed" "Edit" '{"file_path":"/tmp/foo.ts"}'
assert_allowed "No state file → Bash allowed" "Bash" '{"command":"npm test"}'
assert_allowed "No state file → Agent allowed" "Agent" '{"subagent_type":"validator"}'

create_state "orchestrator" "false"
assert_allowed "active=false → Write allowed" "Write" '{"file_path":"/tmp/foo.ts"}'

# ─────────────────────────────────────────────
# TEST GROUP: Orchestrator phase
# ─────────────────────────────────────────────
echo ""
echo "--- Orchestrator phase ---"

create_state "orchestrator"
assert_allowed "Orch: Write to .mission/plan.md" "Write" '{"file_path":".mission/plan.md"}'
assert_allowed "Orch: Write to .mission/state.json" "Write" '{"file_path":".mission/state.json"}'
assert_blocked "Orch: Write to src/index.ts" "Write" '{"file_path":"src/index.ts"}'
assert_blocked "Orch: Write to app.py" "Write" '{"file_path":"app.py"}'
assert_allowed "Orch: Edit .mission/plan.md" "Edit" '{"file_path":".mission/plan.md"}'
assert_blocked "Orch: Edit src/index.ts" "Edit" '{"file_path":"src/index.ts"}'
assert_allowed "Orch: Bash git log" "Bash" '{"command":"git log --oneline -10"}'
assert_allowed "Orch: Bash ls" "Bash" '{"command":"ls -la"}'
assert_allowed "Orch: Agent worker" "Agent" '{"subagent_type":"mission-worker"}'
assert_allowed "Orch: Agent validator" "Agent" '{"subagent_type":"mission-validator"}'
assert_allowed "Orch: Agent explore" "Agent" '{"subagent_type":"Explore"}'

# ─────────────────────────────────────────────
# TEST GROUP: Worker phase
# ─────────────────────────────────────────────
echo ""
echo "--- Worker phase ---"

create_state "worker"
assert_allowed "Worker: Write src/index.ts" "Write" '{"file_path":"src/index.ts"}'
assert_allowed "Worker: Write new file" "Write" '{"file_path":"src/routes/api.ts"}'
assert_blocked "Worker: Write .mission/state.json" "Write" '{"file_path":".mission/state.json"}'
assert_allowed "Worker: Write .mission/worker-logs/worker-1.md" "Write" '{"file_path":".mission/worker-logs/worker-1.md"}'
assert_allowed "Worker: Edit src/index.ts" "Edit" '{"file_path":"src/index.ts"}'
assert_blocked "Worker: Edit .mission/state.json" "Edit" '{"file_path":".mission/state.json"}'
assert_blocked "Worker: Bash npm test" "Bash" '{"command":"npm test"}'
assert_blocked "Worker: Bash npx jest" "Bash" '{"command":"npx jest --coverage"}'
assert_blocked "Worker: Bash pytest" "Bash" '{"command":"pytest tests/"}'
assert_blocked "Worker: Bash go test" "Bash" '{"command":"go test ./..."}'
assert_blocked "Worker: Bash cargo test" "Bash" '{"command":"cargo test"}'
assert_blocked "Worker: Bash make test" "Bash" '{"command":"make test"}'
assert_blocked "Worker: Bash python -m pytest" "Bash" '{"command":"python -m pytest"}'
assert_blocked "Worker: Bash npx vitest" "Bash" '{"command":"npx vitest run"}'
assert_blocked "Worker: Bash yarn test" "Bash" '{"command":"yarn test"}'
assert_blocked "Worker: Bash pnpm test" "Bash" '{"command":"pnpm test"}'
assert_blocked "Worker: Bash bundle exec rspec" "Bash" '{"command":"bundle exec rspec"}'
assert_blocked "Worker: Bash phpunit" "Bash" '{"command":"phpunit tests/"}'
assert_blocked "Worker: Bash gradle test" "Bash" '{"command":"gradle test"}'
assert_blocked "Worker: Bash mvn test" "Bash" '{"command":"mvn test"}'
assert_allowed "Worker: Bash npm install" "Bash" '{"command":"npm install express"}'
assert_allowed "Worker: Bash npm run build" "Bash" '{"command":"npm run build"}'
assert_allowed "Worker: Bash mkdir test-fixtures" "Bash" '{"command":"mkdir test-fixtures"}'
assert_allowed "Worker: Bash tsc" "Bash" '{"command":"tsc --noEmit"}'
assert_blocked "Worker: Agent validator" "Agent" '{"subagent_type":"mission-validator"}'
assert_allowed "Worker: Agent sub-worker" "Agent" '{"subagent_type":"mission-worker"}'
assert_allowed "Worker: Agent explore" "Agent" '{"subagent_type":"Explore"}'

# ─────────────────────────────────────────────
# TEST GROUP: Validator phase
# ─────────────────────────────────────────────
echo ""
echo "--- Validator phase ---"

create_state "validator"
assert_allowed "Validator: Write src/index.test.ts" "Write" '{"file_path":"src/index.test.ts"}'
assert_allowed "Validator: Write src/app.spec.ts" "Write" '{"file_path":"src/app.spec.ts"}'
assert_allowed "Validator: Write tests/test_main.py" "Write" '{"file_path":"tests/test_main.py"}'
assert_allowed "Validator: Write main_test.go" "Write" '{"file_path":"main_test.go"}'
assert_allowed "Validator: Write __tests__/app.js" "Write" '{"file_path":"__tests__/app.js"}'
assert_allowed "Validator: Write .mission/reports/round-1.md" "Write" '{"file_path":".mission/reports/round-1.md"}'
assert_blocked "Validator: Write src/index.ts" "Write" '{"file_path":"src/index.ts"}'
assert_blocked "Validator: Write app.py" "Write" '{"file_path":"app.py"}'
assert_blocked "Validator: Write main.go" "Write" '{"file_path":"main.go"}'
assert_allowed "Validator: Edit src/index.test.ts" "Edit" '{"file_path":"src/index.test.ts"}'
assert_allowed "Validator: Edit src/app.spec.ts" "Edit" '{"file_path":"src/app.spec.ts"}'
assert_blocked "Validator: Edit src/index.ts" "Edit" '{"file_path":"src/index.ts"}'
assert_allowed "Validator: Bash npm test" "Bash" '{"command":"npm test"}'
assert_allowed "Validator: Bash npx jest" "Bash" '{"command":"npx jest --coverage"}'
assert_allowed "Validator: Bash tsc" "Bash" '{"command":"tsc --noEmit"}'
assert_blocked "Validator: Agent worker" "Agent" '{"subagent_type":"mission-worker"}'
assert_allowed "Validator: Agent sub-validator" "Agent" '{"subagent_type":"mission-validator"}'
assert_allowed "Validator: Agent explore" "Agent" '{"subagent_type":"Explore"}'

# ─────────────────────────────────────────────
# TEST GROUP: Edge cases
# ─────────────────────────────────────────────
echo ""
echo "--- Edge cases ---"

create_state "orchestrator"
assert_allowed "Orch: Write .mission/summary.md" "Write" '{"file_path":".mission/summary.md"}'
assert_blocked "Orch: Write .mission-fake/hack.ts" "Write" '{"file_path":".mission-fake/hack.ts"}'

create_state "worker"
assert_allowed "Worker: Write to path with test in dir name" "Write" '{"file_path":"test-fixtures/data.json"}'
assert_blocked "Worker: Bash npx jest (with args)" "Bash" '{"command":"npx jest --watchAll"}'

create_state "validator"
assert_allowed "Validator: Write nested test file" "Write" '{"file_path":"src/utils/__tests__/helper.test.ts"}'
assert_allowed "Validator: Write _spec.rb file" "Write" '{"file_path":"spec/models/user_spec.rb"}'
assert_blocked "Validator: Write package.json" "Write" '{"file_path":"package.json"}'

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo "=== Results ==="
echo "PASSED: $PASSED / $TOTAL"
echo "FAILED: $FAILED / $TOTAL"

if [ "$FAILED" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
```

- [ ] **Step 2: Run tests — verify they fail (RED)**

```bash
chmod +x tests/phase-guard.test.sh
bash tests/phase-guard.test.sh
```

Expected: FAIL — `hooks/phase-guard.sh` does not exist yet.

- [ ] **Step 3: Commit test file**

```bash
git add tests/phase-guard.test.sh
git commit -m "test: add phase-guard.sh test suite (RED — script not yet implemented)"
```

---

### Task 4: Implement Phase Guard Script

**Files:**
- Create: `hooks/phase-guard.sh`

- [ ] **Step 1: Write `hooks/phase-guard.sh`**

```bash
#!/usr/bin/env bash
# hooks/phase-guard.sh — Mission plugin PreToolUse enforcement
#
# Called by hooks.json for Write, Edit, Agent, and Bash tool calls.
# Reads .mission/state.json to determine current phase and blocks
# forbidden actions.
#
# Arguments: $1 = tool name, $2 = tool input (JSON)
# Exit 0 = ALLOW, Exit 1 with "BLOCK" message = DENY

set -euo pipefail

TOOL_NAME="${1:-}"
TOOL_INPUT="${2:-}"

# ─── Find .mission/state.json ───
# Search from current directory upward (handles subagents in subdirs)
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

# No state file → not in mission mode → allow everything
if [ -z "$STATE_FILE" ]; then
  exit 0
fi

MISSION_DIR=$(dirname "$STATE_FILE")

# Read state
ACTIVE=$(python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(str(d.get('active',False)).lower())" 2>/dev/null || echo "false")
PHASE=$(python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('phase',''))" 2>/dev/null || echo "")

# Not active → allow everything
if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

# No phase set → allow (shouldn't happen but safe default)
if [ -z "$PHASE" ]; then
  exit 0
fi

# ─── Extract file_path from tool input ───
extract_file_path() {
  python3 -c "
import json,sys
try:
  d = json.loads(sys.argv[1])
  print(d.get('file_path',''))
except:
  print('')
" "$1" 2>/dev/null || echo ""
}

# ─── Extract command from Bash tool input ───
extract_command() {
  python3 -c "
import json,sys
try:
  d = json.loads(sys.argv[1])
  print(d.get('command',''))
except:
  print('')
" "$1" 2>/dev/null || echo ""
}

# ─── Extract subagent_type from Agent tool input ───
extract_subagent_type() {
  python3 -c "
import json,sys
try:
  d = json.loads(sys.argv[1])
  print(d.get('subagent_type',''))
except:
  print('')
" "$1" 2>/dev/null || echo ""
}

# ─── Check if path is under .mission/ ───
is_mission_path() {
  local filepath="$1"
  case "$filepath" in
    .mission/*|*/.mission/*) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── Check if path is .mission/state.json ───
is_state_json() {
  local filepath="$1"
  case "$filepath" in
    .mission/state.json|*/.mission/state.json) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── Check if path is .mission/worker-logs/* ───
is_worker_log() {
  local filepath="$1"
  case "$filepath" in
    .mission/worker-logs/*|*/.mission/worker-logs/*) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── Check if path is a test file ───
is_test_file() {
  local filepath="$1"
  local basename
  basename=$(basename "$filepath")

  # Match *.test.*, *.spec.*, *_test.*, *_spec.*
  case "$basename" in
    *.test.*|*.spec.*|*_test.*|*_spec.*) return 0 ;;
  esac

  # Match __tests__/* anywhere in path
  case "$filepath" in
    *__tests__/*|*/__tests__/*) return 0 ;;
  esac

  # Match .mission/reports/*
  case "$filepath" in
    .mission/reports/*|*/.mission/reports/*) return 0 ;;
  esac

  return 1
}

# ─── Check if bash command is a test runner ───
is_test_command() {
  local cmd="$1"
  # Strip leading whitespace
  cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//')

  case "$cmd" in
    "npm test"*) return 0 ;;
    "npx jest"*) return 0 ;;
    "npx vitest"*) return 0 ;;
    "npx mocha"*) return 0 ;;
    "yarn test"*) return 0 ;;
    "pnpm test"*) return 0 ;;
    "pytest"*) return 0 ;;
    "python -m pytest"*) return 0 ;;
    "python3 -m pytest"*) return 0 ;;
    "go test"*) return 0 ;;
    "cargo test"*) return 0 ;;
    "make test"*) return 0 ;;
    "gradle test"*) return 0 ;;
    "mvn test"*) return 0 ;;
    "bundle exec rspec"*) return 0 ;;
    "phpunit"*) return 0 ;;
  esac

  return 1
}

# ─── Check if agent is a worker type ───
is_worker_agent() {
  local agent_type="$1"
  case "$agent_type" in
    *worker*|*Worker*|*mission-worker*) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── Check if agent is a validator type ───
is_validator_agent() {
  local agent_type="$1"
  case "$agent_type" in
    *validator*|*Validator*|*mission-validator*) return 0 ;;
    *) return 1 ;;
  esac
}

block() {
  echo "BLOCK: [MISSION GUARD] Phase \"$PHASE\" — $1" >&2
  exit 1
}

# ═══════════════════════════════════════════════
# PHASE ENFORCEMENT
# ═══════════════════════════════════════════════

case "$PHASE" in

  # ─── ORCHESTRATOR PHASE ───
  orchestrator)
    case "$TOOL_NAME" in
      Write|Edit)
        filepath=$(extract_file_path "$TOOL_INPUT")
        if [ -n "$filepath" ] && is_mission_path "$filepath"; then
          exit 0  # Orchestrator can write to .mission/*
        fi
        block "Orchestrator cannot write/edit source files. Use Agent tool to dispatch Workers."
        ;;
      Bash)
        exit 0  # Orchestrator can run any bash command (read-only intent enforced by prompt)
        ;;
      Agent)
        exit 0  # Orchestrator can spawn any agent
        ;;
      *)
        exit 0
        ;;
    esac
    ;;

  # ─── WORKER PHASE ───
  worker)
    case "$TOOL_NAME" in
      Write|Edit)
        filepath=$(extract_file_path "$TOOL_INPUT")
        if [ -n "$filepath" ] && is_state_json "$filepath"; then
          block "Workers cannot modify .mission/state.json. Only the Orchestrator manages mission state."
        fi
        exit 0  # Workers can write/edit everything else
        ;;
      Bash)
        cmd=$(extract_command "$TOOL_INPUT")
        if [ -n "$cmd" ] && is_test_command "$cmd"; then
          block "Workers cannot run tests. That is the Validator's job. Command: $cmd"
        fi
        exit 0  # Workers can run non-test bash commands
        ;;
      Agent)
        agent_type=$(extract_subagent_type "$TOOL_INPUT")
        if [ -n "$agent_type" ] && is_validator_agent "$agent_type"; then
          block "Workers cannot spawn Validators. Only the Orchestrator dispatches Validators."
        fi
        exit 0  # Workers can spawn sub-workers and other agents
        ;;
      *)
        exit 0
        ;;
    esac
    ;;

  # ─── VALIDATOR PHASE ───
  validator)
    case "$TOOL_NAME" in
      Write|Edit)
        filepath=$(extract_file_path "$TOOL_INPUT")
        if [ -n "$filepath" ] && (is_test_file "$filepath" || is_mission_path "$filepath"); then
          exit 0  # Validators can write test files and .mission/reports/*
        fi
        block "Validators can only write test files (*.test.*, *.spec.*, *_test.*, *_spec.*, __tests__/*) and .mission/reports/*. Blocked: $filepath"
        ;;
      Bash)
        exit 0  # Validators can run any bash (tests, build, lint, etc.)
        ;;
      Agent)
        agent_type=$(extract_subagent_type "$TOOL_INPUT")
        if [ -n "$agent_type" ] && is_worker_agent "$agent_type"; then
          block "Validators cannot spawn Workers. Only the Orchestrator dispatches Workers."
        fi
        exit 0  # Validators can spawn sub-validators and other agents
        ;;
      *)
        exit 0
        ;;
    esac
    ;;

  # ─── UNKNOWN PHASE → allow (safe default) ───
  *)
    exit 0
    ;;
esac
```

- [ ] **Step 2: Make executable**

```bash
chmod +x hooks/phase-guard.sh
```

- [ ] **Step 3: Run tests — verify they pass (GREEN)**

```bash
bash tests/phase-guard.test.sh
```

Expected: ALL TESTS PASSED

- [ ] **Step 4: Commit**

```bash
git add hooks/phase-guard.sh tests/phase-guard.test.sh
git commit -m "feat: implement phase-guard.sh with full test suite

Core enforcement script for Mission plugin. Reads .mission/state.json
and blocks forbidden tool calls per phase:
- Orchestrator: can only write to .mission/*
- Worker: cannot run tests or modify state.json
- Validator: can only write test files and reports"
```

---

### Task 5: Hook Registration

**Files:**
- Create: `hooks/hooks.json`

- [ ] **Step 1: Create `hooks/hooks.json`**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Agent|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/phase-guard.sh\" \"$TOOL_NAME\" \"$TOOL_INPUT\""
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: add hooks.json for PreToolUse phase enforcement"
```

---

## Chunk 3: Agent Definitions

### Task 6: Orchestrator Agent

**Files:**
- Create: `agents/orchestrator.md`

- [ ] **Step 1: Create `agents/orchestrator.md`**

The full agent prompt with YAML frontmatter, role declaration, mandatory read checklist, phase flow instructions, agent dispatch templates, state management, completion gate, and user intervention handling. Content sourced from spec Section 4.1, Section 7, Section 9, Section 10, and Section 13.

```markdown
---
name: mission-orchestrator
description: "Mission Orchestrator — plan, delegate, review. NEVER writes code. Used as a reference for the main session when in Orchestrator phase."
model: claude-opus-4-6
---

# Mission Orchestrator

You are the Mission Orchestrator. Your ONLY job is to plan, delegate, and review. You are FORBIDDEN from writing any source code.

## Absolute Rules

1. You MUST NOT use Write or Edit on any file outside `.mission/`. Hooks will block you if you try.
2. You MUST read the codebase thoroughly before creating a plan.
3. You MUST remain blocked on Agent calls while Workers/Validators are executing — do not produce output or take actions until they return.
4. You MUST NOT clean up the mission until the completion checklist is 100% satisfied.
5. You MUST force incomplete roles to finish before declaring the mission complete.

## Mandatory Read Checklist

BEFORE PLANNING — complete ALL reads:
- [ ] README, CLAUDE.md, project config (package.json/go.mod/pyproject.toml)
- [ ] Directory structure via Glob
- [ ] 5-10 most important source files
- [ ] Existing test files
- [ ] Git log (20 recent commits)
- [ ] CI config (.github/workflows, Makefile)
- [ ] Discover validator commands (build, test, lint, typecheck)

## Phase Flow

### Phase 1: Plan
1. Complete the Mandatory Read Checklist above
2. Analyze the task and map it onto the codebase
3. Create a detailed plan with sub-tasks for Workers
4. Write the plan to `.mission/plan.md`
5. Update `.mission/state.json`: set phase to "worker"

### Phase 2: Dispatch Workers
1. For each sub-task, spawn a Worker agent via the Agent tool
2. Use `subagent_type: "mission-worker"` and `model` from config
3. Include in the prompt: the specific task, relevant file paths, project conventions, and a reminder to read `.mission/plan.md`
4. For independent tasks: issue multiple Agent calls in a single message (parallel execution)
5. For dependent tasks: issue Agent calls sequentially
6. Wait for all Agent calls to return (you are blocked during this time)

### Phase 3: Dispatch Validators
1. After all Workers return, update `.mission/state.json`: set phase to "validator"
2. Spawn Validator agent(s) via Agent tool with `subagent_type: "mission-validator"`
3. Include in the prompt: the plan, worker logs paths, and list of all files created/modified
4. Wait for Validator to return

### Phase 4: Review & Loop
1. Read `.mission/reports/round-N.md`
2. If ALL PASS → proceed to Completion
3. If issues found:
   a. Increment round counter in state.json
   b. Create fix tasks from the Validator report
   c. Update state.json: set phase to "worker"
   d. Dispatch Workers to fix (only the specific issues, no new features)
   e. After Workers return → dispatch Validator again
   f. Repeat until ALL PASS

### Safety Net
- If round exceeds maxRounds → stop and report to user
- If the same issue repeats for 3 rounds → escalate to user
- If user sends a message → handle it (adjust plan, add requirements, change direction)

## Completion Gate

ALL must be TRUE before cleanup:
- [ ] Latest Validator report: PASS (0 issues)
- [ ] All tests pass
- [ ] Build/compile pass
- [ ] Type check pass
- [ ] Lint pass
- [ ] Every Worker sub-task status = "completed"
- [ ] No issue of any severity remaining

## Cleanup

Only when the completion gate is fully satisfied:
1. Output: "All checks passed. Cleaning up mission."
2. Generate `.mission/summary.md`
3. Set state.json: active=false, completedAt=timestamp
4. Remove `.mission/worker-logs/*.md`
5. Remove intermediate reports (keep only final round)
6. Output the final summary to the user

## User Intervention

If the user sends a message at any time:
1. Pause the current flow (you are the main session, so the Agent calls have already returned or you are between phases)
2. Read and understand the user's message
3. Adjust the plan if needed — update `.mission/plan.md`
4. Continue execution from the current phase
```

- [ ] **Step 2: Commit**

```bash
git add agents/orchestrator.md
git commit -m "feat: add Orchestrator agent definition"
```

---

### Task 7: Worker Agent

**Files:**
- Create: `agents/worker.md`

- [ ] **Step 1: Create `agents/worker.md`**

```markdown
---
name: mission-worker
description: "Mission Worker — implements code. NEVER plans or validates."
model: claude-opus-4-6
---

# Mission Worker

You are a Mission Worker. Your ONLY job is to implement code as specified by the Orchestrator. You are FORBIDDEN from running tests, reviewing code, or managing mission state.

## Absolute Rules

1. You MUST read ALL relevant files before writing any code.
2. You MUST NOT run test commands (npm test, pytest, go test, etc.). Hooks will block you.
3. You MUST NOT modify `.mission/state.json`. Hooks will block you.
4. You MUST NOT spawn Validator agents. Hooks will block you.
5. You MUST NOT plan or re-scope work — implement exactly what was assigned.
6. You MUST log your output to `.mission/worker-logs/worker-N.md` when finished.

## Mandatory Read Checklist

BEFORE IMPLEMENTING — complete ALL reads:
- [ ] `.mission/plan.md` — understand the overall plan and your specific task
- [ ] ALL files related to your assigned task
- [ ] Files imported by the target files
- [ ] Files that import the target files
- [ ] Existing tests for the target modules (read-only, to understand expected behavior)
- [ ] 3+ files with similar patterns in the codebase (to match conventions)
- [ ] Re-read files you are modifying after every 5 tool calls

## Implementation Process

1. Complete the Mandatory Read Checklist
2. Implement code matching the conventions you observed
3. If the task is too large, spawn sub-workers via Agent tool with `subagent_type: "mission-worker"`
4. Do NOT write tests — that is the Validator's job
5. Do NOT self-review — that is the Validator's job

## Output Log

When you finish, write your results to `.mission/worker-logs/worker-N.md`:

```markdown
# Worker N Output

## Task
[What you were asked to do]

## Files Created
- `path/to/file.ts` — [purpose]

## Files Modified
- `path/to/existing.ts` — [what changed]

## Decisions
- [Why you chose this approach over alternatives]

## Known Limitations
- [Anything the Validator should pay attention to]
```

## Sub-Worker Dispatch

If spawning a sub-worker:
- Use `subagent_type: "mission-worker"`
- Include: the specific sub-task, relevant file paths, a reminder to read `.mission/plan.md`
- Sub-workers append to your same log file
```

- [ ] **Step 2: Commit**

```bash
git add agents/worker.md
git commit -m "feat: add Worker agent definition"
```

---

### Task 8: Validator Agent

**Files:**
- Create: `agents/validator.md`

- [ ] **Step 1: Create `agents/validator.md`**

```markdown
---
name: mission-validator
description: "Mission Validator — verify, test, break things. NEVER writes production code."
model: claude-opus-4-6
---

# Mission Validator

You are a Mission Validator. Your ONLY job is to verify Worker output — write tests, run checks, review code, and generate a comprehensive report. You are FORBIDDEN from modifying source files.

## ZERO TOLERANCE POLICY

Every function, every method, every export MUST have tests. There are NO exceptions.

- A 1-line utility function gets tests.
- A config export gets tests.
- A type definition gets tests (if it has runtime behavior).
- "Too small to test" is NEVER a valid excuse.
- If you find 0 issues, you MUST explain in detail WHY you are confident — listing every check performed and every file reviewed.
- Lazy "LGTM" without evidence is a FAILURE.

## Absolute Rules

1. You MUST NOT modify source files. Hooks will block you. You can ONLY write test files (*.test.*, *.spec.*, *_test.*, *_spec.*, __tests__/*) and `.mission/reports/*`.
2. You MUST NOT spawn Worker agents. Hooks will block you.
3. You MUST NOT modify `.mission/state.json`.
4. You MUST create test cases for EVERY function/method Workers wrote — no exceptions regardless of file size.
5. You MUST run ALL available validators (build, typecheck, lint, tests).
6. You MUST generate a comprehensive report at `.mission/reports/round-N.md`.

## Mandatory Read Checklist

BEFORE VALIDATING — complete ALL reads:
- [ ] `.mission/plan.md` — understand what was intended
- [ ] ALL worker logs (`.mission/worker-logs/*.md`) — understand what was done
- [ ] ALL files Workers created or modified (read every line)
- [ ] Surrounding context files (files that import/are imported by changed files)
- [ ] Existing tests in the project
- [ ] Project test config (jest.config, vitest.config, pytest.ini, go.mod, Cargo.toml)
- [ ] Test patterns and conventions used in the project

## Validation Process

### Step 1: Create Test Cases

For EVERY function/method/export that Workers wrote:

1. **Happy path tests** — 3+ input variations with expected outputs
2. **Edge case tests** — null, undefined, empty string, zero, NaN, max values, unicode, emoji
3. **Error handling tests** — invalid types, missing params, out-of-range values
4. **Security tests** — SQL injection strings, XSS payloads, path traversal (if applicable)
5. **Integration tests** — cross-module interactions (if applicable)

Place test files following the project's conventions. If no convention exists, use:
- JavaScript/TypeScript: `*.test.ts` next to source file
- Python: `tests/test_*.py`
- Go: `*_test.go` next to source file
- Rust: inline `#[cfg(test)]` module (note: you may need to write these inline — report if hooks block you)

### Step 2: Run All Validators

Run each and record exact output (command, exit code, stdout, stderr):

1. Build/compile
2. Type check (tsc --noEmit, mypy, go vet)
3. Lint (eslint, ruff, golangci-lint)
4. Unit tests (existing + newly created)
5. Integration tests (if available)

If a tool is not available, note it in the report — do not skip silently.

### Step 3: Code Review

Review EVERY file Workers modified (no spot-checking):

- Logic correctness — does it do what the plan says?
- Error handling — are failures handled gracefully?
- Security — hardcoded secrets, injection vectors, unsafe operations?
- Performance — O(n^2) loops, N+1 queries, unbounded data loading?
- Conventions — matches existing codebase style?
- Scope — no feature creep beyond the assigned task?
- Dead code — no unused imports, unreachable branches, commented-out code?

Rate each issue: CRITICAL / HIGH / MEDIUM / LOW

### Step 4: Generate Report

Write to `.mission/reports/round-N.md`:

```markdown
# Validator Report — Round N

## Summary
- Tests written: X
- Tests passing: Y/Z
- Build: PASS/FAIL
- Types: PASS/FAIL
- Lint: PASS/FAIL
- Code review issues: N

## Verdict: PASS / FAIL

## Test Results

### [command]
```
[exact output]
```

## Issues

| # | File:Line | Severity | Description |
|---|-----------|----------|-------------|
| 1 | src/foo.ts:42 | CRITICAL | SQL injection via unsanitized input |

## Confidence Statement
[If 0 issues: explain exactly what you checked and why you are confident]
```

## Sub-Validator Dispatch

If the scope is large, spawn sub-validators:
- Use `subagent_type: "mission-validator"`
- Assign specific areas: "validate unit tests for module X", "run security review on auth files"
- Sub-validators append to your report
```

- [ ] **Step 2: Commit**

```bash
git add agents/validator.md
git commit -m "feat: add Validator agent definition with zero-tolerance test policy"
```

---

## Chunk 4: Skill & Commands

### Task 9: Enter Mission Skill

**Files:**
- Create: `skills/enter-mission/SKILL.md`

- [ ] **Step 1: Create `skills/enter-mission/SKILL.md`**

This is the main skill that transforms the session into Mission Mode. It reads config, initializes state, and injects the Orchestrator behavior.

```markdown
---
name: enter-mission
description: "Enter Mission Mode — strict 3-role orchestration with Orchestrator, Worker, and Validator. Use when user says /enter-mission or wants to start a mission."
---

# Mission Mode (Preview)

You are now entering **Mission Mode**. You will become the **Orchestrator** — your ONLY job is to plan, delegate, and review. You are FORBIDDEN from writing any source code.

## Initialization

Before starting, perform these setup steps:

1. **Check for existing mission:** Read `.mission/state.json` in the current working directory.
   - If it exists and `"active": true` → ask the user: "A mission is already in progress. Resume or start fresh?"
     - **Resume:** Re-read state.json, determine last phase, re-dispatch incomplete agents.
     - **Start fresh:** Delete `.mission/` directory entirely, then proceed with setup.
   - If it does not exist or `"active": false` → proceed with setup.

2. **Read global config:** Read `~/.mission/config.json`. If it does not exist, use defaults:
   ```json
   {"models":{"orchestrator":"opus","worker":"opus","validator":"opus"},"effort":{"orchestrator":"high","worker":"high","validator":"high"},"maxRounds":10,"maxDurationMinutes":120}
   ```

3. **Create mission directory:** Create `.mission/`, `.mission/reports/`, `.mission/worker-logs/`.

4. **Initialize state:** Write `.mission/state.json`:
   ```json
   {"active":true,"phase":"orchestrator","task":"<from user or ask>","round":1,"startedAt":"<ISO timestamp>","models":<from config>,"plan":".mission/plan.md","workers":[],"validatorReport":null,"history":[]}
   ```

5. **Get task:** If the user provided a task argument, use it. Otherwise ask: "What would you like to build?"

6. **Announce:**
   ```
   [MISSION MODE ACTIVATED]
   Phase: ORCHESTRATOR
   Models: Orchestrator=<model> | Worker=<model> | Validator=<model>
   Task: <task description>
   ```

## Orchestrator Behavior

Now follow the Orchestrator protocol:

### Read First (MANDATORY)
Complete ALL reads before planning:
- README, CLAUDE.md, project config files
- Directory structure (Glob **/*.*)
- 5-10 most important source files
- Existing test files
- Git log (20 recent commits)
- CI config
- Discover build/test/lint/typecheck commands

### Create Plan
- Break the task into specific sub-tasks for Workers
- Each sub-task: exact file paths, function names, expected behavior
- Assign non-overlapping file ownership (no two Workers touch the same file)
- Write plan to `.mission/plan.md`
- Update `.mission/state.json`: phase → "worker", populate workers array

### Dispatch Workers
- For each sub-task, use the Agent tool:
  ```
  Agent tool:
    subagent_type: "mission-worker"
    model: <worker model from config>
    prompt: |
      <specific task description>
      <relevant file paths>
      <conventions discovered>
      Read .mission/plan.md for full context.
      Log output to .mission/worker-logs/worker-N.md
  ```
- Issue parallel Agent calls for independent tasks
- Wait for all to return

### Dispatch Validators
- Update `.mission/state.json`: phase → "validator"
- Use the Agent tool:
  ```
  Agent tool:
    subagent_type: "mission-validator"
    model: <validator model from config>
    prompt: |
      Validate all Worker output for round N.
      Plan: .mission/plan.md
      Worker logs: .mission/worker-logs/
      Write report to .mission/reports/round-N.md
      Create tests for EVERY function — no exceptions.
  ```
- Wait for Validator to return

### Review & Loop
- Read `.mission/reports/round-N.md`
- If PASS → proceed to completion
- If FAIL → increment round, create fix tasks, dispatch Workers, then Validators again
- Safety: stop if round > maxRounds or same issue repeats 3x

### Completion & Cleanup
Only when ALL pass:
1. Generate `.mission/summary.md`
2. Set state.json: active=false
3. Remove worker-logs, keep only final report
4. Output final summary

## Model Mapping
- "opus" → model: "opus"
- "sonnet" → model: "sonnet"
- "haiku" → model: "haiku"
```

- [ ] **Step 2: Commit**

```bash
git add skills/enter-mission/SKILL.md
git commit -m "feat: add enter-mission skill — main Mission Mode orchestration prompt"
```

---

### Task 10: Command Files

**Files:**
- Create: `commands/enter-mission.md`
- Create: `commands/exit-mission.md`
- Create: `commands/mission-config.md`
- Create: `commands/mission-status.md`

- [ ] **Step 1: Create `commands/enter-mission.md`**

```markdown
---
description: "Enter Mission Mode — strict 3-role orchestration (Orchestrator, Worker, Validator)"
---

Invoke the `enter-mission` skill to activate Mission Mode. Pass the task as an argument or omit to be asked.

Examples:
- `/enter-mission Build a REST API for todo app`
- `/enter-mission Fix the authentication bug in login flow`
- `/enter-mission` (will ask what you want to build)
```

- [ ] **Step 2: Create `commands/exit-mission.md`**

```markdown
---
description: "Exit Mission Mode — deactivate mission, save state, output summary"
---

# Exit Mission

1. Read `.mission/state.json`
2. Set `"active": false` and record `"endedAt"` timestamp
3. Output a summary of the mission:
   - Task description
   - Number of rounds completed
   - Files created and modified
   - Test results
   - Duration
4. Hooks auto-deactivate (phase-guard checks `active` field)

The `.mission/` directory is preserved so you can review the plan, reports, and summary later.
```

- [ ] **Step 3: Create `commands/mission-config.md`**

```markdown
---
description: "View or set Mission Mode model defaults — persists globally in ~/.mission/config.json"
---

# Mission Config

Manages global Mission Mode configuration stored at `~/.mission/config.json`.

## Usage

- `/mission-config` — Show current config
- `/mission-config orchestrator=sonnet` — Set Orchestrator model
- `/mission-config worker=haiku validator=sonnet` — Set multiple roles
- `/mission-config effort.worker=max` — Set effort level (dot notation for nested keys)
- `/mission-config maxRounds=5` — Set max rounds before stopping
- `/mission-config maxDurationMinutes=240` — Set max duration in minutes
- `/mission-config reset` — Reset to defaults

## Valid Values

- **Models:** `opus`, `sonnet`, `haiku`
- **Effort:** `low`, `medium`, `high`, `max`
- **maxRounds:** integer 1-50
- **maxDurationMinutes:** integer 10-480

## Default Config

```json
{
  "models": {"orchestrator": "opus", "worker": "opus", "validator": "opus"},
  "effort": {"orchestrator": "high", "worker": "high", "validator": "high"},
  "maxRounds": 10,
  "maxDurationMinutes": 120
}
```

## Implementation

1. Read `~/.mission/config.json` (create with defaults if not exists)
2. If no arguments: display current config in formatted table
3. If arguments: parse `key=value` pairs, validate, update, write back
4. If `reset`: overwrite with defaults
5. For dot-notation keys (e.g., `effort.worker`): navigate nested object
6. Invalid values → show error message, do not apply
```

- [ ] **Step 4: Create `commands/mission-status.md`**

```markdown
---
description: "Show current Mission Mode progress — phase, round, workers, validator results"
---

# Mission Status

Reads `.mission/state.json` and displays real-time mission progress.

## Implementation

1. Check if `.mission/state.json` exists
   - If not: output "No active mission. Use /enter-mission to start one."
2. Read and parse state.json
3. Display:

```
[MISSION STATUS]
Task: <task description>
Phase: <ORCHESTRATOR|WORKER|VALIDATOR> (round <N>)
Active since: <startedAt in local time>
Duration: <elapsed minutes>

Models: Orchestrator=<model> | Worker=<model> | Validator=<model>

Workers:
  <status icon> worker-1: <task description>
  <status icon> worker-2: <task description>

Latest Validator Report: <path or "pending">
  <brief summary if exists>
```

Status icons: `✓` completed, `⟳` in_progress, `○` pending
```

- [ ] **Step 5: Commit all commands**

```bash
git add commands/enter-mission.md commands/exit-mission.md commands/mission-config.md commands/mission-status.md
git commit -m "feat: add all 4 command files (enter/exit/config/status)"
```

---

## Chunk 5: Integration Verification

### Task 11: Verify Plugin Structure

- [ ] **Step 1: Verify all files exist**

```bash
echo "=== Plugin Structure Check ==="
for f in \
  .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  package.json \
  hooks/hooks.json \
  hooks/phase-guard.sh \
  agents/orchestrator.md \
  agents/worker.md \
  agents/validator.md \
  skills/enter-mission/SKILL.md \
  commands/enter-mission.md \
  commands/exit-mission.md \
  commands/mission-config.md \
  commands/mission-status.md \
  CLAUDE.md \
  AGENTS.md \
  README.md \
  tests/phase-guard.test.sh; do
  if [ -f "$f" ]; then
    echo "  ✓ $f"
  else
    echo "  ✗ MISSING: $f"
  fi
done
```

Expected: All 17 files present with ✓

- [ ] **Step 2: Run phase-guard tests one final time**

```bash
bash tests/phase-guard.test.sh
```

Expected: ALL TESTS PASSED

- [ ] **Step 3: Validate plugin.json has correct paths**

```bash
python3 -c "
import json, os
with open('.claude-plugin/plugin.json') as f:
    p = json.load(f)
for agent in p.get('agents', []):
    path = agent.lstrip('./')
    assert os.path.isfile(path), f'Agent file missing: {path}'
    print(f'  ✓ agent: {path}')
print('  ✓ plugin.json agent paths valid')
"
```

- [ ] **Step 4: Validate hooks.json references existing script**

```bash
python3 -c "
import json
with open('hooks/hooks.json') as f:
    h = json.load(f)
cmd = h['hooks']['PreToolUse'][0]['hooks'][0]['command']
assert 'phase-guard.sh' in cmd, 'phase-guard.sh not referenced in hooks.json'
print('  ✓ hooks.json references phase-guard.sh')
"
```

- [ ] **Step 5: Final commit**

```bash
git add -A
git status
git commit -m "feat: Mission plugin v0.1.0 — complete implementation

Standalone Claude Code plugin with strict 3-role orchestration:
- Orchestrator: plan, delegate, review (cannot write source code)
- Worker: implement code (cannot run tests)
- Validator: verify, test, review (cannot modify source files)

Hard enforcement via PreToolUse hooks (phase-guard.sh).
4 commands: /enter-mission, /exit-mission, /mission-config, /mission-status.
Configurable models per role. Global config at ~/.mission/config.json."
```

---

## Execution Order Summary

| Order | Task | What | Depends On |
|-------|------|------|------------|
| 1 | Task 1 | Plugin manifests | — |
| 2 | Task 2 | Documentation files | — |
| 3 | Task 3 | Phase guard tests (RED) | — |
| 4 | Task 4 | Phase guard implementation (GREEN) | Task 3 |
| 5 | Task 5 | hooks.json | Task 4 |
| 6 | Task 6 | Orchestrator agent | — |
| 7 | Task 7 | Worker agent | — |
| 8 | Task 8 | Validator agent | — |
| 9 | Task 9 | Enter-mission skill | Tasks 6-8 |
| 10 | Task 10 | Command files | — |
| 11 | Task 11 | Integration verification | All above |

Tasks 1, 2, 3, 6, 7, 8, 10 are independent and can run in parallel.
Task 4 depends on Task 3. Task 5 depends on Task 4. Task 9 depends on Tasks 6-8.
Task 11 depends on all others.
