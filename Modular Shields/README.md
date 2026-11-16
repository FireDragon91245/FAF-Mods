# Modular Shields

Supreme Commander: Forged Alliance (FAF) simulation mod adding modular T3/T4 shields.
Player-facing documentation: [ModularShields/README.md](ModularShields/README.md).

## Layout

| Path | Purpose |
| --- | --- |
| `ModularShields/` | Mod sources (mounted in-game as `/mods/ModularShields/`) |
| `tests/` | Lua test suites with engine mocks |
| `scripts/` | Asset generators (module icons) |
| `docs/` | Design and planning documents |
| `artifacts/` | Generated assets (git-ignored) |
| `dist/` | Build output (git-ignored) |

## Requirements

- PowerShell, `lua` and `luac` (5.4) on PATH
- Python 3 with Pillow (`pip install pillow`) for icon generation

## Commands

```powershell
./test.ps1                 # run all tests + syntax checks
./test.ps1 -Filter gameplay
./build.ps1                # generate icons if missing, test, bundle into dist/
./build.ps1 -Install       # ...and mirror into the FAF mods folder
./build.ps1 -Regenerate    # force icon regeneration
```

Bump `version` in `ModularShields/mod_info.lua` for every release.
