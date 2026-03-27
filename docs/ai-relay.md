# AI Relay Protocol

Before substantial work, read:

1. `AGENTS.md`
2. `docs/ai-relay.md`
3. `docs/ai-collaboration.md` when multiple AIs are collaborating
4. `.ai/system/ai-ltc-config.json` when it exists
5. The area-specific handoff file for the lane you are touching

## Active Lane Registry

- Active lane
  - handoff: `.ai/active-lane/ai-handoff.md`
  - status: `.ai/active-lane/current-status.md`
  - roadmap: `.ai/active-lane/roadmap.md`

Optional v1 control files:
- root handoff bootstrap: `00_HANDOFF.md`
- targeted escalation summary: `ESCALATION_REQUEST.md`
- init resolver config: `.ai/system/ai-ltc-config.json`
- init state note: `.ai/system/init-status.md`
- default resolver policy: local AI-LTC first, remote fallback second

The `.ai/` paths listed here are the authoritative active-lane state.
If similarly named files also exist under `docs/`, treat them as stable notes only, not as current relay state.

## Standard Stop Phrases

- `STOP_NO_NEW_EVIDENCE`
- `STOP_REPEATED_BLOCKER`
- `STOP_BOUNDED_PASS_EXHAUSTED`
- `STOP_WAIT_NO_PROGRESS`
- `STOP_REVIEW_GATE_REACHED`

## Standard Status Fields

- `Status`
- `Decision`
- `Stop Reason`
- `Next Action`

## Guardrails

- Prefer updating the existing handoff file over creating ad hoc status files.
- `docs/` is for human/stable operational docs and general AI initialization, not private AI working state.
- `.ai/` is the local-only workspace for active AI handoff, status, roadmap, and resolver files.
- When `00_HANDOFF.md` exists, keep its lane identity aligned with `.ai/system/ai-ltc-config.json` and `.ai/active-lane/current-status.md`, or explicitly mark it historical.
- Prefer a narrow GitHub Actions proof path over a broad local build loop when both can prove the same point.
- Use local builds mainly for fast sanity checks, blocker isolation, and minimal repros.
- In v1, Qwen is the default ongoing operator.
- GPT should normally appear only for bootstrap architecture, explicit optimization, or escalation response.
- If the repository provides an architecture contract gate such as `npm run architecture:check`, run it before declaring the relay surface and package graph healthy.
