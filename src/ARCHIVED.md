# src/ Directory Archived

**Date**: 2026-03-27  
**Reason**: Migration to packages/ structure

## Current Structure

The TypeScript implementation has been moved to:

```
packages/
├── cli/       # CLI entry point and commands
├── core/      # Core runtime (Pool, Session, Plugin)
└── modules/   # Feature modules (Backup, Cloud, Conflict, I18n, Perf, TUI)
```

## Archived Files

Legacy files from this directory are now in: `archive/src-legacy/`

## Use packages/ Instead

For all development work, use:
- `packages/cli/` - CLI commands
- `packages/core/` - Core modules
- `packages/modules/` - Feature modules

## Documentation

- [packages/README.md](../packages/README.md)
- [TYPESCRIPT-MIGRATION-SUMMARY.md](../docs/TYPESCRIPT-MIGRATION-SUMMARY.md)
