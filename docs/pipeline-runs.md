# Pipeline Runs — Real-World Results

Tracked results from APD pipeline usage in production projects. Not every task — only runs that demonstrate pipeline behavior, catch issues, or show metrics worth recording.

## Results

| Date | Project | Task | Effort | Duration | Spec Coverage | Agents | Iterations | Guard Blocks | Adversarial | Notes |
|------|---------|------|--------|----------|---------------|--------|------------|-------------|-------------|-------|
| 2026-04-09 | efiskalizacija | XML Export Računa | high | 12m 29s | 7/7 | 6 dispatches (4 builder, 2 reviewer) | 2 review cycles | 2 (verify-failed, commit-no-prefix) | N/A | First spec traceability run. Guardrails caught bad commit, forced fix before merge. |
