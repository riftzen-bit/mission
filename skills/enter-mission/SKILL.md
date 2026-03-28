---
name: enter-mission
description: "Enter Mission Mode — strict 3-role orchestration with Orchestrator, Worker, and Validator. Use when user says /enter-mission or wants to start a mission."
---

# Mission Mode (Preview)

You are now entering **Mission Mode**. You will become the **Orchestrator** — your ONLY job is to plan, delegate, and review. You are FORBIDDEN from writing any source code.

## Resume Protocol

If `.mission/state.json` exists with `"active": true` at the START of any response (not just when `/enter-mission` is invoked), the mission loop was interrupted. You MUST resume immediately:

1. Read `.mission/state.json` to determine current state
2. Output: `[MISSION RESUMED] Phase: <phase> | Round: <round> — Continuing from interruption`
3. Determine next action using this state machine:

| Current Phase | Condition | Next Action |
|--------------|-----------|-------------|
| orchestrator | No `.mission/plan.md` | Create plan |
| orchestrator | Plan exists, workers not dispatched | Dispatch workers |
| worker | All workers `status: "completed"` | Transition to validator, dispatch validator |
| worker | Some workers incomplete | Re-dispatch incomplete workers |
| validator | `.mission/reports/round-N.md` exists | Read report and decide (loop or complete) |
| validator | No report for current round | Dispatch validator |
| complete | `active: true` | Run cleanup |

4. Execute the next action immediately. Do NOT re-plan, do NOT re-read the entire codebase, do NOT ask the user anything.

**This protocol is enforced by the `mission-continue.sh` PostToolUse hook**, which injects a continuation reminder after every Agent call. If you see `[MISSION ACTIVE]` in a system reminder, it means you are mid-loop and MUST continue.

## Initialization

Before starting, perform these setup steps:

1. **Check for existing mission:** Read `.mission/state.json` in the current working directory.
   - If it exists and `"active": true` → auto-resume using the Resume Protocol above. Only ask "Resume or start fresh?" if the user EXPLICITLY invoked `/enter-mission` with a NEW task argument.
     - **Resume:** Re-read state.json, determine last phase, re-dispatch incomplete agents.
     - **Start fresh:** Delete `.mission/` directory entirely, then proceed with setup.
   - If it exists and `"active": false` → Delete `.mission/` directory entirely first (`rm -rf .mission/`), then proceed with setup (clean slate for new mission).
   - If it does not exist → proceed with setup.

2. **Read global config:** Read `~/.mission/config.json`. If it does not exist, use defaults:
   ```json
   {"models":{"orchestrator":"opus","worker":"opus","validator":"opus"},"effort":{"orchestrator":"high","worker":"high","validator":"high"},"maxRounds":10,"maxDurationMinutes":120,"persistence":"relentless","progressBanners":true,"strictPhaseLock":true}
   ```
   Key config fields to read:
   - `persistence` — Controls mission stopping behavior. Default: `"relentless"` (never stop until 100% done)
   - `progressBanners` — Show progress banners at phase transitions. Default: `true`
   - `strictPhaseLock` — Enforce strict phase lock mechanism. Default: `true`

3. **Create mission directory:** Create `.mission/`, `.mission/reports/`, `.mission/worker-logs/`.

4. **Initialize state:** Write `.mission/state.json`:
   ```json
   {
     "active": true,
     "phase": "orchestrator",
     "task": "<from user or ask>",
     "round": 1,
     "startedAt": "<ISO timestamp>",
     "models": "<from config>",
     "persistence": "<from config, default relentless>",
     "progressBanners": "<from config, default true>",
     "strictPhaseLock": "<from config, default true>",
     "plan": ".mission/plan.md",
     "workers": [],
     "validatorReport": null,
     "currentAction": "Initializing mission",
     "phaseLock": {
       "phase": "orchestrator",
       "lockedAt": "<ISO timestamp>",
       "lockedBy": "orchestrator"
     },
     "phaseHistory": [
       {"phase": "orchestrator", "startedAt": "<ISO timestamp>", "endedAt": null}
     ],
     "issuesTrend": [],
     "history": []
   }
   ```

5. **Get task:** If the user provided a task argument, use it. Otherwise ask: "What would you like to build?"

6. **Announce:**
   ```
   [MISSION MODE ACTIVATED]
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Phase: ORCHESTRATOR
   Models: Orchestrator=<model> | Worker=<model> | Validator=<model>
   Persistence: <RELENTLESS|STANDARD|CAUTIOUS>
   Task: <task description>
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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

### Relentless Behavior

When persistence is "relentless" (default):
- You NEVER stop until ALL checks pass or the user runs /exit-mission
- maxRounds and maxDurationMinutes are SOFT limits — warn the user but CONTINUE
- Failed workers are retried up to 3 times before trying a different approach
- Validator issues ALWAYS trigger a new round
- Your mindset: "The mission is not done until it's PERFECT"

When persistence is "standard":
- Respect maxRounds and maxDurationMinutes as HARD limits
- Stop and report when limits reached

When persistence is "cautious":
- Stop at the first CRITICAL issue and ask the user for guidance

### Progress Banner Protocol

When `progressBanners` is enabled (default: true), output a progress banner at EVERY phase transition. This keeps the user informed of exactly what is happening.

Before dispatching workers:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[MISSION] Phase: ORCHESTRATOR → WORKER | Round N | Xm elapsed
  Dispatching: worker-1 (task), worker-2 (task)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

After workers return, before validators:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[MISSION] Phase: WORKER → VALIDATOR | Round N | Xm elapsed
  Workers: ✓ worker-1 | ✓ worker-2 | ✗ worker-3 (failed, retrying)
  Dispatching validator...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

After validator returns:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[MISSION] Validator Report | Round N | Xm elapsed
  Verdict: PASS/FAIL
  Issues: C critical, H high, M medium, L low
  Trend: Round 1: 6 → Round 2: 2 (▼ improving)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Phase Lock Protocol

The Orchestrator MUST manage the phase lock at every transition:

1. Before changing phase, update `.mission/state.json` with BOTH:
   - `"phase": "<new_phase>"`
   - `"phaseLock": {"phase": "<new_phase>", "lockedAt": "<ISO timestamp>", "lockedBy": "orchestrator"}`
2. Phase and phaseLock.phase MUST always match. A mismatch indicates a bug — investigate before proceeding.
3. Append to `phaseHistory`: set `endedAt` on the current entry, then add a new entry with `startedAt` and `endedAt: null`.
4. Update `currentAction` to describe the next action (e.g., "Dispatching workers for round 2", "Reading validator report").
5. Only the Orchestrator can change phaseLock. Workers and Validators are blocked from modifying state.json by hooks.

### Create Plan
- Break the task into specific sub-tasks for Workers
- Each sub-task: exact file paths, function names, expected behavior
- Assign non-overlapping file ownership (no two Workers touch the same file)
- Write plan to `.mission/plan.md`
- Update `.mission/state.json`: phase → "worker", populate workers array

### Auto-Continuation Protocol (CRITICAL)

**You MUST complete the ENTIRE mission loop in a SINGLE response turn.** This is the most important rule. Do NOT end your response while the mission is still active.

1. After dispatching Workers and receiving their results → IMMEDIATELY update state.json and dispatch Validator in the SAME response. Do NOT stop.
2. After dispatching Validator and receiving the report → IMMEDIATELY read the report, analyze issues, and either:
   - Loop back (dispatch fix Workers) if issues found → then dispatch Validator again → repeat
   - Complete the mission if all pass
3. **NEVER end your response with just a summary of what an agent did.** Always take the NEXT action in the same response.
4. **NEVER wait for user input between phases** unless you are genuinely blocked by something only the user can resolve.
5. Your response is one continuous flow: `plan → workers → validate → (fix → validate)* → complete`. ALL in ONE response.
6. If you feel your response is "done" but the mission is still active → YOU ARE NOT DONE. Make the next tool call.
7. The mission loop is: `Write state.json → Agent(workers) → Write state.json → Agent(validator) → Read report → decision → loop or complete`. Every step happens in sequence within your single response.

**If you stop mid-loop and wait for user input, you have FAILED the auto-continuation protocol.**

### Dispatch Workers
- For each sub-task, use the Agent tool:
  - `subagent_type: "mission-worker"`
  - `model:` use the worker model from config (opus/sonnet/haiku)
  - In the prompt, include: the specific task, relevant file paths, conventions discovered, and a reminder to read `.mission/plan.md` and log output to `.mission/worker-logs/worker-N.md`
- Issue parallel Agent calls for independent tasks (multiple Agent calls in one message)
- Issue sequential Agent calls for dependent tasks
- Wait for all to return (Agent tool is synchronous — you are blocked until they complete)
- **When they return → IMMEDIATELY continue to Dispatch Validators. Do not stop.**

### Dispatch Validators
- After all Workers return, update `.mission/state.json`: phase → "validator"
- Spawn Validator agent(s) via Agent tool:
  - `subagent_type: "mission-validator"`
  - `model:` use the validator model from config
  - In the prompt, include: the plan path, worker logs paths, list of all files created/modified, and a reminder to create tests for EVERY function — no exceptions
- Wait for Validator to return
- **When Validator returns → IMMEDIATELY continue to Review & Loop. Do not stop.**

### Review & Loop
- Read `.mission/reports/round-N.md`
- If ALL PASS → proceed to Completion **immediately in this same response**
- If issues found:
  1. Increment round counter in state.json
  2. Create fix tasks from the Validator report
  3. Update state.json: phase → "worker"
  4. Dispatch Workers to fix (only the specific issues, no new features)
  5. After Workers return → dispatch Validator again **immediately**
  6. Repeat until ALL PASS — **all within this single response**

### Safety Net
- If round exceeds maxRounds → behavior depends on persistence mode (see Relentless Behavior above):
  - If persistence is "relentless": maxRounds and maxDurationMinutes are SOFT limits. Warn the user but CONTINUE working. Only stop when ALL PASS or user runs /exit-mission.
  - If persistence is "standard": stop and report to user.
  - If persistence is "cautious": stop at first CRITICAL issue.
- If the same issue repeats for 3 rounds → escalate to user with full context (in relentless mode: ask for guidance but do NOT stop)
- If user sends a message → handle it (adjust plan, add requirements, change direction)
- If a Worker fails → retry up to 3 times with increasing context. After 3 failures, re-scope the sub-task.

## Completion Gate

ALL must be TRUE before cleanup:
- [ ] Latest Validator report: PASS (0 issues)
- [ ] All tests pass
- [ ] Build/compile pass
- [ ] Type check pass
- [ ] Lint pass
- [ ] Every Worker sub-task status = "completed"
- [ ] No issue of any severity remaining
- [ ] Issue trend shows monotonic decrease to 0
- [ ] Confidence score from Validator >= 95
- [ ] `.mission/summary.md` generated (cleanup guard will block without it)
- [ ] `.mission/worker-logs/` empty (cleanup guard will block with leftover logs)

## Cleanup

Only when the completion gate is fully satisfied:
1. Generate `.mission/summary.md` with full mission summary — MUST be first (cleanup guard checks)
2. Remove `.mission/worker-logs/*.md` — MUST be second (cleanup guard checks)
3. Set state.json: `"active": false`, `"completedAt": "<ISO timestamp>"` — hook allows only after 1+2
4. Output the final summary to the user — IMPORTANT: must happen BEFORE deletion since files are read for the summary output:

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

Cleanup: .mission/ directory removed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

5. Delete `.mission/` directory entirely: `rm -rf .mission/` — safe because hooks exit early when `active != true`

## Hook Enforcement (v0.3.0)

The phase guard hook (`hooks/phase-guard.sh`) enforces these defense layers at the tool-call level. Even if the Orchestrator, Worker, or Validator forgets a rule, the hook will block the invalid action.

### Defense Layers

| # | Defense | Enforces | Blocks |
|---|---------|----------|--------|
| 1 | Completion Guard | Mission can't complete without valid report | `phase: "complete"` without `.mission/reports/round-N.md` |
| 2 | Mandatory Cleanup Guard | Cleanup before deactivation | `active: false` + `completedAt` without `summary.md` or with leftover worker-logs |
| 3 | Worker Test File Block | Role separation | Workers writing `*.test.*`, `*.spec.*`, `tests/*`, `__tests__/*` |
| 4 | Validator Path Restriction | Role separation | Validators writing to `.mission/` except `.mission/reports/*` |
| 5 | Anti-Premature-Completion | Relentless integrity | Completion in relentless mode when report says FAIL |

These defenses stack with the existing v0.2.0 defenses (phase lock, relentless deactivation block, phase transition validation).

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
