# Mission Agents

## mission-orchestrator

Plans, delegates, and reviews. Spawns Workers and Validators via the Agent tool. Cannot write or edit any file outside `.mission/`. Enforced by hooks.

**Model:** Configurable (default: opus)
**Tools:** Read, Grep, Glob, Bash, Agent, Write/Edit (`.mission/*` only)

**v0.2.0 Responsibilities:**
- **Progress Banners:** Outputs a progress banner at every phase transition showing phase, round, elapsed time, worker statuses, and issue trends. Controlled by the `progressBanners` config option.
- **Phase Lock Management:** Writes `phaseLock` to state.json before every phase transition. Phase and phaseLock must always match. Updates `phaseHistory` with timestamps. Updates `currentAction` at every decision point.
- **Relentless Protocol:** When `persistence` is `"relentless"`, the Orchestrator never stops until all checks pass or the user runs `/exit-mission`. Round and duration limits become soft warnings. Failed workers are retried up to 3 times. Validator issues always trigger a new round.
- **Issue Trend Tracking:** After each validator report, appends to `issuesTrend` in state.json and analyzes whether quality is improving, stable, or worsening.

**v0.3.0 Responsibilities:**
- **Mandatory Cleanup:** Must generate `.mission/summary.md` and clean `.mission/worker-logs/` before deactivating. Hooks enforce this — deactivation without cleanup is blocked.
- **Completion Verification:** Cannot transition to "complete" phase without a validator report. In relentless mode, report must say "Verdict: PASS".

## mission-worker

Implements code as specified by the Orchestrator. Must read all relevant files before writing. Cannot run tests, spawn Validators, or modify `.mission/state.json`.

**Model:** Configurable (default: opus)
**Tools:** Read, Grep, Glob, Bash (no test commands), Write, Edit, Agent (sub-workers only)

**v0.2.0 Responsibilities:**
- **Progress Output:** At the START of work, output what you are about to do. At the END, output what you did. This gives the Orchestrator and user visibility into worker activity.
- **Strict Completion:** Every assigned task MUST be completed 100%. No TODOs, no placeholders, no "implement later" comments. Partial implementations are failures.
- **Re-read Enforcement:** After every 5 tool calls, re-read the files being modified. This is mandatory, not optional.

**v0.3.0 Responsibilities:**
- **Test File Restriction:** Cannot write test files (*.test.*, *.spec.*, tests/*, __tests__/*). Hooks enforce this — testing is the Validator's exclusive job.

## mission-validator

Verifies all Worker output. MUST create test cases for every function regardless of size. Cannot modify source files — only test files and `.mission/reports/*`. Cannot spawn Workers.

**Model:** Configurable (default: opus)
**Tools:** Read, Grep, Glob, Bash, Write/Edit (test files and reports only), Agent (sub-validators only)

**v0.2.0 Responsibilities:**
- **Ruthless Quality Gate:** The Validator exists to break things and find bugs. It does NOT give the benefit of the doubt. It does NOT accept "good enough". Every function gets tested. Every edge case gets covered. Every security vector gets probed.
- **Regression Detection:** Compares issues found in the current round with previous rounds. If the SAME issue appears again, severity is escalated by one level (LOW to MEDIUM, MEDIUM to HIGH, HIGH to CRITICAL). Repeated issues indicate systemic failure.
- **Confidence Scoring:** At the end of every report, provides a confidence score from 0-100. A score below 80 means the Validator is NOT confident and MUST explain what it could not verify and why.
- **Progress Output:** Outputs what it is validating at each step so the Orchestrator and user have visibility into the validation process.

**v0.3.0 Responsibilities:**
- **Machine-Parseable Verdict:** Report must contain `## Verdict: PASS` or `## Verdict: FAIL`. The completion guard hook depends on this.
- **Path Restriction:** Can only write to `.mission/reports/*` under `.mission/`. Other `.mission/` paths (plan.md, summary.md, worker-logs/) are blocked by hooks.
