---
name: content-worker
description: Updates markdown content files (agents, skills, commands) and infrastructure config for the Mission Plugin
---

# Content Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Features that involve creating or modifying:
- Agent definition files (agents/orchestrator.md, agents/worker.md, agents/validator.md)
- Skill files (skills/enter-mission/SKILL.md)
- Command files (commands/*.md)
- Infrastructure files (plugin.json, package.json, .github/workflows/ci.yml)
- Documentation files (CLAUDE.md, AGENTS.md, README.md)

## Required Skills

None — direct file editing and content verification.

## Work Procedure

### 1. Understand Context
- Read `.factory/library/architecture.md` for system overview
- Read `AGENTS.md` for coding conventions and v1.0 migration notes
- Read the CURRENT version of each file being modified (ALWAYS re-read before editing)
- Read the feature description carefully — it specifies exact content requirements

### 2. Plan Content Changes
- List all files to modify
- For each file, identify:
  - What must be added (new v1.0 content)
  - What must be preserved (existing v0.5.0 content that's still valid)
  - What must be removed (v0.5.0 content replaced by v1.0)
  - Content requirements from feature description (grep counts, specific phrases)

### 3. Write Content
- For agent definitions:
  - Preserve YAML frontmatter structure
  - Reference features.json as primary tracking mechanism
  - Include structured handoff/validation protocols
  - Maintain existing prohibitions (test block, source write block, etc.)
- For SKILL.md:
  - This is the most critical file — it's the orchestrator's instruction set
  - Must include: anti-drift enforcement, compaction recovery, resume protocol, completion gate
  - features.json schema must be defined
  - State machine table for resume protocol
- For commands:
  - Keep YAML frontmatter
  - Update for v1.0 features (features.json progress, model config)
- For infrastructure:
  - Version bump to 1.0.0
  - Update CI to run all test suites

### 4. Verify Content
- For each file with grep-count requirements, run the grep and verify:
  ```bash
  grep -c 'features.json' agents/orchestrator.md  # expect ≥3
  grep -ci 'forbidden.*writ.*code' agents/orchestrator.md  # expect ≥1
  ```
- Read back the modified file to confirm structure and content
- Check for consistency across related files (e.g., same features.json schema in SKILL.md and orchestrator.md)

### 5. Cross-File Consistency Check
- Verify features.json references are consistent across:
  - SKILL.md (creates it)
  - orchestrator.md (dispatches from it)
  - worker.md (receives from it)
  - validator.md (validates from it)
  - mission-status.md (displays from it)
- Verify model enforcement references are consistent across:
  - mission-config.md (sets it)
  - SKILL.md (reads it)
  - orchestrator.md (uses it in dispatch)

## Example Handoff

```json
{
  "salientSummary": "Rewrote all 3 agent definitions for v1.0. Orchestrator now references features.json 5 times (init, dispatch, tracking, completion gate, resume). Worker has structured JSON handoff protocol. Validator has per-feature validation with assertion tracking. All agents have valid YAML frontmatter. Verified grep counts match requirements.",
  "whatWasImplemented": "agents/orchestrator.md — features.json-based dispatch, structured completion gate, model enforcement acknowledgment. agents/worker.md — JSON handoff protocol, feature-based assignment. agents/validator.md — per-feature validation, assertion tracking, Verdict: PASS/FAIL preserved.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {"command": "grep -c 'features.json' agents/orchestrator.md", "exitCode": 0, "observation": "5 (≥3 required)"},
      {"command": "grep -c 'Verdict: PASS' agents/validator.md", "exitCode": 0, "observation": "2 (both PASS and FAIL mentioned)"},
      {"command": "grep -ci 'forbidden.*writ' agents/orchestrator.md", "exitCode": 0, "observation": "1"}
    ],
    "interactiveChecks": [
      {"action": "Read back orchestrator.md and verified features.json workflow", "observed": "Init creates features.json, dispatch reads it, completion gate checks statuses, resume protocol uses it"},
      {"action": "Cross-checked worker.md handoff format with validator.md validation format", "observed": "Consistent — validator reads handoff fields that worker produces"}
    ]
  },
  "tests": {
    "added": []
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- Feature description requires referencing a mechanism (e.g., features.json schema) that hasn't been defined yet
- Cross-file consistency check reveals contradictions that need architectural decisions
- Existing content has unexpected structure that makes v1.0 migration unclear
- YAML frontmatter format is different from expected
