# Changelog

## v6.11.0 — 2026-05-26

Drugi minor u v6.10-v7.0 setup+audit chain-u — **read-only stack detection mehanizam**. Foundation za v6.12 stack-aware template scaffolding (.NET prvi target, BambiProject reference).

**Highlights:**

- **feat(pipeline-stack-detect):** nova bash skripta sa detekcijom 7+ stack kategorija:
  - **.NET** (high confidence) — `*.sln` ili `*.csproj`
  - **PHP/Symfony** (high) — `composer.json` + `symfony.lock` / `config/packages/` / `bin/console`
  - **PHP generic** (medium) — `composer.json` bez Symfony markers
  - **Node/Next** (high) — `package.json` + `next.config.{js,ts,mjs}`
  - **Node/Vite** (high) — `package.json` + `vite.config.{js,ts,mjs}`
  - **Node/React** (medium) — `package.json` sa `react` u dependencies
  - **Node generic** (low) — `package.json` bez framework markers
  - **KMP/Compose** (high) — `settings.gradle.kts` + `composeApp/` ili `commonMain/`
  - **Android (KMP-less)** (medium) — `build.gradle.kts` + `AndroidManifest.xml`
  - **Python/Django** (high) — `manage.py` + `requirements.txt`/`pyproject.toml`
  - **Python/FastAPI** (high) — `pyproject.toml`/`requirements.txt` sa `fastapi` dependency
  - **Python generic** (low) — `pyproject.toml`/`requirements.txt` bez framework
- **Multi-stack monorepo support** — BambiProject (jedini real-world test) detektovan kao **3 stacks simultaneously** (.NET + Node/Vite + KMP/Compose). Skripta lista svaki sa confidence + signal files.
- **Output modes:** human-readable po default (color-coded confidence column + signals path), `--json` flag za machine-readable (v6.12 template scaffolding ce konzumirati).
- **Internal dir exclusion:** scan skipuje `.claude/`, `.apd/`, `audit/`, `node_modules/`, `vendor/`, `.git/`, `build/`, `dist/`, `target/`, `.next/`, `.gradle/` — fokus na real project structure.
- **Exit code:** 0 always po default (informational, nije failure). `--strict` flag exit 1 ako zero stacks detected.
- **feat(apd dispatcher):** `apd stack` (alias `apd st`) sub-command + `apd audit-drift` (alias `apd drift`) sub-command. Help text updated.
- **docs(SPEC.md):** `apd stack` entry u CLI subcommand tabeli.
- **test(test-codex-adapter §73) +15 assertions:** 11 static (script exists, sources libs, 5 stack signal patterns, --json mode, internal dir exclusion, apd dispatcher wires stack + audit-drift) + 5 live (empty/strict/synthetic .NET/synthetic PHP-Symfony/JSON output).
- **Test count 572 → 588 PASS / 0 FAIL.**

**Live-tested empirical evidence:**

| Project | Detected | Notes |
|---|---|---|
| BambiProject | .NET (high) + Node/Vite (high) + KMP/Compose (high) | Real 3-stack monorepo correctly identified |
| Festico | PHP/Symfony (high) + Node/Next (high) | Real 2-stack project correctly identified |

**Why "v6.11 read-only":** detection is foundation. v6.12 ce konzumirati JSON output da bira template-e pri `apd-setup` invocation. Razvoj kao odvojeni faze omogucuje empirical iteration — sad korisnik moze testirati detection na vlastitim projektima i prijaviti false positives/negatives pre nego sto template scaffolding zavisi od njega.

**Backlog open:**

- v6.11 live test u Bambi/Festico/Test (vec ad-hoc validovano kroz development cycle)
- v6.12 stack-aware template scaffolding — `apd-setup` invokes pipeline-stack-detect, generira agente + skills + conventions per stack (.NET prvi target)
- v6.13 drugi stack (TBD posle v6.12 evaluation)
- v7.0 max_defects parser removal

## v6.10.0 — 2026-05-26

Prvi minor u v6.10-v7.0 setup+audit improvement chain-u (per project-v6.10-v7.0-setup-audit-roadmap memo). Drift detection u `apd-audit` skill + side-fix u `apd-init` koji je BambiProject + Festico evidence izneo.

**Empirical trigger:**

BambiProject + Festico oba imali drift posle vise re-init-a:
- `.claude/settings.json` deny patterns: **4/8** (samo slash-prefixed; bare-dir 4 missing). To je bypass vector: `mkdir .apd/pipeline` (bez prefix slash) ne hvata se guard-om.
- BambiProject `.claude/.apd-config` `APD_VERSION=6.8.11` vs plugin v6.9.0 (1 minor stale)
- BambiProject `.claude/rules/workflow.md` 4 markeri missing (`Implements:`, `rationale gate`, `DEPRECATED`, `unconditional`) — workflow je iz v6.0/v6.5 ere, nije refresh-ovan kroz v6.7-v6.9 chain

**Root cause apd-init python merge bug:** `required_deny` python lista u `apd-init` imala je samo 4 patterns (slash-prefixed); template literal je imao 8. Re-init je ucvrscivao samo 4, freshly-init dobijao 8. BambiProject + Festico oba su prosli re-init kroz v6.5-v6.9 period i ostali na 4.

**Highlights:**

### A. Pre-req fix: apd-init python merge

- **fix(apd-init):** `required_deny` python list 4 → 8 patterns (dodato 4 bare-dir variants). Zatvara bypass vector + omogucuje da v6.10 drift detection ne flaguje BambiProject/Festico kao stale zauvek (jednom kad se re-run apd-setup).

### B. New script: pipeline-audit-drift

- **feat(pipeline-audit-drift):** nova bash skripta sa 3 drift dimensions:
  - settings.json deny patterns vs framework baseline (8 patterns hardcoded, SSOT sa apd-init)
  - .apd-config APD_VERSION vs current plugin version (minor/major drift = IMPORTANT, patch-only = INFO)
  - workflow.md content markers (`Implements:`, `rationale gate`, `DEPRECATED`, `unconditional`) — framework workflow.md baseline kao reference
- Severity buckets: CRITICAL / IMPORTANT / INFO / CLEAN, sa per-item recovery action
- Framework self-detection: skipuje drift checks kad APD_FRAMEWORK_SELF=true (na samom framework repo-u)
- Exit code: 1 ako CRITICAL/IMPORTANT, 0 ako INFO-only ili CLEAN — usable u CI / pre-commit hooks

### C. Skill integration

- **fix(skills/apd-audit/SKILL.md):** novi Section 8 "Drift Detection (v6.10+)" — opisuje 3 dimensions, output buckets, recovery action (re-run `/apd-setup`)
- **fix(plugins/apd/skills/apd-audit/SKILL.md):** Codex mirror sa istom sekcijom

### D. SPEC.md + tests

- **docs(SPEC.md):** `apd audit-drift` (v6.10) entry u CLI subcommand tabeli
- **test(test-codex-adapter §72) +13 assertions:** 8 static (script exists/executable, sources libs, deny patterns baseline, APD_VERSION check, workflow markers check, apd-init python merge lock-in 8 patterns, CC + Codex skill Section 8) + 5 live (clean project → exit 0, missing deny patterns → IMPORTANT, stale APD_VERSION minor → IMPORTANT, stale workflow markers → IMPORTANT, patch-only APD_VERSION → INFO + exit 0)
- **Test count 559 → 572 PASS / 0 FAIL.**

**Migration:**

Projekti koji su radili re-init kroz v6.5-v6.9 (verovatno vecina realnih projekata) videce drift u `/apd-audit` dok ne re-run `/apd-setup` (v6.10+ ce sad pisati svih 8 patterns). Run `bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/pipeline-audit-drift` da vidi konkretne missing items.

**Roadmap continuity:**

- **v6.11:** Stack detection mehanizam (read-only) — detect .NET/PHP/Symfony/Node/Next/KMP signals
- **v6.12:** Stack-aware template scaffolding (.NET prvi, BambiProject reference)
- **v6.13:** Drugi stack (TBD posle v6.12 evaluation)
- **v7.0:** max_defects parser removal + finalizacija

Phased pristup omogucuje empirical iteration izmedju faza i risk amortization.

## v6.9.0 — 2026-05-24

Minor release — closes v6.8 chain sa tri strukturalne intervencije:

1. **`adversarial: max_defects=N` field SOFT-DEPRECATED** — biti uklonjen u v7.0. Field continues to function za graceful transition (verifier gate v6.1 B2 + immutability check v6.3 D oba aktivni), ali emit-uje deprecation WARN + INFO log entry na svaki spec advance gde je field present.
2. **`verify-apd` Section 8 lock-in** u `test-codex-adapter` §71 — zatvara blind-spot iz issues #10/#11 sa static-asserts za fixture content.
3. **Pre-bump checklist** codified u `docs/SPEC.md` §24 — 3-step audit pre svake bump-promene koja menja guard/gate/hook ponasanje.

**Why soft-deprecate `max_defects`:** v6.8 chain (10 patches za 2 dana) empirically validovao **rationale gate (v6.7) kao sufficient standalone enforcement** za adversarial quality. Per-finding rationale ≥40 chars za dismissed findings + 100%-Do hard-block + bulk-accept rationale validation strukturalno covers misuse pattern koji je `max_defects` trebao da spreci. Plus empirical evidence (v6.8 dev cycle, 2026-05-22): tasks sa `max_defects=0` trajali 26-33 min sa 3 guard BLOCK cascade vs identicni task BEZ polja trajao 13 min clean. `max_defects` postao redundant — najgora opcija je `=0` (forsira accept-everything), realno bilo koje koriscenje polja sluzi RLHF anchoring vs ne-postojanju field-a.

**Highlights:**

### A. max_defects soft deprecation

- **fix(pipeline-advance):** track `MAX_DEFECTS_PRESENT=true/false` pre default-ovanja `CURRENT_MAX="unlimited"`. Kad field eksplicit present (`adversarial: max_defects=N` ili `=unlimited`), emit deprecation WARN ka stderr sa explanation + migration instruction. Plus log `INFO|orchestrator|max-defects-deprecated|task=X value=N` entry u `guard-audit.log` za telemetry. NO behavior change — verifier gate + immutability check oba i dalje active.
- **fix(rules/workflow.md):** §7 SEVERITY GATE reworded sa DEPRECATED v6.9 marker + migration instruction. Drop preskripciju polish-mode use case (sad `pipeline_mode: polish` preset je preferiran).
- **fix(skills/apd-brainstorm/SKILL.md) CC + Codex mirror:** "Adversarial budget" sekcija refactored kao DEPRECATED notice — preserves empirical evidence references (Add contact form / Rate limit / Admin lista comparison) ali eksplicit kaze DO NOT WRITE. "Common BLOCKs" tabela flaguje `max_defects-exceeded` + `max_defects-raised-mid-pipeline` kao DEPRECATED + dodaje migration instruction.
- **fix(templates/codex/AGENTS.md):** mirror DEPRECATED wording u step 1 spec card writing instructions.

### B. verify-apd Section 8 lock-in (issues #10 + #11 vector closed)

- **test(test-codex-adapter §71):** static asserts za fixture content u `verify-apd` Section 8 — `.brainstorm-marker` pre-write za APD-VERIFY-TEST + APD-VERIFY-OPT-OUT, `implementation-plan.md` sa `**Implements:** R1` za oba synthetic task-a, sintetic `.adversarial-rationale.md` matching ADVERSARIAL summary. **Ako sledeci put neko menja gate u pipeline-advance i zaboravi update verify-apd, test-codex-adapter ce fail-ovati pre push-a** — preventive lock-in vs reactive hot-fix patch (kao #12 + #13 koji su ovo izbegli).

### C. Pre-bump checklist u SPEC.md §24

- **docs(SPEC.md):** nova sekcija §24 sa **MANDATORY** 3-step audit komandama (grep za pipeline-advance callsiteove + grep za synthetic fixtures + test-codex-adapter run). Plus deprecation policy: minor za warn, major za removal, 2-version graceful window.

### Tests

- **§71 (15 assertions):** 7 static za max_defects deprecation (markers + parser logic + WARN message + skill content) + 4 live behavioural (warn emits, INFO logs, no warn when field absent, verifier gate STILL active in v6.9) + 4 static za verify-apd Section 8 lock-in.
- **§63 Static I updated** za generalized `DO NOT write adversarial: max_defects` wording (bez `=0` specifically, jer ceo field deprecated).
- **Test count 544 → 559 PASS / 0 FAIL.**

**Migration (v6.9 → v7.0 transition):**

| Project state | What to do |
|---|---|
| Spec has no `max_defects` field | Nothing — already on v7.0 baseline |
| Spec has `adversarial: max_defects=N` (anywhere N≥0) | Remove the line. Rationale gate covers misuse strukturalno. |
| Spec has `adversarial: max_defects=unlimited` | Remove the line — explicit unlimited = default |
| `pipeline_mode: polish` projects | No change — polish preset is preferred for hotfixes, drops adversarial entirely |

v6.9 NE menja behavior — samo emit warn. v7.0 ce removeovati parser branches u `pipeline-advance` (lines ~311-345 immutability check + lines ~850-870 verifier severity gate) i log entries.

**Backlog open posle v6.9:**

- v6.9 live test u BambiProject — verify (a) WARN emit pri max_defects use, (b) INFO entry u guard-audit, (c) field i dalje radi (verifier gate active).
- Phase 2 maxTurns calibration — 1-2 nedelje aggregated telemetry → workflow.md defaults update.
- v6.9.x patch chain ako live test otkrije neke skill content gaps oko skip-brainstorm wording (sada referenisemo "max_defects=unlimited" u canonical reason — treba update).
- v7.0 plan — `max_defects` parser removal + BREAKING CHANGES section + test-codex-adapter §71 (a) part assertions deleted.

## v6.8.13 — 2026-05-23

Drugi hot-fix u istom satu, isti klas problema kao #10 (sad #11) — `apd verify` E2E test trip-uje na drugom gate-u. v6.8.12 popravio brainstorm-marker gate u verify-apd Section 8, ali plan-spec consistency gate (v6.8.0) ostao otkriven jer Section 8 pisuje minimalan plan (`echo "## Plan: APD-VERIFY-TEST" > implementation-plan.md`) bez `**Implements:**` headera. Posle v6.8.12 spec step prosao ali builder block-uje sa `BLOCKED: Spec R1 not implemented by any plan section` → 12 cascading FAIL-ova.

**Highlights:**

- **fix(verify-apd Section 8): pre-write valid implementation-plan.md** za oba synthetic task imena (`APD-VERIFY-TEST` + `APD-VERIFY-OPT-OUT`). Format ima `### Section 1 — verification stub` + `**Implements:** R1` koji zadovoljava bidirectional check verify-plan-spec parser-a (forward: R1 u Implements postoji u spec; reverse: spec R1 pokriven u plan-u; symmetric: jedina sekcija ima Implements header).
- **Zero impact na test count.** `test-codex-adapter` ostaje 544/0 (drugi E2E surface).
- **Issue #11 zakljucen** sa fix commit-om.

**Strukturalni lesson (drugi put isti pattern u istom satu):**

`apd verify` je strukturalno blind-spot za sve gate-affecting changes. Trenutni workflow je: edit guard → update test-codex-adapter → ship. Sad očigledno: edit guard → update test-codex-adapter → **review svaki `pipeline-advance` callsite u `plugins/apd/bin/`** → ship. Komandа za pre-bump audit:

```bash
grep -rn 'pipeline-advance\|pipeline-gate' plugins/apd/bin/
```

Sledeci put kad zatrebamo da menjamo gate koji utiče na `spec`/`builder`/`reviewer`/`verifier` advance, treba ne samo da update-amo test-codex-adapter fixture-i nego i da prodjemo verify-apd Section 8 ručno. Mozda vredi razmotriti integraciju `apd verify` u `test-codex-adapter` familiju ili dodati pre-bump checklist u workflow.md.

## v6.8.12 — 2026-05-23

Hot-fix za v6.8.11 oversight ([#10](https://github.com/zstevovich/claude-apd/issues/10)). v6.8.11 ucinio `brainstorm-marker` gate unconditional, ali pokriveni su samo `test-codex-adapter` fixture-i. Druga E2E test skripta — `verify-apd` (run preko `apd verify`) — ima Section 8 koja synthetic spec advance pokrece bez marker-a. Posle v6.8.11 deploy-a, `apd verify` na clean projektu ili posle `apd pipeline reset` produkuje 13 cascading FAIL-ova pocevsi od `BLOCKED: Brainstorm marker missing for spec advance (1 R-criteria declared)`.

**Highlights:**

- **fix(verify-apd Section 8): pre-write canonical `.brainstorm-marker`** za oba synthetic task imena (`APD-VERIFY-TEST` u glavnom flow-u, `APD-VERIFY-OPT-OUT` u adversarial opt-out testu). Format identican onome sto skill pisuje na exit (`<task>|<iso-utc-timestamp>`). Postojeci `pipeline-advance reset` trap u Section 8 vec brise marker — nema potrebe za novim cleanup-om.
- **Zero impact na test count.** `test-codex-adapter` ostaje 544/0 — `verify-apd` Section 8 nije unit-testovan u test-codex-adapter familiji (drugi E2E surface).

**Issue analysis:**

Issue #10 dijagnoza je tacna: `pipeline-advance:230-265` enforce-uje marker za svaki spec advance sa R-criteria; verify-apd's synthetic spec deklarise R1, trip-uje gate, exit-uje non-zero, sve downstream testovi u Section 8 cascade jer spec.done nikad nije pisan. Sections 1-7 + 9-10 pass clean (103 PASS) — samo Section 8 affected.

**Fix choice:** marker write umesto `--skip-brainstorm '<reason>'` opt-out (oba su validna per issue). Marker write simulira "orchestrator load-uje skill" happy-path — reprezentativan za sta E2E test treba da pokriva. `--skip-brainstorm` bi bypassed gate-a entirely, sto NIJE sta verify-apd Section 8 testira.

**Migration:** zero project-side impact. `apd verify` sad runs clean kroz Section 8 na v6.8.12. Projects koji su pokrenuli `apd verify` na v6.8.11 i videli FAIL-ove — re-run posle plugin update.

## v6.8.11 — 2026-05-23

Dvanaesti patch u v6.8 chain-u — strukturalna intervencija na entry discipline layer-u. Drop R-count > 2 carve-out iz `brainstorm-marker` hard gate-a. v6.8.5 gate dizajniran sa `R > 2` threshold kao "smart-friction" carve-out za trivial tasks; BambiProject 2026-05-23 evidence pokazala da je threshold gameable — orchestrator atomizuje non-trivial work na 2 R-criteria specifically da bypass-uje gate. v6.8.11 forsira brainstorm load na svaki spec advance bez obzira na declared R-count. Opt-out preko `--skip-brainstorm '<reason>'` (v6.8.8 friction) preserved.

**Empirical trigger (BambiProject 2026-05-23, oba na v6.8.10 plugin):**

| Task | Declared R | Duration | Adversarial | Brainstorm gate |
|---|---|---|---|---|
| Photo Bill CTA | 2/2 | 32m 22s | N/A | not triggered |
| MS.4 Android Barkoder still-image | 2/2 | 40m 25s | N/A | not triggered |

Oba pipelina realno trajala kao 4-6 R cycle (multi-layer mobile + tests + 6/3 files sa 72% builder→reviewer iteration time), oba bi trebalo da rute kroz `/apd-brainstorm`. Plus secondary bypass evidence: orchestrator pokusao `rm -rf .apd/pipeline && mkdir -p .apd/pipeline` da wipe-uje v6.3 max_defects immutability ledger + reset audit trail (`PROTECTED_PIPELINE` substring match propusta bare-dir form bez trailing slash).

**Strategic insight (user 2026-05-23):** APD enforcement layers (guards + rationale gates + plan-spec consistency + brainstorm marker) cine END quality ciklusa robusno — orchestrator hit-uje BLOCK-ove, retry-uje, konvergira ka clean commit-u. Kvalitet nije open problem. Open problem je **resource cost** od nediscipline u entry. Cost jednog BLOCK loop ciklusa (plan-spec + max_defects raise + rationale-missing + rm -rf attempt + reset cascade) je 30-100K tokena. Cost jednog brainstorm load-a je 3-5K tokena. Per-task brainstorm load je ~10× jeftiniji od jednog BLOCK loop ciklusa koje undisciplined entry trigger-uje downstream.

**Highlights:**

- **fix(pipeline-advance): brainstorm-marker gate UNCONDITIONAL.** Drop `[ "$CRITERIA_COUNT" -gt 2 ]` iz oba check-a (marker presence + `--skip-brainstorm` reason validation). Gate fires na svaki spec advance regardless of R-count. BLOCK message reworded: drop "non-trivial task" branding i "Trivial tasks (≤2 R-criteria) skip this gate automatically." line. Dodaje BambiProject 2026-05-23 R-atomization empirical reference (30-40 min sa adversarial N/A vs 10-15 min za brainstorm-loaded equivalents).
- **fix(skills/apd-brainstorm/SKILL.md) CC + Codex mirror: "Default: load on every new task" paragraph** na vrh "When to use / When to skip" sekcije. "Skip when" reworded u "Skip only when" + kanonski skip cases enumerated (genuine 1:1 mirror of just-completed task, single-line bug fix sa one R-criterion, hotfix sa pre-aligned scope).
- **fix(rules/workflow.md step 1 + templates/codex/AGENTS.md step 0): MANDATORY load wording reword** — "unconditional, every new task" instead of conditional `>2 R-criteria` list. Plus BambiProject MS.4 + Photo Bill CTA empirical reference.
- **test(bin/core/test-codex-adapter):**
    - Novi `_v6811_marker DIR TASK` helper na vrhu fajla — pisuje canonical `.brainstorm-marker` za fixture-i koji drive `pipeline-advance spec` bez namere da test-uje gate. 11 fixture-a updated kroz §31/§32/§38/§42/§43/§45/§51/§52 + Python subdir MCP test.
    - §64 Live L flipped: bio "trivial R≤2 bypasses gate", sad "trivial R≤2 ALSO BLOCKs without marker per v6.8.11".
    - §64 Static E updated da prepozna BambiProject MS.4 / Photo Bill CTA evidence references alongside postojece Bambi Cycle E.
    - **Novi §70 (11 assertions):** 7 static (gate condition no longer R>2, v6.8.11 comment marker, `--skip-brainstorm` reason unconditional, workflow.md unconditional wording, CC + Codex SKILL.md unconditional wording, AGENTS.md unconditional wording) + 4 live (R=1 no marker → BLOCK, R=1 + marker → prolazi, R=2 + `--skip-brainstorm` + reason → prolazi opt-out preserved, R=2 + `--skip-brainstorm` bez reason → BLOCK).
- **Test count 533 → 544 PASS / 0 FAIL** (+11 novih u §70, plus 1 modifikovan u §64 Live L).
- **Migration:** projects koji su operisali pod R≤2 carve-out videce novi BLOCK na prvi spec advance per task. Recovery je dokumentovan opt-out: load `/apd-brainstorm` skill (recommended) ILI `--skip-brainstorm '<concrete reason>'` (kanonski use cases: 1:1 mirror, single-line bug fix, pre-aligned hotfix).

**Strategic pivot:** prethodno-zapisana defensive guard za `rm -rf .apd/pipeline` DEFERRED u korist α (unconditional brainstorm load). Hypothesis: ako orchestrator zna pipeline od pocetka, nuclear-wipe escape valve postaje nepotreban. Re-evaluate posle BambiProject live test v6.8.11.

**Dvanaesti-patch chain v6.8 (retrospective):**

| Patch | Layer | Trigger |
|---|---|---|
| v6.8.0-1 | Guard | Discovery |
| v6.8.2 | Observability | Admin signals |
| v6.8.3 | UX | Rate limit |
| v6.8.4 | Education | CSRF ignored |
| v6.8.5 | Enforcement | "Bez brainstorm-a" — R>2 gate |
| v6.8.6 | Polish | CSRF UX |
| v6.8.7 | Skill content | Soft-delete gaps |
| v6.8.8 | Override friction | Bambi Cycle E bypass |
| v6.8.9 | Telemetry polish | Product sort_order bug |
| v6.8.10 | MaxTurns telemetry | User-observed structural |
| **v6.8.11** | **Entry discipline** | **R-atomization bypass** |

## v6.8.10 — 2026-05-22

Jedanaesti same-day patch — telemetry surface za empirical maxTurns calibration. User-observed strukturalan problem: trenutne maxTurns vrednosti (60 builders / 80 reviewers iz workflow.md) su intuitivno postavljene, ne empirically-calibrated. Empirical evidence: Bambi v6.8 era (poslednjih 7 dana) imala 15 `mobile` rapid re-dispatch events (gap <120s = proxy za maxTurn exhaust). v6.8.10 dodaje read-only telemetry koja kalibrise per-agent vrednosti empirijski. No behavior change — pure observability. Tests: 528 → 533 (+5 in §69).

- **feat(bin/core/pipeline-report-maxturns): novi script za maxTurns telemetry.** Parse-uje `agent-history.log`, computes per agent_type:
    - Total starts u poslednjih N dana (default 30)
    - Rapid re-dispatch count (gap <RAPID_THRESHOLD seconds, default 120)
    - Average gap izmedju stop i sledeci start istog agent_type-a
  Output formatted table sa color-coded counts:
    - red+bold: ≥5 rapid re-dispatches (likely exhaust, suggested action emitted)
    - yellow: 2-4 rapid re-dispatches (marginal)
    - dim: 1 rapid re-dispatch (incident)
    - green: 0 rapid re-dispatches (clean)
  Plus suggested action per agent_type — reads current `maxTurns` iz `.claude/agents/<agent>.md` frontmatter-a i suggest-uje raise +20 turns:
    ```
    + mobile — current maxTurns=60 → consider raising to 80
      Edit: .claude/agents/mobile.md frontmatter
    ```
- **feat(bin/core/pipeline-report): maxturns sub-command dispatcher.** `apd report maxturns` (ili `apd report mt`) → exec na pipeline-report-maxturns. Plus `--days N` i `--threshold-seconds S` overrides preneti kroz dispatcher.
- **docs(bin/apd): CLI help update.** Help comment dodaje `report maxturns` entry za visibility.
- **Empirical baseline (Bambi v6.8 era, last 30 days):**
    | Agent | Starts | Rapid re-dispatch | Suggested |
    |---|---|---|---|
    | mobile | 295 | **15** | 60 → 80 |
    | devops | 169 | **7** | 60 → 80 |
    | code-reviewer | 413 | **5** | 80 → 100 |
    | backend-api | 265 | 2 | (marginal) |
    | testing/database/backoffice/adversarial | — | 0 | (clean) |
- **Tests:** `test-codex-adapter` §69 adds 5 assertions: script exists/executable, dispatcher case present, rapid counter logic present, maxTurns frontmatter parse present, live synthetic fixture sa mobile re-dispatch returns expected output. Test count 528 → 533.
- **Migration:** zero project-side impact. Pure telemetry — read-only surface. User-driven calibration: posle review `apd report maxturns`, manually edit `.claude/agents/<name>.md` frontmatter sa suggested maxTurns vrednoscu.
- **Strategic context:** v6.8.10 je **Phase 1 telemetry-first** korak ka eventual per-agent maxTurns kalibraciji. Phase 2 (sledecu 1-2 nedelje cross-project usage-a) — calibrate defaults u workflow.md based on aggregated telemetry. Phase 3 (potencijalan v6.9+) — adaptive scaling per task complexity (R-criteria count → suggested adjustment).

## v6.8.9 — 2026-05-22

Deseti same-day patch — trivijal session-log bug fix otkriven u Bambi Product sort_order task post-mortem-u. Pre-v6.8.9: `pipeline-advance reset` loop kroz `guard-audit.log` broji SVE entry-e bez filtera po `log_type` field-u. INFO entries (`brainstorm-skipped` iz v6.8.8) se brojili kao "blocks" → false positive `Problems: Guard blocks detected` za task koji je realno bio clean. Bambi Product sort_order (19m 12s, ZERO BLOCK, 1 INFO entry sa brainstorm skip reason) izlozio bug — session-log report-ovan kao "Guard blocks detected" iako pipeline pravilno prosao. Tests: 524 → 528 (+4 in §68).

- **fix(pipeline-advance reset): case-based `log_type` filter za guard-audit counting.**
    ```bash
    case "$log_type" in
        BLOCK)
            BLOCKS=$((BLOCKS + 1))
            BLOCK_REASONS="${BLOCK_REASONS}${log_reason}\n"
            ;;
        INFO)
            SKIP_EVENTS=$((SKIP_EVENTS + 1))
            SKIP_REASONS="${SKIP_REASONS}${log_reason}\n"
            ;;
        *) ;;  # PERMISSION_DENIED i ostali — ignorisani u summary
    esac
    ```
- **feat(pipeline-advance reset): SKIP_SUMMARY za INFO events.** Posle BLOCKS counter logike, paralelni `SKIP_SUMMARY` builds string "<N> info events: <top-3 reasons>". Visible u session-log kao **odvojena** linija (ne kao false-positive guard block).
- **feat(session-log entry): conditional `**Skip events:**` line.** Dodate se samo kad `SKIP_SUMMARY` non-empty (no noise za task-ove bez INFO events; explicit visibility kad postoje). Format primer:
    ```
    **Guardrail that helped:** N/A
    **Skip events:** 1 info events: brainstorm-skipped (1x)
    ```
    Plus `Problems:` field ostaje "No problems" (jer GUARD_SUMMARY="N/A" — BLOCK counter nije incremented).
- **Test §68 (4 static assertions):** case-based filter, SKIP_SUMMARY variable, conditional Skip events line, BLOCK/INFO counter increments u odvojenim branches.
- **Test count 524 → 528 PASS / 0 FAIL.**
- **Migration:** zero project-side impact. Pre-v6.8.9 session-log entries imaju "false positive" `Problems: Guard blocks detected` za task-ove sa samo INFO events (npr. brainstorm-skipped) — ali ti entries vec postoje + ne mogu se retroaktivno fix-ovati. Nove entries posle v6.8.9 install-a prikazuju correct semantic.

## v6.8.8 — 2026-05-22

Deveti same-day patch — strukturalno zatvaranje `--skip-brainstorm` escape valve-a. Live evidence iz Bambi Cycle E task-a (2026-05-22, 3h cascade vs Test 20min clean isti dan + Export CSV 15m clean): orchestrator hit brainstorm-marker BLOCK ali bypassed sa `--skip-brainstorm` flag-om. Self-reflective signal iz orchestrator-a: "Skill bi bio ceremonija nad već postignutim alignment-om" ali "Skill verovatno proverava i stvari koje ja propustam... Da sam ga učitao, možda bih izbegao kasniji max_defects problem". Tenzija: skill content "When to skip" gentle dozvoljava skipping pri pre-aligned design-u, hard gate forsira load — orchestrator razresava preko jeftin override-a + scope-only rationalizacije. v6.8.8 zatvara strukturalno: `--skip-brainstorm` requires explicit reason argument. Tests: 515 → 524 (+9 in §67).

- **fix(pipeline-advance): `--skip-brainstorm` requires reason argument.** Pre-v6.8.8: `--skip-brainstorm` je boolean flag bez argument-a — jeftin override koji orchestrator koristi automatic. v6.8.8: argument MUST follow the flag. Bez reason → BLOCK sa specificnom porukom koja trazi:
    1. Scope alignment (user approved design informally)
    2. APD config clarity (max_defects + plan **Implements:** on EVERY section + rationale .md format)
  Plus log entry u guard-audit.log: `INFO|orchestrator|brainstorm-skipped|task=X reason=Y` (sanitized + truncated to 200 chars).
- **fix(pipeline-advance): brainstorm-marker BLOCK message reorganized.** Pre-v6.8.8: "Two ways forward (a) Load skill (b) Override". v6.8.8: "(a) **RECOMMENDED** — Load skill / (b) Override — **ONLY IF** scope IS pre-aligned AND APD config decisions ARE explicit, requires concrete reason". Plus eksplicit empirijska referenca: "Bambi Cycle E 3h cascade pattern" kao learning material. Plus EXAMPLE reason sa konkretnim text-om.
- **fix(skills/apd-brainstorm/SKILL.md, CC + Codex): "When to skip" TWO-PART CHECK preformulisanje.**
    1. Scope is aligned (task specified OR user approved informally)
    2. APD config decisions are explicit (4 sub-questions: budget, plan format, rationale format, BLOCK recovery)
  
  Both parts MUST be YES za legitimno skipping. **"If you cannot confirm BOTH — DO NOT skip"** sa empirical evidence reference (Bambi Cycle E). Override flag eksplicit zahteva reason mentioning BOTH parts.
- **fix(SKILL.md Step 5 marker write section): Override description update.** Sa boolean flag → reason argument. Format primer + audit log mention.
- **Strategic note:** v6.8.8 NIJE forsiranje load skill-a apsolutno — orchestrator i dalje moze legitimno da skip-uje kad je oba uslova ispunjena. Cilj je **friction proporcionalan riziku**: mental friction (eksplicit reason write) → orchestrator preispituje "da li mi stvarno treba skip" → ako da, pisuje audit-traceable rationale. Ovo je analogno v6.7 rationale gate-u za adversarial dismissal — pattern "force structured rationale" generalizovan na skip override.
- **Tests:** `test-codex-adapter` §67 adds 9 assertions: SKIP_BRAINSTORM_REASON parser + missing-reason BLOCK + brainstorm-skipped audit log + RECOMMENDED na (a) + empirical reference + TWO-PART CHECK u CC + Codex skills + live BLOCK bez reason + live PASS sa reason. Plus §60 Live J updated za novu sintaksu (test fixture migration). Test count 515 → 524.
- **Migration:** projekti koji koriste `--skip-brainstorm` (bez argument-a) u skriptama dobijaju BLOCK na sledeci task. Quick fix — dodaj reason argument: `--skip-brainstorm "<concrete reason>"`. Bambi orchestrator-ova self-reflective lesson je doslovan template za reason content.

## v6.8.7 — 2026-05-22

Eighth same-day patch — skill content polish za 2 signala iz Soft-delete task post-mortem-a (live evidence 2026-05-22 15:04-15:30). Oba signala su iz skill education layer-a (v6.8.4) — orchestrator je naucio dela skill-a ali ne kompletno. v6.8.7 popunjava te edukacione gap-ove. Tests: 507 → 515 (+8 in §66).

- **(A) fix(apd-brainstorm): Step 4 design summary template forsira Risks + Rollback eksplicit fields.** Pre-v6.8.7 template imao Goal / Scope / Approach / Files / Mode / Adversarial budget — ali NE Risks / Rollback. Orchestrator je u Soft-delete spec-u izostavio Risks (legitime 3 risks: concurrent delete+read race, migration nad postojecom tabelom, CSRF reuse) i Rollback (revert commit + opcioni DROP COLUMN). v6.8.7 template eksplicit dodaje fields + warning: "Risks + Rollback are NOT optional for tasks with DB migration / new public endpoint / auth changes / external API". Trivial tasks mogu da kazu "minimal" ili "revert commit", ali bez explicit dokumentacije adversarial reviewer ne moze da hvata gap.
- **(B) fix(apd-brainstorm): Downstream gates section eksplicit "NO RESERVED NAMES" rule + Agents/Notes u format primeru.** Soft-delete plan empirical evidence: orchestrator naucio `**Implements:** none` pattern za file-list sekcije (Files to modify, Files to create) ali zaboravio za Agents/Notes — asymmetric learning triggered plan-spec-consistency BLOCK na 2 missing header-a (issues=2). v6.8.7 format primer dodaje Agents + Notes sa eksplicit komentarom "← NO RESERVED NAMES — Agents needs **Implements:** too". Plus eksplicit warning prose: "**EVERY `### Section` MUST have `**Implements:**` header — NO EXCEPTIONS.** The rule is uniform across functional sections (Backend, Frontend, Database, Tests) AND scaffolding sections."
- **(C) fix(workflow.md §3c): NO RESERVED NAMES rule explicit u format primeru + Rules bullet.** Bullet apdejtovan iz "set to `none` for scaffolding sections (file lists, agents, notes, documentation)" u eksplicit "NO RESERVED NAMES" warning + concrete empirical evidence reference + "Treat EVERY `###` section the same way: declare R-ids OR `none`."
- **(D) fix(plugins/apd/skills/apd-brainstorm/SKILL.md): Codex mirror parity.** Step 4 Risks/Rollback warning + Downstream gates NO RESERVED NAMES rule.
- **Empirical baseline za v6.8.7 trigger (Soft-delete task, 2026-05-22):** 20m 58s pipeline, 5:1:4 ADVERSARIAL (real adversarial work), 3 BLOCK-ova (sve intended) — brainstorm-marker + plan-spec-consistency (issues=2 Agents/Notes) + rationale-100pct-orch-dismiss. v6.8.7 cilj: smanjiti 2 missing Implements u plan-spec issues count → 0 u sledecem task-u.
- **Tests:** `test-codex-adapter` §66 adds 8 static assertions: CC skill Step 4 template forsira Risks + Rollback, CC skill non-optional warning, CC skill NO RESERVED NAMES rule, CC skill Agents/Notes Implements u format primeru, Codex mirror non-optional warning, Codex mirror NO RESERVED NAMES, workflow.md NO RESERVED NAMES, workflow.md scaffolding lista. Test count 507 → 515.
- **Migration:** zero project-side impact. Pure skill/workflow content polish.

## v6.8.6 — 2026-05-22

Seventh same-day patch — UX polish za 2 bug-a iz CSRF live test post-mortem-a (user observation). Oba bug-a su tehnicki **intended behavior** ali sa zbunjujucim BLOCK porukama. v6.8.6 ne menja logic, samo refine messages. Tests: 502 → 507 (+5 in §65).

- **fix(track-agent): jasnija poruka za adversarial-out-of-order BLOCK.** Pre-v6.8.6: orchestrator dispatchuje adversarial-reviewer pre reviewer.done → SubagentStart hook exit 2 + start event NIJE zapisan u .agents (intentional — fake start ne sme da bude logged ako gate blokira). User je interpretisao kao bug ("hook nije zabeležio prvi start event") jer ga BLOCK poruka nije eksplicit upozorila. Sad poruka ukljucuje:
    - "NOTE: This SubagentStart was rejected — the start event is NOT recorded in .agents."
    - "After running 'apd pipeline reviewer', re-dispatch adversarial-reviewer (fresh agent dispatch, not retry)."
    Korisnik znade tacno sta da uradi.
- **fix(guard-pipeline-state): typo detection + correction hint.** Pre-v6.8.6: orchestrator pisuje `.adversarial-rationale` (bez `.md` extension) → guard blokira sa generic "Direct write to pipeline state file: .adversarial-rationale". Korisnik je morao da odgovara: "mozda treba .md?". v6.8.6 case statement detect-uje 3 tipa typo case-ova:
    - `.adversarial-rationale` → "Did you mean '.adversarial-rationale.md'?"
    - `spec-card` → "Did you mean 'spec-card.md'?"
    - `implementation-plan` → "Did you mean 'implementation-plan.md'?"
    Sve tri standardne pipeline state markdown fajl-ove sa potencijalom za ext typo dobijaju eksplicit correction suggestion.
- **Live evidence (CSRF task, 2026-05-22):** orchestrator je hit oba scenarija — re-dispatch adversarial posle prvog BLOCK-a + pipeline-state-direct-write BLOCK na `.adversarial-rationale`. Oba su radila gate-skim semantics OK ali su confused orchestrator-a + kosta minute u recovery-u. v6.8.6 cilj: <5s recovery po typo-u.
- **Tests:** `test-codex-adapter` §65 adds 5 assertions: track-agent "NOT recorded" note + re-dispatch instruction, guard-pipeline-state typo case + "Did you mean" hint, live BLOCK output sa typo-bait input. Test count 502 → 507.
- **Migration:** zero impact. Pure message polish.

## v6.8.5 — 2026-05-22

Sixth same-day patch — hard gate koji **forsira `/apd-brainstorm` skill load** pre netrivijalnog spec advance-a. v6.8.4 educational layer je passive (workflow.md MANDATORY guidance je tekstualan), pa orchestrator ga je preskakao. Live evidence iz Test CSRF task-a (2026-05-22): 4 BLOCK-ova u 7 minuta (plan-spec-consistency + adversarial-before-reviewer × 2 + pipeline-state-direct-write) uprkos v6.8.0-4 chain-u. User-ova teza: "bez brainstorm skill-a necemo naterati orchestrator-a da postuje discipline" empirijski potvrdjena. v6.8.5 transformise skill load iz "preporuke" u "mandatory checkpoint" preko marker fajla. Tests: 489 → 502 (+13 in §64).

- **feat(pipeline-advance): brainstorm-marker hard gate.** Pre `create_done "spec"` u spec branch-u, novi check: ako R-criteria count u spec-card.md > 2 i `.apd/pipeline/.brainstorm-marker` ne postoji (ili task name unutar njega ne match-uje), BLOCK sa eksplicit instrukcijom "Load /apd-brainstorm skill first". `log_block "brainstorm-marker-missing"` u guard-audit.log.
- **feat(pipeline-advance): `--skip-brainstorm` override flag.** Escape valve za eksperimentalne / pre-specified task-ove. `bash .claude/bin/apd pipeline spec --skip-brainstorm "Task name"`. Flag parsiran iz `$@` (moze pre ili posle task name-a).
- **feat(apd-brainstorm SKILL.md): Step 5 instructs marker write.** Skill exit action sad ukljucuje:
    ```bash
    printf '%s|%s\n' "Task name" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .apd/pipeline/.brainstorm-marker
    bash .claude/bin/apd pipeline spec "Task name"
    ```
    Plus eksplicit explanation o gate-u i override flag-u. Codex mirror identican (sa `apd:apd_advance_pipeline` MCP tool path).
- **fix(guard-pipeline-state): allowlist `.brainstorm-marker`.** Bez ovog allowlist-a, skill bi udari u BLOCK kad pokusa da pisuje marker. Header comment + case statement updated.
- **fix(guard-file-edit, Codex): allowlist `.brainstorm-marker`.** AUTHORING_ALLOWLIST dobija novi entry. Codex orchestrator moze da pisuje marker preko apply_patch / Edit / Write.
- **fix(guard-bash-scope): allow brainstorm-marker bash redirect.** Skill koristi `printf > .apd/pipeline/.brainstorm-marker` — bez ove exception bi udari u "Bash redirect to protected pipeline state directory" BLOCK.
- **fix(pipeline-advance reset cleanup): wipe `.brainstorm-marker`.** Oba reset path-a (spec re-advance soft cleanup + explicit `pipeline-advance reset`) dobijaju `.brainstorm-marker` u rm -f listi. Sledeci task starts fresh.
- **Trivial tasks bypass automatic.** R-count ≤ 2 (hotfix/polish) ne triggers gate — orchestrator nije forsiran da load skill za 1-2 R-criterion task-ove. Smart-friction: friction samo gde se cascade BLOCK pattern observed.
- **Empirical baseline iz v6.8 dev cycle-a (5 task-a u Test-u):**
    | Task | Duration | T:A:D | BLOCK-ovi | brainstorm load |
    |---|---|---|---|---|
    | Landing page (v6.6 baseline) | 8m 49s | 5:0:5 | 0 | n/a |
    | Add contact form | 33 min | 0:0:0 (anticipatorni) | 3 cascade | NE |
    | Admin lista | 13m 25s | 10:1:9 | 2 rationale | NE |
    | Rate limit | 26m 11s | 8:8:0 (forced accept) | 3 | NE |
    | **CSRF zaštita (v6.8.4)** | **N/A (in progress)** | **N/A** | **4 BLOCK-ova u 7min** | **NE** |
  Pattern: orchestrator preskakao skill load sve 4 task-a uprkos workflow.md hint-u + v6.8.4 SKILL update. v6.8.5 hard gate je realan jedini structural fix.
- **Tests:** `test-codex-adapter` §64 adds 13 assertions: BRAINSTORM_MARKER + SKIP_BRAINSTORM static parsers, reset cleanup, guard-pipeline-state + guard-file-edit + guard-bash-scope allowlists, CC + Codex SKILL.md marker instruction, live R>2 without marker → BLOCK, --skip-brainstorm override radi, matching marker → spec advance prolazi, R≤2 trivial bypass automatic, reset wipes marker. Test count 489 → 502.
- **Migration:** projekti koji upgrade v6.8.4 → v6.8.5 i nastavljaju aktivnu pipeline-u: ako sledeci task ima >2 R-criteria, orchestrator dobija BLOCK sa instrukcijom. Quick fix — load `/apd-brainstorm` skill, walk through it (skill pise marker), pa `apd pipeline spec`. Trivial tasks (1-2 R) ne pucaju.

## v6.8.4 — 2026-05-22

Fifth same-day patch — strukturalna intervencija na obrazovnom surface-u, ne na guard layer-u. **Root cause spotted by user observation:** `apd-brainstorm` SKILL.md jos uvek preskripuje `max_defects=0` u Adversarial budget table-u uprkos v6.8.1 workflow §0b update-u. Orchestrator citajuci skill je tako i dalje uci pre-v6.8.1 guidance, sto je triggered cascade BLOCK-ove u Add contact form (33 min, 3 cascade BLOCK-a) i Rate limit (26 min, T=8:A=8:D=0 forced accept all). v6.8.4 transformise apd-brainstorm iz "vague-task clarifier" u **"APD pipeline tutor"** — orchestrator dobija edukaciju o gate-ovima PRE pisanja spec-a. Plus workflow.md/AGENTS.md eksplicit MANDATORY load skill za netrivijalne task-ove. Tests: 480 → 489 (+9 in §63).

- **fix(skills/apd-brainstorm/SKILL.md): drop pre-v6.8.1 max_defects=0 preskripcija.** Pre-v6.8.4 tabela:
    ```
    | 1–2 (hotfix)     | max_defects=unlimited |
    | 3–4 (real task)  | max_defects=0         |
    | 5+ (complex)     | max_defects=0 or N    |
    ```
    Post-v6.8.4:
    ```
    | 1–7 R (default — almost all tasks) | omit field (= unlimited) |
    | polish-mode (1-2 R hotfix)         | pipeline_mode: polish    |
    | Power-user explicit budget         | max_defects=N (rare)     |
    ```
    Plus eksplicit "DO NOT write max_defects=0 for standard tasks" sa empirical evidence iz v6.8 dev cycle-a.
- **feat(skills/apd-brainstorm/SKILL.md): nova sekcija "Downstream gates the spec triggers".** Educate-uje orchestrator-a PRE pisanja spec-a o:
    - Implementation plan format sa `**Implements:** R1, R3` headerima per sekciji + scaffolding `none`
    - Plan-spec gate bidirectional check + v6.8.1 strict default
    - Adversarial rationale file format (Finding/Severity/Status/Rationale) + v7.1 + v7.6 BLOCK consequences
- **feat(skills/apd-brainstorm/SKILL.md): nova sekcija "Common BLOCKs + recovery".** Tabela sa 7 BLOCK reason-a (plan-spec-consistency, max_defects-exceeded, max_defects-raised-mid-pipeline, rationale-missing, rationale-100pct-orch-dismiss, max_builder_cycles-exceeded, adversarial-before-reviewer) + konkretan quick fix per slucaj.
- **fix(plugins/apd/skills/apd-brainstorm/SKILL.md): Codex mirror update.** Slicna struktura, krace teze (Codex skill je generalno saze-ija). Drop preskripciju + dodaj gates + BLOCKs sekcije.
- **fix(workflow.md step 1): MANDATORY load /apd-brainstorm BEFORE writing spec-card.md** kad ANY:
    - Task je vague/broad/improve X style
    - Task ima >2 R-criteria
    - Task uvodi DB migration ili security surface
    - User nije pre-specified files/R-criteria/budget
  Plus eksplicit description "Skill is the APD pipeline tutor (v6.8.4+)" + empirical reference.
- **fix(templates/codex/AGENTS.md): step 0 MANDATORY brainstorm load** + step 1 (Write spec card) dobija "DO NOT write `adversarial: max_defects=0`" eksplicit warning sa rationale.
- **Empirical baseline (4 task-a u v6.8 dev cycle):**
    | Task | Duration | T:A:D | BLOCK-ovi | `max_defects` field |
    |---|---|---|---|---|
    | Landing page (v6.6 baseline) | 8m 49s | 5:0:5 | 0 | unlimited (no field) |
    | Add contact form | **33 min** | 0:0:0 (anticipatorni) | 3 cascade | **=0 explicit** |
    | Admin lista | 13m 25s | 10:1:9 | 2 rationale | unlimited (no field) |
    | Rate limit | **26m 11s** | **8:8:0** (forced accept) | 3 | **=0 explicit** |
  Pattern: max_defects=0 = 2x-4x slower vs no-field. Apd-brainstorm SKILL bio uzrok pisanja max_defects=0.
- **Tests:** `test-codex-adapter` §63 adds 9 static assertions: CC skill drops 3-4 preskripciju, default omit-field, Downstream gates section, Common BLOCKs section, Codex mirror parity (drop + sections), workflow.md MANDATORY load, AGENTS.md step 0 MANDATORY, AGENTS.md spec-card warning. Test count 480 → 489.
- **Migration:** zero project-side impact. Skill content + workflow guidance polish.

## v6.8.3 — 2026-05-22

Same-day usability patch responding to v6.8.2 live evidence (Test 2nd task): `verify-plan-spec` log_block radi ali workflow.md MANDATORY/Sanity preventive guidance NIJE pomogao — orchestrator je ponovo zaboravio `**Implements:**` headers (2× plan-spec-consistency BLOCK u 17s razmaka) i ponovo zaboravio `.adversarial-rationale.md` (rationale-missing + 100pct-orch-dismiss BLOCK pair). Root cause: workflow.md je context-document koji se cita pri SessionStart-u, ne aktivno u tool-call kontekstu pri plan/rationale writing-u. Tests: 476 → 480 (+4 in §62).

- **fix(pipeline-advance): actionable BLOCK message za plan-spec consistency.** Pre-v6.8.3: `BLOCKED: plan-spec consistency check failed. Fix .apd/pipeline/implementation-plan.md per the messages above` — vague, orchestrator mora da ide nazad u workflow.md za sintaksu (~60s cost). v6.8.3: konkretan copy-paste fix template direktno u BLOCK output sa `### Backend / **Implements:** R1, R3` primer + `### Files to modify / **Implements:** none` primer + "Apply fix, then re-run" instrukcija. Orchestrator apply odmah (~5-10s).
- **fix(workflow): §3c MANDATORY marker na vrhu sekcije.** Premostio "rules-na-dnu" problem: pre-v6.8.3 pravila su bila ispod format primera (1 scroll). v6.8.3 dodaje eksplicit **MANDATORY** marker odmah ispod naslova §3c sa "Common mistake" warning ("write plan without **Implements:** headers → BLOCK → go back and add. Saves 60s by writing headers from the start").
- **fix(AGENTS.md): step 3 MANDATORY marker (Codex mirror).** Codex orchestrator dobija jednaku visualno-istaknutu instrukciju. Plus "Write headers FROM THE START — verify-plan-spec strict mode hard-BLOCKS otherwise" eksplicit pre apokaliptic.
- **Empirical baseline (v6.8.2 Test):** 2 plan-spec-consistency BLOCK-ova (12 issues → 9 issues → pass) u 17s razmaka + 2 rationale BLOCK-ova (rationale-missing → rationale-100pct-orch-dismiss). Net cost ~3-5 min recovery vs ~5-10s sa v6.8.3 inline templates. **Realan limit:** orchestrator-ov RLHF training pattern i memory weight mogu i dalje da zaboravljaju. v6.8.3 ne brise BLOCK pattern — smanjuje friction recovery.
- **Tests:** `test-codex-adapter` §62 adds 4 static assertions: pipeline-advance BLOCK contains `**Implements:** R1, R3` literal, `**Implements:** none` scaffolding hint, workflow §3c MANDATORY marker, Codex AGENTS.md MANDATORY marker. Test count 476 → 480.
- **Strategic note:** v6.8.3 close-uje "vague BLOCK message" gap. Sledeci patch (ako bude) verovatno targira **session-start hook reminder** ili **on-demand plan-check command** za preventive validation. Open question za buduce.

## v6.8.2 — 2026-05-22

Same-day observability patch responding to v6.8.1 live verification in `~/Projects/Test` "Admin lista kontakt poruka" task (13m 25s, 3× ubrzanje vs v6.8.0 baseline). Run prosao clean ali otkrio dva fina signala: (a) `verify-plan-spec` ne loguje BLOCK-ove u guard-audit.log dok ostali gateovi rade (observability gap); (b) orchestrator zaboravlja `.adversarial-rationale.md` pre verifier advance-a — gate radi reactive (v7.1 BLOCK), ali workflow guidance nije visually prominent. Tests: 472 → 476 (+4 in §61).

- **fix(verify-plan-spec): log_block "plan-spec-consistency" call u BLOCK granu.** Strict-mode BLOCK sad pise entry u guard-audit.log sa format `BLOCK|orchestrator|plan-spec-consistency|issues=N mode=strict`. Format konzistentan sa ostalim gate log entries (max_defects-exceeded, rationale-missing, etc.). `apd report` i forensic analiza sad imaju vidljivost u plan-spec block events.
- **fix(workflow): step 6 + step 7 jaca preventivna reminder za .adversarial-rationale.md.** Step 6 — eksplicitan **MANDATORY** marker za pisanje rationale fajla "BEFORE attempting verifier advance"; eksplicit objasnjenje "Common mistake: orchestrator finishes adversarial dispatch, jumps directly to verifier, hits v7.1 BLOCK". Step 7 — novi **Sanity check FIRST** bullet koji eksplicitno trazi `.adversarial-rationale.md` presence pre `apd pipeline verifier`. Pre-v6.8.2 instrukcija je bila tu, ali ugnezdjena u dugacku checklist; sad je visually salient. Codex AGENTS.md vec ima jednako jaku instrukciju (linije 46 + 57) — workflow.md sad u paritetu.
- **Empirical baseline iz v6.8.1 live verify:** Pipeline duration 13m 25s vs 33m predhodnog task-a istog scope-a (**3.0× ubrzanje**). ADVERSARIAL:10:1:9 — real adversarial work, ne front-load anticipation. Spec `max_defects=unlimited` (workflow §0b update aktivan). Plan ima `**Implements:**` headere na svim sekcijama (strict default forsira). 2 BLOCK-ova u session-log: `rationale-missing (1x)` + `rationale-100pct-orch-dismiss (1x)` — gate radio reactive ali efektivno; orchestrator naucio u realtime-u (3 ponasanja zapisana po user-u). Zero max_defects/cycle-cap cascade BLOCK-ova.
- **Tests:** `test-codex-adapter` §61 adds 4 assertions: (a) verify-plan-spec source contains log_block call sa plan-spec-consistency reason, (b) workflow.md step 6 has MANDATORY marker za rationale file, (c) workflow.md step 7 has preventive Sanity check, (d) live default-strict BLOCK actually writes entry to guard-audit.log. Test count 472 → 476.
- **Migration:** zero impact na postojece projekte. Pure observability + docs polish. Korisnici koji vec imaju v6.8.1 install: jedna marketplace upgrade + reinstall, no project-side fixup needed.

## v6.8.1 — 2026-05-22

Same-day patch responding to live evidence from `~/Projects/Test` "Add contact form" run (~33 min total, 3 guard block triggers, 16 agent dispatches vs 6 baseline for similar scope). Root cause: workflow.md §0b preskripcija **"real task → max_defects=0"** caused orchestrator to:
1. Hit `max_defects-exceeded` BLOCK at 03:21:33 (`ADV_D=5 max_defects=0`).
2. Attempt mid-pipeline raise → caught by v6.3 D immutability gate at 03:22:48.
3. Cascade into multi-cycle reset + builder-cycle-cap exhaustion (03:36:47).
4. Front-load anti-pattern: orchestrator pre-emptively packed 5 anticipated fixes (F1-F5) into FIRST plan to ensure max_defects=0 passes — bigger builder context, lost adversarial fresh-eyes value.

Plus the v6.8.0 verify-plan-spec gate emitted 11 WARN linija but orchestrator ignored them (soft-warn mode = ignored signal). Tests: 468 → 472 (+4 in §60).

- **fix(workflow): §0b removes preskripciju `max_defects=0` for real-task default.** Default is now `unlimited` (= no field in spec-card.md). Polje opcioni power-user override za polish-mode tasks gde stvarno znas budget unapred. Rationale: v6.7 rationale gate (per-finding ≥40 chars + 100%-Do hard-block) strukturalno covers same misuse pattern without preflight budget cap; v6.1 B2 budget cap is now belt-without-suspenders.
- **fix(verify-plan-spec): DEFAULT_MODE flip from `warn` to `strict`.** Single-line change. Plan sections without `**Implements:**` headers, or plans missing R-ids from spec-card.md, now BLOCK by default. Graceful migration path: set `plan_consistency_gate: warn` in spec-card.md to keep v6.8.0 soft behavior; `plan_consistency_gate: off` to skip entirely.
- **test(test-codex-adapter): §60 — strict-by-default lock-in.** Four new assertions: no-mode-field + missing-R-id → BLOCK + exit 1; no-mode-field + section-without-Implements → BLOCK + exit 1; no-mode-field + perfect plan → exit 0 silent; explicit `plan_consistency_gate: warn` override → WARN + exit 0 (migration path verification). Plus updated §59 Static E from `DEFAULT_MODE="warn"` baseline to `DEFAULT_MODE="strict"`. Plus retro-added `plan_consistency_gate: off` to 5 existing test fixtures (§42 builder cycle cap, §43 reviewer cycle cap + polish mode, §45 reviewer rollback, §51 stale dispatch filter, §52 rationale gate) so they continue testing their own gate logic without v6.8 strict mode interference.
- **Migration note.** Projekti koji upgrade v6.8.0 → v6.8.1 i jos uvek imaju plan-ove bez `**Implements:**` header-a dobijaju BLOCK na prvi `apd pipeline builder`. Fix: dodati `**Implements:** R1, R3` (ili `none`) headere na svakoj `### Section`. Alternativa: dodati `plan_consistency_gate: warn` u spec-card.md za soft mode tokom prelaza. **Projekti koji imaju `max_defects=0` u svojim spec-card template-ima ili reuse-uju spec patterns dobijaju soft hint** (no automatic BLOCK on field presence; field continues to work as before — but workflow.md guidance više ne preporucuje pisati ga).
- **Empirical record.** `.claude/memory/status.md` v6.8.1 phase section zapisuje detalje 2026-05-22 Test 33-min run-a kao baseline za buduce force-multiplier comparisons. `feedback-max-defects-zero-friction` memory entry trebalo bi dodati nezavisno za projekt memory.

## v6.8.0 — 2026-05-22

New structural gate that closes the **plan-spec ambiguity rupu**: orchestrator-authored `implementation-plan.md` is now mechanically verified against `spec-card.md` R-criteria via per-section `**Implements:**` headers. Bidirectional check — every spec `R*` must be referenced by ≥1 plan section, every plan section must declare R-ids or `none`. Ships with `plan_consistency_gate: strict|warn|off` field in spec-card.md; default `warn` in v6.8.0 (issues emit WARN, no block) to give postojeci projekti grace window. v6.8.1 will flip default to `strict`. Tests: 456 → 468 (+12 in §59; baseline +37 already grew from §53–§58 across v6.7.x).

- **feat(verify): new `plugins/apd/bin/core/verify-plan-spec` parser.** Parses `### Section` headings in `.apd/pipeline/implementation-plan.md`, extracts per-section `**Implements:** R1, R3` declarations, runs three checks: (1) forward — every R-id in `**Implements:**` must exist in spec-card.md, (2) reverse — every spec R-id must appear in ≥1 section's `**Implements:**`, (3) symmetric — every section must have an `**Implements:**` header (or `**Implements:** none` for scaffolding like file lists, agents, notes). Backward compat: if spec-card.md is missing R-criteria entirely, or if implementation-plan.md doesn't exist, exit 0 silent (other gates already block).
- **feat(pipeline): `pipeline-advance builder` calls verify-plan-spec.** Gate runs after the existing implementation-plan.md presence check, before BUILDER_RAN. Skripta sama odlucuje exit code po mode-u (read from spec-card.md). v6.8.0 default mode `warn`: issues print to stderr but `pipeline-advance` continues. `plan_consistency_gate: strict` opt-in: BLOCK with explicit error directing orchestrator to fix the plan or downgrade to `warn`.
- **feat(spec-card): tri-level `plan_consistency_gate` field.** New opt-out field in spec-card.md alongside existing `adversarial: max_defects=N` / `adversarial: rationale_gate=off` patterns. Three values: `strict` (BLOCK on missing/unknown R-id or missing `**Implements:**`), `warn` (emit WARN, no block), `off` (skip entirely — for exploratory/experimental tasks where plan is deliberately rough draft). Default v6.8.0 = `warn`, v6.8.1+ = `strict`.
- **docs: workflow.md §3c rewritten.** New format example shows every `### Section` with mandatory `**Implements:**` header (Backend → R1, R3; Frontend → R2, R4; Files to modify/create/Agents/Notes → `none`). Two new bullets in Rules section: format requirement + opt-out field semantics.
- **docs: AGENTS.md (Codex) Order of operations step 3.** Mirror update — Codex orchestrator gets the same instruction with same opt-out flag reference.
- **docs: SPEC.md §9.** New `verify-plan-spec` row in verifiers table; spans gate behavior, mode parser, exit codes, builder-branch caller.
- **Strict simetricno pravilo, no reserved section names.** Earlier design draft considered exempting `Files to modify`, `Files to create`, `Agents`, `Notes` from the `**Implements:**` requirement. Rejected in favor of explicit `**Implements:** none` on those sections — eliminates parser special cases, gives consistent rule to orchestrator, and the WARN-on-missing-header signal genuinely distinguishes "orchestrator forgot" from "scaffolding section by design".
- **Gaming pattern closed by reverse check.** Mehanicki `**Implements:** none` na sve sekcije ne defeat-uje gate jer reverse check pucа na nepokrivenim R-id-ovima — every spec R* must appear in ≥1 non-none section.
- **Tests:** `test-codex-adapter` §59 adds 12 assertions covering: binary exists/executable, forward+reverse+mode-parser+DEFAULT_MODE static greps (5), live perfect plan, live missing-R, live unknown-R-id, live section-without-Implements (default warn mode, 4), live opt-out off, live strict mode + missing-R, live strict mode + section-without-Implements (3). Live setup uses isolated synthetic project with .apd/pipeline/{spec-card.md,implementation-plan.md} fixtures. Test count 456 → 468.
- **Migration:** postojeci projekti continue to work — gate emits WARN, doesn't block. To upgrade plan-ove to the new format, add `**Implements:** R1, R3` (or `none`) to each `### Section`. v6.8.1 will flip default to `strict`; CHANGELOG v6.8.1 entry will document migration step explicitly.
- **Why this matters strategically.** Diskusioni record (`~/.claude/plans/hajde-da-prodiskutujemo-na-sequential-giraffe.md`, 2026-05-20) traces the root cause analysis: pravi koren defekata nije adversarial dismissal ili builder overrun, već **rasplinut spec → rasplinut plan → builder radi u magli → downstream gateovi rade na sirokoj ambiguity surface**. Trenutni pipeline ima dva mehanicka anchor-a (`verify-trace` for spec↔tests, presence check for plan), ali nepokrivena rupa između je da plan tehnicki postoji ali ne mapira eksplicit na R-kriterije. v6.8 zatvara taj sloj.

## v6.7.7 — 2026-05-20

Closes the 2 WARN signals reported from FiscalFusionAI v6.7.6 validation (126 PASS / 0 FAIL / 2 WARN baseline). Both review-class agent templates now self-declare the no-commit boundary, matching what `guard-git` already enforces at the bash level. Defense-in-depth: the bash guard catches actual attempts; the template text tells the agent the boundary BEFORE it tests the guard. Tests: 454 → 456 (+2 in §58).

- **fix(templates): add explicit FORBIDDEN / no-commit block to all 4 reviewer templates.** Both CC (`templates/reviewer-template.md` + `templates/adversarial-reviewer-template.md`) and Codex (`templates/codex/agents/code-reviewer.md` + `templates/codex/agents/adversarial-reviewer.md`) gain a `## FORBIDDEN` section listing: "NEVER commit changes" (with reference to `guard-git` being the runtime enforcer), "NEVER edit or create project source files" (reviewers are read-only by role), "NEVER add AI signatures" (style is human). The text patches the same gap that `templates/agent-template.md` already had — reviewers were the only template family missing it.
- **Why this matters even though `guard-git` already enforces.** The bash-level block is the safety net, not the docs. Agents that learn about the prohibition only by hitting the guard waste turns + emit confusing failure paths. Explicit template text says "here's the boundary, don't go near it" before the agent has to discover it experimentally. `verify-apd` Section 6 validator at lines 480-485 specifically checks for `NEVER.*commit | FORBIDDEN | ZABRANJENO | NIKADA.*commit` patterns in agent .md files — the WARN existed because reviewers genuinely lacked the text, not because the validator was wrong.
- **Existing projects** scaffolded pre-v6.7.7 do NOT auto-pick up the template changes — agent files in `.claude/agents/` are copied once at `/apd-setup` time and never overwritten. To pick up the new prohibition, re-run `apd-init` or manually copy the templates. The 2 WARN signals will persist on those projects until refreshed.
- **Tests:** `test-codex-adapter` §58 adds 2 assertions: all 4 reviewer templates contain `NEVER commit` or `FORBIDDEN` text; `verify-apd` Section 6 still does the validation check (keeps the lock-in alive). Test count 454 → 456.

## v6.7.6 — 2026-05-20

**Hotfix.** `verify-apd` had three stale assumptions from prior version migrations that surfaced when a user ran `/apd-setup` on a v6.7.5 install. None affected production behavior — the hooks fired correctly per the direct §7 guard tests — but the E2E verification script reported false failures, undermining trust in `apd verify` output. Tests: 450 → 454 (+4 in §57).

- **fix(verify-apd): hook detection reads `args[0]`, not `.command` (v6.6.0 exec-form catch-up).** Three checks at lines 264 / 275 / 284 (`SessionStart → session-start`, `PreToolUse(Bash) → guard-git`, `PostToolUse(Bash) → pipeline-post-commit`) used `jq '.hooks[].command'` then `grep` for the script name. Since v6.6.0 migrated `hooks/hooks.json` to args exec form, `.command` is now just `"bash"` and the script path lives in `.args[0]` — grep against `"bash"` always failed → 3 false-FAIL reports per `apd verify` run. Helper jq expression `(.command // "") + " " + ((.args // []) | join(" "))` concatenates both fields and matches across the old shell-string form (backward compat) and the new args form. Surfaced 2026-05-20 by an orchestrator running `/apd-setup` in `~/Projects/NetProjects/FiscalFusionAI` — a separate project from BambiProject, giving APD its first multi-project fresh-install validation signal.
- **fix(verify-apd): Section 8 writes `.adversarial-rationale.md` before verifier (v6.7.0 catch-up).** Section 8 line 904 wrote `ADVERSARIAL:3:2:1` to `.adversarial-summary` then expected verifier to pass; line 926 wrote `ADVERSARIAL:1:0:1` for the ordering-test BLOCK assertion. v6.7.0 added the rationale-file hard-block (v7.1) — both calls now hit `BLOCKED: Adversarial rationale file missing` instead of their intended outcome. Both spots now write a minimal valid rationale matching the T:A:D count + clean up the file at the end. The ordering-test gate fires earlier in `pipeline-advance` than the rationale gate, so the test assertion (`grep "before reviewer"`) still works, but the rationale file is now present defensively.
- **fix(verify-apd): cascade — adversarial ordering test setup failure resolves.** The original report mentioned a third bug: "adversarial ordering test setup failed (no reviewer.done after rollback)". Root cause was the previous test (Bug #2) blocking on rationale-missing and never completing the rollback handoff cleanly. Fixing Bug #2 resolves this cascade automatically.
- **No production behavior change.** Guards still fire correctly (the §7 direct-call guard tests prove this — 12/12 PASS pre-fix). The fix is to `verify-apd`'s detection logic, not to any hook script. Hooks have always worked since v6.6.0.
- **Lesson:** `verify-apd` runs in the framework's own development workflow (`bash plugins/apd/bin/core/test-codex-adapter` includes Section 8 of verify-apd indirectly), but the hook-detection grep ran against the framework's own `hooks/hooks.json` — which was migrated to args form in v6.6.0. We should have caught these false-FAILs at the v6.6.0 ship moment but didn't, because nobody ran a fresh `apd verify` cycle on a freshly-installed project. The 2026-05-20 user-report is the first such fresh-install signal in 4 days. Adds to [[feedback-test-hook-path-blindspot]] — there is a sibling pattern: scripts that VALIDATE the runtime hook surface need to be re-run after every hook-format migration, not just regression-checked via static parser tests.
- **Tests:** `test-codex-adapter` §57 adds 4 static assertions: `_CMD_CONCAT` helper present, Section 8 3:2:1 test writes rationale, ordering test writes rationale, cleanup removes rationale. Test count 450 → 454.

## v6.7.5 — 2026-05-19

Quick in-session toggle for the APD plugin's enabled state. CC-only — Codex has no `enabledPlugins` concept. Tests: 443 → 450 (+7 in §56).

- **feat(cli): `apd toggle [on|off]` flips `claude-apd@zstevovich-plugins` in CC settings.** New `plugins/apd/bin/core/toggle-apd` script wired into the apd CLI dispatcher. Default behavior: smart-detection scans `<project>/.claude/settings.local.json` → `<project>/.claude/settings.json` → `~/.claude/settings.json` and edits the first file that already contains the key. If the key is absent everywhere, defaults to `settings.local.json` (per-developer, gitignored, no team-wide impact). Why smart-detection matters: CC merges `settings.local.json` over `settings.json`, so writing to a file that does NOT hold the active value has no visible effect. Detection picks the file whose value CC will actually read.
- **fix(jq): smart-detection uses `has()` presence check, not truthiness.** Initial implementation used `jq -e '.enabledPlugins[$k]'` which returns failure for `false` (jq treats `false` as not-truthy) — this mis-classified an explicitly-disabled APD as "key missing" and edited the wrong file. Caught during local sanity test before ship; fixed by switching to `jq -e '.enabledPlugins | has($k)'`. Same gotcha resolved in the current-value reader: `jq '.enabledPlugins[$k] // "missing"'` returns RHS on both `null` AND `false`; replaced with an explicit `if has($k) then ... else "missing" end` conditional. Lock-in assertion in §56 (Static B) ensures this regression cannot ship again.
- **feat(skill): `/apd-toggle` CC slash command (`skills/apd-toggle/SKILL.md`).** Parses user intent (off/on/flip + optional `--global` / `--project` / `--local`), invokes `bash .claude/bin/apd toggle [arg]`, then calls `/reload-plugins` via the SlashCommand tool for in-session pickup — closes the bonus reload-without-restart wish. Anti-patterns section warns against manually editing settings JSON instead of using the script (smart-detection + jq atomic edit are not trivial to reproduce by hand). Total CC skill count 8 → 9.
- **flags supported:** `on`/`enable`/`true`/`1` force enable; `off`/`disable`/`false`/`0` force disable; `--global` writes to `~/.claude/settings.json`; `--project` writes to project tracked `settings.json`; `--local` writes to per-dev `settings.local.json`; no-arg flips current.
- **Atomic edit safety:** writes go through `mktemp` + `jq` + `mv`; partial-write or jq failure cannot corrupt the existing settings file. Trap cleans the temp file on early exit.
- **Reports:** prints `Old → New`, the edited file path, smart-detection note (if applied), and the reload hint. Output line `APD plugin: true → false` is the primary user-visible signal.
- **docs: SPEC.md §2** new `toggle` row in CLI surface table. **SPEC.md §7.1** CC skills table grows to 9 with `apd-toggle` row.
- **Tests:** `test-codex-adapter` §56 adds 7 assertions: script + CLI verb presence, `has()` static check, true→false flip, false→true flip (the bug-regression case), explicit `off` arg, missing-file → settings.local.json creation, smart-detection picks settings.json when key lives there. HOME-isolated test setup ensures no real `~/.claude/settings.json` is touched. Test count 443 → 450.

## v6.7.4 — 2026-05-19

**Hotfix.** v6.7.0 introduced `.adversarial-rationale.md` as a required pipeline state file that the orchestrator authors directly, but the guards on both runtimes (`guard-pipeline-state` on CC, `guard-file-edit` on Codex) were never updated to allow that path. Result: the orchestrator hit a hard BLOCK when trying to write the rationale file the verifier demanded, leaving the pipeline stuck between adversarial and verifier. Surfaced live on BambiProject MR.13a (2026-05-19, v6.7.3 install). Tests: 441 → 443 (+2 static).

- **fix(guard-pipeline-state, CC): allow `.adversarial-rationale.md`.** Added to the orchestrator-writeable allowlist (`spec-card.md`, `implementation-plan.md`, `.adversarial-summary`, `.adversarial-rationale.md`). Header comment + case statement updated.
- **fix(guard-file-edit, Codex): allow `.adversarial-rationale.md`.** Added to `AUTHORING_ALLOWLIST` in the Python guard block — Codex orchestrator can now write the rationale file via apply_patch / Edit / Write without needing a prior `apd_guard_write` call to clear the path.
- **docs: SPEC.md §4.3** `guard-pipeline-state` allowlist row updated; v6.7.4 tag added in-line.
- **Test §52 lock-in:** 2 new static assertions verify the allowlist additions on both runtimes so this regression cannot ship silently again.
- **Lesson:** the v6.7.0 test suite covered the rationale gate logic end-to-end via direct `cat > file` writes from the test harness — never going through the CC Write tool path, so the guard-pipeline-state hook was bypassed in tests. Real-world dispatch goes through the hook. Added to `feedback-validation-futility` thinking: format tests aren't enough when the runtime hook path differs from the test write path.

## v6.7.3 — 2026-05-18

v6.4 backlog F1 + F3 — template-only directives that complement the v6.7.2 F2 detection arm. F1 makes the orchestrator include an explicit finalization clause in every builder dispatch prompt; F3 forces builders to ground their self-reports in `git diff --stat` + `git status --short`, preventing hallucinated rename/file-add claims. Tests: 438 → 441 (+3 in §55).

- **docs(workflow): F1 mandatory dispatch finalization clause.** `workflow.md` step 5 now reads: "Mandatory finalization clause in EVERY builder dispatch prompt: 'When the build passes AND the tests you wrote pass, STOP IMMEDIATELY. Do NOT re-verify. Do NOT search "one more time" to confirm. Verification of completeness is the reviewer's job, not yours.'". Cross-ref to v6.7.2 F2 in the same block — F2 is the telemetry/detection arm; F1 is the upstream dispatch-prompt rule. Pure template; can't be runtime-enforced (we don't see what orchestrator writes to its subagent), but reinforces against the RLHF "thorough" default and complements the F4 `STOP IMMEDIATELY` wording in dispatch templates shipped in v6.3.0.
- **docs(templates): F3 git-state self-check directive.** Added a "Before stopping — git-state self-check" block to the Exit criteria section of `templates/agent-template.md` (CC master) + Codex `templates/codex/agents/{backend-builder,frontend-builder,testing}.md`. Each block instructs: `command -v git >/dev/null 2>&1 && git diff --stat && git status --short`, then "Report **exactly** which files you changed (or that you changed none). Do not claim work you did not do — hallucinated renames or file additions that aren't in `git status` mislead the reviewer and waste a re-dispatch.". Targets the 2026-05-11 incident where the agent claimed "renamed nonPursQrDoesNotResetTimers" but didn't actually do so — verifier confidence broke down. Reviewer templates intentionally skipped — they don't write code; the directive doesn't apply.
- **Memory: v6.4 builder-overrun backlog** marks F1 + F3 as DONE. Full F-family now closed:
  - F1 — workflow.md dispatch finalization (DONE v6.7.3)
  - F2 — track-agent duration outlier flag (DONE v6.7.2)
  - F3 — agent-template git-state self-check (DONE v6.7.3)
  - F4 — dispatch-template STOP IMMEDIATELY wording (DONE v6.3.0)
- **Existing projects:** scaffolded pre-v6.7.3 do NOT auto-pick up the template changes — re-run `apd-init` or refresh agent files manually. Codex projects do not regenerate agents from the cache automatically.
- **Tests:** `test-codex-adapter` §55 adds 3 assertions: workflow.md carries F1 clause; CC `agent-template.md` has F3 directive; all 3 Codex builder/testing templates have F3 directive + `command -v git` guard. Test count 438 → 441.

## v6.7.2 — 2026-05-18

v6.4 backlog F2 — `track-agent` SubagentStop now flags long-running agents that produced no recent file writes. Targets the 2026-05-11 intra-dispatch overrun pattern (1 builder, 23 min, 15 min of post-success "verification" loop with no code changes). Post-hoc detection only — surfaces signal, does not block. Tests: 435 → 438 (+3 in §54).

- **feat(track-agent): agent duration outlier flag (F2).** On `SubagentStop`, compute duration from the paired start event in `.agents`. When `> APD_AGENT_LONG_RUN_THRESHOLD_SEC` (default 600s) AND no uncommitted file (via `git status --porcelain` + `stat` mtime) has been modified in the trailing 5 min, emit a stderr WARN ("possible verification loop") and append `ts|agent_type|agent_id|duration_sec` to `$MEMORY_DIR/agent-overrun.log`. Disable: `APD_AGENT_LONG_RUN_THRESHOLD_SEC=0`.
- **Write-detection method:** `git status --porcelain` filters to candidate files (uncommitted changes + untracked); per-file `stat` mtime compared against `stop_epoch - 300s`. Avoids filesystem-wide `find` — no false-positive noise from build artifacts or dependency caches. False-positive scenario: legitimate long-but-quiet research tasks (e.g., extensive Read-only scan); user can lift the threshold per session.
- **Why post-hoc instead of intercepting:** track-agent is a SubagentStop hook — by the time it fires, the agent has already exited. Real-time intervention would need a SubagentInProgress hook (doesn't exist) or polling. Post-hoc WARN at stop time + `agent-overrun.log` history is enough for users to spot the pattern and re-tune their dispatch prompts.
- **docs: SPEC.md §5.4** documents the new telemetry file format, threshold env var, and 2026-05-11 incident reference.
- **Memory: v6.4 builder-overrun backlog** marks F2 as DONE. F1 (workflow.md dispatch finalization helper) + F3 (git-state mandatory self-check in agent template) remain open.
- **Tests:** `test-codex-adapter` §54 adds 3 assertions: static check for env var + WARN msg + log path; live simulation (20-min back-dated start + no file writes) → WARN + log entry; live with `APD_AGENT_LONG_RUN_THRESHOLD_SEC=0` → silent. Test count 435 → 438.

## v6.7.1 — 2026-05-18

Phase 4 patch — `pipeline-metrics.log` extended with per-status dismissal columns and rationale-warn counter. `apd pipeline metrics` cumulative report surfaces the new data without breaking legacy 12-column rows. Tests: 430 → 435 (+5 in §53).

- **feat(metrics): three new columns at positions 13–15.** `adv_do` (orchestrator dismissals), `adv_dr` (reviewer-self-dismissals), `adv_w` (count of soft-warn lines from rationale-quality scan: short rationales <40 chars or lazy-pattern matches). Read from `.adversarial-rationale.md` at reset time; the awk pass that runs in verifier is mirrored here so the warn count is consistent between live verifier output and historical metrics. Column 10 (`adv_d`) stays as `adv_do + adv_dr` for backward compat with v6.6 and earlier readers — no breaking change.
- **feat(metrics): apd pipeline metrics renders dismissal split + warns line.** Cumulative "Adversarial review" section now shows `Dismissal split: Do=N (orchestrator) Dr=N (reviewer-self)` and `Rationale warns: N (rationale text <40 chars or lazy pattern)` when non-zero. Old 12-column rows produce empty trailing fields that default to 0 — they render the same as before.
- **docs: SPEC.md §5.4** documents the v6.7.1 column extension and backward-compat behavior.
- **Tests:** `test-codex-adapter` §53 adds 5 assertions (2 static + 3 live): writer emits Do/Dr/Warns vars, apd report parses + renders them, 12-col legacy row renders without Do/Dr split, 15-col row renders with split + warns, end-to-end (rationale → verifier → reset → 15-col row with correct counts). Test count 430 → 435.

## v6.7.0 — 2026-05-18

Adversarial dismissal quality — `pipeline-advance verifier` now reads `.apd/pipeline/.adversarial-rationale.md` and hard-blocks the 100% orchestrator-dismissal bypass pattern. Three-status classification (accepted / dismissed / reviewer-self-dismissed) lets clean reviewer-self-dismiss runs sign through while catching orchestrator rationalization-without-action. Tests: 419 → 430 (+11 in §52).

- **feat(pipeline): adversarial rationale gate.** New file `.apd/pipeline/.adversarial-rationale.md` required after every adversarial pass with `T>0`. One `## Finding N — <title>` block per finding with `**Severity:** critical|important|minor`, `**Status:** accepted|dismissed|reviewer-self-dismissed`, `**Rationale:** <text>`. `pipeline-advance verifier` hard-blocks on six conditions: missing file (v7.1), finding-block count != T (v7.3), Severity/Status/Rationale field count drift per block (v7.4), accepted count != A (v7.5), dismissed sum != D (v7.5), and the 100%-orchestrator-dismiss pattern T>=3 && A==0 && Do>=1 (v7.6). Reset, full reset, and verifier/reviewer rollback all wipe the rationale file.
- **feat(pipeline): per-task opt-out.** spec-card.md `adversarial: rationale_gate=off` skips the entire rationale gate for tasks where strict structured rationales are not appropriate (exploratory phase, hotfix path). Default is on. Same bold/italic tolerance pattern as `adversarial: max_defects` (v6.1.2).
- **feat(pipeline): soft quality warnings.** When all hard gates pass, `pipeline-advance verifier` runs an awk pass over the rationale file. Rationale text under 40 chars for dismissed/reviewer-self-dismissed entries emits `! WARN Finding N: rationale only N chars`. Lazy-pattern matches (`ok`, `n/a`, `false positive`, `not applicable`, `skip`, `no`) emit `! WARN Finding N: rationale matches lazy pattern`. Non-blocking — surfaces in stderr for visibility.
- **feat(templates): adversarial-reviewer Status field.** Both CC (`adversarial-reviewer-template.md`) and Codex (`templates/codex/agents/adversarial-reviewer.md`) now require per-finding `Status: active | self-dismissed`. Self-dismissed entries must include a `Note: <reason>` for the orchestrator to copy verbatim into the rationale file as `reviewer-self-dismissed`. The distinction prevents healthy adversarial runs (reviewer raises noise and processes it itself) from false-triggering the 100%-dismiss gate.
- **docs: workflow.md step 6b expanded.** New rationale-file write instruction between adversarial dispatch and verifier step, including format spec and gate behavior notes. Step 7 documents the rationale gate alongside the existing severity gate (v6.1 B2).
- **docs: Codex AGENTS.md guardrails.** `apd_adversarial_pass` row expanded with rationale-file requirement; new guardrail bullet for orchestrators on Codex runtime.
- **docs: SPEC.md §5.3** documents the new state file row with full format spec and gate behavior.
- **Live evidence motivating the fix:** 2026-05-16 landing-page test (`~/Projects/Test`, v6.6.0) produced `ADVERSARIAL:5:0:5` with five orchestrator-only dismissals — three legitimate (out-of-scope per APD diff rule), two weak ("already an existing pattern elsewhere"). 2026-05-18 MR.9 BambiProject (cross-stack mobile + backend) had a numerically-healthy 8:4:4 but the session transcript revealed the orchestrator's entire dismissal rationale was one line: *"1 Critical + 3 Important. Dispatch fixes."*. Zero per-finding documentation; closure summary mentioned only the four accepted findings. v6.7 forces the structured rationale and hard-blocks the bypass pattern at the verifier gate.
- **Tests:** `test-codex-adapter` §52 adds 11 assertions (4 static + 7 live): hard-gate expression presence, BLOCK message identifiers, reset cleanup coverage, 5:0:5+no-file BLOCK, count-mismatch BLOCK, 100%-dismiss BLOCK, Dr=5 SIGN, 5:2:3 SIGN, short-rationale WARN, lazy-pattern WARN. Test count 419 → 430.
- **Implementation design:** `docs/plans/v6.7-adversarial-dismissal-quality.md` — full phased plan with file format spec, parser rules, BLOCK message catalog, risk register, and bump strategy. Phase 4 (pipeline-metrics columns + `apd report` integration) deferred to v6.7.1 patch.

## v6.6.0 — 2026-05-16

`hooks/hooks.json` migrated to CC 2.1.139 `args: string[]` exec form. Hard-block on CC < 2.1.139. Tests: 416/0 (no regressions). Live-verified end-to-end in `~/Projects/Test`.

- **feat(hooks): migrate to args exec form.** All 13 hook entries in `hooks/hooks.json` (1 SessionStart, 6 PreToolUse, 1 PostToolUse, 1 SubagentStart, 1 SubagentStop, 1 PreCompact, 1 PostCompact, 1 PermissionDenied) now use `"command": "bash", "args": ["${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/..."]` instead of `"command": "bash \"<path>\""`. Exec form spawns the command directly without a shell — fewer escaping pitfalls, no shell-injection surface, and matches CC's documented modern hook form.
- **Hard-block below CC 2.1.139.** On CC < 2.1.139 the `args` field is silently ignored and `bash` runs with no script path — every APD guard becomes a silent no-op. To make this user-visible instead of a silent failure, `APD_MIN_VERSION` and `APD_FUNCTIONAL_VERSION` in both `session-start` and `verify-apd` (plus the `plugins/apd/.apd-version` overrides) pin to `2.1.139`. Users on older CC see a hard-block message at SessionStart with the upgrade command, not a degraded session where guards quietly stop working.
- **SPEC.md §4.1 updated** to document the exec form migration, the version-pin rationale, and that Codex hooks (`install-codex-config`) are unaffected — `args` exec form is a CC-only feature; Codex hook schema is separate.
- **Live test (2026-05-16):** after `/plugin marketplace update zstevovich-plugins` + `/plugin uninstall claude-apd` + `/plugin install claude-apd@zstevovich-plugins` + hard restart, `~/Projects/Test` showed: plugin cache populated `claude-apd/6.6.0/`, `installed_plugins.json` updated to version 6.6.0, exec form rendered as `[bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/adapter/cc/guard-bash-scope]` in CC hook trace, and `guard-bash-scope` correctly blocked `echo test > .apd/pipeline/spec-card.md` with `BLOCKED: Bash redirect to protected pipeline state directory`. End-to-end signal: hook fired, script reached its `exit 2 + BLOCKED:` message, args exec form is functional on this CC version.

## v6.5.4 — 2026-05-14

`pipeline-doctor` §9 GitHub Sync no longer warns on idle pipelines. Tests: 413 → 416.

- **fix(doctor): gate GH-sync warning on active pipeline.** `pipeline-doctor` §9 GitHub Sync emitted `gh CLI available but no issue linked (.gh-issue missing)` on every doctor run when `gh` was installed — including idle pipelines (no `spec-card.md`) where there is no task to link an issue to. The warn was pure noise: users who want GitHub Projects integration run `/apd-github` when starting a task, and users who don't want it skip it entirely; nagging on every idle doctor run adds nothing. Fix: gate the warn behind `[ -f "$PIPELINE_DIR/spec-card.md" ]`. Idle pipelines now print a softer dim hint ("link a task with /apd-github when needed") that doesn't register as a WARN line in the summary. Active pipelines (real task in flight) keep the warn — that's where linking an issue actually matters. The fix is one if-branch + one dim echo; no behavioral changes outside §9.
- **Live-verified before bump:** tmp project with `.apd/config` + empty `.apd/pipeline/` → `pipeline-doctor` prints the dim hint, no WARN. Same project with `spec-card.md` added → WARN fires as before.
- **Test:** `test-codex-adapter` §50 (3 assertions): static gate check (grep finds `spec-card.md` adjacent to the warn string), live idle test (no `spec-card.md` → no warn in output), live active test (with `spec-card.md` → warn fires). Live block guarded by `command -v gh` so CI hosts without `gh` installed don't false-pass. Test count 413 → 416.

## v6.5.3 — 2026-05-14

`verify-apd` Section 6 stub-tolerance + defensive cleanup. Diagnosed from BambiProject v6.5.2 live test on the same evening v6.5.2 shipped. Tests: 410 → 413.

- **fix(verify): F1 — Section 6 (Agents) skips reserved `apd-verify-*` namespace.** BambiProject v6.5.2 live test surfaced two new `✗` lines in verify-apd output: `Agent apd-verify-builder — model is NOT defined` and `Agent apd-verify-builder — guard-git is NOT registered (agent can commit!)`. The Section 6 quality validator (lines 384-451) iterates every `.md` file under `$APD_AGENTS_DIR` and asserts that frontmatter contains `model:`, that hook config registers `guard-git`, that secrets are gated, etc. The Section 8 synthetic builder stub introduced in v6.5.2 (3-line `---\nname: apd-verify-builder\n---`) cannot pass these checks by design — it's a dispatch-placeholder, not a real agent. Fix: a `case "$AGENT_NAME" in apd-verify-*) continue ;; esac` at the top of the for-loop short-circuits the `apd-verify-*` reserved namespace before any check fires, and `AGENT_COUNT` is incremented only after the namespace filter clears (so the registry count stays accurate). Real project agents never use this prefix (B2 reserved-namespace decision from v6.5.2). With v6.5.2 in production, every BambiProject-style consumer where the stub survives a SIGKILL-ed prior run would hit this FAIL — F1 makes the agent-quality check tolerant of the namespace.
- **fix(verify): F2 — defensive cleanup at the top of verify-apd.** Diagnosed root cause for "stub keeps coming back": the Section 8 cleanup trap fires only on EXIT/INT/TERM. SIGKILL, CC harness timeouts (Background command termination, `kill -9`, process-group reaper) all bypass the trap, so the stub written at Section 8 line 775 lives on indefinitely after an abnormal termination. v6.5.2's "bezuslovan" trap was a real fix for graceful exits but not for SIGKILL — the trap mechanism itself depends on signal-handler cooperation. Fix: a 9-line cleanup block runs immediately after `apd_header "Verification"` and before Section 1. It globs `$APD_AGENTS_DIR/apd-verify-*.md` with `for _stale_stub in ...; do [ -f "$_stale_stub" ] && rm -f "$_stale_stub"; done` (the `[ -f ]` guard handles the no-match-literal-glob case under bash without `nullglob`); also: if `spec-card.md` heading matches `^##? *\[?APD-VERIFY-`, it invokes `pipeline-advance reset` to wipe any leftover synthetic pipeline state from a prior run. Both guards are scoped to the reserved namespace so they never touch real project agents or non-synthetic spec cards. Belt-and-suspenders with the v6.5.2 trap-side cleanup — F2 catches what the trap missed.
- **Live-verified before bump:** scripted reproduction with two `apd-verify-*` stubs (`apd-verify-builder.md`, `apd-verify-stuff.md`) + real `backend-builder.md` (`---\nname: backend-builder\nmodel: opus\n---\nREAL`) → simulated F2 glob → both stubs gone, real `backend-builder.md` intact with the `REAL` sentinel preserved.
- **Test:** `bin/core/test-codex-adapter` §49 grows from 7 to 10 assertions: (F1) grep finds the `apd-verify-*) continue` case clause in verify-apd source; (F2 static) grep finds the `apd-verify-*.md` glob paired with `rm -f "$_stale_stub"`; (F2 live) the mktemp + 2-stub + 1-real-agent scenario asserts the glob purges all `apd-verify-*` files while leaving the real agent untouched. Test count 410 → 413.
- **Note for existing BambiProject contamination:** v6.5.3 defensive cleanup will purge the `apd-verify-builder.md` stub on the next `verify-apd` invocation. The 30-byte `backend-builder.md` (+ `.bak.preaudit`) leftover from old pre-v6.5.2 verify-apd runs is NOT touched by F2 because the filter is `apd-verify-*`, not `backend-builder`. User-driven recovery: inspect file size — real APD agent files are 2-4 KB; the 30-byte file is the historical stub. `rm` at user discretion.

## v6.5.2 — 2026-05-14

`verify-apd` Section 8 cleanup hardening — two failure modes diagnosed from BambiProject `apd doctor` output on the same day v6.5.1 shipped. Tests: 403 → 410.

- **fix(verify): bezuslovan Section 8 cleanup on every exit path.** `restore_pipeline_state` (the EXIT/INT/TERM trap) previously branched on `HAD_EXISTING_PIPELINE`: if the pipeline was empty when verify-apd started (the common case on a freshly reset project), the trap restored nothing and left every synthetic artifact behind — `spec-card.md` with the `## APD-VERIFY-TEST` heading, `spec.done` / `builder.done` / `reviewer.done`, four `a000000…`-ID start/stop pairs in `.agents`, plus `.adversarial-pending` and `.adversarial-summary`. The next `apd doctor` run on that project showed `Active task: APD-VERIFY-TEST` with `✗ verifier: NOT done` despite the user never having run a real pipeline. Fix: new `SECTION_8_ENTERED` flag set `true` at the very top of Section 8 (right after the `_apd_verify_pipeline_busy` skip-gate clears). Trap branches on the flag and calls `bash $SCRIPT_DIR/pipeline-advance reset` bezuslovno before the existing backup-restore layer fires. The existing `HAD_EXISTING_PIPELINE`-gated `cp $BACKUP_DIR/*.done $PIPELINE_DIR/` then layers backup state on top of the reset, preserving the original behavior for projects that did have prior `.done` files. Net effect: idle-project verify-apd runs now end in a fully clean pipeline directory instead of half-state.
- **fix(verify): synthetic builder uses reserved name `apd-verify-builder`.** Section 8 line 754 (pre-fix) wrote a 30-byte stub at `$APD_AGENTS_DIR/backend-builder.md` when the file was absent. `CREATED_BUILDER=true` then gated the trap-side `rm -f`. The bug: every subsequent verify-apd run found the stub present → set `CREATED_BUILDER=false` → trap left the file untouched → the stub became permanent. BambiProject's real agent roster is backend-api / backoffice / database / mobile / testing (no `backend-builder`), so the Apr 29 verify-apd run created the stub, `apd-audit` backed it up as `backend-builder.md.bak.preaudit` (same 30 bytes), and from that point on every `apd doctor` run on BambiProject showed `✓ backend-builder (?/?)` because the agent-registry parser found YAML with only a `name:` field, no `model:` or `effort:`. Fix: synthetic builder name changed to `apd-verify-builder` (reserved namespace for verify-apd's internal use). Trap removes it bezuslovno (no `CREATED_*` flag) because the name is guaranteed never to belong to a real project agent. `code-reviewer` and `adversarial-reviewer` keep their original names because `pipeline-advance` hardcodes `adversarial-reviewer` for the ordering check at lines 631 (`grep "|stop|adversarial-reviewer|"`) and 672 (`grep "|start|adversarial-reviewer|"`); their stub creation continues to gate on `CREATED_REVIEWER` + `CREATED_ADVERSARIAL`. The opt-out section (APD-VERIFY-OPT-OUT, line 905-906) also re-creates the `apd-verify-builder.md` stub idempotently in case `pipeline-advance reset` between the two sub-tests wiped agent files.
- **Live-verified before bump:** scripted reproduction of the BambiProject scenario — tmp project with `APD-VERIFY-TEST` synthetic state (spec-card.md, *.done, .agents, .adversarial-*) + `apd-verify-builder.md` (30-byte stub) + real `backend-builder.md` (55 bytes, mock content) → `pipeline-advance reset` + `rm -f apd-verify-builder.md` (the trap's bezuslovan cleanup pair) → pipeline directory empty, `apd-verify-builder.md` removed, real `backend-builder.md` untouched with all 55 bytes intact.
- **Test:** `bin/core/test-codex-adapter` §49 (7 assertions): (A) `verify-apd` source has zero `backend-builder` references confirming B2 rename completeness; (B) `SECTION_8_ENTERED=true` flag literal present; (C) `awk` extract of the trap function body grep-matches both `SECTION_8_ENTERED.*true` and `pipeline-advance.*reset`; (D) same extract finds the `rm -f "$APD_AGENTS_DIR/apd-verify-builder.md"` literal; (E-G) live cleanup test reproduces BambiProject scenario via `mktemp -d` + manual synthetic state seeding + `pipeline-advance reset` invocation, asserts pipeline directory empty + stub removed + real `backend-builder.md` (with `REAL CONTENT` sentinel) preserved. Test count 403 → 410.
- **Note:** existing BambiProject contamination (the artifacts that surfaced this bug) is NOT auto-recovered by v6.5.2 — fix is forward-only. To clean BambiProject: `bash .claude/bin/apd pipeline reset` + `rm .claude/agents/backend-builder.md .claude/agents/backend-builder.md.bak.preaudit` if those are stale stubs (verify size — real agent files are 2-4 KB; the 30-byte stub is the BambiProject regression artifact).

## v6.5.1 — 2026-05-14

Verification-script path fix. No behavior change in any pipeline, guard, or MCP code path. Tests: 403/0 (unchanged baseline).

- **fix(verify): `hooks/hooks.json` lives at repo root, not `plugins/apd/`.** `plugins/apd/bin/core/verify-apd:230` and `plugins/apd/bin/core/test-hooks:94` both read `$APD_PLUGIN_ROOT/hooks/hooks.json` (= `plugins/apd/hooks/hooks.json`), but per the CLAUDE.md architecture map `hooks/hooks.json` is at the repo root (CC auto-discovery anchor — the v6.0 self-containment plan considered moving it under `plugins/apd/hooks/` but the move never happened because CC requires the anchor at the top-level plugin root, not nested). The two references were stale remnants of that proposed move. Post-fresh-install `verify-apd` therefore printed `✗ Plugin hooks/hooks.json DOES NOT EXIST` as the very first hooks-section result, which masked the rest of the verification report and made the install look broken when in fact every hook was wired correctly. Both scripts now compute `REPO_ROOT="$APD_PLUGIN_ROOT/../.."` (per CLAUDE.md convention for scripts that need repo-root paths — the same pattern the Codex marketplace manifest and top-level CC skills already use) and read `$REPO_ROOT/hooks/hooks.json`. After fix `verify-apd` emits `✓ Plugin hooks/hooks.json valid JSON` and continues into the rest of section 3a (SessionStart, PreToolUse Bash → adapter/cc/guard-git, PostToolUse Bash → pipeline-post-commit, PostCompact, PermissionDenied — all of which were previously skipped because the parent `if` branch short-circuited on the missing file). `test-codex-adapter`: 403/0 — no regressions in the primary E2E suite (the test does not exercise this code path because verify-apd is invoked separately).

## v6.5.0 — 2026-05-13

Framework self-detection — plugin can be enabled in its own source repo without auto-scaffolding or pipeline enforcement turning the framework into a managed consumer project. Tests: 397 → 403.

- **feat(resolve): framework self-detection.** Until v6.5 the only way to keep APD out of its own source was a total plugin disable in `.claude/settings.local.json` (`"claude-apd@zstevovich-plugins": false`). That worked but cost the framework developer access to slash skills + MCP tools while working in the dev repo itself. `resolve-project.sh` now flags `APD_FRAMEWORK_SELF=true` when the resolved `PROJECT_DIR` contains BOTH `plugins/apd/VERSION` AND `.claude-plugin/plugin.json` with `"name": "claude-apd"`. When the flag is set, `APD_ACTIVE=false` is forced regardless of whether a config file exists. `apd-init` prints a one-line "framework dev mode" message and exits 0 (`--quick` stays silent for hook callers). `session-start` emits a once-per-session banner and exits 0 before any scaffolding can run. Guards (which already no-op on `APD_ACTIVE=false`) stay silent. Skills + MCP tools register normally because CC handles those at the plugin level, not via APD's activation marker — so enabling `claude-apd@zstevovich-plugins` in `settings.local.json` now gives the framework developer slash skills + MCP without auto-scaffolding the framework into a managed consumer project. Override for dogfooding the framework on itself: `APD_FRAMEWORK_DEV_MODE=force-enable`. New `test-codex-adapter` §48 (6 assertions: detection on real markers, force-enable override restores activation, foreign plugin.json doesn't false-positive, apd-init message + no scaffold writes, --quick silent exit). Test count 397 → 403. CLAUDE.md Critical Rules section documents the new flag + override.

## v6.4.0 — 2026-05-12

v6.3 audit cleanup + Codex config drift mitigation. Tests: 369 → 397.

- **fix: nine logic-quality findings from v6.3.0 audit.** Max-effort code review across the non-Codex-adapter framework caught 1 CRITICAL + 4 HIGH + 3 MEDIUM + 1 LOW issue. CRITICAL: `guard-bash-scope` checked "any path in scope" rather than "the write target in scope" — `cp src/innocent /etc/passwd` passed when scope=src/. Now identifies the actual destination per write-op family (redirects, tee, cp/mv/install positional tail, dd of=, mkdir/touch/rm/rmdir args, sed -i files after pattern; BSD/GNU sed handled, octal escape for embedded quotes in awk source). HIGH: spec re-advance now wipes `.builder-count`/`.reviewer-count` (was carrying counters across tasks, blocking fresh tasks with misleading prior-task messages); `gh-sync` uses `jq --arg t "$ARG2"` + `contains($t)` to prevent injection; `verify-apd` parses the actual spec-card heading format (was matching `^# Task:` which the template never emits, so Section 8 always skipped); `workflow.md §0b` reworded "every dispatch costs a cycle" → "every `pipeline-advance <phase>` call costs a cycle" to match code semantic. MEDIUM: zombie sweep filters by ancestor PID chain (no more cross-terminal false positives); reviewer rollback clears stale `.adversarial-summary`; `apd-init` eager `.apd-version` sync drops `[ -n "$PROJ_V" ]` guard so missing files get the version too. LOW: `rotate-session-log` uses `wc -l | tr -d ' '` instead of `grep -cv … || echo 0` (was producing multi-line "0\n0" in archive metadata). New `test-codex-adapter` §44 (16 assertions: 8 pre-audit bug repros + 8 happy paths covering cp/mv/sed -i BSD+GNU/rm/mkdir/tee/dd/multi-file) + §45 (1 assertion: rollback to reviewer clears stale summary). Test count 369 → 386.
- **feat(cdx): v6.4 G1 — codex-doctor version-mismatch detection + --fix.** Closes the live failure from the 2026-05-12 Test session on Codex 0.130.0: marketplace upgrade cleaned v6.2.0 but project `.codex/config.toml` cwd still pointed there, Codex MCP startup failed with "No such file or directory (os error 2)". Doctor's Project `.codex/` section now reads cwd from `[mcp_servers.apd]` (awk-based), extracts the version (sed regex `cache/codex-apd/apd/<X.Y.Z>`), and compares with installed plugin cache versions (`sort -V` picks highest). Three branches: stale (cwd dir no longer exists in cache) → BAD with explicit recovery command; older-but-still-installed → WARN with migration hint; matching → silent. The new `--fix` flag at the script entry parses out of `$@` before the optional project-path positional; when version-mismatch detected, invokes the latest-installed plugin's `apd cdx init <project>` to rewrite the config.toml. Closes the v6.4 G1 backlog item from `project-v6.4-codex-config-drift-backlog.md`. New `test-codex-adapter` §46 (5 assertions: stale-detection, recovery-hint path, older-version warn, matching-silent, --fix-invokes-recovery). Test count 386 → 391.
- **feat(cdx): v6.4 G2 — `[features].codex_hooks` → `[features].hooks` rename.** Codex 0.130 renamed the hooks feature flag and emits a per-session deprecation warning when only the old key is present. Plugin never wrote the flag directly (only printed CLI hints + checked for it in global config), so scope was detection + auto-recovery. `codex-doctor` Global Codex config section branches on four states: new-name-only (OK, Codex 0.130+ canonical), old-name-only (WARN with rename instructions; `--fix` does macOS-safe `sed -i.bak` rename in place), both (OK + soft warn about redundant deprecated key), neither (BAD with both-form enable hint). `install-codex-config` post-install hint now says `codex features enable hooks` (new form) with a one-line fallback for older Codex 0.121–0.125. `apd help` text updated to match. The legacy form is preserved in hints for now — once we have telemetry that no users are on pre-0.124, the fallback line can drop. New `test-codex-adapter` §47 (6 assertions: all four detection states + --fix rename + install hint mentions both forms). Test count 391 → 397.

## v6.3.0 — 2026-05-11

BambiProject Cycle 1 post-mortem — five framework backlog closures targeting both inter-dispatch overrun (3+ builder cycles for polish work) and the orchestrator-discipline failure modes surfaced by the 2026-05-11 incident. Test count: 328 → 361.

- **feat(pipeline): v6.3 D — spec-card max_defects immutability across re-advance.** `pipeline-advance spec` writes a `.spec-max-defects-history` snapshot (`<task>|<value>`) alongside `.spec-hash`. On subsequent spec advance for the same task name, raising `max_defects` (numeric > prev, or → `unlimited`) is BLOCKED. Lowering is allowed. Reset wipes the snapshot — the explicit escape valve for a real pivot. Closes the rollback+re-advance loophole that defeated the v6.1.2 B2 severity gate (BambiProject Cycle 1 spec-card amended `max_defects=0 → 6` mid-pipeline). Same bold/italic tolerance as the verifier-side parser. New `test-codex-adapter` §38 (7 assertions: first-write, raise-block, lower-allow, different-task-allow, reset-wipes, post-reset-fresh). Test count 328 → 335.
- **feat(rules): v6.3 E — orchestrator communication discipline.** Anti-epilogue rules in orchestrator-facing templates target the RLHF-default end-of-turn lessons-learned recap + "what I did + next steps" multi-bullet wrap-ups. (a) `plugins/apd/rules/workflow.md` — new `## 0a. Communication discipline` section before "Lean vs Full"; Do-NOT list (lessons-learned bullets, recaps, self-narration, restating user command, multi-paragraph wrap-ups) vs Do list (one-line state updates during work, one-sentence end-of-turn, real questions). (b) `plugins/apd/templates/CLAUDE.md.reference` — new `**Communication:**` critical-rule bullet alongside Author/Style. (c) `plugins/apd/templates/codex/AGENTS.md` — new `### Communication discipline` subsection under APD before Pipeline. Dispatch templates (builder/reviewer/adversarial) audited and left untouched — their structured output formats do not license epilogues. New `test-codex-adapter` §39 (6 assertions verifying anti-epilogue phrasing present in all three files). Test count 335 → 341. Existing projects scaffolded pre-v6.3 do not auto-pick up the rule; re-run `apd-init` or manual `workflow.md` refresh required.
- **feat(track-agent): v6.3 A — post-agent zombie sweep on SubagentStop.** `track-agent` SubagentStop branch now runs a process-table audit after every subagent stop. Catches polling-loop zombies (`while pgrep | while true | while sleep | tail -f | watch -n`) and gradle daemons left behind by the subagent's bash invocations. Closes the BambiProject Cycle 1 multi-hour gradle zombie: builder dispatched `while pgrep -f testDebugUnitTest; do sleep 5; done` which infinite-looped because the gradle daemon AND the polling shell both carried the matched pattern in argv. User manually `pkill`-ed 45 min later. Uses `ps -axo "pid= command="` (cross-platform; BSD pgrep lacks `-a`); filters out `track-agent`, `/claude`, sweep itself, `ps -axo`. Surfaces up to 5 hits as WARN to stderr + appends `<ts>|<agent>|<pid>|<cmd>` rows to `zombie-audit.log` under `MEMORY_DIR`. Informational — never blocks the agent stop event. Opt-out: `APD_ZOMBIE_SWEEP=0`. Pattern set deliberately excludes `node`/`python`/`dotnet` — too broad in dev-server-heavy projects, false positives erode trust. Still CC-only — Codex 0.128 has no SubagentStop hook equivalent. New `test-codex-adapter` §40 (5 assertions covering spawn-and-detect, audit-log capture, opt-out, no-stale-match after kill). Test count 341 → 346.
- **feat(pipeline): v6.3 C — builder cycle cap (max_cycles).** `pipeline-advance builder` now counts dispatches per task in `.builder-count` and blocks runaway re-dispatch loops. Default cap = 2 (one initial + one re-dispatch after reviewer rejection). Counter persists across rollback + re-advance — every dispatch costs a cycle. Reset wipes. Closes the BambiProject Cycle 1 runaway pattern (3 builder cycles for a polish task, ~28 min agent time). Override per spec via line in spec-card.md: `builder: max_cycles=4` (explicit higher cap with rationale), `builder: max_cycles=unlimited` (no cap). Parser uses the same bold/italic tolerance as `adversarial: max_defects`. Block message names three forward paths: (a) STOP and review whether implementation-plan.md is complete or adversarial is flagging the same issue repeatedly; (b) decompose into smaller tasks and reset; (c) raise the cap with rationale via rollback + re-advance. Counter is NOT incremented when blocked — re-running after rollback + cap raise starts from the same number, not one above. `workflow.md §0b` documents the field. New `test-codex-adapter` §41 (7 assertions: first/second advance under default cap, third blocked, no counter bump on block, raised cap, unlimited allows arbitrary dispatches, reset wipes). Test count 346 → 353.
- **feat(pipeline): v6.3 B — reviewer cycle cap + `pipeline_mode: polish`.** Scoped down from the original B memo. (a) Reviewer cycle cap (mirror of v6.3 C builder cap). `.reviewer-count` counter at `pipeline-advance reviewer`; default 2; override via `reviewer: max_cycles=N|unlimited`. Reset wipes. (b) `pipeline_mode: polish` preset. Lowers BOTH builder and reviewer default caps to 1 — no re-dispatch. Explicit per-phase `max_cycles` still takes precedence over the preset. Named `polish` (not `lean`) to avoid conflict with the existing "Lean" semantic (= `adversarial: skip` opt-out for tiny tasks). Deliberately deferred to v6.4: adversarial cycle cap (rare in practice; no `pipeline-advance adversarial` step; needs a different counter mechanism) + auto-spec follow-up for dismissed adversarial findings (separate feature, not a fix). `workflow.md §0b` renamed (singular → plural "phase cycle caps"), polish-mode subsection added. New `test-codex-adapter` §42 (8 assertions: default cap=2 first+second allow, third block, no bump on block, reset wipes, polish caps both at 1, explicit override beats preset). Side fix: §40 (v6.3 A zombie sweep) flakiness eliminated. Original wait loop checked pgrep visibility before invoking track-agent, but the sweep uses `ps -axo`, which has different process-table flush timing on some runs. Replaced with explicit ps-only wait (up to 2 s). 8-run stress test confirms stability. Test count 353 → 361. With `pipeline_mode: polish` + defaults, the BambiProject Cycle 1 second builder dispatch would have BLOCKED at #2, forcing human review at the right moment instead of 3 cycles of agent thrash.

## v6.2.0 — 2026-05-06

Diagnostics symmetry across both runtimes for stale plugin cache cleanup, plus SPEC threat-model rationale motivated by the CC 2.1.121–128 scan. Test count: 278 → 280.

- **docs(spec): rationale for guard-based enforcement.** Added a paragraph to §4.3 explaining why APD relies on guard `exit 2` + the compiled `validate-agent` Go binary instead of CC permission prompts. Motivated by CC 2.1.121 + 2.1.126: `--dangerously-skip-permissions` now skips writes to `.claude/skills/`, `.claude/agents/`, `.claude/commands/`, and the entire `.claude/`, `.git/`, `.vscode/`, and shell config files. Anyone running CC in that mode bypasses every permission rule, so APD's enforcement boundary cannot live there.
- **feat(cc): stale plugin cache detection in `pipeline-doctor`.** New block in §10 reads `~/.claude/plugins/installed_plugins.json`, finds the active `claude-apd@<marketplace>` install path, and lists sibling per-version cache directories not referenced by the JSON. Each is shown with `du -sh` size and a manual `rm -rf` hint. Read-only — no destructive action from the doctor. Detected 48 MB of stale cache on the development machine (3 dirs: 6.1.0, 6.1.1, 6.1.2). Verified `claude plugin prune` does not handle this scenario — it only cleans auto-installed dependencies.
- **fix(cc): remove broken `CACHE_NAME` warn from `pipeline-doctor` §10.** The pre-existing `basename(dirname($APD_PLUGIN_ROOT))` check had been a false-positive every run since v6.0 self-containment moved the plugin payload into `plugins/apd/` (`CACHE_NAME` always resolved to `plugins`, never to a version string). New stale-cache detection above covers the meaningful diagnostic; the broken block deleted.
- **feat(codex): symmetric stale plugin cache detection in `codex-doctor`.** New "Plugin cache" section between MCP server and Summary checks `$CODEX_HOME/plugins/cache/*` for sibling version dirs. Codex's v6.0+ self-contained cache layout makes the walk simpler: `$APD_PLUGIN_ROOT` is itself the version dir, so `dirname` lands on the version-parent directly. Dev-mode runs (`$APD_PLUGIN_ROOT` outside the cache prefix) print `_ok` "running from non-cache path" instead of false-positiving.
- **test: 2 new assertions in `test-codex-adapter` §15.** Asserts that `apd cdx doctor` output contains a `Plugin cache` section and that the dev-mode `running from non-cache path` skip fires (tests scaffold via `mktemp`, so APD_PLUGIN_ROOT is the dev repo path). Count 278 → 280.
- **docs(spec): §14 audit cleanup.** Removed 5 stale entries (Codex 0.121.0 marketplace blocker, slash-menu skill listing, .mcp.json gap, manifest version lag from §13 + §14) — all resolved in 0.124+ or v6.0. Reworded 3 entries (`SessionStart`, `codex exec`, pipeline reset) to drop stale version references ("v5.1 candidate", "v4.7.21+F2 docs"). 13 → 9 limitations.
- **test: regression coverage for `guard-bash-scope` read/write distinction.** New `test-codex-adapter` §27 (10 assertions) verifies that read commands (`cat`, `grep`, `head`, `tail`, `wc`, `less`) on `.apd/pipeline/spec-card.md` ALLOW (exit 0) and write commands (`>`, `>>`, `cp`, `rm`, `sed -i`) BLOCK (exit 2). Closes the 2026-04-10 Bambi Run #9 false-positive memo as RESOLVED on current master (the original bug does not reproduce; coverage prevents future regression).
- **feat(pipeline-gate): stage completeness soft warn.** After `.done` signature verification succeeds, `pipeline-gate` now lists modified files in any dispatched builder's scope that are not staged for commit. Reads `.apd/pipeline/.agents` for dispatched builders, finds each agent file (`.apd/agents/<name>.md` or `.claude/agents/<name>.md`), extracts scope from either Codex YAML `scope:` list or CC inline `guard-scope <paths>` hook command, and cross-references against `git diff --name-only` + `git ls-files --others --exclude-standard`. Soft warn — exit 0 always (per memo: sometimes files are intentionally left out). Closes the 2026-04-16 BambiProject "Verifikacija emaila #31" miss (RegisterScreen.kt left out of a 22-file commit). New `test-codex-adapter` §28 (4 assertions: positive warn + file naming + no-false-positive when staged + no-false-positive out-of-scope). Test count 280 → 294.
- **feat(track-agent): CC parallel same-type dispatch gate.** `track-agent` SubagentStart now blocks (exit 2) when an agent of the same `agent_type` started within `APD_PARALLEL_WINDOW` seconds (default 30) and has not emitted a matching `SubagentStop` for its `agent_id`. Closes 2026-04-16 BambiProject #48 (3× backend-api dispatched in 34s, drove orchestrator into destructive-git recovery). Cross-platform epoch math (`date -j` BSD / `date -d` GNU). Different agent types are unaffected. `APD_PARALLEL_WINDOW=0` disables the gate. CC-only — Codex has no equivalent hook surface (per `reference-codex-0.128-doc-verified.md`); Codex side requires orchestrator discipline. New `test-codex-adapter` §29 (5 assertions: first dispatch ALLOW + parallel BLOCK + different-type ALLOW + after-stop ALLOW + window=0 ALLOW). Test count 294 → 299.
- **fix(apd-init): mkdir deny coverage.** `apd-init` settings.json `permissions.deny` block extended from 4 to 8 patterns. The original 4 all required a `*/` prefix (e.g. `Bash(mkdir */.apd/pipeline)`), which CC's glob does not match against the bare form `mkdir .apd/pipeline` — the most common orchestrator pre-pipeline command. New 4 patterns cover the bare form (`Bash(mkdir .apd/pipeline)`, `Bash(mkdir -p .apd/pipeline)`, `Bash(mkdir .apd/pipeline/*)`, `Bash(mkdir -p .apd/pipeline/*)`). `permissions.deny` overrides hook-ask since CC 2.1.101, so the prompt never appears — naive users no longer get the chance to approve a destructive directory create. Defense in depth still includes `guard-bash-scope` and `guard-pipeline-state`. New `test-codex-adapter` §30 (9 assertions: settings.json exists + each of the 8 deny patterns present verbatim). Test count 299 → 308.
- **test: lock-in `pipeline-advance spec` hard block.** Existing behavior since v3.6.0 (lines 184-198) — exits 1 when `spec-card.md` is missing or has no `R*` acceptance criteria — was never covered by an automated test. New `test-codex-adapter` §31 (2 assertions). Closes the spec-card side of `project-enforcement-gaps`; the adversarial-summary side is superseded by the v6.1 `.adversarial-pending` hard gate (already covered by §23/§25). Test count 308 → 310.
- **test: lock-in `pipeline-advance builder` hard block on missing plan.** Existing behavior (lines 240-244) — builder exits 1 when `.apd/pipeline/implementation-plan.md` is absent — was never covered by an automated test. New `test-codex-adapter` §32 (1 assertion). Closes `project-implementation-plan-step` (the plan-as-precondition design ships as builder-step gate rather than a separate `pipeline-advance plan` subcommand). Test count 310 → 311.
- **test: lock-in `superpowers:` agent prefix rejection.** Existing behavior (`pipeline-advance` lines 257-265 reviewer + 363-371 builder) — reviewer/builder steps reject any `.agents` `stop` event whose `agent_type` matches `^superpowers:` and emit `BLOCKED: No project Reviewer/Builder agent was dispatched!` with guidance toward `Agent({ subagent_type: "code-reviewer", ... })` — was never covered by an automated test. New `test-codex-adapter` §33 (2 assertions: rejection exit + guidance message). Closes `feedback-superpowers-conflict`; superpowers is also disabled at the `enabledPlugins` level by `apd-init`. Test count 311 → 313.
- **feat(mcp): `apd_pipeline_metrics()` 9th MCP tool.** Reads `.apd/memory/pipeline-metrics.log` and returns structured runs (timestamp, task, phase ts, status, adversarial summary T/A/D, agent counts). `limit` arg caps recent runs (0 = all, max 200). Closes the v6.1 deferred item; replaces the `apd-miro` workaround that read the log directly. Also wired into `install-codex-config` `_APD_TOOLS` tuple, `codex-doctor` `EXPECTED_TOOLS` list, and `plugins/apd/.mcp.json` per-tool approval block. New `test-codex-adapter` §34 (3 assertions: total/list, limit subset, numeric field parse) + §2 loop count adjusted from 8 → 9. Test count 313 → 317.
- **docs(skill): switch Codex `apd-miro` to `apd:apd_pipeline_metrics()`.** Procedure step 1 now calls the MCP tool instead of `cat .apd/memory/metrics.csv`; Exit criteria reference updated; `agents/openai.yaml` `default_prompt` rewrites the workaround language. Closes the v6.1.0 known gap noted in the original `apd_pipeline_metrics()` audit (CHANGELOG v6.1.0 A6 bullet). CC `skills/apd-miro/SKILL.md` is unchanged — CC uses the `bash .claude/bin/apd pipeline metrics` CLI shortcut, not MCP. No test impact.
- **feat(mcp): C2 Phase 2a — TOML agent parser support.** `apd_mcp_server` now reads Codex-canonical `.codex/agents/<name>.toml` files alongside the legacy `.apd/agents/<name>.md` format. New `_parse_agent_toml()` (via `tomllib` on 3.11+, `tomli` fallback) and `_parse_agent()` dispatcher; `_agents_dir()` priority is `.claude/agents/` → `.codex/agents/` → `.apd/agents/`. `apd_list_agents` globs both extensions; `apd_guard_write` tries `.toml` before `.md`. `--with tomli` added to `args` in `plugin .mcp.json`, `install-codex-config`, and `codex-doctor` so Python <3.11 has the parser. **No behavior change for existing users** — projects with only `.apd/agents/*.md` keep working. Test §35 (4 assertions: TOML list discovery + in-scope allow + out-scope block + legacy `.md` backward-compat). Test count 317 → 321. Phases 2b–2d (migration utility, flip default, sunset) deferred to subsequent v6.2 sessions.
- **feat(cdx): C2 Phase 2b — `apd cdx agents migrate` utility.** New subcommand in `agents-scaffold` converts `.apd/agents/*.md` → `.codex/agents/*.toml` in-place. Supports `--dry-run` (preview without writing) and `--force` (overwrite existing targets). Idempotent: re-run skips files that already exist. Source `.md` files are preserved so the legacy fallback in `_agents_dir()` continues to work. Output TOML has Codex-documented fields (`name`, `description`, `model`, `model_reasoning_effort`, `developer_instructions`) plus a clearly labelled "APD extensions" section (`max_turns`, `scope`, `readonly`). Body content uses `"""..."""` by default, falls back to `'''...'''` literal string if body itself contains `"""`. `bin/apd` help text + `agents-scaffold` help text updated. Test §36 (5 assertions: dry-run no-write, real migrate creates target, TOML field shape, idempotent skip, source preserved). Test count 321 → 326. Phases 2c (flip `add` default to `.toml`/`.codex/agents/`) and 2d (sunset `.md` fallback target v6.4) remain.
- **fix(cdx): codex-doctor surfaces migrate hint.** When `.apd/agents/` contains `.md` agent files but `.codex/agents/` has no `.toml` files, `codex-doctor` now warns and suggests `apd cdx agents migrate` so users discover the C2 migration path through their existing health check. Hint clears automatically once migration completes (counts go to 0/N+ on next run). Test §37 (2 assertions: hint appears + hint clears). Test count 326 → 328.

## v6.1.3 — 2026-05-04

CC + Codex plugin audit cleanup. Test count: 257 → 278. Verified against `developers.openai.com/codex/{hooks,subagents,mcp,plugins/build}`.

- **fix(cc): drop redundant monitor declaration.** `monitors/monitors.json` ran the same `session-start` script that already fires as `SessionStart` + `PostCompact` hooks. The monitor produced a "Monitor stream ended" notification every session with zero added behavior. Removed the file and the `monitors:` field in `plugin.json`; SPEC §11.1 + §19 + README + CLAUDE.md aligned with the monitor-less layout.
- **fix(cc): bump `APD_MIN_VERSION` to 2.1.101.** First CC release where the `SessionStart` hook fires reliably for plugins. `session-start` + `verify-apd` now read `MIN_CC_VERSION` from `plugins/apd/.apd-version` (relocated from repo root, where it had been orphaned since v6.0 plugin self-containment).
- **feat(codex): apply_patch / Edit / Write enforcement.** New `bin/core/guard-file-edit` (core) + `bin/adapter/cdx/guard-file-edit` (cdx shim) block file-edit targets that have not been pre-cleared by `apd_guard_write`. The MCP tool records cleared targets into `.apd/pipeline/.guarded-writes` (10 min TTL); the file-edit hook reads that cache. `install-codex-config` block 5a wires the `PreToolUse apply_patch|Edit|Write` hook into project `.codex/hooks.json`. `spec-card.md` + `implementation-plan.md` allowlisted; `.apd/pipeline/` state and outside-project paths block hard. Canonical payload `tool_name: "apply_patch"` per Codex docs.
- **fix(guard): runtime-write detection in protected dirs.** `guard-bash-scope` now also runs the runtime-write detector (node / python / ruby / php / perl `-e` writes) when the command targets the plugin cache or `.apd/pipeline/`, closing a shell-bypass for those paths. DRY refactor extracted `_runtime_write_detected` helper.
- **fix(codex): canonical agent frontmatter.** All 5 `templates/codex/agents/*.md` use `model: gpt-5.4` (was `sonnet`/`opus`) and `model_reasoning_effort: high` (was `effort: xhigh`). Documented Codex 0.128 model values are `gpt-5.3-codex-spark` / `gpt-5.4` / `gpt-5.4-mini`; canonical effort field is `model_reasoning_effort`. Closes the v6.1.1 deferred M4 item.
- **fix(codex): `AGENTS.md` template structure.** Replaced `<fill in>` placeholders with required `## Stack` / `## APD` / `### Pipeline` / `### Guardrails` / `### Mandatory skills` / `### Human gate` sections so freshly scaffolded projects pass `apd-audit` + `codex-doctor` checks. Skill refs use bare names (`apd-brainstorm`) instead of MCP-tool-style `apd:apd-brainstorm`.
- **fix(codex): `codex-doctor` extended checks.** Added `AGENTS.md` required-sections + `<fill in>` + file-edit hook wiring checks. Hybrid checkout `.claude/` warning softened.
- **fix(pipeline): reset clears `.guarded-writes`.** `pipeline-advance reset` rm-line includes the new clearance cache file.

## v6.1.2 — 2026-04-29

Hotfix from BambiProject live pipeline evidence: spec-card.md authored with markdown-bold around the `adversarial:` directive (`**adversarial:** skip — <reason>`) was not recognized by `pipeline-advance`'s opt-out parser. The verifier therefore demanded the adversarial pass even though the spec opted out — the user's workaround was to dispatch a trivial adversarial-reviewer to satisfy the gate.

- **fix(pipeline): markdown-bold tolerance on adversarial directive parsing.** Both `pipeline-advance` parser sites — the reviewer-step `adversarial: skip` opt-out (introduced in v3.x) and the verifier-step `adversarial: max_defects=N` severity gate (introduced in v6.1 B2) — relaxed their regex from `^adversarial:` to `^[-*_ \t]*adversarial[-*_ \t]*:`. Six skip-variant inputs and three max_defects bold-variant inputs now match: `**adversarial:**`, `**adversarial**:`, `*adversarial:*`, `- adversarial:`, `**Adversarial:**`, plus the original plain form. Test section 26 covers all variants. Tests: 248 → 257.

## v6.1.1 — 2026-04-29

Codex skill-payload quality fixes from the v6.1.0 audit. Test count: 246 → 248.

- **H1 — apd-brainstorm advance-vs-exit clarified.** Codex and CC brainstorm skill text now distinguishes "do not advance while asking questions / presenting options / revising design" from the required exit: after explicit user approval, write the spec-card.md and call the spec pipeline advance as the only valid exit. Codex `agents/openai.yaml` prompt now carries the same wording.
- **H2 — Codex-native audit evals.** Added three `runtime: codex` apd-audit scenarios covering missing builder scope, stale `.claude/` references in `AGENTS.md`, and missing APD MCP per-tool approval blocks. Canonical evals now total 27; `eval-mirror` keeps CC mirror at 24 by excluding Codex-only scenarios and keeps Codex mirror at 24.
- **H3 — Both-runtime eval fixtures seed AGENTS.md.** The brainstorm, GitHub Projects, and Miro "both" scenarios now materialize `AGENTS.md` alongside `CLAUDE.md`, so Codex skill behavior is not tested against Claude-only context.
- **M5 — skill-eval runtime filtering.** `skill-eval --list` now shows the `runtime` field. `--rubric` and `--judge` execute only scenarios whose `runtime` is `both` or matches `--runtime`; explicit `--dry-run --runtime <cc|codex>` validates the same no-spawn execution subset. Section 24 adds coverage for the Codex subset (21/27), raising `test-codex-adapter` to 248 checks.
- **Deferred M4 — Codex agent `model:` values.** Left `sonnet` / `opus` in Codex agent templates untouched. Needs an author decision on whether those fields are descriptive labels or runtime selectors before changing to `gpt-5.x`.

## v6.1.0 — 2026-04-28

Skill quality + pipeline gate refinements per `docs/plans/v6.1-skills-and-pipeline-improvements.md`. Test count: 226 → 246.

**Track A — Skills authoring quality**

- **A1 — Pushy descriptions across 15 skills.** Description field now leads with a third-person trigger statement, lists explicit trigger phrases, and uses MANDATORY for hard-required skills (apd-tdd, apd-debug, apd-finish). Targets undertriggering surfaced by skill-creator audit. CC + Codex mirrors. Char counts 373–556, all under the 1024 description limit.
- **A2 — Concrete examples in 5 skills.** Anthropic-format Input/Output Example blocks (2-3 per skill) added to apd-debug, apd-audit, apd-finish, apd-github, apd-miro for both CC and Codex mirrors. Each example grounds the skill methodology in a realistic scenario: failing-test → root-cause walks for apd-debug, audit recommendation blocks for apd-audit, decision trees for apd-finish, lifecycle states for apd-github, and frame-update before/after for apd-miro.
- **A3 — Terminology consistency sweep.** Glossary normalized across all 15 skill files: `pipeline step → pipeline phase`, `acceptance criteria → R-criteria`, `Result: X issues → X findings`, `structural issue → structural finding`, `spec card → spec-card.md` for file references. The literal `## Spec card` heading inside sample issue bodies is left as-is.
- **A4 — Eval framework.** Scenario-driven evaluation harness for every shipped skill. Canonical source `plugins/apd/evals/<skill>/*.json` (24 scenarios — 8 skills × 3 each); `bin/core/skill-eval` runner with `--list`, `--dry-run`, `--rubric`, `--judge` modes; `bin/core/eval-mirror` syncs canonical scenarios into `skills/<skill>/evals/` (CC) and `plugins/apd/skills/<skill>/evals/` (Codex). Evals are advisory, not a pipeline gate. Spec under `plugins/apd/evals/README.md`.
- **A5 — Progressive disclosure for `apd-setup`.** Split the 389-line monolith SKILL.md (over Anthropic's 500-line soft ceiling for active-context skills, and frequently triggered) into a 140-line top-level guide plus three on-demand `reference/` files: `agent-templates.md` (auto-detect rules + builder/reviewer specs), `rules-templates.md` (CLAUDE.md sections, verify-all, rules, memory, settings, gitignore, MCP recommendations), and `init-checklist.md` (gap analysis table + example walkthrough + verification). SKILL.md links to each reference using Anthropic Pattern 1 (`See [reference/Y](reference/Y)`). CC-only — Codex `apd cdx init` CLI is unaffected.
- **A6 — Fully-qualified MCP tool names in Codex skills.** 83 bare references to APD MCP tools (`apd_advance_pipeline`, `apd_pipeline_state`, `apd_guard_write`, etc.) across 7 Codex `SKILL.md` + 7 `agents/openai.yaml` files now use Anthropic's `ServerName:tool_name` form (`apd:apd_advance_pipeline`, …). Audit also surfaced three references to a non-existent `apd_pipeline_metrics()` tool in `apd-miro`; replaced with a documented combination of `apd:apd_pipeline_state()` plus a direct `.apd/memory/metrics.csv` read until a metrics MCP tool ships.
- **A7 — Time-sensitive language audit.** Single hit: `apd-tdd` Codex SKILL.md pinned the `apd_role` parameter workaround to Codex 0.121.0. Rephrased as version-free ("Codex's multi_agent role-mismatch approval prompt") so the note ages cleanly across Codex releases.

**Track B — Pipeline gate refinements**

- **B1 — Adversarial pre-flight gate.** Closes the bambi run #34 ~2m wasted dispatch surfaced when adversarial-reviewer was triggered before reviewer.done. Two-prong gate:
    - **Hard (mechanical):** CC `track-agent` SubagentStart exits 2 when `adversarial-reviewer` is dispatched without `reviewer.done` OR without the `.adversarial-pending` marker (= adversarial opted out or already recorded). Codex `apd:apd_adversarial_pass` refuses early at the recording step with a parallel error.
    - **Soft (instruction):** `plugins/apd/rules/workflow.md` step 6b spells out the order gate; both `apd-tdd` SKILL.md Hand-off blocks (CC + Codex) point at the marker as the green light; `apd:apd_advance_pipeline` and `apd:apd_adversarial_pass` MCP docstrings name the gate.
    - test-codex-adapter section 23 covers all three branches per runtime (no marker → block, only reviewer.done → block, both markers → accept) plus a fourth check that regular `code-reviewer` dispatch is never caught by the adversarial gate. 232 → 239 checks.
- **B2 — Severity gate (`max_defects` spec-card field).** New optional `adversarial: max_defects=N|unlimited` line in `spec-card.md` lets the user opt into a strict severity threshold. `pipeline-advance verifier` parses the field and refuses to advance when the adversarial dismissed-defect count (`D` in `ADVERSARIAL:T:A:D`) exceeds the budget. Default (field absent) = `unlimited` — same behavior as pre-v6.1, no migration cost. Both `apd-brainstorm` skill files (CC + Codex) recommend per task size: hotfix → `unlimited`, real task → `0`, complex → `0` or `N` with rationale. test-codex-adapter section 25 covers parse + decision branches: `max_defects=2` (parsed, D=8 > 2 → block, D=2 → allow), missing field (default unlimited), `max_defects=unlimited` (explicit), colon variant `max_defects: 3`, plus a smoke test on the BLOCKED message wording. 239 → 246 checks.
- **B3 — maxTurns bump across the board.** Bambi run #34 produced 2 maxTurn exhausts on 7-R features (code-reviewer hit at 4m 8s, adversarial-reviewer at 5m+) and live builder runs showed re-dispatch mid-feature too. Memory feedback `feedback-maxturn-counterintuitive-speedup.md` already validated higher maxTurns wins because re-dispatch costs more turns than running through. Final landscape:
    - **Builders** (backend, frontend, testing, master `agent-template.md`): `40 → 60`
    - **Reviewers** (`reviewer-template.md`, `adversarial-reviewer-template.md` + matching Codex variants): `30 → 80`
    - Reviewers get the larger budget because they walk every file in the diff; builders write code in chunks. testing was at 30 pre-bump (drift); now aligned with the builder default at 60.
    - workflow.md, apd-setup SKILL + reference docs updated. Test count unchanged (246) — the change is purely data-value.

**Other**

- `docs/SPEC.md` 7.2 updated to 7 Codex skills (was stale at 4); new 7.3 section documents the eval framework; test-codex-adapter check count updated.

## v6.0.3 — 2026-04-27

Critical regression fix for CC users on v6.0.x. Session-start hook reported
`guard-git`, `pipeline-advance`, and `pipeline-gate` as MISSING, breaking
the pipeline.

**Root cause.** v6.0 moved every framework binary into `<repo>/plugins/apd/`,
but `bin/lib/resolve-project.sh` still set `APD_PLUGIN_ROOT = $CLAUDE_PLUGIN_ROOT`
verbatim when CC was running the hook. CC sets `CLAUDE_PLUGIN_ROOT` to the
plugin cache **repo root** (e.g. `~/.claude/plugins/cache/.../6.0.1/`),
not the plugin folder. So `SCRIPT_DIR = $APD_PLUGIN_ROOT/bin/core` resolved
to a path that no longer exists in v6.0+ (`bin/` lives under
`plugins/apd/`, not at root). Direct script invocation kept working
because the fallback branch walked up from `${BASH_SOURCE[0]}` to land
inside `plugins/apd/`. The mismatch only surfaced under CC hook execution.

**Fix.** `resolve-project.sh` now detects v6.0+ layout and adjusts:
when `$CLAUDE_PLUGIN_ROOT/plugins/apd/bin` exists, set
`APD_PLUGIN_ROOT = $CLAUDE_PLUGIN_ROOT/plugins/apd`. Falls back to the
old behaviour for pre-v6.0 caches that still have `bin/` at the plugin
root, so users on a stale cache during transition keep working until
they `/plugin update`.

## v6.0.2 — 2026-04-27

Fixes Codex TUI prompting for APD MCP tool approval even though `plugins/apd/.mcp.json` declared every APD tool with `approval_mode = "approve"`.

Live Codex 0.125 testing showed that plugin-shipped MCP approval metadata is not applied by the TUI approval gate. `install-codex-config` now writes a project-local, complete `[mcp_servers.apd]` override into `<project>/.codex/config.toml`: `command = "uv"`, relative `mcp/apd_mcp_server.py`, `cwd = "<plugin-root>"`, plus all eight `[mcp_servers.apd.tools.<tool>] approval_mode = "approve"` blocks. This keeps plugin `.mcp.json` as the self-registration fallback while making the effective no-prompt path use Codex's working config surface.

Important detail: APD writes the full parent transport block, not just per-tool approval sections. Per-tool sections alone create an implicit TOML parent with no transport and Codex fails with `invalid transport in mcp_servers.apd`.

`codex-doctor`, `test-codex-adapter`, `docs/SPEC.md`, and `plugins/apd/mcp/README.md` were updated to match the hybrid model.

## v6.0.1 — 2026-04-27

`verify-apd` Section 8 (synthetic pipeline end-to-end test) now refuses to run when an active real-task pipeline is in flight. Previously, if the test got triggered (via `apd verify` re-run, or other code paths that invoke verify-apd) while a project was mid-pipeline, it would overwrite `spec-card.md` and `implementation-plan.md` with `APD-VERIFY-OPT-OUT`/`APD-VERIFY-TEST` content, append fake agent events to `.agents`, set the pipeline lock, and (when gh-sync is wired) open a GitHub issue — forcing a manual ~3-minute recovery to restore real state.

Hard guard added at the top of Section 8: skips the entire end-to-end test when any of these are true:
- `spec-card.md` exists with a task name not starting with `APD-VERIFY-` (or with no `# Task:` header at all)
- `.lock` directory present (another pipeline operation in flight)
- `spec.done` exists for a task other than an `APD-VERIFY-*` synthetic

When skipped, `verify-apd` prints a clear warning telling the user to `apd pipeline reset` first if they want to exercise the test, and surfaces the skip in the summary as `Pipeline: skipped (active pipeline)`. The remaining 8 sections still run as usual.

Reported live by a CC user during a real GDPR-delete task pipeline, with the same incident also having corrupted a previous welcome-bonus pipeline (commits `58dde25` etc.). No more silent overwrites.

## v6.0.0 — 2026-04-27 — Plugin self-containment

**Major refactor.** Every framework binary, template, rule, and the MCP server itself now live inside `plugins/apd/`. The Codex plugin cache, which only mirrors the plugin folder, finally contains everything the MCP server needs — closing the v5.0.9–10 plugin-shipped `.mcp.json` gap that was reverted in v5.0.11. `install-codex-config` becomes cleanup-only for the MCP server section; per-project `<project>/.codex/config.toml` no longer carries `[mcp_servers.apd*]` blocks.

### Layout changes (repo root → `plugins/apd/`)

```
bin/        →  plugins/apd/bin/
mcp/        →  plugins/apd/mcp/
rules/      →  plugins/apd/rules/
templates/  →  plugins/apd/templates/
VERSION     →  plugins/apd/VERSION
```

Stays on the repo root (CC plugin auto-discovery + repo tooling):

- `.claude-plugin/{plugin.json,marketplace.json}` — CC manifests
- `hooks/hooks.json` — auto-discovered by Claude Code from `${CLAUDE_PLUGIN_ROOT}/hooks/`
- `skills/` — auto-discovered by Claude Code (top-level CC skills, including the CC-only `apd-setup`)
- `monitors/monitors.json` — referenced by `.claude-plugin/plugin.json` relative to repo root
- `.agents/plugins/marketplace.json` — Codex marketplace manifest
- `bump-version`, `.gitignore`, `README.md`, `CHANGELOG.md`, `LICENSE`, `docs/`, `examples/`

### MCP server self-registration

`plugins/apd/.mcp.json` now ships with the plugin and registers the APD MCP server with `cwd: "."`. Codex auto-loads this from the plugin cache at `~/.codex/plugins/cache/codex-apd/apd/<v>/`, which now contains `mcp/apd_mcp_server.py`. Per-tool approval modes for all 8 tools live in the same manifest under `mcpServers.apd.tools.<name>.approval_mode`.

### Migration for existing users

`apd cdx init` (i.e. `install-codex-config`) detects any legacy `[mcp_servers.apd]` and `[mcp_servers.apd.tools.<tool>]` blocks in `<project>/.codex/config.toml` and removes them. Backup of the original is written next to the file (`config.toml.bak.<epoch>`). After upgrading the plugin via `codex plugin marketplace upgrade codex-apd`, run `apd cdx init` once per project to clean up the legacy blocks.

### Path reference updates

- `${CLAUDE_PLUGIN_ROOT}/bin/...` → `${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/...` in all CC hooks, monitors, top-level CC skills, agent templates, and example agent files
- `APD_PLUGIN_ROOT` (computed by every script) now resolves to `plugins/apd/` instead of repo root. Scripts that need repo-root-only paths (the Codex marketplace manifest, top-level skills) reference an explicit `REPO_ROOT="$APD_PLUGIN_ROOT/../.."` instead
- `bump-version` updates `plugins/apd/VERSION`, `plugins/apd/.codex-plugin/plugin.json`, and `.agents/plugins/marketplace.json` in addition to the CC manifests

### Tests

`bin/core/test-codex-adapter` reorganised: 213 passing checks (was 209 before v6.0). New checks cover plugin `.mcp.json` validity, `cwd: "."`, all 8 per-tool approval entries, and migration of legacy `[mcp_servers.apd*]` blocks. `codex-doctor` now flags legacy MCP blocks and verifies plugin `.mcp.json` presence.

### Breaking

- Anyone with hardcoded `apd-template/bin/...` or `apd-template/mcp/...` paths in external scripts must update to `apd-template/plugins/apd/bin/...` etc.
- Pre-v6.0 `.codex/config.toml` files keep working until `apd cdx init` is rerun, but the plugin-shipped registration takes precedence — running both can cause Codex to spawn the MCP server twice.

## v5.0.11 — 2026-04-27

Fourth patch in the v5.1 chain. Reverts the v5.0.9-10 plugin .mcp.json self-registration experiment after a second live-test crash.

### What broke (again)

After v5.0.10 shipped, `codex plugin marketplace upgrade codex-apd` pulled the new `plugins/apd/.mcp.json`. Codex started without the v5.0.9 `invalid transport` crash (good), but `apd_ping` failed with:

```
⚠ MCP client for `apd` failed to start: MCP startup failed: handshaking with MCP server failed: connection closed: initialize response
```

`~/.codex/log/codex-tui.log` shows the actual cause:

```
MCP server stderr (uv): can't open file '/Users/zoranstevovic/.codex/plugins/cache/codex-apd/mcp/apd_mcp_server.py': [Errno 2] No such file or directory
```

### Root cause

The Codex plugin cache layout is narrower than we assumed. After `codex plugin marketplace upgrade`, the plugin lives at `~/.codex/plugins/cache/codex-apd/apd/<version>/` and contains only the contents of `plugins/apd/` from the repo — `.codex-plugin/`, `.mcp.json`, `skills/`. It does **not** include `mcp/apd_mcp_server.py`, `bin/core/*`, `bin/adapter/cdx/*`, or `VERSION`, all of which live at the repo root *outside* the plugin directory. With `cwd: "../.."` in our manifest, Codex resolved cwd to `~/.codex/plugins/cache/codex-apd/` and spawned `uv run python mcp/apd_mcp_server.py` from there — file not found.

Plugin-shipped self-registration is fundamentally incompatible with our current layout. The fix is to move `mcp/`, `bin/`, and `VERSION` into `plugins/apd/` (plugin self-containment), which is a structural refactor — v6.0 territory, not a patch. Until then, the absolute-path writer in `install-codex-config` stays.

### Revert

- **Removed: `plugins/apd/.mcp.json`** — broken self-registration entry.
- **`bin/adapter/cdx/install-codex-config`** — restored to v5.0.8 behaviour. Writes `[mcp_servers.apd]` (command + args, absolute path to the active checkout's `mcp/apd_mcp_server.py`) plus 8 per-tool `[mcp_servers.apd.tools.<name>]` approval blocks. The legacy block is no longer "removed on next run"; it is now the canonical block we want there.
- **`bin/adapter/cdx/codex-doctor`** — MCP checks reverted to config.toml-based (looks for `[mcp_servers.apd]` + 8 per-tool blocks; warns when path doesn't match `APD_PLUGIN_ROOT`).
- **`docs/SPEC.md` §3, §12, §18.1** — reverted to v5.0.8 wording, with a new explanatory paragraph at the end of §3 documenting the failed v5.0.9-10 attempt as a cautionary note pointing at the v6.0 plugin-self-containment refactor.
- **`bin/core/test-codex-adapter`** — back to the v5.0.8 form. Total 211 → 209 PASS / 0 FAIL (the 2 plugin-mcp-specific checks added in v5.0.10 are gone with their feature).

### Lessons

- The "test through marketplace" rule held: v5.0.9 and v5.0.10 both passed all 211 unit tests because the framework tests run against the dev repo where `mcp/apd_mcp_server.py` exists at `${APD_PLUGIN_ROOT}/mcp/`. The marketplace cache is a different path layout entirely. Only the live `codex plugin marketplace upgrade` + TUI session catches this.
- Feedback memory updated: don't assume the plugin cache mirrors the repo; check what files Codex actually copies into `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/` before designing plugin-relative paths.

### Live unblock for users on v5.0.10

If your project's `.codex/config.toml` was emptied during the v5.0.10 attempt, run `apd cdx init` once v5.0.11 ships — it will rewrite `[mcp_servers.apd]` and per-tool approvals back into the file.

## v5.0.10 — 2026-04-26

Third patch in the v5.1 chain. Emergency fix for v5.0.9 — live test caught a Codex startup crash that local-cache testing would have missed.

### What was broken in v5.0.9

v5.0.9 shipped `plugins/apd/.mcp.json` and stopped writing top-level `[mcp_servers.apd]` into user config.toml — but kept writing the eight `[mcp_servers.apd.tools.<name>]` per-tool approval blocks. After running `apd cdx init` on a v5.0.9 project, `<project>/.codex/config.toml` contained only the per-tool blocks. TOML semantics implicitly defines `mcp_servers.apd` as a parent table whenever any `[mcp_servers.apd.tools.<name>]` block exists; that parent had no `command` / `url`, so Codex refused to start: `Error loading config.toml: invalid transport in mcp_servers.apd`. Per-tool blocks cannot legally exist without a parent transport block in user config.

### Fix

- **`plugins/apd/.mcp.json` gains a `tools` field.** Codex `RawMcpServerConfig` accepts `tools: HashMap<String, McpServerToolConfig>` per `codex-rs/config/src/mcp_types.rs:241`; `McpServerToolConfig` carries the `approval_mode` field (line 56). All eight APD tools (`apd_ping`, `apd_doctor`, `apd_advance_pipeline`, `apd_guard_write`, `apd_verify_step`, `apd_adversarial_pass`, `apd_list_agents`, `apd_pipeline_state`) now declare `approval_mode = "approve"` inside the plugin manifest itself. Codex picks them up alongside the server registration.
- **`bin/adapter/cdx/install-codex-config` is cleanup-only.** It writes nothing under `[mcp_servers.apd*]`; on re-run it strips both pre-v5.0.9 top-level `[mcp_servers.apd]` and v5.0.9 per-tool `[mcp_servers.apd.tools.*]` blocks. If config.toml has nothing to clean, the script is a no-op (the file is not even created).
- **`bin/adapter/cdx/codex-doctor` updated.** New OK check: plugin `.mcp.json` includes per-tool approvals for all 8 APD tools. New BAD check: legacy `[mcp_servers.apd.tools.*]` block(s) still in user config.toml — explains the `invalid transport` crash and points at `apd cdx init` for cleanup.

### Doc updates

- `docs/SPEC.md` §3 — clarifies that all MCP config (server + per-tool approvals) ships in plugin `.mcp.json` since v5.0.10.
- `docs/SPEC.md` §12 (configuration surfaces) — `<project>/.codex/config.toml` row reworded as cleanup-only.
- `docs/SPEC.md` §18.1 — Step 1 of `install-codex-config` is now "MCP cleanup-only" with a pointer back to v5.0.10 motivation.

### Tests

- `bin/core/test-codex-adapter` — replaced `wrote per-tool approval blocks` assertion with `first install skips MCP cleanup on empty config (nothing to remove)`. Replaced eight `config.toml auto-approves <tool>` checks with eight `plugin .mcp.json auto-approves <tool>` checks. Added a hard fail-on-presence check for `[mcp_servers.apd*]` in user config. Repair test now expects "[removed] legacy APD MCP block" instead of "[updated] APD per-tool approvals". TOML parse check now skips when config.toml doesn't exist (no-op installs leave it absent). Total 210 → 211 PASS / 0 FAIL.

### Live unblock

If you ran `apd cdx init` on v5.0.9 and Codex now refuses to start with `invalid transport in mcp_servers.apd`, empty the project config (or run v5.0.10's `apd cdx init` once it ships):

```bash
> <project>/.codex/config.toml          # one-shot unblock
# OR after v5.0.10 marketplace-upgrade:
bash <project>/.codex/bin/apd cdx init   # cleanup happens automatically
```

## v5.0.9 — 2026-04-26

Second patch in the v5.1 chain. Plugin self-registers its MCP server via `plugins/apd/.mcp.json`; closes the v5.0.6 exec-mode bootstrap gap.

### What was broken

`install-codex-config` wrote `[mcp_servers.apd]` into every user's `<project>/.codex/config.toml` with the absolute path to the dev checkout's `mcp/apd_mcp_server.py`. That worked locally but was the root cause of every "MCP path is stale" repair, every WARN about plugin MCP overwriting earlier definitions, and the entire reason `codex exec` had no automatic APD bootstrap (the user-config block had to be written manually first via `apd cdx init`, which doesn't fire in exec mode).

### Fix

- **New file: `plugins/apd/.mcp.json`** registers the APD MCP server with `command: "uv"`, `args: ["run", "--with", "mcp", "python", "mcp/apd_mcp_server.py"]`, `cwd: "../.."`. Codex 0.124+ auto-loads plugin-shipped `.mcp.json` (`core-plugins/loader.rs::normalize_plugin_mcp_server_value`), normalises `cwd` against the plugin root (`plugins/apd/`), and the resulting `cwd = repo-root` is then applied to the stdio launcher's `Command::current_dir` (`rmcp-client/stdio_server_launcher.rs:231`). The Python server already self-locates via `Path(__file__).resolve().parent.parent`, so it finds the rest of the repo from there.
- **`bin/adapter/cdx/install-codex-config` no longer writes `[mcp_servers.apd]`.** That block is now provided by the plugin. The installer keeps the per-tool `[mcp_servers.apd.tools.<name>]` approval blocks (plugin `.mcp.json` doesn't carry per-tool approvals). Crucially, the existing replace logic still treats `[mcp_servers.apd]` as APD-owned, so any legacy block from APD < v5.0.9 is **removed on next run** — without that cleanup, Codex would print "plugin MCP overwrote earlier server definition" on every session.
- **`bin/adapter/cdx/codex-doctor` updated.** Old check ("config.toml has `[mcp_servers.apd]`") now reports a WARN if it finds the legacy block, and a new check confirms `plugins/apd/.mcp.json` registers the apd server. A second new check verifies all 8 per-tool approval blocks are present.

### Why `cwd: "../.."`?

The plugin's MCP server (`mcp/apd_mcp_server.py`) lives at the repo root — outside the plugin directory itself — because it depends on `bin/core/*`, `bin/adapter/cdx/*`, and `VERSION` which all live at the repo root. The `cwd: "../.."` value places the spawned process at `plugins/apd/../..` = repo root, which is what the Python server expects via its `__file__`-based path resolution. A future major release will move all of this into a self-contained `plugins/apd/` and drop the `../..`.

### Doc updates

- `docs/SPEC.md` §3 (MCP server) — explains the plugin .mcp.json registration path, the `cwd: "../.."` rationale, and the residual install-codex-config role.
- `docs/SPEC.md` §12 (configuration surfaces) — `<project>/.codex/config.toml` row reworded: "8 per-tool approval blocks; `[mcp_servers.apd]` ships in plugins/apd/.mcp.json".
- `docs/SPEC.md` §18.1 (install-codex-config steps) — Step 1 reworded as "per-tool approvals + legacy cleanup".

### Tests

- `bin/core/test-codex-adapter` — replaced "config.toml has `[mcp_servers.apd]`" check with a paired "no legacy block" + "plugin .mcp.json registers apd". Repair test now asserts the legacy block is removed instead of rewritten. Doctor label scan updated. Total: 209 → 210 PASS / 0 FAIL.

### Live verification still needed

This patch ships untested-in-TUI per the marketplace-only rule. Next step is `codex plugin marketplace upgrade codex-apd` on `~/Projects/Test`, then a fresh TUI session to confirm `apd_ping` works **without** `install-codex-config` having pre-written the server block.

## v5.0.8 — 2026-04-26

First patch in the v5.1 chain. Surfaces a real install bug discovered during the v5.0.7 live marketplace test on `~/Projects/Test`.

### What was broken

`apd cdx skills install` defaulted to `direct-drop` mode (symlinks into `~/.codex/skills/apd-*`). That default was correct for Codex 0.121.0 because the marketplace install path was upstream-blocked (openai/codex#18258). On Codex 0.124+ the marketplace path works, the plugin cache populates correctly, and skills surface in the `/` slash menu — but the legacy `~/.codex/skills/apd-*` symlinks coexist with the plugin cache and produce **duplicates in the slash menu** (4 historical Codex skills shown twice; the 3 newly-ported v5.0.7 skills shown once because they had no legacy symlinks).

### Fix

- **`bin/adapter/cdx/skills-install` default flipped to marketplace.** `apd cdx skills install` (no flag) now registers the local marketplace and enables `[plugins."apd@codex-apd"]` instead of writing user-level symlinks. Reflected in subcommand dispatch: `MODE` now defaults to `marketplace`.
- **`--legacy-symlink` flag retained** (alias `--direct`, `--symlink-mode`). Existing automation that explicitly opts into direct-drop continues to work, but the script now prints a deprecation banner on every run explaining why the mode is bad on 0.124+ and pointing the user at the new default. The flag will be removed in a future major.
- **`--marketplace` install no longer prints the `EXPERIMENTAL` warning.** That warning was specific to 0.121's broken path-resolution; on 0.124+ the install is the supported flow. Replaced with a one-liner pointing the user at `codex plugin marketplace upgrade codex-apd` for the cache-refresh step.
- **`status` output reordered.** Marketplace block now leads (labeled "default since v5.0.8"); direct-drop block follows under a "deprecated" header.

### Doc updates

- `docs/SPEC.md` §1 (install matrix) and §19 (skill install spec) — reworded to match the new defaults.
- `bin/adapter/cdx/skills-install` header comment rewritten to lead with marketplace and label direct-drop as deprecated.
- `bin/adapter/cdx/skills-install` help text updated to surface `--legacy-symlink` instead of bare `--copy` / `--force` flags.

### Tests

- `bin/core/test-codex-adapter` — three updates and two new checks. Old "default install creates 4 symlinks" reframed as "`--legacy-symlink` install creates 4 symlinks". New checks: `--legacy-symlink prints deprecation warning`, `status shows legacy Direct-drop section labelled deprecated`. Total 207 → 209 PASS / 0 FAIL.

### Live cleanup for existing installs

If you ran `apd cdx skills install` before v5.0.8 and now see duplicate APD skills in the slash menu, remove the legacy symlinks once:

```bash
rm ~/.codex/skills/apd-brainstorm ~/.codex/skills/apd-debug ~/.codex/skills/apd-finish ~/.codex/skills/apd-tdd
```

Then restart the TUI. The marketplace cache will continue to provide the skills.

## v5.0.7 — 2026-04-26

Skill quality release — every APD skill on both runtimes now conforms to a single canonical template, with explicit triggers, exit criteria, and anti-patterns. Closes the long-standing structural drift across the eight CC skills and brings the Codex side from 4 → 7 skills.

### Skill template canon

- **New file** — `templates/skill-template.md` codifies frontmatter (CC: `name`, `description`, `effort`, `allowed-tools`, optional `disable-model-invocation`; Codex: just `name` and `description`), a four-section mandatory body (When to use / When to skip · Steps · Exit criteria · Anti-patterns) plus two optional sections (Iron Law where the skill has a real invariant, Hand-off where transitions exist), and an effort taxonomy. Anti-patterns explicitly accepts two formats: "Don't → Do" pairs (procedural skills) and "Common rationalizations" tables (anti-self-deception, used by tdd / debug / brainstorm / finish).
- **Cross-runtime parity table** — eight CC skills, seven on Codex; `apd-setup` is intentionally CC-only because `apd cdx init` CLI replaces it.

### CC skills brought to compliance (8 of 8)

- **Frontmatter** — added missing `allowed-tools` to `apd-setup`, `apd-brainstorm`, `apd-finish`, `apd-github`, `apd-miro`. The remaining three already had it.
- **Body** — added explicit `When to use / When to skip`, `Exit criteria`, and `Hand-off` sections to all eight (most had implicit equivalents in `Integration` / checklist tail).
- **Specific fixes:**
  - `apd-setup` — Step 1's "MANDATORY: run init scripts" was a top-level paragraph; refactored into a numbered first step under `## Steps`. Renumbered the rest (1→2 detect, 2→3 gather, 3→4 auto-detect agents, 4→5 generate files with subsections renumbered 5.1–5.8, 5→6 verify). Added Anti-patterns and Hand-off (→ `apd-audit`) — previously had neither.
  - `apd-audit` — removed forced "Iron Law" line ("NO TASK WITHOUT A HEALTHY PIPELINE FIRST" wasn't really an invariant, just a recommendation).
  - `apd-github` and `apd-miro` — added Anti-patterns sections (had none before).
  - All four "Common Rationalizations" tables (audit, brainstorm, debug, tdd) renamed to lower-case "Common rationalizations" to match template wording.

### Codex skills brought to compliance + parity (4 → 7)

- **New ports** — `plugins/apd/skills/apd-audit/`, `plugins/apd/skills/apd-github/`, `plugins/apd/skills/apd-miro/`. Each ships a `SKILL.md` adapted for Codex (references `AGENTS.md` instead of `CLAUDE.md`, `.apd/agents/` instead of `.claude/agents/`, `apd_pipeline_state()` / `apd_doctor()` / `apd_verify_step()` MCP tools instead of bash commands, `${APD_PLUGIN_ROOT}` instead of `${CLAUDE_PLUGIN_ROOT}`) plus an `agents/openai.yaml` with `display_name`, `short_description`, and `default_prompt` (Codex per-skill UX metadata, distinct schema from the plugin manifest's `interface.defaultPrompt`).
- **Existing 4 Codex skills** (`apd-brainstorm`, `apd-debug`, `apd-finish`, `apd-tdd`) — added explicit `When to use / When to skip`, `Exit criteria`, and `Hand-off` sections to match the template. Bodies otherwise unchanged.

### Validation

- `bin/core/test-codex-adapter` — 207 PASS / 0 FAIL.
- All 7 Codex `agents/openai.yaml` files parse as valid YAML.
- All 15 `SKILL.md` files (8 CC + 7 Codex) have valid YAML frontmatter.

### Known carry-over (not in this release)

- **`codex exec` has no APD bootstrap path** — flagged in v5.0.6, still open. Candidate for v5.1, likely via `.mcp.json` self-registration.

## v5.0.6 — 2026-04-26

Live re-validation against Codex 0.125.0 + manifest fix for hard limit introduced in 0.124+.

- **Codex 0.125.0 sanity test passed.** TUI session opened from `~/Projects/Test`, first user prompt fired `SessionStart` hook on schedule (`gap-analysis: ran` after stale-cache detection). `codex_hooks` is now listed in the stable feature set on 0.125. Tracks original v5.0.4 evidence (0.124) plus this re-confirmation; openai/codex#15269 quirk (fires on first prompt, not banner) still applies.
- **`plugins/apd/.codex-plugin/plugin.json` — `defaultPrompt` schema fix.** Codex 0.124+ enforces a hard cap of 3 entries × 128 chars each on `interface.defaultPrompt`; longer entries are silently dropped (`codex-tui.log` shows `WARN ... ignoring interface.defaultPrompt[0]: prompt must be at most 128 characters`). The previous single 240+ char entry was being ignored entirely. Replaced with three short user-facing starter prompts: "Bootstrap APD: run apd_doctor and gap analysis." / "Brainstorm a new APD spec card." / "Audit APD setup with apd_doctor."
- **Doc consequence — exec-mode bootstrap is no longer claimed via `defaultPrompt`.** SPEC §4.2, §11.2, §14, §19.3 reworded. The earlier hypothesis that the orchestrator picked up a long `defaultPrompt` as a system-style instruction is no longer valid in 0.124+; `defaultPrompt` is now strictly user-facing UX. `codex exec` lacks an automatic APD bootstrap path until a real upstream entry point ships — flagged as a known limitation, candidate for v5.1 (likely via `.mcp.json` self-registration).

## v5.0.5 — 2026-04-26

Docs-only patch closing two issues surfaced by `framework-audit`:

- **`docs/SPEC.md` §4.1 heading** — corrected "13 entries across **7** event types" → "**8** event types". The table below already listed all eight (adding `PostCompact` between `PreCompact` and `PermissionDenied`); only the heading counter was stale. Restores alignment with the durable rule "update SPEC in same commit as any framework change".
- **`README.md` Skills table** — added the missing `/apd-miro` row. `skills/apd-miro/` ships, but the Skills table listed only 7 of 8 skills.

## v5.0.4 — 2026-04-26

Documentation-only patch capturing live Codex 0.124.0 validation findings from a full TUI session test against `~/Projects/Test`.

### What we learned live

- **Plugin install via GitHub marketplace works on 0.124.** `codex plugin marketplace add zstevovich/claude-apd` clones the repo into `~/.codex/.tmp/marketplaces/codex-apd`, then enabling the plugin (`[plugins."apd@codex-apd"] enabled = true`) makes skills appear in the slash menu immediately.
- **MCP auto-registration works end-to-end.** After plugin enable, a fresh TUI session on a clean project leads to `.codex/config.toml` being populated with `[mcp_servers.apd]` + 8 per-tool approval blocks, and `.codex/hooks.json` with both `PreToolUse Bash → guard-bash-scope` and `SessionStart → cdx session-start`. Working hypothesis (not yet proven): the orchestrator invokes `apd cdx init` on its own because `defaultPrompt` tells it to call `apd_doctor`, which flags the gap. Unknown whether Codex itself also has a post-install hook path.
- **`apd_ping` via MCP returns a valid response on every session.** Confirmed output: `{"ok": true, "version": "5.0.2", "plugin_root": "/Users/.../apd-template", "project_dir": "/Users/.../Test", "runtime": "codex"}`.
- **`SessionStart` hook fires in TUI — but on first user prompt, not at banner display.** Tracked upstream as openai/codex#15269 ("SessionStart not firing on session start instead it fires on first user prompt submission"). Practical effect: gap-analysis runs on the first turn of every fresh TUI session, not at open. If the user cancels before sending the first message, the hook does not fire for that session.
- **`codex_hooks` feature is now `stable` on 0.124** (was "under development" on 0.121).
- **Plugin marketplace upstream is no longer blocked on 0.124.** The 0.121 issue (openai/codex#18258) appears resolved — `plugins` feature flag is stable, GitHub and local marketplaces both register cleanly.

### Documentation updates

- `docs/SPEC.md` §4.2 — version bumped from 0.121 to 0.124; added SessionStart first-prompt quirk + reference to openai/codex#15269.
- `docs/SPEC.md` §11.2 — reworded for 0.124 semantics; added live-validation paragraph with exact session and hook timestamps from the 2026-04-26 test.
- `docs/SPEC.md` §14 — updated SessionStart known-limitation entry; added new entry for the `.mcp.json` plugin-manifest gap (ongoing backlog for v5.1).

### Outstanding research (not blocking)

- **`.mcp.json` in plugin manifest.** Other Codex plugins (cloudflare, build-ios-apps) declare MCP servers via `.mcp.json` at plugin root. APD's `plugins/apd/` does not, so our MCP server is registered via post-install `apd cdx init` rather than natively by the plugin. Worth investigating whether we can ship an `.mcp.json` that tolerates a Python stdio server without hardcoded paths — deferred to v5.1 unless blocking.
- **Which actor wrote `.codex/config.toml` during the first fresh session** — the leading guess is the orchestrator itself, triggered by `defaultPrompt → apd_doctor` spotting the gap. Not a correctness issue but worth confirming so we know whether we can rely on it or need a harder post-install hook.

## v5.0.3 — 2026-04-26

Fixes a project-resolution bug surfaced by the first real Codex 0.124 TUI SessionStart test on a pure-Codex project.

### Context

- **New reality on Codex 0.124.0:** `SessionStart` hook **does** fire in TUI mode (per live test on `~/Projects/Test`, 2026-04-26 21:13:39). The earlier assumption that Codex only fired `SessionStart` in TUI on 0.121 and `codex exec` was blocked is now obsolete — in 0.124, hooks declared in `.codex/hooks.json` are honoured.
- Plugin-based MCP + hooks distribution (registered via `codex plugin marketplace add`) also works end-to-end: `apd_ping` returns a valid response with `version: 5.0.2`, `runtime: codex`, and the right `project_dir` after marketplace install + plugin enable.

### Bug

`bin/lib/resolve-project.sh` only recognised `.claude/` and `CLAUDE.md` as project markers. On a pure-Codex project (only `.codex/` and `AGENTS.md`), the upward walk climbed past the project and matched `~/.claude/` (the user-global CC config), resolving `PROJECT_DIR=$HOME` and tripping `APD_ACTIVE=false`. The session-start script then exited early, skipping the apd-init gap analysis.

Log evidence from the failing run:

```
21:13:39 START pwd=/Users/zoranstevovic/Projects/Test
21:13:39 resolve: PROJECT_DIR=/Users/zoranstevovic APD_ACTIVE=false
21:13:39 EXIT: APD_ACTIVE=false
```

### Fix

- `bin/lib/resolve-project.sh` now treats `.codex/` and `AGENTS.md` as first-class project markers alongside `.claude/` and `CLAUDE.md`, via a new `_apd_has_marker` helper used in all three resolution paths (git toplevel, pwd, upward walk).
- The upward-walk path now explicitly stops at `$HOME` and refuses to resolve `PROJECT_DIR=$HOME`. This prevents `~/.codex/` (global Codex config) and `~/.claude/` (global CC config) from being mistaken for a project root when a hook fires from a path with no markers above it.
- Verified on a clean `~/Projects/Test` (only `.codex/` present): `resolve: PROJECT_DIR=/Users/zoranstevovic/Projects/Test APD_ACTIVE=true gap-analysis: ran`.

### Tests

- `bash bin/core/test-codex-adapter` → **207/0 PASS** (no regressions).
- `verify-apd` on `examples/nodejs-react` → **60/20/2** (baseline held).

## v5.0.2 — 2026-04-26

Two fixes that together close the CRITICAL "SessionStart on Codex" gap, plus a convenience CLI for plugin updates.

### Codex SessionStart equivalent (A + B combined)

The CC `SessionStart` hook was fixed in CC 2.1.101 (re-confirmed on 2.1.119). Codex 0.121.0 fires `SessionStart` in TUI only, never in `codex exec`. Before this release, cdx had no runtime equivalent to CC's `bin/core/session-start` — no dynamic gap-analysis, no shortcut drift guard, no auto apd-init.

- **`bin/adapter/cdx/session-start`** (new) — drains stdin, restores `.codex/bin/apd` shortcut if deleted, runs `apd-init --quick` gap analysis with the same 1h throttle pattern as CC. Silent log at `<APD_PLUGIN_ROOT>/cdx-session-start.log`.
- **`bin/adapter/cdx/install-codex-config`** — new block 6 merges `SessionStart` into `.codex/hooks.json` idempotently, preserving any existing PreToolUse/PostToolUse entries.
- **`plugins/apd/.codex-plugin/plugin.json`** — `defaultPrompt` extended to instruct the orchestrator to call `apd_doctor` at session open. This is the exec-mode path (hook does not fire there). Caveat: activation of the new `defaultPrompt` depends on upstream `/plugin install` marketplace path, which is blocked in Codex 0.121.0 (openai/codex#18258). Fully active once upstream issue resolves.
- **`bin/adapter/cdx/codex-doctor`** — new check reports whether `.codex/hooks.json` wires SessionStart.
- **`bin/core/test-codex-adapter`** — +6 tests covering first-run write, hooks.json content, script executable bit, manifest mention of `apd_doctor`, and merge preservation in the repair scenario. Baseline moved 201 → 207.

### `apd update` convenience CLI

- **`bin/core/apd-update`** (new) — one command that pulls the framework with `git pull --ff-only` and re-runs project init (`install-codex-config` for `.codex/`, `apd-init --quick` for `.claude/`). Idempotent. Flags: `--check-only` (dry-run, exits before pull), `--skip-pull` (reinit only, no git fetch). Aborts cleanly on dirty working tree or non-FF divergence.
- **`bin/apd`** — dispatches `update` / `up` to the new script, help block updated.

### Documentation

- **`docs/SPEC.md`** — §1 (Distribution: `apd update` row), §2 (CLI surface: `update` subcommand), §4.2 (Codex hooks: now 2 hooks, SessionStart tabela), §11.2 (Codex session-start dual path — TUI hook + exec `defaultPrompt`), §12 (hooks.json content), §14 (SessionStart known-limitations updated).

## v5.0.1 — 2026-04-24

Two small post-merge fixes.

- **`rules/workflow.md`** — align opener of `## 0. Lean vs Full mode` with Codex `AGENTS.md` (*"Not every task needs every gate. Pick the mode at spec time:"*). Previously the CC wording (*"Every pipeline cycle runs in one of two modes"*) read neutrally and the orchestrator defaulted to Full even for Lean-eligible tasks; the Codex phrasing encourages picking the lighter mode when it fits.
- **`bin/core/pipeline-doctor`** — include `guard-compact` and `guard-send-message` in the Guard Coverage section. Both guards exist in `bin/core/` and are wired in `hooks/hooks.json`, but doctor listed only 8/10. Now reports 10/10.

Verified on `examples/nodejs-react`: `verify-apd` baseline unchanged at 60/20/2.

## v5.0.0 — 2026-04-24

**Multi-runtime era.** APD becomes first-class on both Claude Code and OpenAI Codex. The major bump reflects the conceptual shift, not breaking changes — existing CC users see only additive changes (new files under `mcp/`, `plugins/apd/`, `bin/adapter/cdx/`, `bin/compiled/`). Codex side ships an MCP server (8 tools), per-tool approval registration, hook adapter, install flow, 4 Codex-native skills, AGENTS.md template, and direct-drop plus marketplace distribution paths.

The release also bundles four runtime-polish fixes (F1-F4), a documentation reorganisation (Part B for Codex install + authoritative runtime SPEC), and the corrections from two real-world Codex Lean tests (commits `bc6a93a` and `7374bd7`) on the PHP test project.

### Codex adapter (consolidated since v4.7.x)

- **MCP server** (`mcp/apd_mcp_server.py`) — FastMCP wrapper exposing 8 tools: `apd_ping`, `apd_doctor`, `apd_pipeline_state`, `apd_list_agents`, `apd_advance_pipeline`, `apd_guard_write`, `apd_verify_step`, `apd_adversarial_pass`. Defense in depth on `apd_guard_write` (regex `[A-Za-z0-9_.-]+` whitelist + filesystem escape detection). Empty-pass guard on `apd_adversarial_pass` (notes ≥80 chars when total=0). Per-tool approval blocks written into project `.codex/config.toml` (Codex 0.121.0 has no server-wide default).
- **Codex plugin manifest** (`plugins/apd/.codex-plugin/plugin.json`) — APD interface, capabilities, `defaultPrompt` injecting "Follow the APD pipeline …" at session start.
- **Codex marketplace** (`.agents/plugins/marketplace.json`) — `INSTALLED_BY_DEFAULT` registration so APD is first-class in every Codex project (when upstream `/plugin install` works; current 0.121.0 has openai/codex#18258 blocking it — direct-drop is the supported path).
- **Codex skills** (`plugins/apd/skills/{apd-brainstorm, apd-tdd, apd-debug, apd-finish}/`) — markdown body + `agents/openai.yaml` per skill.
- **Codex install adapter** (`bin/adapter/cdx/install-codex-config`) — 8-step idempotent flow: MCP server registration → per-agent sandbox skip (intentional, Codex 0.121.0 doesn't enforce) → `.codex/bin/apd` shortcut → `.apd/config` seed → AGENTS.md write-only-if-missing → `.apd/rules/*` → pure-Codex `.apd/` scaffold (skipped on hybrid) → hooks.json merge.
- **Codex skills install** (`bin/adapter/cdx/skills-install`) — direct-drop (default, symlinks `~/.codex/skills/apd-*` → repo) and `--marketplace` modes (latter experimental, blocked upstream).
- **Codex hook adapter shim** (`bin/adapter/cdx/guard-bash-scope`) — parses Codex hook stdin JSON and forwards to core `guard-bash-scope`. Single PreToolUse Bash event wired (Codex 0.121.0 supports only this reliably in `codex exec` mode).
- **Codex doctor** (`bin/adapter/cdx/codex-doctor`) — 6-section audit (prerequisites, global config, project `.codex/`, .apd content, AGENTS.md, MCP server syntax + 8 tool functions present).
- **AGENTS.md template** (`templates/codex/AGENTS.md`) — Codex orchestrator master guide; mirrors CLAUDE.md role for the Codex runtime.
- **5 Codex agent templates** (`templates/codex/agents/`) — backend-builder, frontend-builder, testing, code-reviewer, adversarial-reviewer.
- **4 Codex rules** (`templates/codex/rules/{brainstorm, debug, finish, tdd}.md`) — phase-specific orchestrator guidance.

### F1 — Inline "Next:" runtime guidance

`bin/core/pipeline-advance` builder/reviewer/verifier cases now print a runtime-neutral "Next:" line at the end of each gate. Reviewer case has 3 branches (Lean opt-out / Full pending / fallback). Spec case retained its existing CC-flavored Next-steps block as separate concern. **Why:** orchestrator was reading lifecycle from AGENTS.md/workflow.md only — runtime reinforcement closes the loop.

### F2 — Reset lifecycle documentation

- `templates/codex/AGENTS.md` — added step 10 (`apd_advance_pipeline("reset")`) to the Order of operations. Previously orchestrator never knew to call reset, causing telemetry loss + stale spec-card.
- `rules/workflow.md` — corrected two false "auto-resets" claims (lines 43, 86); pipeline does NOT auto-reset, must be called manually. Documented the correct command and what it archives.

### F3 — guard-audit.log sanitisation

Heredoc commit messages were producing 51 garbage lines in real Test logs, surfacing as 51 WARNs per `apd report` call.

- **Writers** (`bin/lib/style.sh::log_block` + `bin/core/guard-git::log_block`): collapse newlines/CR in `cmd_summary` so each blocked event is exactly one log line.
- **Parsers** (`bin/core/pipeline-report` + `bin/core/pipeline-advance` reset case): silently skip orphan lines (legacy multi-line entries from pre-fix writers) instead of WARN-spamming. Pattern matches `^YYYY-MM-DD HH:MM:SS|`.

Net: zero WARN output post-fix; legacy garbage is invisible to users; future writes are one-line.

### F4 — Caller-provided "New rule" with "None" default

`pipeline-advance` reset case: caller passes optional learning string as 2nd arg (`apd_advance_pipeline("reset", "always run composer dump-autoload after model changes")`); session-log entry uses it directly. Empty/missing → "None" (no manual session-log edit needed). Newlines sanitised so each event stays one log line.

Removes user-facing placeholder `[fill in or "None"]` that previously required manual session-log edit. AGENTS.md step 10 + workflow.md document the optional 2nd arg.

### Documentation

- **`docs/SPEC.md`** — authoritative runtime map. 23 sections (Part I surface map + Part II internals). Documents every guard, MCP tool, hook event, constant (budget thresholds, timeouts, regex patterns), install step, manifest field. Auto-loaded into framework-internal CLAUDE.md context. **Convention:** code without a SPEC entry is undocumented; update SPEC in the same commit as any framework change.
- **`GETTING-STARTED.md` Part B polish** — Step 1 (marketplace) flagged as Codex 0.121.0 upstream-blocked (openai/codex#18258); Part B (direct-drop) noted as recommended Codex install today.

### Tests

- `bash bin/core/test-codex-adapter` → **201/0 PASS** maintained throughout the F1-F4 series; bash syntax checks (`bash -n`) clean on every modified script.
- Two real-world Codex Lean test cycles: comment-validator-minimum-lengths (1m 32s) and category-validator-no-leading-digit (1m 39s). Test 2 was the definitive Lean decision-logic validation (clean prompt, orchestrator independently picked Lean with original-wording rationale).
- `examples/nodejs-react` verify-apd baseline confirmed at **60/20/2** (the 20 FAILs are structural: install-time files not shipped in example + 8 guard tests needing real hook context).

### Known limitations (carried forward)

- Codex 0.121.0 marketplace install upstream-blocked (openai/codex#18258). Direct-drop is the supported install path.
- Codex `/` slash menu doesn't list APD skills (same upstream).
- `pipeline-advance` spec case retains CC-specific Next-steps block (works for CC, ignored by Codex orchestrator).
- `SessionStart` hook flagged not firing on some projects (CRITICAL backlog).
- F4 caller-provided arg path live-validated only via documentation read in Test 2; arg-path live test pending (default "None" path is exercised on every reset).
- `bump-version` script does NOT update `plugins/apd/.codex-plugin/plugin.json` automatically — fixed manually for this release; backlog item to extend the script.

---

## v4.7.21 — 2026-04-23

Codex usage tuning — four soft levers that shave ~25-35% tokens on a typical mixed workload without touching pipeline gating. Additive changes only; existing callers of `apd_verify_step()` / `apd_pipeline_state()` keep working unchanged.

### Added
- **`templates/codex/AGENTS.md` — Recon section** before "Order of operations". Gives the Codex orchestrator three explicit rules before writing the spec card: (1) structural tools first (`apd_list_agents()` + `apd_pipeline_state()`) instead of opening files, (2) Grep/rg over full-file Read, (3) `≤ 7 file reads` green zone with "decompose the task instead" as the escape hatch beyond that. Pure guidance — no gate. Addresses the biggest concrete token burner observed on real Codex cycles (orchestrator reading 14+ files during recon when 5-7 would suffice).
- **Lean vs Full pipeline documentation** — formalises the previously-undocumented `adversarial: skip — <reason>` opt-out in `bin/core/pipeline-advance`. Lean skips adversarial for small, contained work (<5 files, no migration/auth/public-API/security/cross-module refactor); Full (default) runs every gate. Mechanical cap preserved: opt-out is only honored when the spec has ≤ 2 `R*:` criteria, otherwise the line is ignored. Added to `rules/workflow.md` (new `## 0. Lean vs Full mode` section), `templates/codex/AGENTS.md` (new section + step 7/8 reorder so adversarial correctly precedes the verifier gate — matches actual `pipeline-advance` enforcement), and `templates/codex/rules/brainstorm.md` (mode selection in the "Converge on a design" summary template).
- **`apd_pipeline_state()` `budgets` field** — advisory green/yellow/red status for `spec_criteria` (green ≤4, yellow 5-7), `reviewed_files` (green ≤4 → Lean-eligible, yellow 5-6, red 7+ → split the task), and `verifier_duration_s` (informational, nullable until verifier.done exists). No gate blocks on status — pure visibility to inform the Lean vs Full choice. New helper `_budget_status(value, green_max, yellow_max)`.
- **`apd_verify_step(scope="full"|"fast")` parameter** — fast mode passes `APD_VERIFY_SCOPE=fast` to verify-all.sh so a customised verifier can run build + touched-files tests only during builder REFACTOR iteration. Invalid scope rejected; empty string falls back to `full`. `pipeline-advance verifier` always runs with the default (env var unset → `full`) so the gate is unaffected. Safe-by-default: an uncustomised verify-all.sh just ignores the env var and runs its full logic. Framework reference at `bin/core/verify-all` and generated header in `apd-init` both `export APD_VERIFY_SCOPE="${APD_VERIFY_SCOPE:-full}"`; `.NET` example in `bin/core/verify-all` gains a commented fast-mode branch as the template pattern.

### Fixed
- **Framework-fallback path in `apd_verify_step` dropped `APD_VERIFY_SCOPE`.** When neither `.codex/bin/verify-all.sh` nor `.claude/bin/verify-all.sh` existed, the tool fell through to `_run_core("verify-all", ...)` which built a fresh env dict independently — `scope="fast"` silently degraded to `full` on the fallback. `_run_script`/`_run_core` now accept an optional `env_extra` kwarg overlaid on `_codex_env()`; `apd_verify_step` forwards `{"APD_VERIFY_SCOPE": scope}` explicitly on the fallback call. Caught by code review before landing.

### Tests
- `test-codex-adapter` grows four checks under new section **20c. apd_verify_step scope**: default resolves to `full` with env propagation, `scope="fast"` propagates `APD_VERIFY_SCOPE=fast`, invalid scope rejected with descriptive error, framework-fallback path forwards `APD_VERIFY_SCOPE` through `_run_core` (spy-based). Section 20 (`apd_pipeline_state`) gains a budgets-shape check. Test harness helper extraction now pulls `_budget_status` alongside the existing helpers. Total: **201/0 passing** (up from 196).

---

## v4.7.20 — 2026-04-18

### Added
- **`rules/workflow.md`** — new orchestrator rule explicitly permitting evidence-based verification of review findings against primary external sources (API docs, protocol specs, library contracts). Clarifies the adjacent "NEVER re-read code" rule: `WebFetch`-ing official documentation to check a specific claim in a review finding is NOT the same as replicating review work. Captures real-world pattern from BambiProject where the orchestrator dismissed a `Postmark ContentId` format finding by consulting Postmark docs — reviewer had hallucinated the format requirement, docs confirmed our code was correct. Documents the `accept-with-evidence | dismiss-with-evidence` requirement so future orchestrators don't drift back to feeling-based dismissals.

---

## v4.7.19 — 2026-04-18

### Added
- **`rules/workflow.md`** — new "MaxTurn sizing" subsection under *Model and effort discipline*. Captures the counterintuitive but real finding from two consecutive BambiProject runs: raising `maxTurns` makes pipelines *faster*, not slower, because it eliminates re-dispatch overhead (new agent re-reading spec/plan/sources from scratch) and prevents the context discontinuity bugs that reviewers catch and force fix cycles for. Documents APD defaults (40 builders / 30 reviewers), per-project override path (edit `.claude/agents/<name>.md`, auto-migration preserves non-legacy values), and an anti-pattern warning against lowering maxTurns "to save tokens".

---

## v4.7.18 — 2026-04-18

Deep audit bundle 5 — docs and nits. Closes out the audit cycle.

### Fixed
- **L2. `rotate-session-log` inconsistent echo/printf.** Line 72 used `printf '%s\n'`, line 74 used plain `echo` — the latter drops a trailing newline when the final line of kept content has none. Normalized to `printf '%s\n'` in both branches.

### Added
- **`docs/plans/README.md` + `docs/specs/README.md`** — archival markers explaining that dated planning/design documents reflect the state at time of writing and are not updated as the framework evolves. Points readers to authoritative current sources (CHANGELOG, templates, rules) and flags the specific drifts the audit found (`.claude/.pipeline/` → `.apd/pipeline/` in v4.3.4; `maxTurns` bumped in v4.7.13). Addresses L3 + L4 without editing every historical line — the docs remain as-written for context.

### Not applicable
- **L1** (`adapter/cc/guard-scope` missing scope paths) was a false positive. The adapter receives scope paths via `"$@"` from the per-agent hook template definition (`bash .../guard-scope {{SCOPE_PATHS}}`), which expands to `src/ tests/`-style positional args at template instantiation. Audit assumed hooks don't forward args — but this adapter is only called from template-generated agent frontmatter, not from `hooks/hooks.json`, so the args path works as designed.

---

## v4.7.17 — 2026-04-18

Deep audit bundle 4 — medium cleanup. Seven fixes across guards, init, reset, and test harness.

### Fixed
- **M1. `verify-contracts` file listing broke on spaces.** `for file in $file_list` word-split filenames that contain spaces, silently skipping them. Replaced with NUL-delimited `find -print0 | while read -r -d ''` and inline filtering for `node_modules`/`bin`/`obj`/`.d.ts`.
- **M2. `apd-init` stale-path migration left `.bak` leaks.** Four consecutive `sed -i.bak` calls on the same file each overwrote the previous `.bak`, and any intermediate failure left the file partially patched. Collapsed into one `sed -i.bak -e … -e … -e … -e …` invocation plus a post-loop `rm -f agents/*.bak` safety net.
- **M3. `pipeline-post-commit` regex was fragile to whitespace.** Now tolerant of leading whitespace and multiple spaces between the env var prefix and `git commit`, so CC payload formatters that collapse spaces no longer silently skip the post-commit reset.
- **M4. `verify-apd` session-log cleanup missed `APD-VERIFY-OPT-OUT`.** Only matched `APD-VERIFY-TEST`, so every run leaked one opt-out entry into the permanent log. Now matches any `APD-VERIFY-` prefix (TEST, OPT-OUT, and any future variants).
- **M6. `guard-bash-scope` whitelist was substring match, not prefix.** An allowed path of `src/` matched `other-project/src/foo` because `"src/"` appears as a substring. Now prefix-match after normalizing leading `./` and `~/`. **Behavior change for existing agents:** any agent whose allowed paths only passed via substring coincidence (e.g. allowed `lib/` matching `src/lib/foo`, or allowed `backend/src/` matching `api/backend/src/...`) will now correctly block. If an existing agent starts failing Bash writes after upgrade, the fix is to add the actual directory to the agent's scope paths.
- **M7. `session-start` → `apd-init --quick` timeout risk.** On projects with many agents and legacy frontmatter, the sed loops inside could approach the 5s hook budget on every new session. Cached: re-runs at most once per hour (stored in `.apd/pipeline/.last-init-check`).
- **M8. Half-done reset left no breadcrumb.** A killed `pipeline-advance reset` released the lock on EXIT but left the pipeline dir in a partial state with no indication. Now marks `.reset-in-progress` at reset start, removes it only on clean completion, and emits a `WARN: previous pipeline reset did not complete cleanly` on the next `pipeline-advance` call so the user can inspect.

### Not applicable
- **M5** (spec step deletes `implementation-plan.md` without atomic replace) was already fixed in a prior cleanup — spec-step `rm -f` no longer lists `implementation-plan.md`. Audit caught a false positive from an older source snapshot.

---

## v4.7.16 — 2026-04-18

Deep audit bundle 3 — security hardening across guards and timestamp parsing.

### Fixed
- **`guard-scope` path traversal.** `${FILE_PATH#"$PROJECT_DIR"/}` does not normalize paths, so `src/../../escape/foo` could slip past a prefix match on `src/`. Added canonicalization via `realpath` with a `cd + pwd -P` fallback, plus a defensive `..`-substring check that blocks any unresolved traversal even if normalization failed.
- **Adversarial-ordering check silent skip.** When the `.agents` timestamp couldn't be parsed by either `date -j -f` (BSD) or `date -d` (GNU), `ADV_EPOCH` became 0 and the whole ordering check was bypassed. Now fail-closed: unparseable timestamp → block with `adversarial-timestamp-unparseable` reason.
- **`guard-audit.log` silent skip.** Same pattern in `pipeline-advance` session-log enrichment and `pipeline-report` guard-blocks count — unparseable log timestamps were silently dropped from the count. Now emit a `WARN: … timestamp unparseable …` line before continuing, so the gap is visible.
- **`guard-git` mass-staging regex missed `--all=` long-form.** Expanded trailing character class to include `=`, so `git add --all=anything` and `git add -A=anything` also trip the block.
- **`validate_agent_entry` bash fallback was a single grep.** When the Go binary was missing (unsupported platform, corrupted install), enforcement silently degraded to `grep -q "|evt|name|"` — trivially satisfied by writing one forged line. Now fail-closed by default; users on unsupported platforms can opt in with `APD_ALLOW_UNVALIDATED_AGENTS=1`, which also prints a WARN every run.

### Note
H6 (`eval` with unsanitized `$ts` in `pipeline-report`) was already eliminated in v4.7.14 when the per-agent duration block was refactored — no longer applicable.

---

## v4.7.15 — 2026-04-18

Deep audit bundle 2 — lock handling and atomicity fixes.

### Fixed
- **Stale-lock reclaim race in `pipeline-advance`.** When two processes concurrently detected a stale lock (>5min), both could run `rmdir` + `mkdir` and both thought they owned the lock. The fallback `mkdir` return code is now checked, and a loser bails out with a clear "reclaimed by another session" message.
- **`verify-apd` backup directory collision.** Backup of live `.done` files went to a fixed `/tmp/apd-verify-backup/`, so concurrent runs or a stale leftover could silently restore wrong state into a live pipeline. Backup now uses `mktemp -d` (per-run unique path) and the cleanup restore clears it explicitly.
- **`pipeline-advance reset` agent-log atomicity.** The sequence was: parse `.agents` for metrics → write metrics → write session log → archive `.agents`. A crash between metrics write and archive lost the agent log permanently. Archive now happens immediately after parse, before any other write — the least-reconstructible record is safe first.

### Why it matters
All three issues were invisible under normal operation but guaranteed data loss on specific failure paths: concurrent dispatch (already observed in MEMORY), interrupted verify-apd runs, and Claude-Code timeouts mid-reset. None were reproducible in day-to-day use, hence the need for an audit to find them.

---

## v4.7.14 — 2026-04-18

Deep audit bundle 1 — three quick-win fixes surfaced by the v4.7.13 framework audit.

### Fixed
- **`pipeline-report` per-agent duration was dead code.** The Agents box compared the event field against `"START"`/`"STOP"` (uppercase) while `track-agent` writes lowercase `start`/`stop`, so durations never materialized. The `eval`-based bash parsing also treated the timestamp as an epoch integer when it is actually a human-readable string. Rewrote to lowercase match + `date -j`/`date -d` epoch conversion + tmp-file start/stop pairing (no `eval`).
- **`apd report --history` on Linux silently rendered an empty runs list.** The reverse-display used `tail -r || tac`, but `tail -r` is BSD-only and `tac` is GNU-only — fine on macOS, fine on most Linux distros, but the chain could still fail silently on setups missing both. Replaced with portable `awk` reverse.
- **`gh-sync builder|reviewer|verifier` recursively re-ran the pipeline step.** It added a GitHub comment and then called `pipeline-advance "$STEP"`, but `pipeline-advance` already invokes `gh-sync` at the end of each step — any direct call to `gh-sync builder` double-advanced. Removed the self-referential pipeline-advance call; gh-sync is now strictly side-effects (issue comment).

### Migration
Zero-effort. The per-agent duration section will now populate in `apd report`; the history list renders correctly on all platforms; any existing automation that used `gh-sync builder` directly no longer double-advances the pipeline.

---

## v4.7.13 — 2026-04-18

Follow-up to v4.7.12 (maxTurn metric). The metric revealed that default `maxTurns` values baked into templates were the actual cause of silent agent exhaust — builders capped at 20, reviewers at 15, both too tight for realistic tasks.

### Changed
- **`templates/agent-template.md`** — builder `maxTurns: 20` → `40`
- **`templates/reviewer-template.md`** — `maxTurns: 15` → `30`
- **`templates/adversarial-reviewer-template.md`** — `maxTurns: 15` → `30`
- **`examples/nodejs-react/.claude/agents/*`** — bumped to match new defaults
- **`skills/apd-setup/SKILL.md`** + **`skills/apd-audit/SKILL.md`** — documented new values

### Auto-migration
`apd init` (or `/apd-setup` gap analysis) now detects legacy `maxTurns: 20` on builders and `maxTurns: 15` on reviewers, bumps them to the new defaults, and reports `bumped maxTurns 20 → 40`. User-set values (anything other than the exact legacy numbers) are left untouched.

### How to customize
If you want a different limit on any agent, edit `.claude/agents/<name>.md` directly — the auto-migration only rewrites the exact legacy values.

---

## v4.7.12 — 2026-04-18

Real-world signal surfaced from BambiProject run #24: agents that exhaust maxTurn never fire `SubagentStop`, so the pipeline looked healthy in `apd report` even when 2/4 agents silently hit the budget wall.

### Added
- **MaxTurn exhaust tracking** — `.agents` log is parsed at pipeline reset; counts of total dispatches and exhausted agents (`start` without matching `stop`) are appended as two new columns to `pipeline-metrics.log`.
- **`apd report`** — new `MaxTurn exhaust: N/M agents` line in the current-run Agents box (only when > 0) and in the last-completed Quality box.
- **`apd report --history`** — new `MaxTurn Exhaust` section with aggregate rate across runs (green <10%, yellow <25%, red above), plus `mx:N` marker on each run row.
- **`bin/lib/agents-parse.sh`** — `parse_agents_log FILE` helper for consistent counting across callers.

### Migration
Zero-effort. Existing `pipeline-metrics.log` rows without the new columns render as before (aggregate section hidden). New rows start accumulating from the first post-upgrade pipeline.

---

## v4.7.11 — 2026-04-17

Follow-up to v4.7.10 — auto-refresh existing reviewer agents + stop `apd verify` from polluting metrics.

### Fixed
- **`pipeline-metrics.log` pollution** — `apd verify` creates synthetic APD-VERIFY-TEST / APD-VERIFY-OPT-OUT pipelines to exercise pipeline-advance. Those were being logged as real runs, showing up in `apd report --history` as "…" partial entries. Now `pipeline-advance` skips metrics writes when task name matches `APD-VERIFY-*`.

### Changed
- **`apd-init` auto-refreshes reviewer agents** — detects missing `.reviewed-files` directive (added in v4.7.10) in `code-reviewer.md` / `adversarial-reviewer.md` and regenerates from the current plugin templates. Lets existing projects adopt the scope fix without re-running `/apd-setup`.
- **`apd-init` cleans existing pollution** — one-time pass that strips `APD-VERIFY-*` entries from `pipeline-metrics.log` if present.

### Migration
Run `bash .claude/bin/apd init --quick` on any existing project to:
1. Refresh reviewer templates with the `.reviewed-files` scope directive
2. Clean historical APD-VERIFY pollution from metrics log

---

## v4.7.10 — 2026-04-17

### Fixed
- **Reviewer scope drift** — second real-world incident on BambiProject: `adversarial-reviewer` was auditing files from a previous commit (ProcessFfaiWebhookCommand + WebhookSignatureMiddleware) instead of the current pipeline's changes — all 3 findings out-of-scope. Root cause: templates told the orchestrator "give the reviewer a list of changed files" without defining *how* to compute that list, letting orchestrator reasoning drift to `git diff HEAD~1 HEAD` after a fresh commit.

### Changed
- **`pipeline-advance reviewer`** now writes `.apd/pipeline/.reviewed-files` — the authoritative file scope for the current run. Computed as uncommitted tracked changes (`git diff --name-only HEAD`) plus untracked files (`git ls-files --others --exclude-standard`).
- **`templates/adversarial-reviewer-template.md`** — "What you receive" section rewritten: read ONLY files in `.reviewed-files`, dismiss findings outside that list, stop if empty/missing.
- **`templates/reviewer-template.md`** — new "Scope — files to review" section with the same directive.
- **`pipeline-advance reset` / post-commit cleanup / rollback** — all paths now also remove `.reviewed-files` for consistency.

### Migration notes
Existing projects keep using their generated `code-reviewer.md` / `adversarial-reviewer.md` until re-run of `/apd-setup` or `apd-init`. The `pipeline-advance` scope-write runs immediately for everyone — new runs produce `.reviewed-files`, agents that don't yet reference it will behave as before.

---

## v4.7.9 — 2026-04-16

### Fixed
- **verify-apd test harness** — "verifier passes with adversarial summary" test (lines 775–782) wrote `.adversarial-summary` without first injecting `|start|adversarial-reviewer|` into the agents log. `pipeline-advance` correctly hard-gates this (adversarial-summary-without-dispatch), so the test FAILed even on a healthy framework. The subsequent "adversarial ordering" test (lines 784–813) cascaded: rollback after the failed verifier removed `reviewer.done` instead of the never-created `verifier.done`, breaking setup.

Fix: inject fake `adversarial-reviewer` start/stop entries before writing `.adversarial-summary`, matching the pattern used at lines 796–797 for the ordering test. Reported by an external orchestrator analysis.

---

## v4.7.8 — 2026-04-16

Pipeline report now distinguishes critical guard saves from routine enforcement blocks.

### Changed
- **`apd report` — guard block breakdown** — the Quality section now lists each triggered guard reason with its count, marked `!` (critical save) or `·` (routine enforcement). Previously reports showed only a total count, which treated `destructive-git (2)` the same as `commit-no-prefix (1)`.

### Critical reasons (`!` yellow)
`destructive-git`, `force-push`, `--no-verify`, `secret-access`, `out-of-scope-write`, `out-of-scope-bash-write`, `lockfile-write`, `orchestrator-code-write`, `mass-staging` — these would have caused real damage if allowed through.

### Routine reasons (`·` dim)
`commit-no-prefix`, `push-no-prefix`, `adversarial-before-reviewer`, `pipeline-state-write`, `adversarial-summary-without-dispatch`, `pipeline-incomplete` — framework enforcing ordering/process, not damage prevention.

### Motivation
Real-world run (BambiProject "Verifikacija emaila #31") fired 3 guard blocks — two were `destructive-git` saves (builder tried `git stash drop`, orchestrator tried `git checkout -- . && git clean -fd` on 22 modified files), one was `orchestrator-code-write`. Previous report showed `Guard blocks: 3` with no indication that the framework had just prevented data loss.

---

## v4.7.7 — 2026-04-16

Builder effort bumped to `xhigh` for Opus 4.7 / future Sonnet 4.7 coding gains.

### Changed
- **Builder effort: `high` → `xhigh`** — new Opus 4.7 effort tier is Anthropic's recommended default for coding and agentic tasks. Applied to:
  - `templates/agent-template.md` — master builder frontmatter
  - `skills/apd-tdd/SKILL.md` — TDD skill runs at xhigh
  - `skills/apd-setup/SKILL.md` — setup generates new builders with xhigh
  - `rules/workflow.md` — model/effort discipline tables
  - `templates/CLAUDE.md.reference` — project template table
  - `README.md` — Five roles table

### Forward-compat note
Sonnet 4.6 does not support `xhigh` and will transparently degrade to `high` (Claude Code graceful fallback). Real effect kicks in when Sonnet 4.7 lands. No token cost change on Sonnet 4.6.

### Unchanged
- Orchestrator, Reviewer, Adversarial Reviewer — still `max` (all valid on their respective models).
- Builder model stays `sonnet` — we do not switch to Opus for implementation.

---

## v4.7.6 — 2026-04-15

### Added
- **Case study** — GLM-5 vs Claude Opus comparison on `apd.run` landing page. First completed pipeline run on a non-Anthropic model: 17m 13s, 52 guard blocks, 7/7 spec coverage, 99 files changed.

---

## v4.7.5 — 2026-04-14

### Fixed
- **session-start** — explicit `exit 0` at end prevents monitor from reporting false failure. `apd-init --quick` failure logged but does not propagate.
- **apd-init** — quick mode reports fix count before exiting

---

## v4.7.4 — 2026-04-14

### Fixed
- **monitors.json** — correct schema: `name` (required), `description`, `command`. Removed `timeout_ms` (not in plugin manifest schema, only in Monitor tool schema).

---

## v4.7.3 — 2026-04-14

### Fixed
- **monitors.json** — removed `name` and `persistent` keys not recognized by CC plugin system

---

## v4.7.2 — 2026-04-14

### Updated
- **Homepage** — plugin "Visit website" now links to `apd.run`

---

## v4.7.1 — 2026-04-14

### Added
- **PreCompact guard** — `guard-compact` blocks compaction while pipeline is in progress (CC 2.1.105+). Prevents context loss mid-pipeline. Allows compaction when pipeline is idle or complete.

### New enforcement
| What is blocked | Guard |
|----------------|-------|
| Compaction during active pipeline | `guard-compact` (PreCompact hook) |

---

## v4.7.0 — 2026-04-14

Plugin monitors — reliable session context loading.

### Added
- **Plugin monitors** — `monitors/monitors.json` with `apd-session-context` monitor that auto-arms on session start (CC 2.1.105+). Replaces unreliable SessionStart hook as primary context loader.
- SessionStart hook kept as fallback for CC < 2.1.105. Both are idempotent.

### Infrastructure
- Scanned CC 2.1.105–2.1.107 for APD-relevant changes

---

## v4.6.4 — 2026-04-14

### Added
- **Landing page** — `apd.run` homepage with hero, pipeline visualization, feature cards, stats, and install CTA
- **CNAME** — custom domain configuration for `apd.run`

---

## v4.6.3 — 2026-04-14

### Added
- **Interactive demo** — Report scene added to demo page with auto-padded box drawing
- **Pipeline Runs reports view** — Dashboard/Reports tab toggle with side-by-side terminal reports for Bambi and MojOff (last 10 runs each, all stats: trend, session, adversarial insights)

---

## v4.6.2 — 2026-04-14

### Fixed
- **History limit scopes all stats** — `--history N` now computes all statistics (avg, success rate, adversarial, session, trend) from the last N runs only, not the full log

---

## v4.6.1 — 2026-04-14

### Added
- **History limit** — `apd report --history 5` or `--history=5` shows last N runs
- **Desc sort** — history runs listed newest-first

---

## v4.6.0 — 2026-04-14

Pipeline report command — full recap dashboard for CLI.

### Added
- **`apd report`** — formatted pipeline recap with task info, step timing, spec coverage bar, adversarial findings, guard blocks, and agent durations. Called automatically by `apd-finish` before presenting push/PR options.
- **`apd report --history`** — all completed runs with success rate, trend analysis (last 3 vs prev 3), session stats (today/this week), adversarial insights (most hits, cleanest task).
- **Visual progress bars** — pipeline progress (`████████ 4/4`) and spec coverage (`██████████░░ 5/6`) with color-coded bars.
- **Iteration detection** — warns when builder→reviewer dominates total time, indicating possible rework cycles.
- **Changed files summary** — shows file count and top-level directories affected by the pipeline run.
- **Pipeline report screenshot** in README.

### Updated
- `apd-finish` SKILL.md — new Step 2 shows report before presenting options to user.

---

## v4.5.1 — 2026-04-13

### Added
- **`apd version`** — new command to display current version
- **Version in help** — `apd help` now shows version next to title

---

## v4.5.0 — 2026-04-13

CLI branding and stale hook cleanup.

### Added
- **CLI logo** — `apd_logo()` in `style.sh` renders pixel-art APD logo with terminal colors (violet A, blue P, green D, pipeline indicator). Displayed in `apd help` and `apd init`.
- **Stale SessionStart cleanup** — `apd-init` update mode detects and removes project-level SessionStart hooks from `settings.json` that override the plugin's `hooks.json` (common in pre-v4 projects).

---

## v4.4.0 — 2026-04-12

Runtime contract adapter layer — Phase 2 of ADR-001.

### Architecture
- **Adapter layer** — 9 guard scripts split into `bin/adapter/cc/` (CC-specific stdin JSON parsing) and `bin/core/` (platform-agnostic CLI args). Core guards are now testable without Claude Code or jq.
- **Explicit fail-open/fail-closed policy** — enforcement guards (git, scope, bash-scope, secrets, orchestrator, pipeline-state) fail-closed when jq is missing; advisory guards (lockfile, track-agent, pipeline-post-commit) fail-open with documented rationale.

### Updated
- `hooks.json` — all 8 hook entries point to `bin/adapter/cc/` shims
- Agent templates — all guard references updated to adapter paths
- `verify-apd` — functional tests use CLI args; adapter shim existence checks added; plugin detection validates both core and adapter layers
- `apd-init` — detects and auto-migrates stale `bin/core/guard-*` paths in existing agent files with visible STALE PATH warning

### Infrastructure
- `track-agent` debug logging moved from adapter to core via `--raw-payload` arg — adapter layer stays thin
- ADR-001 design spec and implementation plan added to `docs/`

---

## v4.3.4 — 2026-04-12

Pipeline relocation, quality enforcement, and SubagentStop workaround.

### Breaking change
- **Pipeline directory relocated** — `.claude/.pipeline/` → `.apd/pipeline/`. Claude Code treats `.claude/` as a protected path, causing permission prompts on every Write/Edit regardless of `permissions.allow` settings. Moving to `.apd/pipeline/` eliminates forced prompts.
- **Automatic migration** — `apd init` (update mode) detects old `.claude/.pipeline/`, moves contents to `.apd/pipeline/`, updates `.gitignore`, permission patterns in `settings.json`, and `workflow.md`.

### New enforcement
- **Adversarial dispatch verification** — verifier blocks if `.adversarial-summary` exists but no `adversarial-reviewer` start entry in `.agents` log. Prevents `ADVERSARIAL:0:0:0` bypass without actual dispatch.
- **Orchestrator code write instructions** — stronger workflow.md rules against orchestrator writing code directly or reading files after review to "verify". Reduced code-write guard blocks from 3/task to 0/task.

### Fixes
- **SubagentStop workaround** — CC SubagentStop hook has ~42% failure rate (GitHub #27755). Go binary now accepts agents with start but no stop if 30+ seconds elapsed. Eliminates false "No agent dispatched" blocks.
- **Rollback preserves implementation plan** — `pipeline-advance rollback` of builder step no longer deletes `implementation-plan.md`. Plan is frozen spec.
- **Workflow.md auto-update** — `apd init` update mode now replaces `workflow.md` when it contains stale `.claude/.pipeline` paths.
- **Timezone fix in Go binary** — elapsed time calculation uses local timezone for start timestamp parsing.
- **test-system agent_id format** — fake agent entries use valid CC agent_id format and realistic start/stop timing.

### Infrastructure
- **Agent dispatch debug logging** — `track-agent` logs full SubagentStart/Stop hook JSON to `agent-dispatch-debug.log` for dispatch analysis.
- **bump-version script** — local tool for consistent version updates across all files (plugin.json, marketplace.json, README, CLAUDE.md, memory).
- All guards, templates, rules, documentation, and tests updated for new `.apd/pipeline/` path.

---

## v4.2.0 — 2026-04-11

Enforcement hardening + quality gates.

### New enforcement
- **Adversarial ordering** — verifier blocks if adversarial-reviewer ran before reviewer step completed. Pipeline flow: builder → reviewer → fix → adversarial.
- **Adversarial opt-out limit** — skip only allowed for tasks with <=2 criteria. 3+ criteria = must dispatch adversarial-reviewer.
- **mkdir deny** — `permissions.deny` blocks orchestrator from creating `.pipeline/` directory manually. Must use `apd pipeline spec`.
- **SendMessage guard** — blocks SendMessage during active pipeline (SubagentStart/Stop hooks don't fire for continued agents).

### Fixes
- **Guard read false positive** — `cat spec-card.md 2>/dev/null` no longer blocked (redirect operators excluded from pipeline write check)
- **AGENTS_LOG missing in verifier** — adversarial ordering check was silently skipped because variable was undefined
- **sed criteria terminator** — `^\*\*[^A]` → `^\*\*[A-Z]` (correctly stops at `**Affected modules:`)
- **guard-bash-scope** — `*pipeline*` → `*.pipeline/*` (avoids matching APD tool names)
- **track-agent** — removed `log_block` from SubagentStart warning (not a real block, inflated counter)
- **Glob permissions** — added `**/.pipeline/` wildcard variants for absolute path matching
- **Implementation plan preserved** — `pipeline-advance spec` no longer deletes plan on re-run

### Infrastructure
- **Plugin update flow** — version bump required for `/plugin update` to pull changes (same version = cached)
- **Verify-apd** — adversarial ordering E2E test added (98 checks total)

---

## v4.1.1 — 2026-04-10

Fixes and hardening after real-world testing on Bambi and Test projects.

- **Complete audit trail** — all 8 guards now log to guard-audit.log via shared `log_block()`. Previously only guard-git logged blocks.
- **Forgery detection logged** — verify_done tamper attempts now written to guard-audit.log
- **Plugin cache guard** — fixed false positive blocking script execution (2>&1 matched as write)
- **verify-apd E2E tests** — fixed signed .done parsing, lock cleanup, adversarial agent ordering, trace markers, session-log fill-in cleanup
- **test-hooks** — checks plugin hooks.json instead of project settings.json (removed 3 false WARNs)
- **session-start** — shortcut creation moved before apd-init (prevents hook timeout), debug log includes date
- **apd-setup** — runs session-start as workaround for SessionStart hook not firing
- **guard-bash-scope** — removed over-broad "apd " whitelist bypass
- **.adversarial-summary** — multi-line safe parsing (head -1)
- **Dead feature removed** — pipeline-skip-log.md references cleaned up
- **Pipeline run #8** — documented (Test blog, 3 guard blocks, 8 adversarial findings)

---

## v4.1.0 — 2026-04-10

Tamper-proof pipeline enforcement with compiled Go binary.

### Highlights
- **Compiled Go validator** — `bin/compiled/validate-agent-*` creates HMAC-signed `.done` files. Orchestrator cannot forge pipeline steps — signature verified at every step transition and commit gate.
- **Adversarial reviewer hard gate** — verifier blocks if adversarial-reviewer agent exists but was not dispatched. Opt-out via `adversarial: skip` in spec-card.md.
- **SendMessage guard** — blocks SendMessage during active pipeline (SubagentStart/Stop hooks don't fire for continued agents).

### Enforcement
- Agent dispatch validation via compiled binary (timestamp, hex agent_id, start/stop pairs, duration)
- guard-bash-scope: blocks mkdir, touch, rm on .pipeline/ and all writes to plugin cache
- Criteria counter: counts R* only within Acceptance criteria section
- Git toplevel resolution: `resolve-project.sh` uses `git rev-parse --show-toplevel`
- Pipeline permissions: `apd-init` auto-configures settings.json allowlist
- Stale path detection: `apd-init` and `pipeline-doctor` detect legacy directories and old path references
- workflow.md: all paths updated to `bash .claude/bin/apd pipeline`

### Pipeline runs
- Run #6: First clean run — adversarial gate blocked verifier, forced dispatch
- Run #7: 7 bypass attempts, all blocked (direct edit, fake dispatch, SendMessage, max criteria)

---

## v4.0.0 — 2026-04-10

Scripts restructured — single entry point, clean architecture.

- **`scripts/apd`** — single entry point for all APD commands: `apd pipeline|doctor|verify|trace|init|gh|test`. One shortcut, one interface.
- **`scripts/core/`** — all 22 scripts moved here without `.sh` extensions. Executables have no extension, libraries (lib/) keep `.sh`.
- **Planned agents check** — implementation-plan.md `### Agents` section lists needed agents. pipeline-advance.sh builder warns if planned agents were not dispatched.
- **guard-bash-scope.sh in plugin hooks** — orchestrator's Bash writes to .pipeline/ now blocked (was only in agent templates before).
- **Auto GitHub sync** — gh-sync reuses existing issues instead of creating duplicates, circular call removed.
- **POSIX file lock** — replaced Linux-only flock with mkdir-based lock, auto-removes on exit, stale detection >5min.
- **Pipeline doctor shortcut** — session-start creates `.claude/scripts/apd` (replaces separate apd-pipeline/apd-doctor shortcuts).
- **track-agent.sh warnings** — red WARNING when builder dispatched without pipeline-advance.sh builder.

### Breaking changes
- All hook paths changed: `scripts/<name>.sh` → `scripts/core/<name>`
- Existing projects must run `/apd-setup` to update agent hook paths
- Old shortcuts (apd-pipeline, apd-doctor) auto-removed, replaced by single `apd`

### Enforcement hardening (v4.0.0)
- **Compiled Go validator** — `bin/compiled/validate-agent-*` creates HMAC-signed `.done` files. Orchestrator cannot forge pipeline steps — signatures verified at every step transition and commit gate.
- **Adversarial reviewer hard gate** — `pipeline-advance verifier` blocks if adversarial-reviewer agent exists but was not dispatched. Opt-out via `adversarial: skip` in spec-card.md.
- **Agent dispatch validation** — compiled binary checks timestamp format, hex agent_id, start/stop pairs, minimum duration.
- **SendMessage guard** — `guard-send-message` blocks SendMessage during active pipeline (SubagentStart/Stop hooks don't fire for SendMessage).
- **guard-bash-scope hardened** — blocks mkdir, touch, rm on .pipeline/ and all writes to plugin cache directory.
- **Criteria counter fix** — counts R* only within Acceptance criteria section (sed instead of grep).
- **Git toplevel resolution** — `resolve-project.sh` uses `git rev-parse --show-toplevel` as primary method for correct subdirectory/worktree support.
- **Pipeline permissions** — `apd-init` auto-configures settings.json allowlist for pipeline files and apd commands.
- **Stale path detection** — `apd-init` and `pipeline-doctor` detect and remove legacy `scripts.old/` directories and stale `pipeline-advance` references.
- **workflow.md** — all paths updated from `${CLAUDE_PLUGIN_ROOT}/bin/core/pipeline-advance` to `bash .claude/bin/apd pipeline`.

---

## v3.7.0 — 2026-04-10

Pipeline hardening — mechanical enforcement, anti-bypass, concurrent session protection.

- **Max 7 acceptance criteria** — `pipeline-advance.sh spec` hard-blocks specs with >7 R* criteria, forcing feature decomposition into smaller pipeline cycles.
- **Pre-flight checklist** — after spec step, displays next steps with exact Agent tool dispatch format and superpowers warning.
- **Spec freeze** — sha256 hash saved on spec step, verifier blocks if spec-card.md modified mid-pipeline. Must rollback to change scope.
- **Auto GitHub sync** — `pipeline-advance.sh` calls `gh-sync.sh` at every step (best-effort, non-blocking). Board moves automatically: Spec → In Progress → Review → Testing → Done.
- **Pipeline state guard** — `guard-pipeline-state.sh` blocks Write/Edit to .done, .agents, .spec-hash, .trace-summary. Only pipeline-advance.sh can create state files.
- **Bash write protection** — `guard-bash-scope.sh` always protects `.pipeline/` directory, even without ALLOWED_PATHS. Blocks echo/tee/sed/cp/mv to pipeline state via Bash.
- **File lock** — `flock` prevents concurrent pipeline operations. Second session gets BLOCKED.
- **Reviewer block message** — specific fix instructions with exact Agent tool syntax, "do not rollback" warning.
- **No-rollback rule** — workflow.md: if pipeline step fails, fix and retry instead of rolling back code.
- **Explicit agent dispatch format** — workflow.md documents `Agent({ subagent_type: "code-reviewer" })`, warns against superpowers agents.

---

## v3.6.0 — 2026-04-10

Implementation plan step and enforcement gaps — orchestrator must write plan before dispatching builder, spec-card.md is now mandatory.

- **Implementation plan step** — orchestrator writes `.pipeline/implementation-plan.md` (files to change + 1-2 sentences per file) before dispatching builder. Builder reads the plan instead of searching the codebase. `pipeline-advance.sh builder` hard-blocks without it.
- **Hard block: spec-card.md** — `pipeline-advance.sh spec` now requires spec-card.md to exist with R* acceptance criteria. Previously allowed advance without it, making spec traceability a no-op.
- **Soft warn: adversarial-summary** — `pipeline-advance.sh verifier` warns if adversarial-reviewer agent is configured but `.adversarial-summary` was not written. Does not block.
- **workflow.md** — step 4 clarified with plan file requirement, new section 3c (implementation plan format).
- **Builder template** — reads implementation-plan.md and spec-card.md in workflow step 1.
- **Cleanup** — `implementation-plan.md` added to spec, reset, and builder rollback cleanup.

---

## v3.5.2 — 2026-04-09

- **`apd-init.sh`** — gap analysis now creates `adversarial-reviewer.md` from template when missing. Previously `/apd-setup` reported 100 PASS but didn't detect the missing agent.

---

## v3.5.1 — 2026-04-09

Audit fixes and polish.

- **Critical fix: spec-card.md lifecycle** — was deleted during spec step (before builder/verifier could read it), now correctly deleted on pipeline reset
- **Dynamic version** — `apd-init.sh` reads version from `plugin.json` instead of hardcoding; no more version drift
- **Version sync** — marketplace.json, CLAUDE.md, README.md, apd-setup SKILL.md all aligned
- **README.md** — "Four roles" → "Five roles", added Adversarial Reviewer section and Mermaid diagram update
- **CLAUDE.md** — fixed stale `/apd-init` → `/apd-setup`, updated skills directory listing
- **Templates** — CLAUDE.md.reference and workflow.md section 8 model tables include Adversarial Reviewer
- **Metrics display fix** — "Last 5" and duration loop properly consume adversarial columns, preventing partial task misidentification
- **Adversarial parsing** — triple cat|cut replaced with single IFS read

---

## v3.5.0 — 2026-04-09

Adversarial reviewer — context-free code review that catches what contextual reviewers miss.

- **Adversarial reviewer template** — new agent (sonnet/max, `memory: none`, read-only). Reviews code changes with zero task context. Finds bugs, security issues, and edge cases that the regular reviewer misses because it "knows what the builder was trying to do."
- **Pipeline step 6b** — optional step between reviewer and verifier. Orchestrator dispatches adversarial reviewer, evaluates findings (accept/dismiss), fixes legitimate issues before verifier.
- **Hit rate metrics** — orchestrator writes `ADVERSARIAL:total:accepted:dismissed` to `.pipeline/.adversarial-summary`. Session-log shows per-task hit rate, pipeline metrics show cumulative hit rate across all tasks. Tracks whether the feature adds value or generates noise.
- **Five roles** — workflow.md updated from four to five roles (Orchestrator, Builder, Reviewer, Adversarial Reviewer, Verifier) with model/effort table.
- **Metrics fix** — `grep '|completed$'` pattern updated to handle trailing adversarial columns in pipeline-metrics.log.

---

## v3.4.0 — 2026-04-09

Spec traceability — mechanical verification that every acceptance criterion has test coverage.

- **`verify-trace.sh`** — new verification script. Parses `.pipeline/spec-card.md` for R1-RN acceptance criteria, scans test files for `@trace R*` markers, blocks commit if any criterion lacks test coverage. Stack-aware test file detection (nodejs, python, php, dotnet, go, java). Colored output via style.sh.
- **Spec persistence** — orchestrator writes spec card to `.pipeline/spec-card.md` before advancing pipeline. Ephemeral lifecycle: born on spec step, verified before commit, deleted on reset.
- **Pipeline integration** — `pipeline-advance.sh` validates spec-card.md has R* criteria on spec step, runs verify-trace.sh as verifier gate, caches trace summary for session-log, cleans up on rollback.
- **Session-log enhancement** — auto-generated session-log entries now include `**Spec coverage:**` field (e.g., "3/3 (all covered)").
- **Builder template** — updated workflow: read spec-card.md, add `@trace R*` markers in test files.
- **Reviewer template** — new check: verify `@trace R*` markers cover all acceptance criteria, flag missing as Critical.
- **workflow.md** — R* format for acceptance criteria, spec persistence rule, new section 3b (spec traceability).

---

## v3.3.2 — 2026-04-08

Framework polish and naming consistency.

- **`/apd-audit` skill** — qualitative framework audit (version consistency, stale refs, hook correctness, script quality, docs accuracy)
- **Skill prefix convention** — all skills renamed to `apd-*` prefix (`github-projects` → `apd-github`, `miro-dashboard` → `apd-miro`) to avoid name conflicts with project skills
- **`apd-init.sh --version`** — reads version dynamically from plugin.json
- **verify-apd.sh** — skip guard-scope check for read-only agents (0 WARN for properly configured projects)
- **MCP recommendations** — `/apd-setup` recommends MCP servers based on stack (context7, postgres, github, docker, miro)
- **Correct MCP packages** — `@modelcontextprotocol/server-postgres` and `server-github` (not `@anthropic-ai`)

---

## v3.2.7 — 2026-04-08

Visual identity, skill quality, pipeline fixes. See [GitHub Release](https://github.com/zstevovich/claude-apd/releases/tag/v3.2.7).

---

## v3.2.6 — 2026-04-08

Skill quality overhaul and `/apd-init` → `/apd-setup` rename.

- **Skill refactor** — all 7 skills rewritten with CSO descriptions ("Use when..." trigger-only), Iron Laws, rationalization tables, Red Flags, DOT process diagrams, integration sections
- **`/apd-init` → `/apd-setup`** — renamed to reflect both init and maintenance role
- **`/apd-upgrade` removed** — replaced by `apd-init.sh --quick` auto-update on session start
- **Mandatory skill enforcement** — workflow.md step 9 added, brainstorm/tdd/debug/finish are mandatory at specified pipeline points
- **`allowed-tools`** — apd-tdd and apd-debug get tool access without permission prompts
- **`disable-model-invocation`** — apd-setup is user-only (not auto-triggered)

---

## v3.2.5 — 2026-04-08

Mandatory skill enforcement in workflow and version bump.

---

## v3.2.4 — 2026-04-08

Per-step pipeline colors, agent visual identity, hook and template fixes.

- Per-step colors: spec=violet, builder=blue, reviewer=orange, verifier=green, commit=violet
- Agent `color` field in templates (purple/blue/orange/green)
- ☭ agent dispatch icon in track-agent.sh
- `if` field moved to hook object level in agent/reviewer templates (was at matcher-group)
- ANSI color tuning: lighter violet (177), sharper orange (208)
- TERM-based color detection for Claude Code Bash context
- Auto-allow memory file writes in generated settings.json

---

## v3.2.3 — 2026-04-08

Post-commit hook fix and color detection.

- Fixed `if` patterns in hooks.json — env var prefixes not matched by Claude Code pattern matching. Simplified to `Bash(git *)` and `Bash(git commit*)`
- Added TERM color detection (covers Claude Code Bash tool where no TTY exists)

---

## v3.2.2 — 2026-04-08

Fix verify-apd.sh spec assertion to match new branded header format.

---

## v3.2.1 — 2026-04-08

Unified CLI visual identity. Shared style library replaces inline color definitions and box drawing across all scripts.

### New

- **`scripts/lib/style.sh`** — shared style library with TTY-aware colors, branded markers (■ □ ◆ ✓ ✗ !), and output helpers (apd_header, apd_blocked, pass, fail, warn, ok, fix, skip, err, section, show_pipeline, format_duration)
- **Branded headers** — all script output uses `APD ■ Title` prefix instead of box drawing
- **Minimal sections** — `── Name ──` dim separators replace double-line boxes (╔══╗)
- **Consistent markers** — ✓/✗/! replace [PASS]/[FAIL]/[WARN] in test-hooks.sh

### Changed

- `pipeline-advance.sh` — all box headers/footers removed, uses style.sh (-82 lines)
- `pipeline-gate.sh` — box blocked output → `APD □ BLOCKED:` format
- `session-start.sh` — 5 boxes (version warnings, self-heal, header) → branded headers
- `apd-init.sh` — inline colors/helpers → source style.sh
- `verify-apd.sh` — box header/summary → sections with dim separators
- `verify-contracts.sh` — RED/GREEN/YELLOW → style.sh aliases, boxes → sections
- `test-hooks.sh` — [PASS]/[FAIL]/[WARN] → ✓/✗/!, === → branded header

---

## v3.2.0 — 2026-04-08

Comprehensive audit and fix release. 21 issues fixed across scripts, skills, hooks, templates and documentation.

### Critical fixes

- **hooks.json `if` field placement** — moved from matcher group level to individual hook objects. Conditional hooks (guard-git, guard-lockfile, pipeline-post-commit) now filter correctly instead of firing on every tool call
- **Non-existent `apd-pipeline` command** — `rules/workflow.md` and `templates/CLAUDE.md.reference` referenced `bash .claude/scripts/apd-pipeline` which never existed. Fixed to `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh`
- **verify-apd.sh test assertions** — 4 E2E pipeline tests checked for strings that `pipeline-advance.sh` never emits ("Pipeline started", "Builder completed", etc). Fixed to match actual output ("APD Pipeline", "Builder Complete", etc)
- **Portable sed** — replaced macOS-only `sed -i ''` with `sed -i.bak` + cleanup (5 occurrences in `apd-init.sh`). Replaced `\n` in sed replacement strings with `awk` for cross-platform JSON manipulation
- **Version consistency** — hardcoded versions `3.0.0` and `3.1.2` updated to `3.2.0` across `apd-init.sh`, `apd-init/SKILL.md`, `apd-upgrade/SKILL.md`, `CLAUDE.md`, `README.md`, `MEMORY.md`
- **principles template** — ".claude/ directory must not go to git" was wrong. Fixed to accurate gitignore policy (only `.pipeline/` and `settings.local.json` are excluded)
- **apd-upgrade skill** — `rm -f .claude/rules/workflow.md` replaced with `cp` from plugin, since rules are not auto-loaded from plugins

### Important fixes

- **verify-apd.sh agent cleanup** — dummy agent files created during E2E test now use proper `printf` (not `echo` with `\n`) and are cleaned up via `restore_pipeline_state`
- **pipeline-advance.sh init guard** — changed from counting all repo commits to counting only `.claude/`-related commits. Existing repos with 3+ commits can now init APD without `APD_FORCE_INIT=1`
- **pipeline-advance.sh usage header** — removed non-existent `skip` command, added `init "Description"`
- **apd-brainstorm skill** — bare `pipeline-advance.sh` call fixed to full `bash ${CLAUDE_PLUGIN_ROOT}/scripts/` path
- **apd-finish skill** — relative `.claude/scripts/verify-all.sh` path fixed to use `git rev-parse --show-toplevel`
- **GETTING-STARTED.md** — duplicate "Step 3" heading fixed (now Steps 3, 4, 5)

---

## v3.1.0–v3.1.9 — 2026-04-08

Mechanical enforcement release. Agents must actually run before pipeline advances, orchestrator cannot write code, superpowers plugin blocked.

### Mechanical enforcement (v3.1.0)

- **Agent dispatch verification** — `pipeline-advance.sh builder/reviewer` checks `.agents` log for actual agent dispatch. No more self-reporting
- **guard-orchestrator.sh** — blocks orchestrator from writing code files directly. Forces agent dispatch
- **Standardized reviewer agent** — `reviewer-template.md` with opus/max enforcement
- **Model and effort discipline** — workflow.md enforces sonnet/high for builders, opus/max for reviewers
- **userConfig support** — `plugin.json` userConfig fields for `project_name`, `stack`, `author_name`

### Superpowers blocking (v3.1.1–v3.1.2)

- **APD dormant mode** — hooks exit early in non-initialized projects (no `.apd-config`)
- **Superpowers disabled** — `/apd-setup` writes `"superpowers@claude-plugins-official": false` to project `settings.json`
- **apd-init.sh** — mechanical init/update script with gap analysis for existing projects

### Pipeline automation (v3.1.3–v3.1.6)

- **Shell injection for /apd-setup** — skill auto-executes bash script via `!command` pattern
- **Stronger wording** — MANDATORY run script first, no agent self-analysis
- **session-start.sh runs apd-init.sh --quick** — automatic gap check on every session start
- **Pipeline shortcut** — `session-start.sh` creates `.claude/scripts/apd-pipeline` symlink

### Tracking and cleanup (v3.1.7–v3.1.9)

- **Agent history log** — `track-agent.sh` records agent dispatches to `.agents` and archives to `agent-history.log`
- **Session log agents field** — session-log entries include dispatched agent names
- **workflow.md refresh** — `apd-init.sh` update mode detects and replaces stale `CLAUDE_PLUGIN_ROOT` references in project `workflow.md`

### Visual identity (v3.1.0)

- Stellar violet squares for pipeline indicators (■ □ ◆)
- Enterprise-grade terminal output with consistent color scheme
- 4 APD skills replacing superpowers equivalents: `apd-brainstorm`, `apd-tdd`, `apd-debug`, `apd-finish`

---

## v3.0.0 — 2026-04-08

**Major release: APD evolves from a copy-paste template into a full Claude Code plugin ecosystem.**

APD v1.0 started as a folder you copied into your project. v2.0 grew into a framework with 20 patterns across 4 layers. v3.0 completes the transformation: APD is now a proper Claude Code plugin — install it once, use it everywhere.

### The journey: template → framework → ecosystem

| Version | Era | How it worked |
|---------|-----|---------------|
| v1.0 | Template | Copy `.claude/` into project, replace placeholders manually |
| v2.0–2.8 | Framework | 17 scripts, 4 skills, 20 patterns, but still copy-paste |
| **v3.0** | **Ecosystem** | **Install once via marketplace, `/apd-setup` generates everything** |

### Breaking changes

- APD no longer works by copying `.claude/` into projects
- Install via marketplace: `/plugin marketplace add zstevovich/claude-apd` + `/plugin install claude-apd@zstevovich-plugins`
- Start new session, then run `/apd-setup`
- Scripts live in the plugin (`${CLAUDE_PLUGIN_ROOT}/scripts/`), not in the project
- Only `verify-all.sh` remains in the project (stack-specific build commands)
- Agent hooks use `${CLAUDE_PLUGIN_ROOT}` instead of hardcoded paths

### New architecture

```
Plugin (installed once):           Project (generated per-project):
  scripts/ (17 scripts)              .claude/agents/*.md
  hooks/hooks.json                   .claude/rules/workflow.md
  rules/workflow.md                  .claude/rules/principles.md
  skills/ (4 skills)                 .claude/scripts/verify-all.sh
  templates/agent-template.md        .claude/memory/
  templates/verify-all/              .claude/.apd-config
  templates/principles/              .claude/.apd-version
  templates/memory/                  .claude/settings.json
  .claude-plugin/plugin.json         CLAUDE.md
  .claude-plugin/marketplace.json
```

### New features

- **Plugin distribution** — marketplace.json for self-hosted distribution via `/plugin install`
- **`resolve-project.sh`** — shared library sourced by all scripts. Resolves `PROJECT_DIR` (user's project) and `APD_PLUGIN_ROOT` (plugin install) automatically. Enables scripts to work from any directory
- **`/apd-upgrade` skill** — migrates v2.x copy-paste installations to v3.x plugin architecture (backup, extract config, remove old scripts, update agent hooks)
- **`pipeline-advance.sh init`** — dedicated command for initial project setup. Distinct from `skip` (hotfix): no HOTFIX label, no skip log entry, auto-fills "None" in session log
- **Visual pipeline progress** — ASCII progress bar shows pipeline state at every step:
  ```
  [spec]---[builder]---[reviewer]--- verifier  --> commit
  ```
- **Improved auto-summary** — session-log entries now capture committed files (via `git diff HEAD~1`) instead of working tree. Guard block count filtered by task timestamp (excludes E2E test blocks)
- **Complete settings.json** — `/apd-setup` generates attribution (empty, no AI signatures) and Notification hook
- **`.apd-config`** — project configuration file (`PROJECT_NAME`, `APD_VERSION`, `STACK`) read by session-start.sh for dynamic project name
- **`.apd-version`** — tracks installed APD version for upgrade detection
- **Per-stack verify-all templates** — `templates/verify-all/` with ready-made snippets for .NET, Node.js, Java, Python, Go, PHP
- **Per-language principles templates** — `templates/principles/` for English and Serbian
- **Plugin hooks** — `hooks/hooks.json` with `${CLAUDE_PLUGIN_ROOT}` paths, conditional `if` fields, PostCompact, PermissionDenied

### Full English internationalization

All 400+ Serbian strings translated to English across 46 files:
- 17 bash scripts (comments, echo messages, error output)
- 4 skills (descriptions, procedures, examples)
- Rules, templates, agents, examples, documentation
- README.sr.md removed — single English README

### Deep audit — 52 issues fixed

Pre-release audit identified and fixed 52 issues:
- 11 critical (broken YAML quotes, missing files, wrong paths)
- 13 high (unquoted patterns, non-atomic writes, missing script lists)
- 14 medium (POSIX compatibility, trap cleanup, template gaps)
- 14 low (documentation, comments, minor inconsistencies)

Critical fixes include:
- Agent TEMPLATE.md had missing opening quotes in all `command:` values — hooks would not work
- `[popuni]` grep pattern not updated to `[fill in]` — session-log gate was non-functional
- 6 verify-all templates had untranslated Serbian error messages
- Script paths in skills/rules referenced `.claude/scripts/` instead of `${CLAUDE_PLUGIN_ROOT}/scripts/`

### Plugin system alignment

Verified against real Claude Code v2.1.94 plugin system:
- `hooks/hooks.json` auto-discovered (NOT declared in plugin.json — causes duplicate error)
- `skills/` auto-discovered (NOT declared in plugin.json)
- Agent template moved from `agents/` to `templates/` (avoid auto-discovery as invocable agent)
- Rules NOT auto-loaded from plugins — `/apd-setup` copies `workflow.md` to project
- Marketplace file enables self-hosted distribution

### Real-world validation

Tested end-to-end on a PHP + PostgreSQL + Vanilla JS project:
- `/apd-setup` generated 80 PASS, 0 FAIL setup
- Guard system blocked 16 violations (mass-staging, force-push, pipeline-incomplete, verify-failed)
- Pipeline gate correctly blocked commits without completed steps
- verify-all.sh ran PHPUnit and blocked on test failures
- Session log populated with auto-summaries

### Migration from v2.x

Run `/apd-upgrade` after installing the plugin. It will:
1. Backup your `.claude/` directory
2. Extract configuration from existing files
3. Remove scripts (now in plugin)
4. Update agent hook paths to `${CLAUDE_PLUGIN_ROOT}`
5. Create `.apd-config` and `.apd-version`
6. Verify with `verify-apd.sh`

### Installation

```bash
# In Claude Code:
/plugin marketplace add zstevovich/claude-apd
/plugin install claude-apd@zstevovich-plugins

# Start new session, then:
/apd-setup
```

---

## v2.8 — 2026-04-07

Adopts Claude Code v2.1.85–v2.1.89 platform features. Reduces hook overhead, adds context resilience and audit coverage.

### New features

- **Conditional `if` hooks** (v2.1.85+) — guard-git fires only on `Bash(git *)`, guard-lockfile only on lock file writes, pipeline-post-commit only on `APD_ORCHESTRATOR_COMMIT=1 git commit*`. Eliminates unnecessary process spawning for every `ls`, `cat`, or non-git Bash command
- **PostCompact hook** (v2.1.76+) — re-runs `session-start.sh` after context compaction to reinject project status, pipeline state, and last session. Prevents context loss in long sessions
- **PermissionDenied hook** (v2.1.89+) — `guard-permission-denied.sh` logs denied actions with tool name and agent ID (read from stdin JSON via jq) to `guard-audit.log`. Catches what guard scripts do not cover
- **`effort` frontmatter** (v2.1.80+) — `/apd-setup` runs at `effort: max`, `/miro-dashboard` and `/github-projects` at `effort: high`
- **Version check** — `session-start.sh` warns on startup if Claude Code is below v2.1.89 (recommended) or v2.1.32 (minimum functional). `verify-apd.sh` includes version as a PASS/WARN/FAIL check (54 checks total)

### Review fixes

- PermissionDenied hook changed from inline `echo` with shell env vars (always logged `unknown`/`orchestrator`) to proper script that reads `tool_name` and `agent_id` from stdin JSON
- `if` pattern on guard-git expanded to `Bash(git *) | Bash(APD_ORCHESTRATOR_COMMIT=1 git *)` to catch prefixed commands in both orchestrator and agent contexts
- `verify-apd.sh` now checks PostCompact and PermissionDenied hook registration

### Minimum Claude Code versions

| Level | Version | What works |
|-------|---------|-----------|
| Minimum functional | v2.1.32 | Pipeline, guards, agents |
| Recommended | v2.1.89+ | All features including conditional hooks, PostCompact, PermissionDenied, effort |

---

## v2.7 — 2026-04-06

Performance optimisation based on Trivue production analysis.

### New features

- **Verifier cache** — `pipeline-advance.sh verifier` writes a timestamp to `verified.timestamp`. When `verify-all.sh` runs again during the commit hook (<120s later), it detects the fresh cache and skips the rebuild. Eliminates the double build+test that was causing ~12 min overhead on .NET + Next.js projects
- Cache is invalidated on: pipeline reset, new spec, verifier rollback

### Impact

Trivue reported Reviewer→Verifier taking 12m 39s due to double verification (Verifier agent + guard-git commit hook both running `verify-all.sh`). With cache, the commit hook completes in <1s when Verifier has already passed.

---

## v2.6 — 2026-04-06

- **Getting Started guide** — step-by-step walkthrough from zero to first pipeline commit in 5 minutes. macOS terminal-style examples, verify output as readable table, spec card as blockquote, quick reference table
- **Interactive demo** — animated terminal demo showing guardrails blocking and pipeline flow (GitHub Pages)
- **Demo GIF** — embedded in README for instant visual preview
- **Architecture diagrams** — "20 Patterns in 4 Layers" grid + Pipeline Flow with GitHub Projects feedback loops
- **Gitignore cleanup** — `guard-audit.log` and `pipeline-metrics.log` added as runtime files
- **Review fixes** — session-log gate regex, stat fallback, PostToolUse verification, skip log silent drop

---

## v2.5.2 — 2026-04-06

- **New architecture diagrams** — "20 Patterns in 4 Layers" grid (Memory, Pipeline, Guards, Integrations) + Pipeline Flow with GitHub Projects feedback loops. Both EN and SR README
- **Gitignore cleanup** — added `guard-audit.log` and `pipeline-metrics.log` as runtime files

---

## v2.5.1 — 2026-04-06

Patch release: 2 HIGH and 4 MEDIUM fixes from code review.

### Bug fixes

- **HIGH: Session-log gate bypassed** — v2.4 gate checked for `[fill in]` but v2.5 auto-generated entries wrote `[fill in or "None"]` which didn't match. Gate was non-functional against auto-summaries. Fixed: pattern now matches `[fill in` (any variant)
- **HIGH: Spurious pipeline reset** — empty `stat` output in self-healing evaluated as `now - 0`, producing a massive age that triggered stale pipeline reset. Fixed: validates output before arithmetic
- **MEDIUM: PostToolUse hook not verified** — `verify-apd.sh` (51 checks now) and `test-hooks.sh` now check that `pipeline-post-commit.sh` is registered
- **MEDIUM: E2E test blocked by gate** — `verify-apd.sh` pipeline test now backs up and cleans session-log before `spec` step
- **MEDIUM: Skip log silent drop** — `pipeline-advance.sh skip` now always appends even if skip-log file doesn't exist

---

## v2.5 — 2026-04-06

Dream Consolidation: auto-generated session-log summaries from pipeline context.

### New features

- **Auto-summary on pipeline reset** — `pipeline-advance.sh reset` now generates populated session-log entries from pipeline context instead of `[fill in]` skeletons. Collects: changed files from `git diff`, guard blocks from `guard-audit.log`, bottleneck detection from step timestamps. Only **New rule** remains as `[fill in]` (requires human judgement)
- **Meta-summary on session-log rotation** — `rotate-session-log.sh` now generates a one-line consolidation when archiving entries: total tasks, date range, problem count, guard block count, new rules count
- **Fixed rotation regex** — `rotate-session-log.sh` now correctly matches `## [date]` format (was missing the brackets)

### Context

Production analysis (MojOff, 19 tasks) showed 12 of 14 auto-generated entries had unfilled `[fill in]` placeholders. v2.4 added a gate that blocks new tasks until entries are filled. v2.5 eliminates most placeholders by auto-generating content from data already available in the pipeline.

### Closes

- Closes #2 — auto-generate session-log summary from pipeline context

---

## v2.4 — 2026-04-06

Session-log enforcement based on real-world production findings.

### New features

- **Session-log gate** — `pipeline-advance.sh spec` now blocks new tasks if the previous session-log entry contains unfilled `[fill in]` placeholders. Shows which entry needs completion and lists the required fields. Forces the orchestrator to document what was done before starting new work

### Context

Production analysis of MojOff (19 pipeline tasks, 77 PASS verify-apd) revealed that 12 of 14 auto-generated session-log entries had unfilled `[fill in]` placeholders. The auto-append on pipeline reset creates skeleton entries, but without enforcement the orchestrator skips filling them in. This was the only soft rule in APD without mechanical enforcement — now it is enforced at the pipeline level.

### Edge cases verified

- Template session-log with HTML-commented examples: passes (no `[fill in]` in examples)
- Empty session-log: passes
- Missing session-log file: passes
- Properly filled entry: passes
- Entry with `[fill in]`: blocks with clear error message

---

## v2.3 — 2026-04-04

Security and reliability fixes based on independent framework audit.

### Bug fixes

- **CRITICAL: Pipeline reset timing** — moved pipeline reset from PreToolUse (before commit) to PostToolUse (after successful commit). Previously, if `git commit` failed after guard-git approved it (merge conflict, disk full, native pre-commit hook), the pipeline was already reset and the next commit would bypass pipeline checks. Now `pipeline-post-commit.sh` runs only after successful commit execution
- **guard-secrets coverage** — added guard-secrets.sh to `Read` and `Write|Edit` matchers in agent TEMPLATE.md. Previously, agents could `Read .env.production` or `Write` to sensitive files without being blocked (guard-secrets was only on the `Bash` matcher)

### New features

- **gh-sync.sh** — wrapper script that synchronises pipeline steps with GitHub Projects. Creates issues with spec cards, adds comments on each step, closes with commit reference or skip label. Remembers issue number across pipeline steps
- **pipeline-post-commit.sh** — PostToolUse hook that resets pipeline only after confirmed successful commit

### Updated files

- `.claude/scripts/guard-git.sh` — removed background pipeline reset (the timing bug)
- `.claude/scripts/pipeline-post-commit.sh` — new PostToolUse hook
- `.claude/scripts/gh-sync.sh` — new GitHub sync wrapper
- `.claude/settings.json` — added PostToolUse hook registration
- `.claude/agents/TEMPLATE.md` — guard-secrets on Read + Write|Edit matchers
- `.claude/skills/github-projects/SKILL.md` — gh-sync.sh documentation
- `examples/nodejs-react/` — both agents updated with new hook coverage

---

## v2.2 — 2026-04-04

Adds GitHub Projects integration for pipeline task tracking.

### New features

- **`/github-projects` skill** — maps APD pipeline phases to GitHub Projects v2 board columns (Spec → In Progress → Review → Testing → Done). Creates issues with spec cards, moves cards through columns, closes on commit
- **GitHub Projects section in CLAUDE.md** — configurable `{{GITHUB_PROJECT_URL}}` placeholder with pipeline tracking rules
- **`/apd-setup` updated** — asks for GitHub Projects URL during setup
- **README.md** — full GitHub Projects integration docs with column mapping, labels, metrics, and Miro vs GitHub comparison table

---

## v2.1 — 2026-04-04

Adopts Claude Code v2.1.72+ features for improved agent control and observability.

### New features

- **effort frontmatter** — `high` for Builders, `max` for Reviewer/Verifier. Enforces reasoning effort at the agent level instead of relying on documentation alone
- **agent_id audit logging** — `guard-git.sh` now logs every blocked action with agent ID, type, reason, and command to `guard-audit.log`. Enables per-agent activity analysis
- **Miro channels** — `claude --channels miro` enables real-time push notifications when the board changes. Supports board change alerts, CI/CD integration, and async human gate approval

### Updated files

- `.claude/agents/TEMPLATE.md` — added `effort: {{effort}}` frontmatter field
- `.claude/scripts/guard-git.sh` — agent metadata extraction + `log_block()` on all 10 exit points
- `.claude/skills/apd-setup/SKILL.md` — effort and channels guidance
- `CLAUDE.md` — Miro channels and dashboard references
- `README.md` — channels documentation in Miro integration section
- `examples/nodejs-react/` — both agents updated with `effort: high`

---

## v2.0 — 2026-04-04

Major release: from template to full-stack agentic development framework.

### New features

**Guardrails**
- Runtime write detection in `guard-bash-scope.sh` — blocks `node -e`, `python -c`, `ruby -e`, `php -r`, `perl -e` filesystem writes outside scope
- `verify-contracts.sh` — cross-layer type verification (TypeScript + C# parser) with nullable awareness, MATCH/MISMATCH/MISSING detection
- `verify-apd.sh` — 50 automated checks across 10 categories with summary table
- Self-healing session start — auto-fixes broken permissions, stale pipelines, shows merge conflict locations

**Pipeline**
- `pipeline-advance.sh metrics` — dashboard with avg/min/max duration, per-step averages, skip rate, last 5 tasks
- `pipeline-advance.sh rollback` — revert one step without full reset
- `pipeline-metrics.log` — append-only structured log for analytics
- Auto-append to session-log on pipeline reset

**Integrations**
- Figma integration — configurable design source with MCP and skill references
- Miro integration — board as source of truth for specs, architecture, planning
- `/miro-dashboard` skill — pushes pipeline status and metrics to Miro board
- Auto-detect agent scope in `/apd-setup` — reads project structure and proposes agents

**Documentation**
- English README (international English) + Serbian README.sr.md with cross-links
- Mermaid architecture diagrams (pipeline flow + guardrail infrastructure)
- CQRS architecture section with agents per stack, spec card templates, contract table
- Agent examples for 7 stacks: .NET, Node.js, Java/Spring Boot, Python/Django, Python/FastAPI, Go, PHP/Symfony
- Populated example project (`examples/nodejs-react/`)

**Quality**
- Canary upgraded to self-healing (auto chmod +x, auto pipeline reset, merge conflict detection)
- `test-hooks.sh` for quick static verification
- Pipeline skip log with `stats` command and >30% threshold warning

### Breaking changes

None. Fully backwards-compatible with v1.x configurations.

---

## v1.4 — 2026-04-04

- Hardened `guard-bash-scope.sh` — exit 2 (block) instead of exit 0 (warn)
- Added `test-hooks.sh` — 21 checks for hook configuration
- Added `pipeline-advance.sh rollback` command
- Added session-log example entries for onboarding
- Auto-append session-log on pipeline reset
- Removed obsolete files (setup.sh, conventions.md, superpowers specs/plans)

## v1.3 — 2026-03-25

- Interactive `/apd-setup` skill for project configuration
- ADR framework with templates
- Guard-lockfile for lock file protection
- Pipeline flag system (spec → builder → reviewer → verifier)
- Pipeline gate (blocks commit without all steps)
- Session log rotation
- MCP configuration example

## v1.2

- Guard-bash-scope and guard-secrets hooks
- Agent template with full hook coverage
- Pipeline advance with timestamps

## v1.0

- Initial APD template
- guard-git.sh, guard-scope.sh
- CLAUDE.md template with placeholders
- Workflow and principles rules
- Memory system (MEMORY.md, status.md, session-log.md)
