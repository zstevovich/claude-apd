#!/bin/bash
# APD workflow.md guidance markers — the ONE list that both apd-init (the
# pre-record refresh path) and pipeline-audit-drift (dimension C) read.
# v7.1.6: until now each script carried its own copy; apd-init's still listed
# `DEPRECATED`, a marker that left the shipped workflow.md in v7.0 and so could
# never fire. A marker must exist in the shipped rules/workflow.md or it guards
# nothing (test-codex-adapter §136 A4 enforces that against THIS list).
# Sourced, never executed.
WORKFLOW_MARKERS=(
    "Implements:"
    "rationale gate"
    "unconditional"
    "apd-pipeline-guide"
    "SUPERVISION"
)
