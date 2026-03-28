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
- [ ] README, CLAUDE.md, project config files (package.json/go.mod/pyproject.toml)
- [ ] Directory structure (Glob **/*.*)
- [ ] 5-10 most important source files
- [ ] Existing test files
- [ ] Git log (20 recent commits)
- [ ] CI config (.github/workflows, Makefile)
- [ ] Discover build/test/lint/typecheck commands

### Create Plan
- Break the task into specific sub-tasks for Workers
- Each sub-task: exact file paths, function names, expected behavior
- Assign non-overlapping file ownership (no two Workers touch the same file)
- Write plan to `.mission/plan.md`
- Update `.mission/state.json`: phase → "worker", populate workers array

### Dispatch Workers
- For each sub-task, use the Agent tool:
  - `subagent_type: "mission-worker"`
  - `model:` use the worker model from config (opus/sonnet/haiku)
  - In the prompt, include: the specific task, relevant file paths, conventions discovered, and a reminder to read `.mission/plan.md` and log output to `.mission/worker-logs/worker-N.md`
- Issue parallel Agent calls for independent tasks (multiple Agent calls in one message)
- Issue sequential Agent calls for dependent tasks
- Wait for all to return (Agent tool is synchronous — you are blocked until they complete)

### Dispatch Validators
- After all Workers return, update `.mission/state.json`: phase → "validator"
- Spawn Validator agent(s) via Agent tool:
  - `subagent_type: "mission-validator"`
  - `model:` use the validator model from config
  - In the prompt, include: the plan path, worker logs paths, list of all files created/modified, and a reminder to create tests for EVERY function — no exceptions
- Wait for Validator to return

### Review & Loop
- Read `.mission/reports/round-N.md`
- If ALL PASS → proceed to Completion
- If issues found:
  1. Increment round counter in state.json
  2. Create fix tasks from the Validator report
  3. Update state.json: phase → "worker"
  4. Dispatch Workers to fix (only the specific issues, no new features)
  5. After Workers return → dispatch Validator again
  6. Repeat until ALL PASS

### Safety Net
- If round exceeds maxRounds (from config, default 10) → stop and report to user
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
2. Generate `.mission/summary.md` with full mission summary
3. Set state.json: `"active": false`, `"completedAt": "<ISO timestamp>"`
4. Remove `.mission/worker-logs/*.md`
5. Remove intermediate reports (keep only final round)
6. Output the final summary:

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

## User Intervention

If the user sends a message at any time:
1. Pause the current flow (you are the main session — Agent calls have returned or you are between phases)
2. Read and understand the user's message
3. Adjust the plan if needed — update `.mission/plan.md`
4. Continue execution from the current phase

## Model Mapping
- "opus" → `model: "opus"`
- "sonnet" → `model: "sonnet"`
- "haiku" → `model: "haiku"`
