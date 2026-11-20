Requires **FireDragon: Core & Loader v3** installed and enabled as a normal FAF mod (shared core dependency).

# FireDragon: Insta Build Render My Units!

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

- **Factory roll-off**: a factory holds the finished unit on its build platform, then
  releases it to drive down the ramp. With an instant build, `OnStopBuild` runs *before*
  the factory thread, so the unit is never attached to the platform; and vanilla detaches
  it in the same tick it would be attached, before the engine moves it onto the platform.
  The unit stays on the ground in the middle of the factory and drives out through it.
- **Upgraded structures lose collision**: vanilla `OnStartBuild` makes an upgrade
  uncollidable and invulnerable while it is being built, and the upgrade's own
  `OnStopBeingBuilt` reverts that. An instant upgrade finishes *before* `OnStartBuild`
  runs, so nothing reverts it: the upgraded structure stays without collision and cannot
  take damage for the rest of the game. On a factory the missing collision is the
  platform its units stand on, so they drop into the factory even with the roll-off fixed.

Hidden units still exist, fight and can be selected; only their mesh is not drawn.

## The fix

The mod wraps `Unit.HideBone`/`ShowBone` to record when the root bone is hidden. When a
unit finishes construction, a short watch (5 seconds) starts. If the unit is still hidden
1 second after it was last hidden, the watch shows it again, along with the land and
enhancement bones vanilla re-applies after construction.

For factories, `FactoryUnit.OnStopBuild` attaches an instantly finished unit to the build
pad itself when the factory thread has not started yet, then lets vanilla issue the
move-off order. `FinishBuildThread` keeps the unit attached for 3 ticks (factory busy,
queue blocked) so the engine places it on the platform before vanilla detaches it. The
late factory thread is skipped. The unit then rolls off the ramp exactly like a normal
build. If the factory thread did hide the unit but was cut off, the unit is shown as soon
as the roll-off begins.

For upgrades, `Unit.OnStartBuild` checks whether the upgrade had already finished being
built; if so it restores collision (including blueprint sphere collision) and damage, as
vanilla `OnStopBeingBuilt` would have.

Hides that are meant to last are left alone:

- teleport invisibility
- units in internal storage
- commander warp-in
- external factory helper units
- the normal 3–4 tick factory roll-out hides

## Usage

Enable **FireDragon: Insta Build Render My Units!** in the mod manager. It is a sim mod, so the host
must enable it and every player gets it. There are no settings. Units that were already
invisible before you enabled the mod are not fixed; only new builds are covered.

## Development

Version 5 fixes `Invalid args to yield(); expected tick count` warnings when the
render watch finishes. Watch threads now return no values to FAF's scheduler.

```powershell
./test.ps1              # Lua tests, syntax checks and import-path lint (needs lua/luac 5.4)
./build.ps1             # test + bundle into dist/FireDragon Insta Build Render My Units (+ versioned zip)
./build.ps1 -Install    # also mirror into the FAF mods folder
```

| Path | Purpose |
|---|---|
| `src/mod_info.lua` | Mod metadata (bump `version` per release) |
| `src/hook/lua/sim/Unit.lua` | Thin Unit class wrapper (bone visibility, `OnStartBuild`) |
| `src/hook/lua/sim/units/FactoryUnit.lua` | Thin FactoryUnit wrapper (`OnStopBuild`, `FinishBuildThread`, `BuildingState.Main`) |
| `src/lua/InstaBuildRenderFix/RenderGuard.lua` | Hide tracking, watch window and repair rules |
| `src/lua/InstaBuildRenderFix/FactoryFix.lua` | Instant-build attach, hold and roll-off rules |
| `src/lua/InstaBuildRenderFix/UpgradeFix.lua` | Collision/damage restore for instant upgrades |
| `tests/run.lua` | Simulated-tick tests for the guard, the factory flow and the hooks |

See [../MOD_TEMPLATE.md](../MOD_TEMPLATE.md) for the shared project conventions.
