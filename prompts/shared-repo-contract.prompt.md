Read `AGENTS.md`, `.ai/README.md`, `docs/ai-relay.md`, and `docs/ai-collaboration.md` first.
Then read the active lane handoff/status/roadmap docs listed in `docs/ai-relay.md`.
If `.ai/system/ai-ltc-config.json` exists, read it before assuming any AI-LTC source location.
If the repository is a fresh AI-LTC deployment or a `v0 -> v1` upgrade, run init routing before assuming the prompt source is fully configured.

Framework v1 role default:
- GPT is not the default always-on operator
- Qwen is the default day-to-day supervisor + executor
- use GPT mainly for:
  - early architecture/bootstrap
  - explicit optimization/audit/refactor intervention
  - targeted response to an escalation request

Shared lane rules:
- the active lane docs may live under local-only `.ai/` paths; read them when present and do not commit `.ai/`
- if `.ai/` is missing locally, recreate the minimal local workspace first instead of falling back to tracked `docs/modernization/*` state files
- if similarly named files also exist under `docs/modernization/`, treat them as bridge notes only, not as the active relay source of truth
- if the repository contains historical `summary`, `final`, `report`, or `100% complete` docs, do not treat them as current-state truth unless they are cross-checked against the active lane docs and the current architecture contract
- when the active lane docs point to extra roadmap, dependency, ADR, or architecture docs that affect sequencing, read those too before making lane or phase decisions
- follow only one extra hop of referenced docs unless a referenced document is clearly sequencing-critical
- when `00_HANDOFF.md` exists in the workspace root or active lane directory, read it before starting execution
- when `ESCALATION_REQUEST.md` exists and you are the explicitly-invoked architect/optimizer, use it as the first problem summary instead of re-deriving the whole situation
- when `.ai/system/ai-ltc-config.json` exists, treat it as the authoritative AI-LTC resolver config
- do not hardcode AI-LTC local paths into prompts, lane docs, or copied templates when a resolver config can be used instead
- prefer the configured local AI-LTC checkout first, then the configured remote fallback
- allow Qwen to refresh the local AI-LTC checkout only when the config allows it and the current task actually needs the refresh

Shared language and identifier contract:
- keep file paths, commit IDs, workflow IDs, and code identifiers in their original English form
- use English for relay-file updates, task instructions, commands, and technical evidence unless a role-specific prompt narrows this further
- use the configured `human_summary_language` from `.ai/system/ai-ltc-config.json` for human-facing summaries, evaluations, planning output, and final wrap-ups when available
- if the repository is still in init and no language is configured yet, ask for the human-facing output language first

Shared scope and commit guardrails:
- stay inside the active lane unless the active lane docs clearly say the lane changed
- do not let tracked bridge files under `docs/modernization/` override the `.ai/` lane state listed in `docs/ai-relay.md`
- do not commit `.omx/`, `.ai/`, `.sisyphus/`, or `AGENTS.md`
- when Qwen updates framework docs or lane-governance docs during execution, add a short leading note in the touched file:
  - `// Updated by Qwen on YYYY-MM-DD: <reason>`

Shared execution preference:
- when a build or clean verification can run on GitHub Actions without widening scope, prefer GitHub Actions as the authoritative proof path
- use local builds mainly for fast sanity checks, blocker isolation, and minimal repros
- avoid long local full builds when they are likely to stall, exhaust memory, or create noisy intermediate state
- if a prompt, handoff, or workflow already defines a narrow hosted-runner validation path, use that path before inventing a broader local loop
- if the repository exposes an architecture or composition contract check such as `npm run architecture:check`, run it before declaring the system structurally green

Shared safety limits:
- perform one bounded pass per invocation; do not recursively restate the same prompt to yourself
- if there is no meaningful new evidence after one pass, say so explicitly and stop
- do not invent extra lanes, phases, or workstreams unless the current docs and evidence clearly require them
- prefer updating existing handoff/roadmap files over creating new relay files
- if a loop risk appears (same blocker, same recommendation, same evidence twice), surface it and stop instead of continuing recursively
- if Qwen hits repeated failure, deadlock, or architecture uncertainty that clearly exceeds the current batch, emit `@ARCHITECT_HELP`, create or update `ESCALATION_REQUEST.md`, and stop instead of improvising a large redesign

Standard stop phrases:
- use one exact stop phrase when stopping early or terminating a bounded pass
- allowed stop phrases:
  - `STOP_NO_NEW_EVIDENCE`
  - `STOP_REPEATED_BLOCKER`
  - `STOP_BOUNDED_PASS_EXHAUSTED`
  - `STOP_WAIT_NO_PROGRESS`
  - `STOP_REVIEW_GATE_REACHED`
- when one applies, place it in a dedicated `Stop Reason` field or as a standalone final line
- do not invent alternate stop labels unless the human explicitly asks

Standard status fields:
- when the role-specific prompt asks for structured output, prefer these fixed fields when relevant:
  - `Status`
  - `Decision`
  - `Stop Reason`
  - `Next Action`
- keep field names exact when used
- if a field is not applicable, omit it rather than inventing a replacement

Shared output contract:
- keep outputs structured with named modules or flat lists that are easy to parse
- default cap: at most 7 top-level sections and at most 5 flat bullets per section unless a role-specific prompt narrows this further
- default length cap: target 25 to 45 lines unless the human explicitly asks for more depth
- do not use nested bullets
