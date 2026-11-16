# Insta Build Render My Units!

Fixes units, factories and upgraded structures that stay invisible when they are
completed instantly, for example with the `ai_InstaBuild` console cheat. The bug is
in vanilla FAF; it happens with every other mod disabled.

## The bug

While a unit is under construction, vanilla FAF hides its mesh (root bone) and shows it
again a few ticks later from a script thread:

- **Factories** (`FactoryUnit.BuildingState`) hide the new unit, wait 3 ticks, then show it.
  An instant build finishes inside those 3 ticks. The factory changes state, which destroys
  the thread before it reaches `ShowBone`, so every unit the factory produces stays invisible.
- **Upgrades** (`StructureUnit.UpgradingState`): `OnStopBuild` shows the upgraded structure.
  The upgrade thread runs one tick *later* and calls `StartUpgradeEffects`, which hides the
  finished structure again. An instantly upgraded factory becomes invisible (and so does
  everything it builds).

Hidden units still exist, fight and can be selected; only their mesh is not drawn.

## The fix

The mod wraps `Unit.HideBone`/`ShowBone` to record when the root bone is hidden. When a
unit finishes construction, a short watch (5 seconds) starts. If the unit is still hidden
1 second after it was last hidden, the watch shows it again, along with the land and
enhancement bones vanilla re-applies after construction.

Hides that are meant to last are left alone:

- teleport invisibility
- units in internal storage
- commander warp-in
- external factory helper units
- the normal 3–4 tick factory roll-out hides

## Usage

Enable **Insta Build Render My Units!** in the mod manager. It is a sim mod, so the host
must enable it and every player gets it. There are no settings. Units that were already
invisible before you enabled the mod are not fixed; only new builds are covered.

## Development

```powershell
./test.ps1              # Lua tests, syntax checks and import-path lint (needs lua/luac 5.4)
./build.ps1             # test + bundle into dist/InstaBuildRenderFix (+ versioned zip)
./build.ps1 -Install    # also mirror into the FAF mods folder
```

| Path | Purpose |
|---|---|
| `src/mod_info.lua` | Mod metadata (bump `version` per release) |
| `src/hook/lua/sim/Unit.lua` | Thin Unit class wrapper |
| `src/lua/InstaBuildRenderFix/RenderGuard.lua` | Hide tracking, watch window and repair rules |
| `tests/run.lua` | Simulated-tick tests for the guard and the hook |

See [../MOD_TEMPLATE.md](../MOD_TEMPLATE.md) for the shared project conventions.
