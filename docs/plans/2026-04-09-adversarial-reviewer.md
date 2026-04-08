# Adversarial Reviewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional context-free code reviewer that runs after the regular reviewer, with hit rate metrics tracking.

**Architecture:** New agent template (`adversarial-reviewer-template.md`) with `memory: none` and `model: sonnet`. Workflow.md updated with step 6b and new role. Pipeline-advance.sh extended to read `.adversarial-summary` for session-log and cumulative metrics.

**Tech Stack:** Bash, Markdown (agent template + workflow rules)

---

### Task 1: Create adversarial-reviewer-template.md

**Files:**
- Create: `templates/adversarial-reviewer-template.md`

- [ ] **Step 1: Create the agent template**

```markdown
---
name: adversarial-reviewer
description: Context-free code reviewer — finds issues that contextual reviewers miss
tools: Read, Glob, Grep, Bash
model: sonnet
effort: max
color: red
maxTurns: 15
permissionMode: plan
memory: none
hooks:
  PreToolUse:
    - matcher: "Read"
      hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/guard-secrets.sh"
          timeout: 5
    - matcher: "Bash"
      hooks:
        - type: command
          if: "Bash(git *)"
          command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/guard-git.sh"
          timeout: 5
---

You are the adversarial code reviewer for {{PROJECT_NAME}}.

## Your role

You review code changes with **zero context** about the task or specification. You don't know why these changes were made — you judge the code purely on its own merit. This intentional blindness helps you catch issues that contextual reviewers miss.

## What you receive

The orchestrator gives you a list of changed files. Read each file in full.

## What to check

1. **Bugs** — logic errors, off-by-one, null handling, race conditions
2. **Security** — injection, XSS, auth bypass, data leaks
3. **Edge cases** — empty input, boundary values, error paths
4. **Design** — unclear names, tight coupling, missing abstractions
5. **Missed tests** — untested code paths, weak assertions

## What NOT to do

- Do NOT ask what the task was or why changes were made
- Do NOT suggest style changes (formatting, naming conventions)
- Do NOT flag things that are clearly intentional design choices
- Do NOT recommend refactoring outside the changed files
- Do NOT commit, push, or modify any files

## Output format

```
## Adversarial Review

### Findings
1. [file:line] HIGH — Description of the bug/vulnerability
2. [file:line] MEDIUM — Description of the risk
3. [file:line] LOW — Description of the issue

### Summary
X findings (N high, M medium, K low)
```

If no issues found: `### Summary: No issues found — code looks solid.`
```

- [ ] **Step 2: Verify the template renders valid YAML frontmatter**

Run: `head -20 templates/adversarial-reviewer-template.md`
Expected: Valid YAML frontmatter with `name: adversarial-reviewer`, `model: sonnet`, `effort: max`, `memory: none`

---

### Task 2: Update workflow.md — flow diagram and step 6b

**Files:**
- Modify: `rules/workflow.md:22-35` (flow diagram and steps)

- [ ] **Step 1: Add step 6b to the flow diagram**

In the flow diagram (lines 5-35), change:

```
6. DISPATCH REVIEWER AGENT — opus/max, read-only, finds bugs
   → pipeline-advance.sh reviewer (after reviewer completes)
   → If reviewer finds critical issues → dispatch builder to fix → re-review
   ↓
7. RUN VERIFIER — build + test
```

To:

```
6. DISPATCH REVIEWER AGENT — opus/max, read-only, finds bugs
   → pipeline-advance.sh reviewer (after reviewer completes)
   → If reviewer finds critical issues → dispatch builder to fix → re-review
   ↓
6b. DISPATCH ADVERSARIAL REVIEWER (optional, recommended)
   → Dispatch adversarial-reviewer agent (sonnet/max, read-only, no spec context)
   → Agent sees only git diff + touched files, finds issues blind
   → Orchestrator evaluates findings: accept or dismiss each
   → Write ADVERSARIAL:total:accepted:dismissed to .pipeline/.adversarial-summary
   → If accepted findings → fix via builder → re-review
   ↓
7. RUN VERIFIER — build + test
```

- [ ] **Step 2: Verify the flow diagram is consistent**

Run: `head -40 rules/workflow.md`
Expected: Steps 1-9 with new 6b inserted between 6 and 7

---

### Task 3: Update workflow.md — new role and model table

**Files:**
- Modify: `rules/workflow.md:122-161` (roles section)

- [ ] **Step 1: Change section heading from "Four roles" to "Five roles"**

Change line 122:
```
## 2. Four roles — strict model and effort enforcement
```
To:
```
## 2. Five roles — strict model and effort enforcement
```

- [ ] **Step 2: Add Adversarial Reviewer role after Reviewer section**

After the Reviewer section (after line 147 `- Reports findings to orchestrator who decides action`), before the Verifier section (line 149), insert:

```markdown

### Adversarial Reviewer (dispatched agent)
- **Model:** sonnet | **Effort:** max
- Context-free — sees only code changes, not the spec or task
- Finds bugs that contextual reviewers miss by not knowing intent
- Findings are advisory — orchestrator decides what to act on
- Runs AFTER regular reviewer, BEFORE verifier
- Orchestrator tracks hit rate: accepted vs dismissed findings
```

- [ ] **Step 3: Add Adversarial Reviewer to model table**

In the model table (lines 156-161), add a new row after the Reviewer row:

Change:
```
| Reviewer | opus | max | Finding bugs, security issues — must be thorough |
| Verifier | — | — | Script, not a model — runs build + test |
```

To:
```
| Reviewer | opus | max | Finding bugs, security issues — must be thorough |
| Adversarial Reviewer | sonnet | max | Fresh eyes, different model = different blind spots |
| Verifier | — | — | Script, not a model — runs build + test |
```

- [ ] **Step 4: Verify the roles section**

Run: `grep -n "roles\|Model.*Effort\|Adversarial" rules/workflow.md`
Expected: Section says "Five roles", table has Adversarial Reviewer row

---

### Task 4: Update pipeline-advance.sh — adversarial metrics in reset

**Files:**
- Modify: `scripts/pipeline-advance.sh:338-360` (reset case, session-log and cleanup)

- [ ] **Step 1: Add adversarial summary reading after trace coverage section**

After the trace coverage section (after line 338 `fi` that closes the trace coverage block), before the "Generate entry" comment (line 340), insert:

```bash
                # 8. Adversarial review hit rate
                ADV_REVIEW=""
                if [ -f "$PIPELINE_DIR/.adversarial-summary" ]; then
                    ADV_LINE=$(cat "$PIPELINE_DIR/.adversarial-summary")
                    # Format: ADVERSARIAL:total:accepted:dismissed
                    ADV_TOTAL=$(echo "$ADV_LINE" | cut -d: -f2)
                    ADV_ACCEPTED=$(echo "$ADV_LINE" | cut -d: -f3)
                    ADV_DISMISSED=$(echo "$ADV_LINE" | cut -d: -f4)
                    if [ -n "$ADV_TOTAL" ] && [ "$ADV_TOTAL" != "0" ]; then
                        ADV_REVIEW="${ADV_TOTAL} findings (${ADV_ACCEPTED} accepted, ${ADV_DISMISSED} dismissed)"
                    fi
                fi
```

- [ ] **Step 2: Add Adversarial review line to session-log heredoc**

In the heredoc (starts at line 341), add after the `**Spec coverage:**` line:

Change:
```
**Spec coverage:** ${TRACE_COVERAGE:-N/A}
**What was done:** $CHANGED_SUMMARY
```

To:
```
**Spec coverage:** ${TRACE_COVERAGE:-N/A}
**Adversarial review:** ${ADV_REVIEW:-N/A}
**What was done:** $CHANGED_SUMMARY
```

- [ ] **Step 3: Add adversarial columns to metrics log**

Change the metrics log line (line 227):

From:
```bash
            echo "${NOW}|${TASK_NAME}|${SPEC_TS_V}|${BUILDER_TS_V}|${REVIEWER_TS_V}|${VERIFIER_TS_V}|${STATUS}" >> "$METRICS_LOG"
```

To:
```bash
            # Read adversarial stats for metrics
            ADV_T=0; ADV_A=0; ADV_D=0
            if [ -f "$PIPELINE_DIR/.adversarial-summary" ]; then
                ADV_T=$(cat "$PIPELINE_DIR/.adversarial-summary" | cut -d: -f2 2>/dev/null || echo 0)
                ADV_A=$(cat "$PIPELINE_DIR/.adversarial-summary" | cut -d: -f3 2>/dev/null || echo 0)
                ADV_D=$(cat "$PIPELINE_DIR/.adversarial-summary" | cut -d: -f4 2>/dev/null || echo 0)
            fi
            echo "${NOW}|${TASK_NAME}|${SPEC_TS_V}|${BUILDER_TS_V}|${REVIEWER_TS_V}|${VERIFIER_TS_V}|${STATUS}|${ADV_T}|${ADV_A}|${ADV_D}" >> "$METRICS_LOG"
```

- [ ] **Step 4: Add .adversarial-summary to cleanup lines**

In the reset cleanup line (line 360), change:

```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary"
```

To:
```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary"
```

In the spec cleanup line (line 71), change:

```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/spec-card.md"
```

To:
```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary" "$PIPELINE_DIR/spec-card.md"
```

In the rollback verifier cleanup (line 371), change:

```bash
                [ "$step" = "verifier" ] && rm -f "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.trace-summary"
```

To:
```bash
                [ "$step" = "verifier" ] && rm -f "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary"
```

- [ ] **Step 5: Verify pipeline-advance.sh syntax**

Run: `bash -n scripts/pipeline-advance.sh`
Expected: No output (syntax OK)

---

### Task 5: Update pipeline-advance.sh — adversarial hit rate in metrics display

**Files:**
- Modify: `scripts/pipeline-advance.sh:498-502` (metrics display section)

- [ ] **Step 1: Add adversarial hit rate to metrics output**

After the "Average per step" section in the metrics case (after the `reviewer → verifier` line), add a new section:

```bash
        # Adversarial hit rate (cumulative)
        ADV_TOTAL_SUM=0
        ADV_ACCEPTED_SUM=0
        ADV_TASKS=0
        while IFS='|' read -r _ts _task _s _b _r _v _status adv_t adv_a adv_d; do
            adv_t=$(echo "${adv_t:-0}" | tr -d '[:space:]')
            adv_a=$(echo "${adv_a:-0}" | tr -d '[:space:]')
            [ "$adv_t" -gt 0 ] 2>/dev/null && {
                ADV_TOTAL_SUM=$((ADV_TOTAL_SUM + adv_t))
                ADV_ACCEPTED_SUM=$((ADV_ACCEPTED_SUM + adv_a))
                ADV_TASKS=$((ADV_TASKS + 1))
            }
        done < "$METRICS_LOG"

        if [ "$ADV_TASKS" -gt 0 ]; then
            ADV_RATE=$((ADV_ACCEPTED_SUM * 100 / ADV_TOTAL_SUM))
            section "Adversarial review"
            printf "    %-22s %s\n" "Hit rate:" "${ADV_RATE}% (${ADV_ACCEPTED_SUM}/${ADV_TOTAL_SUM} accepted across ${ADV_TASKS} tasks)"
        fi
```

- [ ] **Step 2: Verify pipeline-advance.sh syntax**

Run: `bash -n scripts/pipeline-advance.sh`
Expected: No output (syntax OK)

---

### Task 6: Verify complete implementation

- [ ] **Step 1: Verify all modified files syntax**

Run: `bash -n scripts/pipeline-advance.sh`
Expected: No output

- [ ] **Step 2: Verify template exists and has correct frontmatter**

Run: `head -15 templates/adversarial-reviewer-template.md`
Expected: YAML frontmatter with name, model: sonnet, effort: max, memory: none

- [ ] **Step 3: Verify workflow.md has new step and role**

Run: `grep -c "adversarial\|Adversarial" rules/workflow.md`
Expected: Multiple matches (step 6b, role section, model table)

- [ ] **Step 4: Run test-hooks.sh**

Run: `bash scripts/test-hooks.sh`
Expected: All script checks pass (framework project — structure FAILs are expected)
