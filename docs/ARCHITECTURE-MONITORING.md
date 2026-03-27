# Architecture Monitoring

**Date**: 2026-03-27  
**Purpose**: keep OML from looking green in isolated slices while failing at composition time

## Why This Exists

This repository already has enough implementation surface that local success inside one package no longer proves system health.
The main recurring failure mode is now composition drift:

- relay docs disagree about the active lane
- one package imports another package's subpath without a matching export
- a package works in-source but fails when consumed through its published contract
- a summary doc says `complete` while the code still contains obvious stubs or TODOs

## Mandatory Check

Run:

```bash
npm run architecture:check
```

This check is part of `npm test` and currently verifies:

1. inter-package dependency declarations
2. subpath export coverage for `@oml/*` package imports
3. evidence-based completion claims in `packages/README.md`
4. active-lane consistency across `00_HANDOFF.md`, `.ai/system/ai-ltc-config.json`, and `.ai/active-lane/current-status.md` when local relay state exists

## Source Of Truth Map

Use these as the current tracked architecture truth:

- `docs/MIGRATION-CONSTITUTION.md`
- `docs/AI-LTC-ARCHITECTURE-AUDIT-2026-03-27.md`
- `docs/AI-LTC-BRIDGE-ROADMAP.md`
- `packages/README.md`

Use these as live local truth:

- `.ai/active-lane/ai-handoff.md`
- `.ai/active-lane/current-status.md`
- `.ai/active-lane/roadmap.md`
- `.ai/system/ai-ltc-config.json`

Do not use `docs/*SUMMARY*.md`, `docs/*FINAL*.md`, `docs/*REPORT*.md`, or `docs/PROJECT-100*.md` as current-state truth without revalidation.
Those files are historical evidence or prior closeout snapshots, not authoritative relay state.

## Composition Guardrails

- `@oml/core` must not depend on `@oml/modules` or `@oml/cli`
- `@oml/modules` may depend on `@oml/core`, but not on `@oml/cli`
- `@oml/cli` may depend on `@oml/core` and `@oml/modules`
- if a package is imported through a subpath, that subpath must exist in `exports`
- if a command only prints `coming soon`, it is a stub and must stay labeled as partial in docs

## Qwen-Specific Anti-Slop Rules

These checks exist partly to catch partial delivery that looks finished in a narrow pass:

- wiring a command without behavior does not count as feature completion
- adding tests that only prove a local class works does not prove package-composition correctness
- a successful build does not override a broken package contract
- if relay docs drift, stop and repair the handoff surface before opening another lane

## Next Extension Points

The next monitor additions should cover:

1. command-contract assertions for `qwen chat/config/keys/mcp`
2. bridge-version compatibility between OML and AI-LTC
3. adapter-boundary checks between shell legacy paths, `src/`, and `packages/`
