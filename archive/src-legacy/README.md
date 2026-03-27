# OML TypeScript Migration

This directory contains the TypeScript implementation of OML.

## Status

**Phase 1: In Progress** - Core CLI migration

## Quick Start

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev -- platform detect

# Build
npm run build

# Test
npm test
```

## Architecture

```
src/
├── cli/           # CLI entry point and commands
├── core/          # Core modules (platform, plugin-loader, etc.)
└── hooks/         # Python hooks integration
```

## Migration Progress

| Module | Status | Progress |
|--------|--------|----------|
| CLI (oml) | 🟡 In Progress | 20% |
| platform | 🟢 Complete | 100% |
| plugin-loader | ⚪ Pending | 0% |
| session-manager | ⚪ Pending | 0% |
| pool-manager | ⚪ Pending | 0% |
| hooks | ⚪ Pending | 0% |

## Legacy Compatibility

The TypeScript implementation coexists with the Bash implementation:

```bash
# TypeScript (new)
npm run dev -- platform detect

# Bash (legacy, still supported)
./oml platform detect
```

## Documentation

- [Migration Plan](../docs/MIGRATION-TS-PY.md)
- [TypeScript Types](./core/platform.types.ts)
- [Platform Implementation](./core/platform.ts)
