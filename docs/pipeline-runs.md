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
| **Guard blocks** | 3 (orchestrator code edit, .adversarial-summary via bash, builder without dispatch) |
| **Adversarial** | 8 findings (3 accepted, 5 dismissed) |

First run on v4.1.0 with HMAC-signed .done files and compiled Go validator. Three blocks: guard-orchestrator on direct code edit, guard-bash-scope on .adversarial-summary write, pipeline-advance on premature builder advance. All corrected — orchestrator dispatched agents and used Write tool. Adversarial hard gate forced dispatch, 3 findings accepted and fixed.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### #9 — Backend Audit Batch 1

| | |
|---|---|
| **Date** | 2026-04-10 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | high |
| **Duration** | 16m 44s |
| **Spec coverage** | 7/7 |
| **Agents** | 3 (backend-api, code-reviewer, adversarial-reviewer) |
| **Guard blocks** | 2 (pipeline-state-write, orchestrator-code-write) |
| **Adversarial** | 3 findings (0 accepted, 3 dismissed) |

First run on v4.1.1 with complete audit trail. All 8 guards logging — lockfile-write, secret-access, pipeline-state-write, orchestrator-code-write all captured. Code-reviewer agent also blocked on pipeline-state-write (reading spec-card via Bash). HMAC-signed .done files active, Go binary validator running.

</td>
<td width="50%" valign="top">

### #10 — Backend Audit Batch 7

| | |
|---|---|
| **Date** | 2026-04-11 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | high |
| **Duration** | 18m 39s |
| **Spec coverage** | 7/7 |
| **Agents** | 4 (backend-api, code-reviewer, testing, adversarial-reviewer) |
| **Guard blocks** | 1 (orchestrator-code-write) |
| **Adversarial** | 4 findings (0 accepted, 4 dismissed) |

New session without prior context — orchestrator still follows pipeline. Adversarial actually dispatched (not 0:0:0 skip). Builder dispatched without plan → blocked → wrote plan retroactively. Reviewer hit maxTurns (unfocused prompt) → dispatched focused second reviewer. Quality enforcement is the next frontier.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### #11 — Split Post List/Detail

| | |
|---|---|
| **Date** | 2026-04-11 |
| **Project** | Test Blog (PHP) |
| **Effort** | high |
| **Duration** | 34m 34s |
| **Spec coverage** | 7/7 |
| **Agents** | 4 (backend-builder, frontend-builder, code-reviewer, testing) |
| **Guard blocks** | 6 (orchestrator-code-write ×3, pipeline-state-write ×2, pipeline-state-direct-write ×1) |
| **Adversarial** | bypass (0:0:0 without dispatch) |

First run on v4.3.0 after pipeline relocation to `.apd/pipeline/`. Permission prompts eliminated. But orchestrator wrote code directly 3 times (all blocked), bypassed adversarial, and SubagentStop missing for some agents. Led to three quality fixes in v4.3.3–v4.3.4.

</td>
<td width="50%" valign="top">

### #12 — Page Routes + Dynamic Nav

| | |
|---|---|
| **Date** | 2026-04-11 |
| **Project** | Test Blog (PHP) |
| **Effort** | high |
| **Duration** | 10m 10s |
| **Spec coverage** | 7/7 |
| **Agents** | 5 (backend-builder, frontend-builder, code-reviewer, testing, adversarial-reviewer) |
| **Guard blocks** | 1 (pipeline-state-write) |
| **Adversarial** | 9 findings (0 accepted, 9 dismissed) |

First run after quality fixes. Zero code-write blocks. Adversarial properly dispatched. All SubagentStop events received. Dispatch prompt quality analyzed from transcript JSONL — orchestrator sends precise file:line references and concrete code to builders.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### #13 — Add Comments on Posts

| | |
|---|---|
| **Date** | 2026-04-12 |
| **Project** | Test Blog (PHP) |
| **Effort** | high |
| **Duration** | 11m 41s |
| **Spec coverage** | 7/7 |
| **Agents** | 4 (backend-builder, frontend-builder, code-reviewer, testing) |
| **Guard blocks** | 2 (send-message-during-pipeline ×1, pipeline-state-write ×1) |
| **Adversarial** | dispatched |

Stable run. Zero code-write blocks. New guard-send-message caught SendMessage attempt during pipeline. Pipeline consistently under 12 minutes on PHP project.

</td>
<td width="50%" valign="top">

### #14 — Bambi Audit Batch 10

| | |
|---|---|
| **Date** | 2026-04-12 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | high |
| **Duration** | 17m 23s |
| **Spec coverage** | 5/5 |
| **Agents** | 4 (Explore, backend-api, code-reviewer, adversarial-reviewer) |
| **Guard blocks** | 2 (pipeline-state-write ×1, adversarial-before-reviewer ×1) |
| **Adversarial** | 7 findings (0 accepted, 7 dismissed) |

First Bambi run on v4.3.4. New adversarial-before-reviewer guard caught wrong dispatch order — orchestrator corrected and re-dispatched in correct sequence.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### #15 — Bambi Audit Batch 11

| | |
|---|---|
| **Date** | 2026-04-12 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | high |
| **Duration** | 19m 3s |
| **Spec coverage** | 5/5 |
| **Agents** | 4 (Explore, backend-api, code-reviewer, adversarial-reviewer) |
| **Guard blocks** | 0 |
| **Adversarial** | 5 findings (0 accepted, 5 dismissed) |

First zero-block Bambi run. Pipeline fully autonomous — no guard intervention needed.

</td>
<td width="50%" valign="top">

### #16 — Bambi Audit Batch 12

| | |
|---|---|
| **Date** | 2026-04-12 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | high |
| **Duration** | 11m 40s |
| **Spec coverage** | 5/5 |
| **Agents** | 4 (Explore, backend-api, code-reviewer, adversarial-reviewer) |
| **Guard blocks** | 0 |
| **Adversarial** | 5 findings (0 accepted, 5 dismissed) |

Fastest Bambi run. Distributed locking fixes — complex domain, clean execution.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### #17 — Bambi Audit Batch 14

| | |
|---|---|
| **Date** | 2026-04-12 |
| **Project** | Bambi Plazma (.NET 10) |
| **Effort** | high |
| **Duration** | 8m 32s |
| **Spec coverage** | 5/5 |
| **Agents** | 4 (Explore, testing, code-reviewer, adversarial-reviewer) |
| **Guard blocks** | 0 |
| **Adversarial** | 3 findings (0 accepted, 3 dismissed) |

Fastest run overall. Orchestrator correctly chose `testing` agent (not backend-api) for pure test coverage task. Four consecutive zero-block runs on Bambi.

</td>
<td width="50%" valign="top">

### #18

*Next run...*

</td>
</tr>
</table>
