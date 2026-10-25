# Familiar — HackTX 2026

Social awareness for blind and low-vision people on Ray-Ban Meta Gen 2 glasses. The glasses are camera, mic and speaker; the iPhone does the thinking. Only people who agreed are ever recognized.

Start here:

- [FAMILIAR_MASTER_PLAN.md](FAMILIAR_MASTER_PLAN.md) — the brief: demo, scope, decisions, architecture, schedule, risks, sources.
- [AGENTS.md](AGENTS.md) — shared context that every Devin session reads automatically (product rules, repo layout, Swift contracts, conventions).
- [devin/](devin/) — one paste-ready prompt per Devin session: `01-skeleton` → `02-perception` ∥ `03-audio-speech-voice` ∥ `04-app-memory-consent` ∥ `09-modal-embedding-endpoint` ∥ `06-glasses-source` → `05-integration-demo` → `07`, `08` (stretch).
- [TEAM_CHECKLIST.md](TEAM_CHECKLIST.md) — the human track with clock times, including the fixture-clip shooting script.

The iOS project (`Familiar.xcodeproj`) is created by Devin session S1; build and test instructions land in this README with it. Never commit `Secrets.xcconfig`.
