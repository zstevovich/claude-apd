# Pipeline Runs — Real-World Results

Tracked results from APD pipeline usage in production projects. Not every task — only runs that demonstrate pipeline behavior, catch issues, or show metrics worth recording.

---

<table>
<tr>
<td valign="top">

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
<td valign="top">

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

First adversarial reviewer run. Found CSV separator issue for Serbian locale — only adversarial caught it (no spec context needed).

</td>
<td valign="top">

### #3

| | |
|---|---|
| **Date** | — |
| **Project** | — |
| **Effort** | — |
| **Duration** | — |
| **Spec coverage** | — |
| **Agents** | — |
| **Iterations** | — |
| **Guard blocks** | — |
| **Adversarial** | — |

*Next run...*

</td>
</tr>
</table>
