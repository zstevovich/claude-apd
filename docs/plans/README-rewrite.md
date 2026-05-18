# README rewrite — anti-vibe-coding positioning

> Brainstorm output from 2026-05-18 session. User drafts the final README
> personally. This file is the sketch — iterate freely. Positioning
> decisions in `~/.claude/projects/.../memory/project-readme-positioning.md`.

## Resolved positioning decisions (one-line recap)

- **Audience:** A,B,C,D,E personas (engineers who write the code). NOT F = tech leads.
- **Anti-vibe framing:** subtitle-level (B). Title is positive; tagline mentions softly.
- **Competitor comparison:** zero mentions (C). Differentiation through feature specificity.
- **Format:** pragmatic engineer-front (B). Install → What it gates → When to use → Why → Architecture → Reference.
- **Tone:** engineer-casual (4-5), mostly impersonal with selective "I" in Why, declarative (8-9), minimal humor.

## Draft body (replace the current top portion of README.md, keep logo + badges + footer)

```markdown
<p align="center">
  <img src="docs/logo.svg" alt="APD — Agent Pipeline Development" width="200">
</p>

<p align="center">
  <b>Disciplined AI-assisted development.</b><br>
  Mechanical gates for multi-agent pipelines on Claude Code and OpenAI Codex.
</p>

<p align="center">
  <a href="GETTING-STARTED.md"><b>Getting Started</b></a> &middot;
  <a href="https://zstevovich.github.io/claude-apd/demo/"><b>Demo</b></a> &middot;
  <a href="CHANGELOG.md"><b>Changelog</b></a>
</p>

<p align="center"><b>v6.7.3</b> &middot; MIT &middot; macOS + Linux</p>

![APD Demo](docs/demo/apd-demo.gif)

---

## Install

**Claude Code:**

```bash
/plugin marketplace add zstevovich/claude-apd
/plugin install claude-apd@zstevovich-plugins
/apd-setup
```

**Codex:**

```bash
codex plugin marketplace add zstevovich/claude-apd
codex plugin install codex-apd
apd cdx init .
```

Verify: `bash .claude/bin/apd verify` (CC) or `apd cdx doctor` (Codex). Expects green across hooks, agents, MCP tools, pipeline state.

## What APD gates

APD is a layer of mechanical guardrails over multi-agent AI development. Four gates that hooks, not documentation, enforce:

**1. Pipeline state — orchestrator cannot skip steps.**
Each pipeline phase (spec → builder → reviewer → adversarial → verifier → commit) writes a signed `.done` file via a Go binary using HMAC. The next phase reads and verifies the signature; forged or missing markers block the commit. Doesn't matter what the orchestrator claims to have done — only what the signed pipeline state proves.

**2. Adversarial reviewer with dismissal rationale.**
Every "Full mode" pipeline runs an adversarial-reviewer agent that knows nothing about the spec, just sees the diff. For each finding, the orchestrator writes a structured rationale (`accepted | dismissed | reviewer-self-dismissed`) to `.apd/pipeline/.adversarial-rationale.md`. The verifier hard-blocks the 100%-orchestrator-dismissal pattern (T≥3 && A==0 && Do≥1) — the bypass signature where the orchestrator rationalizes every real finding away. Soft warns on lazy rationales (`ok`, `n/a`, text under 40 chars).

**3. Per-agent scope enforcement.**
Each agent declares its scope in YAML frontmatter (`scope: [src/api, tests/api]`). When the agent tries to write outside scope, the `guard-scope` hook exits 2 and the write is rejected. No "agent decided to also refactor the database layer" — the guard prevents the write at hook time, not after the fact.

**4. R-criteria traceability.**
The spec card lists acceptance criteria as `R1`, `R2`, ..., `RN`. Test files must carry `@trace R<N>` markers. At verifier time, `verify-trace` cross-references criteria against test markers and blocks the commit if any `R*` is uncovered. The verifier doesn't trust "I added tests" — it verifies which criteria those tests actually cover.

Plus: builder cycle cap (no infinite re-dispatch), reviewer cycle cap, max-defects severity gate, post-agent zombie process sweep, agent duration outlier flag, telemetry to `pipeline-metrics.log` for post-mortem analysis.

## When to use APD

- You ship AI-assisted code into a real codebase that other people read and maintain.
- You have hit the edge case explosion that follows when models work at full speed without rigor — scope creep, half-finished features, fabricated test results, regressions where the agent "fixed" the wrong file.
- You spend 30-50% of every AI session on cleanup and human review, and that's not sustainable.
- You want agentic development without giving up on review quality.

## When NOT to use APD

- One-shot scripts, throwaway prototypes, exploratory spikes — overhead larger than benefit.
- Solo learning projects where breaking things is the point.
- Codebases where "looks ok, ship it" is acceptable. APD imposes review friction by design; if you don't need review, you don't need APD.

## Why this exists

I built APD after watching a familiar pattern repeat across months of agentic development.

Vibe-coding produces an *explosion of edge cases*. The model writes plausible code at high speed, but every shortcut compounds — context gets lost between phases, scope quietly expands beyond what was asked, and the discipline you'd expect from a human collaborator is absent. The result is code that passes the model's own self-check but fails the real one: another developer reading it next month, or a corner case the model didn't think to check.

The honest path forward, if you've decided agentic development is worth keeping, is to *bridle the models* — not to abandon them. Treat the orchestrator as a smart-but-overeager pair programmer who will rationalize bypasses if you let it. Hooks, mechanical gates, structured rationale, and signed state are the seatbelts. APD is the framework that wires them in.

A concrete example of the pattern: in a recent test run, the adversarial reviewer raised 5 important findings. The orchestrator wrote `ADVERSARIAL:5:0:5` — five total, zero accepted, five dismissed — and the verifier signed the commit. Three of the dismissals were legitimate (out-of-scope per the diff-only rule); two were "this is already a pattern elsewhere in the suite" — bug propagation reframed as justification. v6.7 closes that loophole with a hard gate on the 100%-orchestrator-dismiss pattern. Every version of APD adds one more such gate.

## Architecture

[Brief overview here — referenca na docs/SPEC.md za deep dive. Možeš zadržati postojeću "What is APD?" sekciju sa ASCII flow + 3 bullet definitions, ili napisati 3-4 paragraph overview pointing at SPEC.]

## Reference

- [Getting Started](GETTING-STARTED.md) — step-by-step setup + first pipeline run
- [SPEC.md](docs/SPEC.md) — authoritative runtime map of every script, hook, guard, MCP tool
- [Changelog](CHANGELOG.md) — release history with motivation per gate
- [Examples](examples/) — full pipeline run on a real Node.js + React project
```

## Open items for the final draft

1. **Architecture section content.** Two options:
   a. Keep the existing "What is APD?" paragraph with the ASCII flow + Agent/Pipeline/Development bullets (zero new writing, conserves voice).
   b. Rewrite as 3-4 paragraph narrative overview pointing at `docs/SPEC.md` for deep dive.
2. **A/B/C/D/E persona names.** Brainstorm only resolved "not F = tech leads". Final copy may or may not name personas explicitly in "When to use" — your call.
3. **Tone calibration on `## Why this exists`.** Current draft = 2 paragraphs + 1 incident example (~190 words). Could be tighter (1 paragraph + incident) or longer (3 paragraphs + incident + 1 follow-on).
4. **The ADVERSARIAL:5:0:5 incident — keep generic or attribute to a public source?** Currently anonymous ("a recent test run"). If you want stronger credibility, could link to the v6.7.0 CHANGELOG entry which references the same incident.

## Next session checklist

When you come back to this:

1. Decide architecture section (open item 1).
2. Trim or expand `## Why this exists` per your preference (open item 3).
3. Replace lines 5-60 of `README.md` with the draft above (preserve logo, badges, demo gif, footer).
4. Optional: link the v6.7.0 CHANGELOG from the incident paragraph if attribution feels safer than anonymity.
5. Update the memory file `project-readme-positioning.md` if any positioning decision changes mid-iteration.
