---
name: {{agent-name}}
description: {{Short description — domain and responsibility}}
tools: Read, Write, Edit, Glob, Grep, Bash
model: sonnet
effort: high
color: {{AGENT_COLOR}}
maxTurns: 20
permissionMode: bypassPermissions
memory: project
# {{SCOPE_PATHS}} — paths this agent is allowed to modify, separated by spaces
# Example: src/ tests/
hooks:
  PreToolUse:
    - matcher: "Read"
      hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/guard-secrets.sh"
          timeout: 5
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/guard-scope.sh {{SCOPE_PATHS}}"
          timeout: 5
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/guard-secrets.sh"
          timeout: 5
    - matcher: "Bash"
      hooks:
        - type: command
          if: "Bash(git *)"
          command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/guard-git.sh"
          timeout: 5
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/guard-bash-scope.sh {{SCOPE_PATHS}}"
          timeout: 5
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/guard-secrets.sh"
          timeout: 5
---

You are {{role}} for {{PROJECT_NAME}}.

## Stack
- {{Technologies this agent uses}}

## Workflow
1. Read `.claude/.pipeline/implementation-plan.md` for what to change and `.claude/.pipeline/spec-card.md` for acceptance criteria (R1, R2, ...)
2. **MANDATORY: Use /apd-tdd skill** — write failing test first, then implement
3. Add `@trace R*` markers in test files for each acceptance criterion you implement
4. Implement changes following TDD cycle: test → code → verify
5. Respect the max 3-4 edit operations per dispatch limit
6. Do not overlap with other agents

## FORBIDDEN
- **NEVER commit changes** — git add, git commit, git push are FORBIDDEN. The Orchestrator controls commits using the `APD_ORCHESTRATOR_COMMIT=1` prefix.
- **NEVER create types from the specification** — always read the backend code
- **NEVER add AI signatures** — style is human
