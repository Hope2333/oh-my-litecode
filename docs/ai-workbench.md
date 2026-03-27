# AI Workbench

This is the human-facing control panel for AI collaboration in this repository.

## Use This First

If you only want one document to look at before talking to an AI, use this one.

## Current System

- Global relay rules: `docs/ai-relay.md`
- AI role split and detailed contracts: `docs/ai-collaboration.md`
- Architecture monitoring: `docs/ARCHITECTURE-MONITORING.md`
- Optional GPT to Qwen handoff: `00_HANDOFF.md`
- Optional Qwen to GPT escalation summary: `ESCALATION_REQUEST.md`
- Active lane handoff: local-only `.ai/active-lane/ai-handoff.md`
- Active status summary: local-only `.ai/active-lane/current-status.md`
- Active roadmap: local-only `.ai/active-lane/roadmap.md`

## Stable Protocol Defaults

- In v1, Qwen is the default ongoing operator.
- GPT should normally appear only for bootstrap architecture or explicit escalation/optimization work.
- Treat one AI invocation as one bounded pass.
- Prefer narrow GitHub Actions validation over long local full builds when both can prove the same point.
- Keep local builds short and scoped for sanity checks, blocker isolation, and minimal repros.
- Run `npm run architecture:check` before trusting package composition or relay consistency.
- Use fixed stop phrases:
  - `STOP_NO_NEW_EVIDENCE`
  - `STOP_REPEATED_BLOCKER`
  - `STOP_BOUNDED_PASS_EXHAUSTED`
  - `STOP_WAIT_NO_PROGRESS`
  - `STOP_REVIEW_GATE_REACHED`
- Prefer fixed fields when the prompt supports them:
  - `Status`
  - `Decision`
  - `Stop Reason`
  - `Next Action`

## Human Control Pattern

- If the project is still at the very beginning, start with GPT as architect.
- Once the skeleton exists, switch to Qwen as the default generalist operator.
- Only wake GPT again when:
  - you explicitly want a high-cost audit or redesign
  - Qwen has emitted `@ARCHITECT_HELP`
  - you need architecture drift correction or long-horizon bridge planning via `prompts/gpt-corrective-strategist.prompt.md`
