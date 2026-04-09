# Pipeline Runs — Real-World Results

Tracked results from APD pipeline usage in production projects. Not every task — only runs that demonstrate pipeline behavior, catch issues, or show metrics worth recording.

---

### #1 — XML Export Računa

| | |
|---|---|
| **Date** | 2026-04-09 |
| **Project** | efiskalizacija (PHP) |
| **Effort** | high |
| **Duration** | 12m 29s |
| **Spec coverage** | 7/7 |
| **Agents** | 6 dispatches (4 builder, 2 reviewer) |
| **Iterations** | 2 review cycles |
| **Guard blocks** | 2 — verify-failed, commit-no-prefix |
| **Adversarial** | N/A |

First spec traceability run. Guardrails caught a bad commit (verification failed) and an unprefixed commit attempt, forced fix before merge.
