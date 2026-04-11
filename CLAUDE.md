# APD Framework

> Agent Pipeline Development — Claude Code plugin for disciplined AI-assisted software development.

## Critical Rules

- **Language:** Documentation and communication in English. Code, commit messages, and README in English.
- **Author:** Zoran Stevovic — NO AI signatures/watermarks
- **Style:** Professional, concise, human style
- **This is a FRAMEWORK project** — not an application. Do not use the APD pipeline to work on APD itself.

## Stack

| Layer | Technology |
|-------|------------|
| Runtime | Bash scripts (POSIX-compatible where possible) |
| Config | JSON (settings.json, plugin.json), YAML frontmatter (agents, skills) |
| Docs | Markdown |
| CI | GitHub Actions |
| Pipeline enforcement | Go (compiled binaries) |
| Distribution | Claude Code plugin (`/plugin install claude-apd@zstevovich-plugins`) |

## Architecture

```
apd-template/
├── bin/
│   ├── apd               # Single entry point
│   ├── core/             # Guard and pipeline scripts
│   ├── compiled/         # Go binaries (validate-agent-*)
│   └── lib/              # Shared libraries (resolve-project.sh, style.sh)
├── hooks/
│   └── hooks.json        # Plugin hook configuration
├── rules/
│   └── workflow.md       # APD workflow rules (copied to project by /apd-setup)
├── skills/               # Claude Code skills
│   ├── apd-setup/        # Project initialization and maintenance
│   ├── apd-brainstorm/   # Pre-spec clarification
│   ├── apd-tdd/          # TDD implementation skill
│   ├── apd-debug/        # Root cause analysis
│   ├── apd-finish/       # Post-commit decision
│   ├── apd-audit/        # Project configuration audit
│   ├── apd-github/       # GitHub Projects integration
│   └── apd-miro/         # Miro dashboard
├── templates/            # Templates for per-project generation
│   ├── CLAUDE.md.reference
│   ├── memory/
│   ├── principles/
│   └── verify-all/
├── examples/             # Example configurations per stack
│   └── nodejs-react/
├── docs/
│   ├── adr/
│   └── demo/
├── CHANGELOG.md
├── GETTING-STARTED.md
└── README.md
```

## Development Conventions

### Scripts
- All scripts must work with `${CLAUDE_PLUGIN_ROOT}` for paths to plugin files
- `resolve-project.sh` (lib/) resolves `PROJECT_DIR` and `APD_PLUGIN_ROOT` — all scripts source it
- Scripts communicate via exit codes and stdout messages
- Guard scripts: exit 2 = BLOCK, exit 0 = ALLOW
- Every script must have a description at the top (comment)

### Skills
- Each skill in its own directory: `skills/{skill-name}/SKILL.md`
- YAML frontmatter with name, description, effort

### Templates
- Placeholders: `{{PLACEHOLDER_NAME}}` format
- `/apd-setup` skill replaces placeholders

### Agents
- `templates/agent-template.md` is the master template — concrete agents are generated per project
- Hook paths use `${CLAUDE_PLUGIN_ROOT}`
- Scope paths in comment: `# {{SCOPE_PATHS}}`

### Git
- No AI signatures in commits
- Commit messages: short, in English, imperative mood
- Branch: main

### Testing
- `verify-apd` is the E2E test for the entire framework (50+ checks)
- `test-hooks` is the quick static test
- After every change to scripts: run `bash bin/core/verify-apd` in the example project

## Versioning

- Current version: v4.3.3
- CHANGELOG.md tracks all changes
- Semantic versioning: major (breaking), minor (feature), patch (fix)

## Memory

@.claude/memory/MEMORY.md
@.claude/memory/status.md

## Anti-patterns

```
❌ Hardcoded project paths             → ✅ ${CLAUDE_PLUGIN_ROOT} and resolve-project.sh
❌ AI signatures in code/documentation → ✅ Human style
❌ Changing universal files            → ✅ Distinguish UNIVERSAL vs CUSTOMISE
❌ Placeholder left unfilled           → ✅ verify-apd.sh detects it
❌ Script without description at top   → ✅ Every script has a comment header
```
