# AI Collaboration Protocol

## Purpose

Use Qwen as the default ongoing generalist operator for supervision and execution.
Use GPT mainly for bootstrap architecture and later optimization/audit interventions.

## Role Split

### GPT Architect / Optimizer

- Bootstrap architecture, interfaces, and initial skeleton
- Short targeted optimization or audit after escalation
- Must not remain the always-on operator by default

### Qwen Generalist Operator

- Owns the normal day-to-day flow
- Performs checkpointing, sequencing, execution, verification, and relay upkeep
- Reads the active roadmap and derives:
  - lane goal
  - current batch
  - immediate next tasks
- Prefers a narrow GitHub Actions proof path over a broad local build loop when both can prove the same point
- Keeps local builds short and scoped
- Updates handoff docs after every meaningful state change

## v1 Handoff And Escalation

- GPT should leave `00_HANDOFF.md` when handing the project to Qwen.
- Qwen should read `00_HANDOFF.md` before first execution when it exists.
- If repeated failure or architecture deadlock exceeds the current batch:
  - emit `@ARCHITECT_HELP`
  - create or refresh `ESCALATION_REQUEST.md`
  - stop instead of improvising a larger redesign

## Self-Evolving Docs

- Qwen may directly update lane/framework docs as real execution changes the truth.
- When changing framework or governance docs, add:
  - `// Updated by Qwen on YYYY-MM-DD: <reason>`

## Bounded-Pass Rule

- Treat each execution or supervisory run as one bounded pass.
- If there is no meaningful new evidence after one pass, stop explicitly.
- If the same blocker, recommendation, or wait state appears twice without new evidence, stop and return with the matching stop phrase.

## Message Contract From Lower-Cost AI

When handing back, include:
- `Status`
- `Decision`
- current branch
- current head commit
- current layered TODO state
- latest relevant workflow run and conclusion
- first confirmed blocker or confirmation of green status
- local verification performed
- exact `Next Action`
- which handoff docs were updated
- `Stop Reason`
