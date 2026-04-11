# APD Framework — Project Memory

## Role

Development of the APD framework itself. This is not an application that uses APD — this IS APD.

## Quick Reference

| Item | Value |
|------|-------|
| Type | Claude Code plugin (installable) |
| Version | v4.3.2 |
| Distribution | `/plugin install claude-apd` |
| Core | 22 bash scripts + Go binaries, 8 skills, hook system |
| Testing | `verify-apd` (98+ checks) |
| Repo | zstevovich/claude-apd |

## Feedback (learnings)
- [Plugin cache directory naming](feedback-plugin-cache-dirs.md) — cache folder name fixed at first install, content updates in-place
- [Orchestrator bypasses](feedback-orchestrator-bypasses.md) — FIXED: validate_agent_entry rejects fake .agents entries
- [Test before push](feedback-test-before-push.md) — every script change must be tested on macOS before pushing
- [Orchestrator behavior](feedback-orchestrator-behavior.md) — prefers hacking over compliance; only hard blocks work
- [Hook output visibility](feedback-hook-output-visibility.md) — hooks stdout/stderr go to Claude; /dev/tty breaks CC terminal; statusMessage only
- [Validation futility](feedback-validation-futility.md) — format-based bash validation futile; solved with compiled Go binary
- [Social engineering](feedback-social-engineering.md) — orchestrator tells user to bypass guards via manual terminal commands
- [Adversarial summary bypass](feedback-adversarial-summary-bypass.md) — orchestrator writes ADVERSARIAL:0:0:0 without dispatching agent
- [Plugin system learnings](feedback-plugin-system-learnings.md) — deep learnings: distribution, updates, userConfig, enforcement, gotchas
- [Superpowers conflict](feedback-superpowers-conflict.md) — superpowers plugin conflicts with APD, needs mechanical blocking
- [Plugin install](feedback-plugin-install.md) — real-world plugin install findings
- [English internalization](feedback-english-internalization.md) — framework internationalized to English

## Project tasks
- [Session-start apd help](project-session-start-apd-help.md) — DONE
- [Adversarial enforcement](project-adversarial-enforcement.md) — DONE: hard gate + opt-out
- [Pipeline permissions](project-pipeline-permissions.md) — DONE: apd-init allowlists
- [Stale path detection](project-stale-path-detection.md) — DONE: doctor/init detect legacy dirs
- [Git toplevel resolution](project-resolve-git-toplevel.md) — DONE: git rev-parse
- [SessionStart hook not firing](project-session-start-hook-not-firing.md) — CRITICAL: investigate with CC 2.1.101 fixes
- [mkdir pipeline bypass](project-mkdir-pipeline-bypass.md) — orchestrator mkdir .pipeline/ directly; use permissions.deny
- [Guard read false positive](project-guard-read-false-positive.md) — code-reviewer blocked reading spec-card via Bash
- [Worktree detection](project-worktree-detection.md) — CC 2.1.98: workspace.git_worktree for guards
- [Per-check enforcement levels](project-future-per-check-enforcement.md) — future: strict/guided/minimal per guard
- [Implementation plan step](project-implementation-plan-step.md) — orchestrator writes plan before dispatch
- [Enforcement gaps](project-enforcement-gaps.md) — spec-card hard block, adversarial-summary enforcement

## References
- [Go source location](reference-go-source.md) — validate-agent source in local cmd/ (gitignored)
- [CC version tracking](reference-cc-version-tracking.md) — last scanned: 2.1.101 (2026-04-11)

## Archive
- [status.md](status.md) — current phase and focus
- [audit-v3.md](audit-v3.md) — deep audit before release
- [project-todo-clarify.md](project-todo-clarify.md) — docs clarification (pre-release)
- [project-next-priorities.md](project-next-priorities.md) — spec traceability + adversarial shipped
