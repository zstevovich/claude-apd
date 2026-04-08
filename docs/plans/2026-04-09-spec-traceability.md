# Spec Traceability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mechanical verification that every spec acceptance criterion (R1, R2...) has `@trace` coverage in test files.

**Architecture:** New `verify-trace.sh` script parses `.pipeline/spec-card.md` for R* IDs, scans project test files for `@trace R*` markers, blocks verifier step if any R* lacks test coverage. Integrated into `pipeline-advance.sh` at three points: spec validation, verifier gate, reset session-log.

**Tech Stack:** Bash, style.sh (APD visual library), grep/sed for parsing

---

### Task 1: Create verify-trace.sh

**Files:**
- Create: `scripts/verify-trace.sh`

- [ ] **Step 1: Create the script with header and argument parsing**

```bash
#!/bin/bash
# APD Trace Verifier — checks @trace coverage against spec-card.md
#
# Usage:
#   verify-trace.sh                  # verify current pipeline spec
#   verify-trace.sh --summary        # one-line output for session-log
#
# Exit codes:
#   0 — all acceptance criteria covered (or no spec-card.md)
#   1 — missing test coverage for one or more criteria

source "$(dirname "$0")/lib/resolve-project.sh"
[ "$APD_ACTIVE" = false ] && exit 0
source "$(dirname "$0")/lib/style.sh"

SPEC_CARD="$PIPELINE_DIR/spec-card.md"
SUMMARY_MODE=false
[ "${1:-}" = "--summary" ] && SUMMARY_MODE=true

# --- No spec-card.md = backward compatible, exit 0 ---
if [ ! -f "$SPEC_CARD" ]; then
    exit 0
fi
```

- [ ] **Step 2: Add acceptance criteria parser**

Parse `spec-card.md` to extract R* IDs and their descriptions. Criteria format: `- R1: description text`.

```bash
# --- Parse acceptance criteria from spec-card.md ---
# Format: "- R1: description" or "- R1 : description"
declare -a SPEC_IDS=()
declare -a SPEC_DESCS=()

while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(R[0-9]+)[[:space:]]*:[[:space:]]*(.+)$ ]]; then
        SPEC_IDS+=("${BASH_REMATCH[1]}")
        SPEC_DESCS+=("${BASH_REMATCH[2]}")
    fi
done < "$SPEC_CARD"

if [ ${#SPEC_IDS[@]} -eq 0 ]; then
    fail "spec-card.md has no acceptance criteria (expected R1:, R2:, ...)"
    exit 1
fi
```

- [ ] **Step 3: Add test file discovery with stack-aware patterns**

Detect project stack and build find patterns for test files.

```bash
# --- Discover test files based on stack ---
STACK="${CLAUDE_PLUGIN_OPTION_STACK:-}"

build_test_patterns() {
    local patterns=""
    case "$STACK" in
        nodejs)
            patterns="-name '*.test.ts' -o -name '*.spec.ts' -o -name '*.test.js' -o -name '*.spec.js' -o -name '*.test.tsx' -o -name '*.spec.tsx'"
            ;;
        python)
            patterns="-name 'test_*.py' -o -name '*_test.py'"
            ;;
        php)
            patterns="-name '*Test.php'"
            ;;
        dotnet)
            patterns="-name '*.Tests.cs' -o -name '*Test.cs'"
            ;;
        go)
            patterns="-name '*_test.go'"
            ;;
        java)
            patterns="-name '*Test.java' -o -name '*Spec.java'"
            ;;
        *)
            # All known patterns when stack is not set
            patterns="-name '*.test.ts' -o -name '*.spec.ts' -o -name '*.test.js' -o -name '*.spec.js' -o -name '*.test.tsx' -o -name '*.spec.tsx' -o -name 'test_*.py' -o -name '*_test.py' -o -name '*Test.php' -o -name '*.Tests.cs' -o -name '*Test.cs' -o -name '*_test.go' -o -name '*Test.java' -o -name '*Spec.java'"
            ;;
    esac
    echo "$patterns"
}

# Also include files inside common test directories
# (e.g., __tests__/foo.ts, tests/test_bar.py, src/test/FooTest.java)
TEST_DIR_PATTERNS="__tests__|/tests/|/test/|/spec/"

PATTERNS=$(build_test_patterns)
TEST_FILES=$(eval "find '$PROJECT_DIR' -type f \( $PATTERNS \)" 2>/dev/null | grep -v node_modules | grep -v vendor | grep -v .git || true)

# Add files from test directories that might not match naming convention
DIR_TEST_FILES=$(find "$PROJECT_DIR" -type f \( -name '*.ts' -o -name '*.js' -o -name '*.py' -o -name '*.php' -o -name '*.cs' -o -name '*.go' -o -name '*.java' \) 2>/dev/null | grep -E "$TEST_DIR_PATTERNS" | grep -v node_modules | grep -v vendor | grep -v .git || true)

ALL_TEST_FILES=$(printf '%s\n%s' "$TEST_FILES" "$DIR_TEST_FILES" | sort -u | grep -v '^$' || true)
```

- [ ] **Step 4: Add @trace marker scanning and comparison**

Scan all test files for `@trace R*` markers and compare against spec IDs.

```bash
# --- Scan test files for @trace markers ---
declare -A TRACE_TEST_COUNT    # TRACE_TEST_COUNT[R1]=2
declare -A TRACE_CODE_COUNT    # TRACE_CODE_COUNT[R1]=1 (informational)
declare -A TRACE_EXTRA         # markers not in spec

# Scan test files
if [ -n "$ALL_TEST_FILES" ]; then
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        while IFS= read -r match; do
            # Extract all R* IDs from the line
            for rid in $(echo "$match" | grep -oE 'R[0-9]+'); do
                TRACE_TEST_COUNT[$rid]=$(( ${TRACE_TEST_COUNT[$rid]:-0} + 1 ))
            done
        done < <(grep -n '@trace' "$file" 2>/dev/null || true)
    done <<< "$ALL_TEST_FILES"
fi

# Optionally scan code files (informational)
CODE_FILES=$(find "$PROJECT_DIR" -type f \( -name '*.ts' -o -name '*.js' -o -name '*.py' -o -name '*.php' -o -name '*.cs' -o -name '*.go' -o -name '*.java' \) 2>/dev/null | grep -v node_modules | grep -v vendor | grep -v .git || true)
if [ -n "$CODE_FILES" ]; then
    # Exclude test files from code files
    NON_TEST_FILES=$(comm -23 <(echo "$CODE_FILES" | sort) <(echo "$ALL_TEST_FILES" | sort) 2>/dev/null || true)
    if [ -n "$NON_TEST_FILES" ]; then
        while IFS= read -r file; do
            [ -f "$file" ] || continue
            while IFS= read -r match; do
                for rid in $(echo "$match" | grep -oE 'R[0-9]+'); do
                    TRACE_CODE_COUNT[$rid]=$(( ${TRACE_CODE_COUNT[$rid]:-0} + 1 ))
                done
            done < <(grep -n '@trace' "$file" 2>/dev/null || true)
        done <<< "$NON_TEST_FILES"
    fi
fi
```

- [ ] **Step 5: Add report generation with style.sh colors**

Generate the colored report and calculate coverage.

```bash
# --- Generate report ---
COVERED=0
TOTAL=${#SPEC_IDS[@]}
UNCOVERED_IDS=""

if [ "$SUMMARY_MODE" = false ]; then
    apd_header "Spec Traceability"
fi

for i in "${!SPEC_IDS[@]}"; do
    rid="${SPEC_IDS[$i]}"
    desc="${SPEC_DESCS[$i]}"
    test_count=${TRACE_TEST_COUNT[$rid]:-0}
    code_count=${TRACE_CODE_COUNT[$rid]:-0}

    if [ "$SUMMARY_MODE" = false ]; then
        # Build detail string
        detail=""
        [ "$code_count" -gt 0 ] && detail="code($code_count) "
        [ "$test_count" -gt 0 ] && detail="${detail}test($test_count)"

        if [ "$test_count" -gt 0 ]; then
            pass "$rid: $desc  ${D}$detail${R}"
            COVERED=$((COVERED + 1))
        else
            fail "$rid: $desc  ${D}test missing${R}"
            UNCOVERED_IDS="${UNCOVERED_IDS}${rid},"
        fi
    else
        if [ "$test_count" -gt 0 ]; then
            COVERED=$((COVERED + 1))
        else
            UNCOVERED_IDS="${UNCOVERED_IDS}${rid},"
        fi
    fi
done

# Check for extra @trace markers not in spec
if [ "$SUMMARY_MODE" = false ]; then
    for rid in "${!TRACE_TEST_COUNT[@]}"; do
        FOUND=false
        for sid in "${SPEC_IDS[@]}"; do
            [ "$rid" = "$sid" ] && FOUND=true && break
        done
        if [ "$FOUND" = false ]; then
            warn "$rid: found in tests but not in spec-card.md"
        fi
    done
fi

# Clean trailing comma
UNCOVERED_IDS="${UNCOVERED_IDS%,}"
```

- [ ] **Step 6: Add summary output and exit code**

```bash
# --- Summary ---
if [ "$SUMMARY_MODE" = true ]; then
    # One-line output for session-log consumption
    echo "TRACE:${COVERED}/${TOTAL}:${UNCOVERED_IDS}"
    [ "$COVERED" -eq "$TOTAL" ] && exit 0 || exit 1
fi

section "Coverage"
if [ "$COVERED" -eq "$TOTAL" ]; then
    printf "    %s${COVERED}/${TOTAL}%s\n" "$G" "$R"
    exit 0
else
    printf "    %s${COVERED}/${TOTAL}%s\n" "$RED" "$R"
    fail "FAILED: ${UNCOVERED_IDS} missing test coverage"
    exit 1
fi
```

- [ ] **Step 7: Make script executable**

Run: `chmod +x scripts/verify-trace.sh`

- [ ] **Step 8: Verify script syntax**

Run: `bash -n scripts/verify-trace.sh`
Expected: No output (syntax OK)

---

### Task 2: Integrate into pipeline-advance.sh — spec step validation

**Files:**
- Modify: `scripts/pipeline-advance.sh:22-63` (spec case block)

- [ ] **Step 1: Add spec-card.md validation after session-log check, before creating spec.done**

Insert after line 53 (end of session-log [fill in] check), before line 55 (archive agent log):

```bash
        # Validate spec-card.md if it exists
        if [ -f "$PIPELINE_DIR/spec-card.md" ]; then
            # Check that spec-card.md has at least one R* acceptance criterion
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

- [ ] **Step 2: Verify pipeline-advance.sh syntax**

Run: `bash -n scripts/pipeline-advance.sh`
Expected: No output (syntax OK)

---

### Task 3: Integrate into pipeline-advance.sh — verifier step gate

**Files:**
- Modify: `scripts/pipeline-advance.sh:166-181` (verifier case block)

- [ ] **Step 1: Add verify-trace.sh call before creating verifier.done**

Insert after line 174 (`TOTAL=$(format_duration ...)`), before line 175 (`echo ... > verifier.done`):

```bash
        # Run spec traceability check (if spec-card.md exists)
        if [ -f "$PIPELINE_DIR/spec-card.md" ]; then
            if ! bash "$SCRIPT_DIR/verify-trace.sh"; then
                echo "" >&2
                echo "  Fix: Add @trace R* markers in test files for uncovered criteria." >&2
                echo "  Then re-run: pipeline-advance.sh verifier" >&2
                exit 1
            fi
            # Cache summary for session-log
            bash "$SCRIPT_DIR/verify-trace.sh" --summary > "$PIPELINE_DIR/.trace-summary" 2>/dev/null || true
        fi
```

- [ ] **Step 2: Verify pipeline-advance.sh syntax**

Run: `bash -n scripts/pipeline-advance.sh`
Expected: No output (syntax OK)

---

### Task 4: Integrate into pipeline-advance.sh — reset session-log enhancement

**Files:**
- Modify: `scripts/pipeline-advance.sh:183-318` (reset case block)

- [ ] **Step 1: Add spec coverage line to session-log entry**

In the reset block, after the `AGENTS_SUMMARY` section (around line 296) and before the `cat >> "$SESSION_LOG"` heredoc (line 299), add trace summary reading:

```bash
                # 7. Spec trace coverage
                TRACE_COVERAGE=""
                if [ -f "$PIPELINE_DIR/.trace-summary" ]; then
                    TRACE_LINE=$(cat "$PIPELINE_DIR/.trace-summary")
                    # Format: TRACE:3/3: or TRACE:2/3:R2
                    TRACE_COVERED=$(echo "$TRACE_LINE" | cut -d: -f2 | cut -d/ -f1)
                    TRACE_TOTAL=$(echo "$TRACE_LINE" | cut -d: -f2 | cut -d/ -f2)
                    TRACE_MISSING=$(echo "$TRACE_LINE" | cut -d: -f3)
                    if [ -n "$TRACE_TOTAL" ] && [ "$TRACE_TOTAL" != "0" ]; then
                        if [ -z "$TRACE_MISSING" ]; then
                            TRACE_COVERAGE="${TRACE_COVERED}/${TRACE_TOTAL} (all covered)"
                        else
                            TRACE_COVERAGE="${TRACE_COVERED}/${TRACE_TOTAL} (missing: ${TRACE_MISSING})"
                        fi
                    fi
                fi
```

- [ ] **Step 2: Add Spec coverage line to the session-log heredoc**

Modify the heredoc starting at line 299 to include the new field. Insert `**Spec coverage:**` line after `**Status:**`:

Change from:
```bash
                cat >> "$SESSION_LOG" << EOF

## [$(date +%Y-%m-%d)] $TASK_NAME
**Status:** $PIPELINE_STATUS
**What was done:** $CHANGED_SUMMARY
```

To:
```bash
                cat >> "$SESSION_LOG" << EOF

## [$(date +%Y-%m-%d)] $TASK_NAME
**Status:** $PIPELINE_STATUS
**Spec coverage:** ${TRACE_COVERAGE:-N/A}
**What was done:** $CHANGED_SUMMARY
```

- [ ] **Step 3: Add .trace-summary to cleanup in reset**

Modify line 317 to also clean up the trace summary file:

Change from:
```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents"
```

To:
```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary"
```

- [ ] **Step 4: Also clean .trace-summary in spec step cleanup**

Modify line 59 (in spec case) to also remove trace summary:

Change from:
```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents"
```

To:
```bash
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary"
```

- [ ] **Step 5: Verify pipeline-advance.sh syntax**

Run: `bash -n scripts/pipeline-advance.sh`
Expected: No output (syntax OK)

---

### Task 5: Update workflow.md — spec format and builder rules

**Files:**
- Modify: `rules/workflow.md:97-113` (spec card section)

- [ ] **Step 1: Update spec card template with R* format**

Change the acceptance criteria line in the spec template (line 106) from:

```
**Acceptance criteria:** List of conditions for "done".
```

To:

```
**Acceptance criteria:**
- R1: [first condition for "done"]
- R2: [second condition]
- RN: [last condition]
```

- [ ] **Step 2: Add spec-card.md instruction after spec template**

After the spec template block (after line 111 ```` ``` ````), add:

```markdown

### Spec persistence

The orchestrator MUST write the spec card to `.claude/.pipeline/spec-card.md` before calling `pipeline-advance.sh spec "Task name"`. This enables mechanical traceability verification.
```

- [ ] **Step 3: Add builder @trace rule**

After the micro-tasks section (section 3, after line 161), add a new section:

```markdown
## 3b. Spec traceability

Builders MUST add `@trace R*` comments in test files for every acceptance criterion from `.claude/.pipeline/spec-card.md`.

```
// Single requirement
// @trace R1

// Multiple requirements on one line
// @trace R2 R3
```

**Rules:**
- Each R* from spec-card.md must appear in at least one test file
- Use the comment syntax appropriate for the language (`//`, `#`, `--`, etc.)
- Markers in code files (non-test) are optional and informational
- `verify-trace.sh` runs during the verifier step and blocks commit if any R* is missing test coverage
```

- [ ] **Step 4: Verify the file is valid markdown**

Run: `head -50 rules/workflow.md`
Expected: Well-formed markdown with new sections

---

### Task 6: Update agent templates

**Files:**
- Modify: `templates/agent-template.md:50-52` (workflow section)
- Modify: `templates/reviewer-template.md:38-47` (what to check section)

- [ ] **Step 1: Add @trace instruction to builder template**

In `templates/agent-template.md`, modify the Workflow section. Change from:

```markdown
## Workflow
1. Read the spec card and understand the requirements
2. **MANDATORY: Use /apd-tdd skill** — write failing test first, then implement
3. Implement changes following TDD cycle: test → code → verify
4. Respect the max 3-4 edit operations per dispatch limit
5. Do not overlap with other agents
```

To:

```markdown
## Workflow
1. Read `.claude/.pipeline/spec-card.md` for acceptance criteria (R1, R2, ...)
2. **MANDATORY: Use /apd-tdd skill** — write failing test first, then implement
3. Add `@trace R*` markers in test files for each acceptance criterion you implement
4. Implement changes following TDD cycle: test → code → verify
5. Respect the max 3-4 edit operations per dispatch limit
6. Do not overlap with other agents
```

- [ ] **Step 2: Add @trace check instruction to reviewer template**

In `templates/reviewer-template.md`, add item 6 to the "What to check" list. Change from:

```markdown
## What to check

1. **Logic errors** — off-by-one, null handling, wrong conditions
2. **Security** — injection, XSS, auth bypass, secrets exposure
3. **Edge cases** — empty input, max values, concurrent access
4. **Cross-layer mismatches** — backend DTO vs frontend types, nullable fields
5. **Regressions** — does the change break existing functionality?
```

To:

```markdown
## What to check

1. **Logic errors** — off-by-one, null handling, wrong conditions
2. **Security** — injection, XSS, auth bypass, secrets exposure
3. **Edge cases** — empty input, max values, concurrent access
4. **Cross-layer mismatches** — backend DTO vs frontend types, nullable fields
5. **Regressions** — does the change break existing functionality?
6. **Spec traceability** — verify `@trace R*` markers in test files cover all acceptance criteria from `.claude/.pipeline/spec-card.md`. Flag missing markers as Critical.
```

---

### Task 7: End-to-end manual test

- [ ] **Step 1: Create a temporary test project structure**

```bash
mkdir -p /tmp/apd-trace-test/.claude/.pipeline
mkdir -p /tmp/apd-trace-test/.claude/memory
mkdir -p /tmp/apd-trace-test/src
mkdir -p /tmp/apd-trace-test/tests
touch /tmp/apd-trace-test/.apd-config
touch /tmp/apd-trace-test/CLAUDE.md
```

- [ ] **Step 2: Create a spec-card.md with 3 criteria**

```bash
cat > /tmp/apd-trace-test/.claude/.pipeline/spec-card.md << 'EOF'
## Add user login
**Goal:** Implement login endpoint.
**Effort:** high
**Out of scope:** Registration, password reset.
**Acceptance criteria:**
- R1: Login endpoint returns JWT token
- R2: JWT validates user role
- R3: Expired tokens are rejected
**Affected modules:** server/auth/
**Risks:** Token leakage.
**Rollback:** Remove auth routes.
EOF
```

- [ ] **Step 3: Run verify-trace.sh with zero coverage — expect exit 1**

```bash
cd /tmp/apd-trace-test && APD_PROJECT_DIR=/tmp/apd-trace-test bash /Users/zoranstevovic/Projects/apd-template/scripts/verify-trace.sh
echo "Exit code: $?"
```

Expected: Report showing R1, R2, R3 all with `test missing`, Coverage 0/3, exit code 1.

- [ ] **Step 4: Add @trace markers to test files — partial coverage**

```bash
cat > /tmp/apd-trace-test/tests/auth.test.js << 'EOF'
// @trace R1
test('login returns JWT', () => { /* ... */ });

// @trace R3
test('expired token rejected', () => { /* ... */ });
EOF
```

- [ ] **Step 5: Run verify-trace.sh with partial coverage — expect exit 1**

```bash
cd /tmp/apd-trace-test && APD_PROJECT_DIR=/tmp/apd-trace-test bash /Users/zoranstevovic/Projects/apd-template/scripts/verify-trace.sh
echo "Exit code: $?"
```

Expected: R1 pass, R2 fail (test missing), R3 pass. Coverage 2/3, exit code 1.

- [ ] **Step 6: Add remaining @trace marker — full coverage**

```bash
cat >> /tmp/apd-trace-test/tests/auth.test.js << 'EOF'

// @trace R2
test('JWT validates role', () => { /* ... */ });
EOF
```

- [ ] **Step 7: Run verify-trace.sh with full coverage — expect exit 0**

```bash
cd /tmp/apd-trace-test && APD_PROJECT_DIR=/tmp/apd-trace-test bash /Users/zoranstevovic/Projects/apd-template/scripts/verify-trace.sh
echo "Exit code: $?"
```

Expected: R1 pass, R2 pass, R3 pass. Coverage 3/3, exit code 0.

- [ ] **Step 8: Test --summary mode**

```bash
cd /tmp/apd-trace-test && APD_PROJECT_DIR=/tmp/apd-trace-test bash /Users/zoranstevovic/Projects/apd-template/scripts/verify-trace.sh --summary
```

Expected: `TRACE:3/3:`

- [ ] **Step 9: Test backward compatibility — no spec-card.md**

```bash
rm /tmp/apd-trace-test/.claude/.pipeline/spec-card.md
cd /tmp/apd-trace-test && APD_PROJECT_DIR=/tmp/apd-trace-test bash /Users/zoranstevovic/Projects/apd-template/scripts/verify-trace.sh
echo "Exit code: $?"
```

Expected: exit code 0 (no output, backward compatible).

- [ ] **Step 10: Clean up**

```bash
rm -rf /tmp/apd-trace-test
```

---

### Task 8: Verify framework integrity

- [ ] **Step 1: Run verify-apd.sh on example project**

Run: `bash scripts/verify-apd.sh`
Expected: All existing checks pass. New script `verify-trace.sh` is detected as executable.

- [ ] **Step 2: Run test-hooks.sh**

Run: `bash scripts/test-hooks.sh`
Expected: All checks pass.

- [ ] **Step 3: Verify all scripts are executable**

Run: `ls -la scripts/verify-trace.sh`
Expected: `-rwxr-xr-x` permissions.
