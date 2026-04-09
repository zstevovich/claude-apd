# Agent Pipeline Development (APD) v4.0.0

Enforced multi-agent pipelines with mechanical guardrails for AI-assisted software development. Distributed as a Claude Code plugin.

[**Getting Started**](GETTING-STARTED.md) | [**Interactive Demo**](https://zstevovich.github.io/claude-apd/demo/) | [**Changelog**](CHANGELOG.md)

![APD Demo](docs/demo/apd-demo.gif)

---

## What is APD?

APD enforces a disciplined workflow where specialised agents build code through a gated pipeline. Every step is mechanically enforced — hooks block violations, not documentation.

```
Spec → Builder → Reviewer → [Adversarial] → Verifier → Commit
```

- **Agent** — work divided among specialised agents with scoped permissions
- **Pipeline** — gated flow with mechanical enforcement at every step
- **Development** — one feature = one pipeline cycle = one commit

## Quick start

```bash
/plugin marketplace add zstevovich/claude-apd          # one time
/plugin install claude-apd@zstevovich-plugins           # per project
/apd-setup                                              # configure
bash .claude/bin/apd verify                             # check setup
```

See [Getting Started](GETTING-STARTED.md) for the full walkthrough.

## Five roles

| Role | Model | Effort | Responsibility |
|------|-------|--------|----------------|
| **Orchestrator** | opus | max | Coordinates pipeline, writes spec, dispatches agents, commits |
| **Builder** | sonnet | high | Implements code per spec, scoped to specific files |
| **Reviewer** | opus | max | Finds bugs, security issues, edge cases (read-only) |
| **Adversarial Reviewer** | sonnet | max | Context-free review — no spec knowledge, fresh perspective |
| **Verifier** | — | — | Script: build + test + spec traceability check |

## Pipeline flow

```mermaid
graph LR
    SPEC["Spec"] --> PLAN["Plan"] --> BUILDER["Builder"] --> REVIEWER["Reviewer"]
    REVIEWER -->|"fix"| BUILDER
    REVIEWER -->|"OK"| ADV["Adversarial"]
    ADV --> VERIFIER["Verifier"]
    VERIFIER --> COMMIT["Commit"]

    style SPEC fill:#4da6ff,stroke:#0073e6,color:#fff
    style PLAN fill:#4da6ff,stroke:#0073e6,color:#fff
    style BUILDER fill:#66cc66,stroke:#339933,color:#fff
    style REVIEWER fill:#ff884d,stroke:#cc5500,color:#fff
    style ADV fill:#ff6666,stroke:#cc0000,color:#fff
    style VERIFIER fill:#66cc66,stroke:#339933,color:#fff
    style COMMIT fill:#555,stroke:#333,color:#fff
```

### Pipeline commands

```bash
apd pipeline spec "Task name"     # Start task (requires spec-card.md with R* criteria)
apd pipeline builder              # Advance after builder (requires implementation-plan.md)
apd pipeline reviewer             # Advance after review
apd pipeline verifier             # Run verification (spec traceability + build + test)
apd pipeline status               # Show current state
apd pipeline rollback             # Undo last step
apd pipeline metrics              # Performance dashboard
apd doctor                        # Full diagnostics
apd verify                        # Setup verification (50+ checks)
```

All commands via: `bash .claude/bin/apd <command>`

## Mechanical enforcement

Every rule is backed by a hook script that **blocks** violations. No bypass from within Claude Code.

| What is blocked | Guard |
|----------------|-------|
| Commit without all 4 pipeline steps | `pipeline-gate` |
| Orchestrator writes code files directly | `guard-orchestrator` |
| Agent writes outside its scope | `guard-scope` |
| Bash writes to pipeline state (.done, .agents) | `guard-bash-scope` + `guard-pipeline-state` |
| Direct Write/Edit to .pipeline/ state files | `guard-pipeline-state` |
| `git commit` without `APD_ORCHESTRATOR_COMMIT=1` | `guard-git` |
| `git add .` / mass staging | `guard-git` |
| `--no-verify` / force push / destructive git ops | `guard-git` |
| Lock file modification | `guard-lockfile` |
| Access to sensitive files (.env, .pem, credentials) | `guard-secrets` |
| Superpowers agents replacing APD roles | `pipeline-advance` (agent type check) |
| Spec modified mid-pipeline | `pipeline-advance` (sha256 hash freeze) |
| More than 7 acceptance criteria per spec | `pipeline-advance` (forces decomposition) |
| Builder dispatch without implementation plan | `pipeline-advance` (hard block) |

## Spec traceability

Acceptance criteria get R* IDs. Builders add `@trace R*` markers in test files. Verification blocks commit if any criterion lacks test coverage.

```markdown
# .pipeline/spec-card.md
**Acceptance criteria:**
- R1: Login endpoint returns JWT
- R2: Invalid credentials return 401
- R3: Password compared via bcrypt
```

```typescript
// @trace R1 R2
test('login returns JWT on valid credentials', () => { ... });
test('login returns 401 on invalid credentials', () => { ... });

// @trace R3
test('password verified via bcrypt', () => { ... });
```

## Implementation plan

Orchestrator writes `.pipeline/implementation-plan.md` before dispatching builder — lists files to change with 1-2 sentences each, plus `### Agents` section.

```markdown
## Implementation Plan: Add user login

### Agents
- backend-api

### Files to create
- `src/Auth/LoginHandler.cs` — POST endpoint, validates credentials, returns JWT

### Files to modify
- `src/Auth/AuthModule.cs` — register the new endpoint
```

## Project structure

### Plugin (installed via `/plugin install`)

```
${CLAUDE_PLUGIN_ROOT}/
├── bin/
│   ├── apd                        # Single entry point
│   ├── core/                      # All executable scripts (no .sh)
│   │   ├── pipeline-advance       # Pipeline state machine
│   │   ├── pipeline-doctor        # Diagnostics
│   │   ├── pipeline-gate          # Commit gate
│   │   ├── guard-git              # Git operations guard
│   │   ├── guard-scope            # File scope per agent
│   │   ├── guard-bash-scope       # Bash write protection
│   │   ├── guard-orchestrator     # Blocks orchestrator code writes
│   │   ├── guard-pipeline-state   # Protects .pipeline/ state files
│   │   ├── guard-secrets          # Sensitive file protection
│   │   ├── guard-lockfile         # Lock file protection
│   │   ├── verify-trace           # Spec traceability checker
│   │   ├── verify-apd             # Full setup verification
│   │   ├── verify-contracts       # Cross-layer type checker
│   │   ├── track-agent            # Agent lifecycle tracking
│   │   ├── gh-sync                # GitHub Projects sync
│   │   ├── session-start          # Context loader + self-healing
│   │   └── ...
│   └── lib/                       # Shared libraries (.sh)
│       ├── resolve-project.sh
│       └── style.sh
├── hooks/hooks.json               # Plugin hook definitions
├── rules/workflow.md              # Pipeline workflow rules
├── templates/                     # Agent + project templates
└── skills/                        # 8 skills (brainstorm, tdd, debug, finish, setup, audit, github, miro)
```

### Your project (generated by `/apd-setup`)

```
my-project/
├── CLAUDE.md                      # Project instructions
├── .claude/
│   ├── agents/                    # One .md per agent with scoped hooks
│   ├── bin/
│   │   └── apd                    # Shortcut to plugin entry point
│   ├── scripts/
│   │   └── verify-all.sh          # Build + test commands (project-specific)
│   ├── rules/
│   │   ├── workflow.md            # Pipeline workflow
│   │   └── principles.md          # Code conventions
│   ├── memory/                    # Session log, status, metrics
│   └── .pipeline/                 # Ephemeral pipeline state (gitignored)
└── docs/adr/                      # Architecture Decision Records
```

## Integrations (optional)

| Integration | What it does | Setup |
|-------------|-------------|-------|
| **GitHub Projects** | Auto-syncs pipeline steps to board columns (Spec → In Progress → Review → Testing → Done) | Configure `.mcp.json` + `gh auth login` |
| **Figma** | Frontend builders get design context via MCP | Configure Figma MCP server |
| **Miro** | Orchestrator reads boards for spec input, pushes pipeline dashboard | `claude mcp add --transport http miro https://mcp.miro.com` |

## Human gate

User MUST approve before: API changes, database migrations, auth/role logic, deploy to production.

## Agent scope example

```yaml
# .claude/agents/backend-api.md
hooks:
  PreToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/bin/core/guard-scope src/ tests/"
```

Agent writing to `apps/frontend/App.tsx`:
```
BLOCKED: File apps/frontend/App.tsx is outside the allowed scope.
Allowed paths: src/ tests/
```

## Skills

| Skill | When | Required? |
|-------|------|-----------|
| `/apd-brainstorm` | Before spec — vague or complex task | Mandatory |
| `/apd-tdd` | During builder implementation | Mandatory |
| `/apd-debug` | On verifier failure or critical review finding | Mandatory |
| `/apd-finish` | After successful commit | Mandatory |
| `/apd-setup` | Project initialization and maintenance | On setup |
| `/apd-audit` | Qualitative framework audit | Optional |
| `/apd-github` | GitHub Projects board sync | Optional |
| `/apd-miro` | Miro dashboard updates | Optional |

## Real-world results

See [Pipeline Runs](docs/pipeline-runs.md) for tracked production results with metrics.

## Plugin compatibility

APD mechanically blocks `superpowers:*` agents — the two pipelines are incompatible. APD includes its own equivalents: brainstorming, TDD, debugging, code review, verification, and finish workflows.

Other plugins (Figma, context7, etc.) work alongside APD without conflicts.

## License

MIT — Zoran Stevovic
