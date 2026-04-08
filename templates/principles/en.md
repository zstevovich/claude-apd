# Principles

## Language
- Documentation and communication: English
- Technical terms remain in English: endpoint, middleware, handler, cache
- Tone: professional and concrete, must not sound AI-generated

## Code
- Minimal comments — only where logic is not obvious
- Application supports internationalisation (i18n) from the start

## Git
- No AI signatures in commits — no Co-Authored-By
- Branches: develop → staging → main, feature/* as needed
- .claude/settings.local.json and .claude/.pipeline/ must not go to git — all other .claude/ files are committed
- Commit messages: short, in English, imperative mood

## Docker (local development)
- Infrastructure only (database, cache, monitoring)
- Applications from debug mode (IDE)
