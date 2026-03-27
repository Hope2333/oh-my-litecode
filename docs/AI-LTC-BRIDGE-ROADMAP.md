# AI-LTC Bridge Roadmap

**Date**: 2026-03-27  
**Decision**: OML may host AI-LTC bridge capabilities, but the repositories stay separate

## Position

OML should become capable of:

- bootstrapping AI-LTC skeletons into another repository
- updating an already-installed AI-LTC surface
- exposing selected AI-LTC capabilities as opt-in agents or skills
- upgrading its bridge logic when OML itself upgrades

OML should **not** absorb the AI-LTC repository or collapse both codebases into one monorepo.

## Architecture Direction

### Bridge Model

- AI-LTC remains the framework source repository
- OML acts as a host and operator-facing bridge
- bridge features are loaded as plugin-like capabilities inside OML
- the bridge can self-start only when the task explicitly needs bootstrap, upgrade, corrective planning, or relay repair

### Boundary Rule

- AI-LTC owns prompts, templates, skeleton patterns, and framework docs
- OML owns runtime orchestration, package/CLI integration, and bridge execution
- copied prompt surfaces inside OML are snapshots and must periodically resync from AI-LTC

## Phased Plan

### Phase 0: Governance Bridge

- keep prompt copies aligned
- keep bridge strategy documented
- keep source resolution inside `.ai/system/ai-ltc-config.json`

### Phase 1: Bootstrap Bridge

- add an OML-facing flow that can install or refresh AI-LTC skeleton files
- make bridge execution opt-in, not automatic
- emit explicit handoff artifacts after bootstrap

### Phase 2: Agent And Skill Bridge

- extract repeatable AI-LTC tasks into optional agents/skills
- keep prompts authoritative even when a skill wraps them
- ensure skill wrappers still respect relay and bounded-pass rules

### Phase 3: Upgrade Bridge

- let OML detect AI-LTC framework drift
- refresh compatible bridge files without overwriting local lane state
- version the bridge contract so OML upgrades can trigger AI-LTC bridge upgrades deliberately

## Constraints

- no repository merge
- no silent framework overwrite
- no background self-upgrade without explicit operator intent
- no claim of bridge completion until bootstrap, update, and upgrade paths all exist with proof

## Immediate Next Questions

1. should the bridge surface start as CLI commands, plugins, or skills first
2. how will bridge version compatibility be stored and checked
3. which AI-LTC prompts should remain raw prompts versus wrapped agent/skill entrypoints
