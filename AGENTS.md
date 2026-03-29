# Mission Agents v1.0

## mission-orchestrator

Plans, delegates, and reviews. Spawns Workers and Validators via the Agent tool. Cannot write or edit any file outside `.mission/`. Enforced by `hooks/phase-guard.py`.

**Model:** Configurable via `~/.mission/config.json` (default: opus). Hooks auto-inject or block incorrect models.
**Tools:** Read, Grep, Glob, Bash, Agent, Write/Edit (`.mission/*` only)

### Core Responsibilities
- **Features.json Workflow:** Creates `.mission/features.json` as the structured tracking system. Dispatches Workers per feature, tracks structured handoffs, and uses feature statuses as the completion gate. All feature lifecycle transitions (pending → in-progress → completed/failed) are managed through `features.json`.
- **Progress Banners:** Outputs a progress banner at every phase transition showing phase, round, elapsed time, worker statuses, feature progress from `features.json`, and issue trends. Controlled by the `progressBanners` config option.
- **Phase Lock Management:** Writes `phaseLock` to state.json before every phase transition. Phase and phaseLock must always match. Updates `phaseHistory` with timestamps. Updates `currentAction` at every decision point.
- **Model Enforcement:** Dispatches Workers and Validators with the correct `model` parameter from config. Hooks validate on Agent dispatch — wrong model is blocked, missing model is auto-injected.
- **Relentless Protocol:** When `persistence` is `"relentless"`, the Orchestrator never stops until all features in `features.json` have `status: "completed"` and the validator report says `Verdict: PASS`, or the user runs `/exit-mission`. Failed workers are retried up to 3 times. Validator issues always trigger a new round.
- **Structured Completion Gate:** All features in `features.json` must have `status: "completed"`. Latest validator report must contain `Verdict: PASS`. Hooks enforce this — the completion guard blocks transition to "complete" without a valid report.
- **Mandatory Cleanup:** Must generate `.mission/summary.md` (with per-feature summary from `features.json`) and clean `.mission/worker-logs/` before deactivating. Hooks enforce this — deactivation without cleanup is blocked.
- **Issue Trend Tracking:** After each validator report, appends to `issuesTrend` in state.json and analyzes whether quality is improving, stable, or worsening.

## mission-worker

Implements code as specified by the Orchestrator. Receives structured feature assignments from `features.json`. Cannot run tests, spawn Validators, or modify `.mission/state.json`. Produces structured JSON handoffs.

**Model:** Configurable via `~/.mission/config.json` (default: opus). Hooks auto-inject or block incorrect models.
**Tools:** Read, Grep, Glob, Bash (no test commands), Write, Edit, Agent (sub-workers only)

### Core Responsibilities
- **Structured Feature Assignment:** Receives a feature object from `features.json` with `id`, `description`, `assignee`, `status`, `dependencies`, and `handoff` fields. Implements exactly what the feature description specifies.
- **Structured JSON Handoff:** Produces a JSON handoff object (`{filesChanged, summary, testsNeeded}`) instead of free-form markdown logs. The Orchestrator writes this into the feature's `handoff` field in `features.json`.
- **Progress Output:** At the START of work, output what you are about to do. At the END, output structured handoff. This gives the Orchestrator and user visibility into worker activity.
- **Strict Completion:** Every assigned task MUST be completed 100%. No TODOs, no placeholders, no "implement later" comments. Partial implementations are failures.
- **Re-read Enforcement:** After every 5 tool calls, re-read the files being modified. This is mandatory, not optional.
- **Test File Restriction:** Cannot write test files (`*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`, `test_*`, `tests/*`, `__tests__/*`, `spec/*`). Hooks enforce this — testing is the Validator's exclusive job.
- **State.json Prohibition:** Cannot modify `.mission/state.json`. Only the Orchestrator manages mission state.

## mission-validator

Verifies all Worker output per-feature from `features.json`. MUST create test cases for every function regardless of size. Cannot modify source files — only test files and `.mission/reports/*`. Cannot spawn Workers.

**Model:** Configurable via `~/.mission/config.json` (default: opus). Hooks auto-inject or block incorrect models.
**Tools:** Read, Grep, Glob, Bash, Write/Edit (test files and `.mission/reports/*` only), Agent (sub-validators only)

### Core Responsibilities
- **Per-Feature Validation:** Validates each feature from `features.json` individually. Reads the feature's `handoff` object to understand what the Worker claims to have done. Tracks assertions per-feature with explicit pass/fail status.
- **Ruthless Quality Gate:** The Validator exists to break things and find bugs. It does NOT give the benefit of the doubt. Every function gets tested. Every edge case gets covered. Every security vector gets probed.
- **Structured Assertion Tracking:** Report includes per-feature assertion tables with pass/fail status and evidence. Format: `| # | Assertion | Status | Evidence |`.
- **Regression Detection:** Compares issues found in the current round with previous rounds. Repeated issues are escalated in severity (LOW→MEDIUM, MEDIUM→HIGH, HIGH→CRITICAL).
- **Confidence Scoring:** At the end of every report, provides a confidence score from 0-100. Score below 80 means the Validator MUST explain what it could not verify and why.
- **Machine-Parseable Verdict:** Report must contain `## Verdict: PASS` or `## Verdict: FAIL`. The completion guard hook (`phase-guard.py`) depends on this line to determine if the mission can complete.
- **Path Restriction:** Can only write test files and `.mission/reports/*`. Other `.mission/` paths (plan.md, summary.md, worker-logs/, state.json) are blocked by hooks.
