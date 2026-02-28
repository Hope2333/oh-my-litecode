# OML ↔ OCT Integration (`oml opencode`)

This document defines the parent-child command bridge between:

- Parent: **oh-my-litecode (OML)**
- Child: **opencode-termux (OCT)**

## Command Contract

```bash
oml opencode <action> <subargs>
```

Supported actions:

- `path`
- `diagnose`
- `plugin <action> [args]`
- `skill list`
- `skill hook <event>`
- `matrix --vers "..." [--odir ... --host ... --port ... --user ...]`
- `build [--ver ... --pkg ... --odir ...]`
- `plugin-build [--plugin ... --mode ... --odir ... --mix]`

## Mapping to OCT tools

- `plugin ...` → `tools/plugin-manager.sh`
- `diagnose` → `tools/plugin-selfcheck.sh` + key path checks
- `skill hook ...` → `scripts/hooks/run-system-skills.sh`
- `matrix ...` → `make matrix ...` (or `tools/upgrade-matrix.sh` through Make)
- `build ...` → `make all ...`
- `plugin-build ...` → `opencode-plugins-termux` `make all ...`

### Termux plugin default recommendation

For Termux environments, prefer **file-plugin mode** in `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "file:///absolute/path/to/local-plugin"
  ]
}
```

Reason: this avoids unstable npm/bun postinstall chains and native dependency drift in Android/Termux.

## Environment policy

- Termux-first, GNU/Linux-second
- No implicit support targets beyond those two without explicit requirement

## Unified build targets (OML orchestrated)

```bash
oml build --project opencode --target termux-dpkg --ver 1.2.10
oml build --project opencode --target termux-pacman --ver 1.2.10
oml build --project opencode --target gnu-debian --ver 1.2.10
oml build --project opencode --target gnu-arch --ver 1.2.10
```

Target mapping:

- `termux-dpkg` -> OCT `make all PKG=deb`
- `termux-pacman` -> OCT `make all PKG=pacman`
- `gnu-debian` -> same build path with GNU/Linux host context
- `gnu-arch` -> same build path with GNU/Linux host context

For bun-termux (currently Termux-only):

```bash
oml build --project bun --target termux-dpkg --ver 1.3.9
oml build --project bun --target termux-pacman --ver 1.3.9
```

## Path override

By default, OML resolves OCT at:

```bash
$OML_ROOT/../opencode-termux
```

Plugin builder repo path (default):

```bash
$OML_ROOT/../opencode-plugins-termux
```

Override with:

```bash
OML_OCT_DIR=/custom/path/to/opencode-termux ./oml opencode path
```
