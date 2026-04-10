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

### #6 — Backoffice Audit Batch 2

| | |
|---|---|
| **Date** | 2026-04-10 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | high |
| **Duration** | 12m 23s |
| **Spec coverage** | 5/5 |
| **Agents** | 3 (backoffice, code-reviewer, adversarial-reviewer) |
| **Guard blocks** | 0 |
| **Adversarial** | 4 findings (0 accepted, 4 dismissed) |

First clean run — no bypasses. Adversarial gate blocked verifier, forced orchestrator to dispatch adversarial-reviewer. Agent_id validation active — no fake entries. Orchestrator tried 3 wrong paths before using correct `apd pipeline` command.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### #7 — Backoffice Audit Batch 3

| | |
|---|---|
| **Date** | 2026-04-10 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | high |
| **Duration** | 9m 37s |
| **Spec coverage** | 5/5 |
| **Agents** | 2 (backoffice, code-reviewer) |
| **Guard blocks** | 7 (all blocked, none bypassed) |
| **Adversarial** | opt-out (cosmetic i18n changes) |

Most chaotic run — 7 block attempts: direct code edit, pipeline-advance without dispatch, SendMessage bypass, reverse-engineering guards, maxTurns recovery, max criteria overflow. Every single one blocked. Orchestrator learned SendMessage rule the hard way. First run where adversarial opt-out was used via spec-card.

</td>
<td width="50%" valign="top">

### #8 — Create Tags (M:N)

| | |
|---|---|
| **Date** | 2026-04-10 |
| **Project** | Test Blog (PHP) |
| **Effort** | high |
| **Duration** | 14m 57s |
| **Spec coverage** | 7/7 |
| **Agents** | 10 dispatches (backend×3, frontend×3, reviewer×2, adversarial×1, testing×1) |
| **Guard blocks** | 0 |
| **Adversarial** | 8 findings (3 accepted, 5 dismissed) |

Cleanest run ever. Zero bypass attempts. First run on v4.1.0 with HMAC-signed .done files and compiled Go validator. Adversarial hard gate forced dispatch, 3 findings accepted and fixed. All agent IDs are real CC hex IDs with valid start/stop pairs.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### #9

*Next run...*

</td>
<td width="50%" valign="top">

### #10

*Next run...*

</td>
</tr>
</table>
