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
