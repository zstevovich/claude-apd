# Pipeline Runs — Real-World Results

Tracked results from APD pipeline usage in production projects. Not every task — only runs that demonstrate pipeline behavior, catch issues, or show metrics worth recording.

---

<table>
<tr>
<td width="50%" valign="top">

### #1 — XML Export Računa

| | |
|---|---|
| **Date** | 2026-04-09 |
| **Project** | efiskalizacija (PHP) |
| **Effort** | high |
| **Duration** | 12m 29s |
| **Spec coverage** | 7/7 |
| **Agents** | 6 (4 builder, 2 reviewer) |
| **Iterations** | 2 review cycles |
| **Guard blocks** | 2 |
| **Adversarial** | N/A |

First spec traceability run. Guardrails caught verify-failed and unprefixed commit.

</td>
<td width="50%" valign="top">

### #2 — Export Računa (XML + CSV)

| | |
|---|---|
| **Date** | 2026-04-09 |
| **Project** | efiskalizacija (PHP) |
| **Effort** | high |
| **Duration** | 7m 50s |
| **Spec coverage** | N/A |
| **Agents** | 4 (2 builder, 1 reviewer, 1 adversarial) |
| **Iterations** | 1 review cycle |
| **Guard blocks** | 0 |
| **Adversarial** | 4 findings (3 accepted, 1 dismissed) |

First adversarial reviewer run. Found CSV separator issue for Serbian locale — only adversarial caught it.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### #3 — Loyalty Program Ciklus 1

| | |
|---|---|
| **Date** | 2026-04-09 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | max |
| **Duration** | 46m 1s |
| **Spec coverage** | 14/14 |
| **Agents** | 7 (backend, db, testing, backoffice, mobile, 2x reviewer) |
| **Iterations** | Multiple review cycles |
| **Guard blocks** | 0 |
| **Adversarial** | 3 findings (0 accepted, 3 dismissed) |

First .NET project. Superpowers reviewer blocked by pipeline — forced project agent. Scope creep detected (14 criteria from original 7). Led to spec freeze and max criteria enforcement.

</td>
<td width="50%" valign="top">

### #4 — Hangfire Migration

| | |
|---|---|
| **Date** | 2026-04-10 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | high |
| **Duration** | 22m 8s |
| **Spec coverage** | 6/6 |
| **Agents** | 2 (backend-api, code-reviewer) |
| **Iterations** | 1 review cycle |
| **Guard blocks** | 0 |
| **Adversarial** | N/A |

First run with spec freeze (hash verification). Spec coverage 6/6 — all criteria traced. Pipeline graph visible for first time. Orchestrator hacked .agents file (guard-bash-scope gap fixed after).

</td>
</tr>
<tr>
<td width="50%" valign="top">

### #3 — Loyalty Program Ciklus 1

| | |
|---|---|
| **Date** | 2026-04-09 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | max |
| **Duration** | 46m 1s |
| **Spec coverage** | 14/14 |
| **Agents** | 7 (backend, db, testing, backoffice, mobile, 2x reviewer) |
| **Guard blocks** | 0 |
| **Adversarial** | 3 findings (0 accepted, 3 dismissed) |

First .NET project. Superpowers reviewer blocked — forced project agent. Led to spec freeze and max criteria enforcement.

</td>
<td width="50%" valign="top">

### #4 — Hangfire Migration

| | |
|---|---|
| **Date** | 2026-04-10 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | high |
| **Duration** | 22m 8s |
| **Spec coverage** | 6/6 |
| **Agents** | 2 (backend-api, code-reviewer) |
| **Guard blocks** | 0 |
| **Adversarial** | N/A |

First run with spec freeze (hash). Pipeline graph visible. Orchestrator hacked .agents file — led to guard-bash-scope fix.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### #5 — Hangfire Job Monitoring

| | |
|---|---|
| **Date** | 2026-04-10 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | high |
| **Duration** | 10m 30s |
| **Spec coverage** | N/A |
| **Agents** | 4 (Explore, backend-api, backoffice, code-reviewer) |
| **Guard blocks** | 0 |
| **Adversarial** | N/A |

First run with v4.0.0 `apd` entry point. Orchestrator bypassed pipeline-advance (old path failed) — spec freeze not activated. Led to bypass investigation task.

</td>
<td width="50%" valign="top">

### #6

*Next run...*

</td>
</tr>
</table>
