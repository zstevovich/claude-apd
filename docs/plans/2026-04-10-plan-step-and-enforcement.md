# Implementation Plan Step + Enforcement Gaps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hard-enforce spec-card.md and implementation-plan.md existence in pipeline, add soft warn for adversarial-summary.

**Architecture:** Three changes to pipeline-advance.sh (spec block, builder block, verifier warn), workflow.md flow diagram and new plan format section, builder template reads plan file.

**Tech Stack:** Bash, Markdown

---

### Task 1: pipeline-advance.sh — hard block spec-card.md on spec step

**Files:**
- Modify: `scripts/pipeline-advance.sh:55-65` (spec case, existing soft validation)

- [ ] **Step 1: Replace soft validation with hard block**

The current code (lines 55-65) only checks R* format IF spec-card.md exists. Replace the entire block:

From:
```bash
        # Validate spec-card.md if it exists
        if [ -f "$PIPELINE_DIR/spec-card.md" ]; then
            if ! grep -qE '^[[:space:]]*-[[:space:]]+R[0-9]+[[:space:]]*:' "$PIPELINE_DIR/spec-card.md"; then
                echo "BLOCKED: spec-card.md exists but has no R* acceptance criteria." >&2
                echo "" >&2
                echo "  Expected format in spec-card.md:" >&2
                echo "    - R1: First requirement" >&2
                echo "    - R2: Second requirement" >&2
                exit 1
            fi
        fi
```

To:
```bash
        # Validate spec-card.md exists and has R* criteria
        if [ ! -f "$PIPELINE_DIR/spec-card.md" ]; then
            echo "BLOCKED: spec-card.md not found." >&2
            echo "" >&2
            echo "  Write the spec card to .claude/.pipeline/spec-card.md before advancing." >&2
            echo "  Acceptance criteria must use R1:, R2:, ... format." >&2
            exit 1
        fi
        if ! grep -qE '^[[:space:]]*-[[:space:]]+R[0-9]+[[:space:]]*:' "$PIPELINE_DIR/spec-card.md"; then
            echo "BLOCKED: spec-card.md has no R* acceptance criteria." >&2
            echo "" >&2
            echo "  Expected format in spec-card.md:" >&2
            echo "    - R1: First requirement" >&2
            echo "    - R2: Second requirement" >&2
            exit 1
        fi
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/pipeline-advance.sh`
Expected: No output

---

### Task 2: pipeline-advance.sh — hard block implementation-plan.md on builder step

**Files:**
- Modify: `scripts/pipeline-advance.sh:77-81` (builder case, after spec.done check)

- [ ] **Step 1: Add implementation-plan.md check after spec.done check**

After line 81 (`fi` closing the spec.done check), before the "Verify that a PROJECT-DEFINED builder agent ran" comment (line 83), insert:

```bash
        # Verify implementation plan exists
        if [ ! -f "$PIPELINE_DIR/implementation-plan.md" ]; then
            echo "BLOCKED: implementation-plan.md not found." >&2
            echo "" >&2
            echo "  Write the implementation plan to .claude/.pipeline/implementation-plan.md" >&2
            echo "  List files to change with 1-2 sentences per file describing the change." >&2
            exit 1
        fi
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/pipeline-advance.sh`
Expected: No output

---

### Task 3: pipeline-advance.sh — soft warn adversarial-summary on verifier step

**Files:**
- Modify: `scripts/pipeline-advance.sh:199-201` (verifier case, after trace check, before verifier.done)

- [ ] **Step 1: Add adversarial-summary warning**

After the trace check block (line 199 `fi`), before `echo ... > verifier.done` (line 201), insert:

```bash
        # Warn if adversarial reviewer is configured but wasn't used
        if [ -f "$CLAUDE_DIR/agents/adversarial-reviewer.md" ] && [ ! -f "$PIPELINE_DIR/.adversarial-summary" ]; then
            warn "Adversarial reviewer is configured but was not used this task." >&2
            echo "    Write ADVERSARIAL:total:accepted:dismissed to .pipeline/.adversarial-summary" >&2
        fi
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/pipeline-advance.sh`
Expected: No output

---

### Task 4: pipeline-advance.sh — cleanup lines

**Files:**
- Modify: `scripts/pipeline-advance.sh` (3 cleanup locations)

- [ ] **Step 1: Add implementation-plan.md to spec step cleanup**

Line 71, change:
```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary"
```
To:
```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary" "$PIPELINE_DIR/implementation-plan.md"
```

- [ ] **Step 2: Add implementation-plan.md to reset step cleanup**

Find the reset cleanup `rm -f` line (has `spec-card.md` at the end), change:
```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary" "$PIPELINE_DIR/spec-card.md"
```
To:
```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary" "$PIPELINE_DIR/spec-card.md" "$PIPELINE_DIR/implementation-plan.md"
```

- [ ] **Step 3: Add implementation-plan.md to rollback builder cleanup**

In the rollback case, after the verifier cleanup line (line 391), add builder cleanup:

Change:
```bash
                [ "$step" = "verifier" ] && rm -f "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary"
```
To:
```bash
                [ "$step" = "verifier" ] && rm -f "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary"
                [ "$step" = "builder" ] && rm -f "$PIPELINE_DIR/implementation-plan.md"
```

- [ ] **Step 4: Verify syntax**

Run: `bash -n scripts/pipeline-advance.sh`
Expected: No output

---

### Task 5: Update workflow.md — flow diagram and plan format

**Files:**
- Modify: `rules/workflow.md:16-17` (step 4 in flow diagram)
- Modify: `rules/workflow.md` (new section after micro-tasks)

- [ ] **Step 1: Update step 4 in flow diagram**

Change lines 16-17:
```
4. WRITE IMPLEMENTATION PLAN — break into micro-tasks, assign to agents
   ↓
```
To:
```
4. WRITE IMPLEMENTATION PLAN
   → Analyze codebase, write .pipeline/implementation-plan.md
   → List files to create/modify with concrete change descriptions
   → pipeline-advance.sh builder validates plan exists before advancing
   ↓
```

- [ ] **Step 2: Add implementation plan format section**

After section "3b. Spec traceability" (ends with the `verify-trace.sh` line), before section "4. Verification before done", insert:

```markdown
## 3c. Implementation plan

Before dispatching the builder, the orchestrator MUST write `.claude/.pipeline/implementation-plan.md`. The plan bridges the gap between spec (what to build) and builder (how to build it).

### Format

```
## Implementation Plan: [Task name]

### Files to modify
- `path/to/file.ext` — description of what to change (1-2 sentences)
- `path/to/other.ext` — description of what to change

### Files to create
- `path/to/new-file.ext` — purpose and what it contains

### Notes
- Any relevant context the builder needs (e.g., "use XMLWriter for streaming", "both invoice_items and stavke_racuna tables")
```

**Rules:**
- List every file the builder will touch
- 1-2 sentences per file — enough context to avoid searching, not code snippets
- Orchestrator reads relevant code BEFORE writing the plan
- `pipeline-advance.sh builder` blocks if the plan does not exist
```

- [ ] **Step 3: Verify workflow.md is valid markdown**

Run: `head -5 rules/workflow.md && grep -c "3c\. Implementation plan" rules/workflow.md`
Expected: Header visible, count = 1

---

### Task 6: Update agent template — builder reads plan

**Files:**
- Modify: `templates/agent-template.md:50` (workflow step 1)

- [ ] **Step 1: Update builder workflow step 1**

Change:
```markdown
1. Read `.claude/.pipeline/spec-card.md` for acceptance criteria (R1, R2, ...)
```
To:
```markdown
1. Read `.claude/.pipeline/implementation-plan.md` for what to change and `.claude/.pipeline/spec-card.md` for acceptance criteria (R1, R2, ...)
```

---

### Task 7: Verify complete implementation

- [ ] **Step 1: Verify pipeline-advance.sh syntax**

Run: `bash -n scripts/pipeline-advance.sh`
Expected: No output

- [ ] **Step 2: Test spec-card.md hard block**

```bash
mkdir -p /tmp/apd-enforce-test/.claude/.pipeline /tmp/apd-enforce-test/.claude/memory
touch /tmp/apd-enforce-test/.claude/.apd-config /tmp/apd-enforce-test/CLAUDE.md
cd /tmp/apd-enforce-test && APD_PROJECT_DIR=/tmp/apd-enforce-test bash /path/to/scripts/pipeline-advance.sh spec "Test" 2>&1; echo "EXIT: $?"
```
Expected: `BLOCKED: spec-card.md not found.` Exit: 1

- [ ] **Step 3: Test implementation-plan.md hard block**

Create spec-card.md with R* criteria, advance spec, then try builder without plan:
```bash
# (after spec-card.md exists and spec step passed)
APD_PROJECT_DIR=/tmp/apd-enforce-test bash /path/to/scripts/pipeline-advance.sh builder 2>&1; echo "EXIT: $?"
```
Expected: `BLOCKED: implementation-plan.md not found.` Exit: 1

- [ ] **Step 4: Test adversarial-summary soft warn**

Create all .done files and adversarial-reviewer.md agent but no .adversarial-summary:
Expected: Warning message but exit 0 (verifier.done created)

- [ ] **Step 5: Clean up**

```bash
rm -rf /tmp/apd-enforce-test
```

- [ ] **Step 6: Run test-hooks.sh**

Run: `bash scripts/test-hooks.sh`
Expected: All script checks pass
