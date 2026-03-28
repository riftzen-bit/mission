# Mission Plugin — Design Specification

**Date:** 2026-03-28
**Author:** Paul (via Claude Code brainstorming)
**Status:** Draft
**Approach:** B — Prompt + Hooks Enforcement

---

## 1. Overview

Mission is a standalone Claude Code plugin that introduces a strict 3-role orchestration system for software engineering tasks. When activated via `/enter-mission`, the session enters **Mission Mode** with three strictly isolated roles:

- **Orchestrator** — plans, delegates, reviews. NEVER writes code.
- **Worker** — implements code. NEVER plans or validates.
- **Validator** — verifies, tests, reviews. NEVER writes production code.

Only ONE role is active at any time. Roles enforce strict isolation via prompt instructions AND PreToolUse hooks (hard enforcement).

## 2. Requirements

### Functional

1. `/enter-mission [task]` — enter Mission Mode. If task provided, start immediately. If not, ask user.
2. `/exit-mission` — leave Mission Mode. Set state to inactive, output summary.
3. `/mission-config` — view and set model defaults (persist globally in `~/.mission/config.json`).
4. `/mission-status` — view real-time progress of current mission.
5. Default models: all Opus 4.6 with effort "high". User can change per-role to haiku, sonnet, or opus.
6. Fully autonomous execution — user can intervene at any time but does not need to.
7. Orchestrator cleanup only when 100% complete — force incomplete roles to finish first.

### Non-Functional

1. Hard enforcement via hooks — roles cannot violate their boundaries even if the LLM tries.
2. Sequential phase execution — only one role type active at a time.
3. Within a phase, multiple instances of the same role can run in parallel.
4. Real-time output visible from the active role.
5. Crash recovery — existing `.mission/state.json` detected on re-entry.
6. Works with any project, any language, any framework.

## 3. Plugin Structure

```
mission/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest
│   └── marketplace.json         # Marketplace registry
├── agents/
│   ├── orchestrator.md          # Orchestrator role definition
│   ├── worker.md                # Worker role definition
│   └── validator.md             # Validator role definition
├── skills/
│   └── enter-mission/
│       └── SKILL.md             # Main skill — transforms session into Orchestrator
├── commands/
│   ├── enter-mission.md         # /enter-mission command
│   ├── exit-mission.md          # /exit-mission command
│   ├── mission-config.md        # /mission-config command
│   └── mission-status.md        # /mission-status command
├── hooks/
│   ├── hooks.json               # Hook registrations (auto-loaded)
│   └── phase-guard.sh           # PreToolUse enforcement script
├── CLAUDE.md                    # Plugin-level guidance
├── AGENTS.md                    # Agent catalog documentation
├── README.md                    # Plugin documentation
└── package.json                 # Version metadata
```

### Runtime State (created per-project)

```
.mission/                        # In the project working directory
├── state.json                   # Phase, task, progress, worker/validator tracking
├── plan.md                      # Orchestrator's plan
├── reports/                     # Validator reports
│   ├── round-1.md
│   └── round-N.md
├── worker-logs/                 # Worker output logs
│   ├── worker-1.md
│   └── worker-N.md
└── summary.md                   # Final summary (created at cleanup)
```

### Global Config

```
~/.mission/config.json           # Persists across projects and sessions
```

## 4. Role Definitions

### 4.1 Orchestrator

**Agent file:** `agents/orchestrator.md`

```yaml
---
name: mission-orchestrator
description: "Mission Orchestrator — plan, delegate, review. NEVER writes code."
model: claude-opus-4-6
---
```

Note: Orchestrator does NOT use `disallowedTools` because it needs `Write` to manage `.mission/` state files (plan.md, state.json, summary.md). Instead, hooks enforce that Orchestrator can ONLY write to `.mission/*` paths — never to project source files.

**Responsibilities:**
- Read codebase thoroughly before planning
- Create detailed plan with sub-tasks for Workers (write to `.mission/plan.md`)
- Update `.mission/state.json` for phase transitions
- Dispatch Worker agents (one per sub-task or grouped) via Agent tool
- Block on Agent tool calls — the Orchestrator is NOT suspended during Worker/Validator phases. It invokes Agent tool calls which are synchronous (blocking). The Orchestrator simply waits for the Agent tool to return. "SILENT" means the Orchestrator does not produce output or take other actions while waiting — it is blocked on the Agent call.
- After all Workers return → write phase transition to state.json → dispatch Validators
- After all Validators return → read report → decide next action
- Force incomplete roles to finish before cleanup
- Clean up `.mission/` only when 100% complete

**Forbidden:**
- Write or Edit any project source file (enforced by hooks — only `.mission/*` writes allowed)
- Clean up before all checks pass
- Skip reading codebase before planning

### 4.2 Worker

**Agent file:** `agents/worker.md`

```yaml
---
name: mission-worker
description: "Mission Worker — implements code. NEVER plans or validates."
model: claude-opus-4-6
---
```

**Responsibilities:**
- Read ALL relevant files before writing any code (mandatory checklist)
- Read `.mission/plan.md` for overall context
- Implement code exactly as specified in the assigned task
- Match existing project conventions (discovered by reading first)
- Can spawn sub-workers for large tasks
- Log output to `.mission/worker-logs/worker-N.md`

**Forbidden:**
- Run tests (Validator's job)
- Review own code (Validator's job)
- Modify `.mission/state.json` (Orchestrator's job)
- Spawn Validators (Orchestrator's job)
- Plan or re-scope work (Orchestrator's job)

### 4.3 Validator

**Agent file:** `agents/validator.md`

```yaml
---
name: mission-validator
description: "Mission Validator — verify, test, break things. NEVER writes production code."
model: claude-opus-4-6
---
```

**Responsibilities:**
- Read ALL files Workers created/modified (every line)
- Read surrounding files for context
- Read worker logs to understand what was done
- **MUST create test cases for EVERY function/method Workers wrote — no exceptions, no matter how small the file**
- Test categories required:
  - Happy path (3+ variations)
  - Edge cases (null, empty, boundary, unicode)
  - Error handling (invalid input, missing params)
  - Security (injection, XSS if applicable)
  - Integration (cross-module if applicable)
- Run all validators: build, typecheck, lint, unit tests, integration tests
- Review code quality, security, conventions
- Generate comprehensive report in `.mission/reports/round-N.md`
- Can spawn sub-validators (e.g., one for unit tests, one for security)

**Forbidden:**
- Modify source files (only test files and report files)
- Spawn Workers (Orchestrator's job)
- Modify `.mission/state.json` (Orchestrator's job)
- Skip test creation for any function regardless of size
- Claim "no issues" without evidence of thorough checking

**Extremism clause:** Validator operates under zero-tolerance policy. Every function, every method, every export MUST have tests. "Too small to test" is not a valid excuse. A 1-line utility function gets tests. A config export gets tests. If the Validator finds 0 issues, it must explain in detail WHY it is confident — listing every check performed and every file reviewed. Lazy "LGTM" is a failure.

## 5. Phase State Machine

### States

```
IDLE → ORCHESTRATOR → WORKER → VALIDATOR → ORCHESTRATOR → ... → COMPLETE → CLEANUP → IDLE
```

### Transitions

| From | To | Trigger |
|------|----|---------|
| IDLE | ORCHESTRATOR | `/enter-mission` invoked |
| ORCHESTRATOR | WORKER | Orchestrator dispatches Workers |
| WORKER | VALIDATOR | All Workers completed, Orchestrator dispatches Validators |
| VALIDATOR | ORCHESTRATOR | Validator report generated |
| ORCHESTRATOR | WORKER | Issues found, Orchestrator dispatches Workers to fix |
| ORCHESTRATOR | COMPLETE | Validator report = ALL PASS |
| COMPLETE | CLEANUP | Orchestrator verifies completion checklist |
| CLEANUP | IDLE | Cleanup done, `/exit-mission` or auto |

### State File Format (`.mission/state.json`)

```json
{
  "active": true,
  "phase": "orchestrator",
  "task": "Build a REST API for todo app with authentication",
  "round": 1,
  "startedAt": "2026-03-28T10:00:00Z",
  "models": {
    "orchestrator": "opus",
    "worker": "opus",
    "validator": "opus"
  },
  "plan": ".mission/plan.md",
  "workers": [
    {
      "id": "worker-1",
      "task": "Create Express server with routes",
      "status": "completed",
      "log": ".mission/worker-logs/worker-1.md"
    },
    {
      "id": "worker-2",
      "task": "Add authentication middleware",
      "status": "in_progress",
      "log": ".mission/worker-logs/worker-2.md"
    }
  ],
  "validatorReport": ".mission/reports/round-1.md",
  "history": [
    {"phase": "orchestrator", "action": "plan_created", "timestamp": "2026-03-28T10:00:00Z"},
    {"phase": "worker", "action": "worker-1_completed", "timestamp": "2026-03-28T10:15:00Z"},
    {"phase": "validator", "action": "report_generated", "timestamp": "2026-03-28T10:20:00Z"}
  ]
}
```

## 6. Hooks Enforcement

### Hook Registration (`hooks/hooks.json`)

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

The hook fires for `Write`, `Edit`, `Agent`, and `Bash` tool calls. `Read`, `Grep`, and `Glob` are always allowed (all roles can read and search). `Bash` is guarded to prevent Workers from running test commands (Validator's job).

### Phase Guard Rules

**Phase `orchestrator`:**

| Tool | Action |
|------|--------|
| `Write` to `.mission/*` | ALLOW — Orchestrator manages mission state files |
| `Write` to any other path | BLOCK — "Orchestrator cannot write source files. Dispatch Workers." |
| `Edit` to `.mission/*` | ALLOW |
| `Edit` to any other path | BLOCK — "Orchestrator cannot edit source files. Dispatch Workers." |
| `Bash` | ALLOW — Orchestrator can run read-only commands (git log, ls, find) |
| `Agent` with worker/validator subagent | ALLOW |
| `Agent` with other subagent types | ALLOW |

**Phase `worker`:**

| Tool | Action |
|------|--------|
| `Write` to `.mission/state.json` | BLOCK — "Workers cannot modify mission state." |
| `Write` to `.mission/worker-logs/*` | ALLOW — Workers log their output |
| `Write` to any other file | ALLOW |
| `Edit` to `.mission/state.json` | BLOCK |
| `Edit` to `.mission/worker-logs/*` | ALLOW |
| `Edit` to any other file | ALLOW |
| `Bash` command starting with `npm test`, `npx jest`, `npx vitest`, `npx mocha`, `yarn test`, `pnpm test`, `pytest`, `python -m pytest`, `go test`, `cargo test`, `make test`, `gradle test`, `mvn test`, `bundle exec rspec`, `phpunit` | BLOCK — "Workers cannot run tests. That is the Validator's job." |
| `Bash` other commands (build, compile, install, format, etc.) | ALLOW — Workers can run non-test commands. The guard matches command prefixes, not arbitrary substrings, so commands like `mkdir test-fixtures` or `npm install @testing-library/react` are allowed. |
| `Agent` with "validator" in subagent_type | BLOCK — "Workers cannot spawn Validators." |
| `Agent` with "worker" in subagent_type | ALLOW (sub-workers) |
| `Agent` with other subagent types | ALLOW |

**Phase `validator`:**

| Tool | Action |
|------|--------|
| `Write` to files matching `*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`, `__tests__/*`, `.mission/reports/*` | ALLOW |
| `Write` to any other file | BLOCK — "Validators can only write test files and reports." |
| `Edit` to files matching `*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`, `__tests__/*`, `.mission/reports/*` | ALLOW |
| `Edit` to any other file | BLOCK |
| `Bash` | ALLOW — Validators run tests, build, lint, typecheck |
| `Agent` with "worker" in subagent_type | BLOCK — "Validators cannot spawn Workers." |
| `Agent` with "validator" in subagent_type | ALLOW (sub-validators) |
| `Agent` with other subagent types | ALLOW |

### When Mission Is Not Active

If `.mission/state.json` does not exist or `"active": false`, the hook exits immediately with code 0 (pass-through). The plugin has zero impact when not in mission mode.

## 7. Skill Prompt — How Main Session Becomes Orchestrator

When `/enter-mission` is invoked, the `skills/enter-mission/SKILL.md` content is injected into the main Claude Code session. This skill prompt transforms the session into the Orchestrator role. The skill prompt contains:

1. **Role declaration** — "You are now the Mission Orchestrator. Your ONLY job is to plan, delegate, and review."
2. **Forbidden actions** — "You MUST NOT use Write or Edit on any file outside `.mission/`. Hooks will block you if you try."
3. **Mandatory read checklist** — The full Orchestrator Read Checklist from Section 12, embedded directly.
4. **Phase flow instructions** — Step-by-step instructions for the Orchestrator phase sequence (plan → dispatch workers → wait → dispatch validators → wait → review → loop).
5. **Agent dispatch templates** — Exact patterns for spawning Workers and Validators via the Agent tool, including the model from config and the full role prompt to inject into each subagent.
6. **State management instructions** — How to create/update `.mission/state.json`, `.mission/plan.md`, and manage phase transitions.
7. **Completion gate** — The full completion checklist and cleanup rules.
8. **User intervention handling** — How to process user messages mid-mission (adjust plan, add requirements, change direction).

The skill prompt does NOT contain Worker or Validator instructions — those live in `agents/worker.md` and `agents/validator.md` respectively. The Orchestrator references these agent files when spawning subagents via the Agent tool.

## 8. Commands

### 8.1 `/enter-mission [task]`

1. Check for existing `.mission/state.json`:
   - If exists and `active: true` → ask user: "Mission in progress. Resume or start fresh?"
   - **Resume behavior:** Re-read `state.json` to determine last completed phase. If phase was "worker" with some workers completed and some not, re-dispatch only incomplete workers. If phase was "validator", re-dispatch validator. If phase was "orchestrator", continue from where the plan left off. Partial file writes from crashed workers are detected by comparing worker-logs (what was claimed done) against actual file state (what actually exists).
   - **Start fresh:** Delete existing `.mission/` directory and create new.
   - If not exists or `active: false` → create new
2. Read global config from `~/.mission/config.json`
3. Create `.mission/` directory with `state.json`, empty `reports/`, empty `worker-logs/`
4. If task argument provided → set task in state, begin Orchestrator planning
5. If no task → ask user "What would you like to build?"
6. Inject Orchestrator skill prompt → main session becomes Orchestrator

### 8.2 `/exit-mission`

1. Read `.mission/state.json`
2. Set `active: false`, write `endedAt` timestamp
3. Output final summary (rounds, files, tests, duration)
4. Hooks auto-deactivate (check `active` field)

### 8.3 `/mission-config`

**Storage:** `~/.mission/config.json` (global, persists across projects and sessions)

**Default config:**

```json
{
  "models": {
    "orchestrator": "opus",
    "worker": "opus",
    "validator": "opus"
  },
  "effort": {
    "orchestrator": "high",
    "worker": "high",
    "validator": "high"
  },
  "maxRounds": 10,
  "maxDurationMinutes": 120
}
```

**Subcommands:**

| Command | Action |
|---------|--------|
| `/mission-config` (no args) | Show current config |
| `/mission-config orchestrator=sonnet` | Set Orchestrator model |
| `/mission-config worker=haiku validator=sonnet` | Set multiple at once |
| `/mission-config effort.worker=max` | Set effort level |
| `/mission-config maxRounds=5` | Set max rounds |
| `/mission-config reset` | Reset to defaults |

**Validation:**
- Model: must be `opus`, `sonnet`, or `haiku`
- Effort: must be `low`, `medium`, `high`, or `max`
- maxRounds: integer 1-50
- maxDurationMinutes: integer 10-480

Invalid values → clear error message, config not applied.

**Effort mapping:** The `effort` config maps directly to Claude Code's `effortLevel` setting per-agent. Values correspond to Claude Code's native effort levels: `low` (fast, minimal reasoning), `medium` (balanced), `high` (comprehensive with extended thinking), `max` (maximum capability with deepest reasoning, Opus 4.6 only). When spawning a Worker or Validator agent, the Orchestrator passes the configured effort level via the Agent tool's model parameter combined with runtime effort instructions in the agent prompt.

### 8.4 `/mission-status`

Reads `.mission/state.json` and displays:
- Current phase and round
- Task description
- Worker statuses (completed/in_progress/pending)
- Latest validator report summary
- Duration since mission start

## 9. Mission Flow — End to End

### Phase 1: ORCHESTRATOR — Plan

```
[1.1] MANDATORY READ (cannot be skipped)
  - README, CLAUDE.md, package.json/go.mod/pyproject.toml
  - Directory structure (Glob **/*.*)
  - 5-10 most important source files
  - Existing test files
  - Git log (20 most recent commits)
  - CI config (.github/workflows, Makefile)
  - Discover validator commands (build, test, lint, typecheck)

[1.2] ANALYZE
  - Map task onto existing codebase
  - Identify files to create/modify
  - Identify dependencies between parts
  - Identify risks and edge cases

[1.3] CREATE PLAN
  - Break task into specific sub-tasks for Workers
  - Each sub-task: file paths, function names, expected behavior
  - Order: which tasks depend on which
  - Write plan to .mission/plan.md
  - Update state.json: phase → "worker"

[1.4] DISPATCH WORKERS
  - Spawn Worker agents (1 per sub-task or grouped)
  - Each Worker receives: task + relevant file paths + conventions
  - Parallel if independent, sequential if dependent
  - Orchestrator goes SILENT — waits for all Workers
```

### Phase 2: WORKER — Implement

```
[2.1] MANDATORY READ (every Worker, cannot be skipped)
  - .mission/plan.md (overall context)
  - ALL files related to assigned task
  - Files imported by target files
  - Files that import target files
  - Existing tests for target modules
  - 3+ files with similar patterns (convention matching)
  - Re-read files after every 5 tool calls

[2.2] IMPLEMENT
  - Write code matching conventions from step 2.1
  - No tests (Validator's job)
  - No self-review (Validator's job)
  - Spawn sub-workers if task is large

[2.3] LOG OUTPUT
  - Write results to .mission/worker-logs/worker-N.md:
    - Files created (path + purpose)
    - Files modified (path + what changed)
    - Decisions made (why this approach)
    - Known limitations

[2.4] HANDOFF
  - The Agent tool in Claude Code is synchronous — each Agent call blocks until the subagent returns.
  - For parallel Workers: Orchestrator issues multiple Agent tool calls in a single message. Claude Code executes them concurrently and returns all results together.
  - For sequential Workers: Orchestrator issues Agent calls one at a time, each blocking until complete.
  - Once all Agent calls return → Orchestrator writes phase transition to .mission/state.json → dispatches Validators via new Agent calls.
  - "Orchestrator goes SILENT" means the Orchestrator is blocked waiting on Agent tool calls — it does not produce output or take actions until the calls return.
```

### Phase 3: VALIDATOR — Verify

```
[3.1] MANDATORY READ (more thorough than Worker)
  - .mission/plan.md (understand intent)
  - .mission/worker-logs/*.md (understand what Workers did)
  - ALL files Workers created/modified (every line)
  - Surrounding files (context)
  - Existing tests
  - Project test config (jest.config, vitest.config, pytest.ini)
  - Test patterns/conventions in the project

[3.2] CREATE TEST CASES (mandatory — zero exceptions)
  - For EVERY function/method Workers wrote, regardless of size:
    - Happy path tests (3+ variations)
    - Edge case tests (null, empty, boundary, unicode)
    - Error handling tests (invalid input, missing params)
    - Security tests (injection, XSS if applicable)
    - Integration tests (cross-module if applicable)
  - A 1-line function gets tests
  - A config export gets tests
  - "Too small to test" is NEVER a valid excuse
  - Test files follow project conventions

[3.3] RUN ALL VALIDATORS
  - Build/compile
  - Type check (tsc, mypy, go vet)
  - Lint (eslint, ruff, golangci-lint)
  - Unit tests (existing + newly created)
  - Integration tests (if applicable)
  - Record exact output: command, exit code, stdout, stderr

[3.4] CODE REVIEW
  - Review EVERY file Workers modified (no spot-checking)
  - Check: logic correctness, error handling, security, performance
  - Check: conventions match, no scope creep, no dead code
  - Check: imports resolve, types correct, no hardcoded secrets
  - Severity: CRITICAL / HIGH / MEDIUM / LOW

[3.5] GENERATE REPORT
  - Write to .mission/reports/round-N.md:
    - Summary: X pass, Y fail, Z issues
    - Test results: command + full output
    - Issues list: file:line, description, severity
    - Verdict: PASS (100% clean) or FAIL (list all issues)
  - If 0 issues found: must explain WHY confident
    - List every check performed
    - List every file reviewed
    - "LGTM" without evidence = failure
```

### Phase 4: ORCHESTRATOR — Review & Loop

```
[4.1] READ VALIDATOR REPORT
  - Read .mission/reports/round-N.md
  - Analyze each issue
  - Decision:
    - ALL PASS → proceed to Completion
    - HAS ISSUES → create fix tasks

[4.2] IF ISSUES → NEW ROUND
  - Increment round counter
  - Create fix tasks from Validator report
  - Dispatch Workers (fix only, no new features)
  - phase → "worker"
  - Loop: Phase 2 → Phase 3 → Phase 4

[4.3] SAFETY NET
  - round > maxRounds (default 10) → stop, report to user
  - Same issue repeats 3 rounds → escalate to user
  - User intervenes → Orchestrator handles
```

## 10. Mission Completion & Cleanup

### Completion Checklist — ALL must be TRUE

```
[ ] Latest Validator report: PASS (0 issues of any severity)
[ ] All tests pass (existing + newly created)
[ ] Build/compile pass
[ ] Type check pass
[ ] Lint pass
[ ] Every Worker sub-task status = "completed"
[ ] Every Validator sub-task status = "completed"
[ ] No issue of any severity remaining
```

### Force Completion

If ANY item is not done, Orchestrator MUST force it:

- Worker task incomplete → dispatch Worker to finish
- Validator hasn't written tests for function X → dispatch Validator
- Tests failing → dispatch Worker to fix
- Build failing → dispatch Worker to fix
- Lint warnings → dispatch Worker to fix

Loop until COMPLETION CHECKLIST = ALL TRUE. Orchestrator is FORBIDDEN from cleaning up before this.

### Cleanup Phase

Only when completion checklist is 100% satisfied:

1. Orchestrator confirms: "All checks passed. Cleaning up mission."
2. Archive mission data:
   - Keep `.mission/plan.md`
   - Keep `.mission/reports/` (final round)
   - Generate `.mission/summary.md` (full mission summary)
3. Set `state.json`: `"active": false`, `"completedAt": <timestamp>`
4. Remove temporary files:
   - `.mission/worker-logs/*.md`
   - `.mission/reports/round-1..N-1.md` (keep only final round)
5. Output final summary to user

### Final Summary Format

```
[MISSION COMPLETE]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Task: <task description>
Rounds: <N>
Duration: <minutes>

Files created: <N>
Files modified: <N>
Tests written: <N>
Tests passing: <N>/<N>
Build: PASS
Types: PASS
Lint: PASS

Archived:
  .mission/plan.md
  .mission/reports/round-N.md
  .mission/summary.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 11. Edge Cases

| Scenario | Handling |
|----------|----------|
| Session crash during mission | `.mission/state.json` persists. Next `/enter-mission` detects it and offers resume. |
| User types `/exit-mission` mid-work | Mission stops. State saved. Can resume later. |
| User intervenes with a message | Orchestrator (main session) handles it. Can adjust plan, add requirements, change direction. |
| Worker encounters an error it cannot fix | Worker logs the error in its output. Orchestrator reads it and decides: retry, re-scope, or escalate to user. |
| Validator finds 0 issues | Validator must provide detailed evidence of thorough checking. Orchestrator reviews the evidence before accepting. |
| Same issue persists 3+ rounds | Orchestrator escalates to user with full context. |
| maxRounds exceeded | Mission pauses. User informed with summary of remaining issues. |
| No test framework in project | Validator detects this and reports it as a CRITICAL issue. Orchestrator then dispatches a Worker to install and configure the test framework. Validator re-runs after framework is set up. Validators CANNOT install frameworks themselves (that would modify source config files like package.json). |
| Project has no build/lint tools | Validator notes this in report. Orchestrator can dispatch Worker to set up tooling. |
| Multiple Workers modify same file | Orchestrator prevents this by assigning non-overlapping file ownership in the plan. If conflict detected, Orchestrator re-assigns. |
| Mission exceeds maxDurationMinutes | Mission pauses. User informed with elapsed time, current phase, and remaining work summary. User can extend duration via `/mission-config maxDurationMinutes=240` and resume, or `/exit-mission` to stop. |
| Sub-workers/sub-validators spawned | Sub-workers inherit the parent Worker's log file — they append to the same `.mission/worker-logs/worker-N.md`. Sub-validators append to the parent Validator's section in `.mission/reports/round-N.md`. The Orchestrator tracks top-level Workers/Validators in `state.json`; sub-agents are implementation details within each top-level agent. |

## 12. Config Validation

| Field | Type | Valid Values | Default |
|-------|------|-------------|---------|
| `models.orchestrator` | string | `opus`, `sonnet`, `haiku` | `opus` |
| `models.worker` | string | `opus`, `sonnet`, `haiku` | `opus` |
| `models.validator` | string | `opus`, `sonnet`, `haiku` | `opus` |
| `effort.orchestrator` | string | `low`, `medium`, `high`, `max` | `high` |
| `effort.worker` | string | `low`, `medium`, `high`, `max` | `high` |
| `effort.validator` | string | `low`, `medium`, `high`, `max` | `high` |
| `maxRounds` | integer | 1-50 | 10 |
| `maxDurationMinutes` | integer | 10-480 | 120 |

## 13. Mandatory Read Checklists

Embedded in every agent prompt as a non-skippable gate.

### Orchestrator Read Checklist

```
BEFORE PLANNING — complete ALL reads:
[ ] README, CLAUDE.md, project config (package.json/go.mod/pyproject.toml)
[ ] Directory structure via Glob
[ ] 5-10 most important source files
[ ] Existing test files
[ ] Git log (20 recent commits)
[ ] CI config
[ ] Discover validator commands
```

### Worker Read Checklist

```
BEFORE IMPLEMENTING — complete ALL reads:
[ ] .mission/plan.md
[ ] ALL files related to assigned task
[ ] Files imported by target files
[ ] Files that import target files
[ ] Existing tests for target modules
[ ] 3+ files with similar patterns for conventions
[ ] Re-read after every 5 tool calls
```

### Validator Read Checklist

```
BEFORE VALIDATING — complete ALL reads:
[ ] .mission/plan.md
[ ] ALL worker logs (.mission/worker-logs/*.md)
[ ] ALL files Workers created/modified (every line)
[ ] Surrounding context files
[ ] Existing tests
[ ] Project test config
[ ] Test patterns/conventions in the project
```
