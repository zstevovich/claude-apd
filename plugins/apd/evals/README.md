# APD Skill Evals

> Scenario-driven evaluations for every shipped skill.
> Authored once here, mirrored into each skill's `evals/` folder by `bin/core/eval-mirror`.

## Layout

```
plugins/apd/evals/
├── README.md              # this file
├── apd-tdd/
│   ├── 01-trivial-fix.json
│   ├── 02-bug-fix-no-test.json
│   └── 03-edge-case-coverage.json
├── apd-debug/...
├── apd-brainstorm/...
├── apd-finish/...
├── apd-audit/...
├── apd-github/...
├── apd-miro/...
└── apd-setup/...           # CC-only skill, evals still here for completeness
```

24 scenarios total (8 skills × 3). Each scenario is runtime-agnostic — the
runner spawns either `claude -p` (CC) or `codex exec` (Codex) depending on
`--runtime`.

## Scenario schema

```json
{
  "id": "apd-tdd-01-trivial-fix",
  "skill": "apd-tdd",
  "runtime": "both",
  "description": "Implement a trivial helper — should write the failing test first",
  "query": "Add a function add(a, b) that returns a + b in src/math.ts",
  "files": {
    "src/math.ts": "// existing helper module — add helpers here\n"
  },
  "expected_behavior": [
    "writes a failing test before any production code",
    "runs the test and observes it fail",
    "writes the minimal implementation to turn the test green",
    "does not bundle unrelated changes into the same edit"
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique across all scenarios. Convention: `<skill>-<NN>-<slug>` |
| `skill` | yes | Must match a shipped skill name |
| `runtime` | yes | `cc`, `codex`, or `both` |
| `description` | yes | One-line summary used in the runner output |
| `query` | yes | The user prompt that should trigger the skill |
| `files` | yes | Map of `path → content` to seed in the scratch dir before spawning the agent |
| `expected_behavior` | yes | Plain-English assertions; both the rubric and the LLM judge consume them |

## Runner

```
plugins/apd/bin/core/skill-eval [options] [skill | scenario.json]

  --list                List all scenarios (no execution)
  --dry-run             Validate JSON, print summary, no agent spawn
  --rubric              Keyword-match expected_behavior against the captured transcript
  --judge               LLM-as-judge — asks claude -p whether each behavior occurred
  --runtime cc|codex    Which runtime to spawn (default: cc)
  -h, --help            Show help

Examples:
  skill-eval --list
  skill-eval --dry-run apd-tdd
  skill-eval --rubric --runtime cc apd-debug
  skill-eval --judge plugins/apd/evals/apd-finish/02-verifier-red.json
```

## Judge modes

**Rubric (default for CI / fast checks).** Each `expected_behavior` is matched
as a case-insensitive substring or regex against the captured agent transcript.
Cheap and deterministic, but loose — passes on superficial mentions.

**LLM-as-judge (default for skill authors when iterating).** The runner asks
`claude -p` "Did the agent satisfy this behavior?" once per assertion, with the
full transcript attached. More accurate, costs ~1–2 messages per scenario.

When in doubt about a result, re-run with `--judge`. Rubric mode is the floor;
the judge is the ceiling.

## When to add scenarios

- A skill is created or its method changes substantially → author 3 scenarios
  covering the happy path, an edge case, and a hand-off into another skill
- A real-world failure surfaces a behavioral gap → write a scenario that
  reproduces the gap, then fix the skill until the eval passes
- Renaming or splitting a skill → re-author scenarios; update `id` and `skill`

## What this is NOT

- A unit-test substitute — `verify-apd` and `test-codex-adapter` cover that
- A pipeline gate — evals are advisory, run on demand by skill authors
- A way to score Claude — they score the SKILL, not the model
