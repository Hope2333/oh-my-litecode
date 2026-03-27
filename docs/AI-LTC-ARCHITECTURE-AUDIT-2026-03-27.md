# OML AI-LTC Architecture Audit

**Date**: 2026-03-27  
**Scope**: `/home/miao/develop/oh-my-litecode`  
**Prompt Mode**: GPT corrective strategist

## Findings

### High

1. **Cross-package composition was broken at runtime**
   - Evidence: `@oml/cli` imports `@oml/core/plugin` and `@oml/modules/tui|cloud|perf`, but the target packages did not export those subpaths and CLI did not declare `@oml/modules` as a dependency.
   - Confirmed by runtime failure: `ERR_PACKAGE_PATH_NOT_EXPORTED`.
   - Impact: packages looked locally usable but failed once consumed through the package contract.

2. **Relay truth had drifted across three sources**
   - Evidence: `00_HANDOFF.md`, `.ai/system/ai-ltc-config.json`, and `.ai/active-lane/current-status.md` were describing different lanes/phases.
   - Impact: the next AI could not safely infer the current lane without re-auditing the repo.

3. **Historical completion narratives still compete with current truth**
   - Evidence: the repo still contains many tracked `SUMMARY`, `FINAL`, `REPORT`, and `PROJECT-100*` documents that read like live status.
   - Impact: lower-cost AI can easily treat stale closeout docs as current truth and plan from a false baseline.

### Medium

4. **Current GPT surface lacked a dedicated corrective-strategy role**
   - GPT had bootstrap and optimizer prompts, but nothing aimed at architecture drift correction plus long-horizon future sequencing.

5. **Qwen stub risk remains concentrated in the `qwen` command surface**
   - `chat`, `config`, `keys`, and `mcp` still stop at placeholder output.
   - These must stay explicitly labeled as partial until behavior and tests exist.

## Decisions

### Decision A: Add a mandatory architecture contract gate

- `npm run architecture:check` is now the composition gate
- it verifies imports/dependencies/exports, evidence-based package status, and relay lane consistency

### Decision B: Treat historical summaries as reference, not live truth

- live truth remains in `.ai/active-lane/*`
- tracked source-of-truth docs are now explicitly named in `docs/ARCHITECTURE-MONITORING.md`

### Decision C: Add a dedicated GPT corrective-strategy role

- new prompt: `prompts/gpt-corrective-strategist.prompt.md`
- use it for course correction, architecture drift cleanup, and bridge planning

### Decision D: Keep AI-LTC and OML as separate repos with a bridge model

- OML may host AI-LTC bootstrap/update/agent/skill bridge features
- repository merge stays out of scope

## Immediate Next 1 To 3 Actions

1. keep `architecture:check` green while Qwen resumes execution
2. narrow the next Qwen lane to real parity or command-contract work, not more broad summary generation
3. decide whether the first bridge surface should be CLI-first or skill-first

## Deferred Work

- command-contract assertions for `qwen chat/config/keys/mcp`
- bridge-version compatibility checks
- explicit `src/` versus `packages/` adapter rules

## Stop Reason

`STOP_REVIEW_GATE_REACHED`
