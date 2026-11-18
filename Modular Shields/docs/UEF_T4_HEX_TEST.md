# UEF T4 hex dome prototype — v35

Only `mdeb4401` uses this experiment. Other factions, UEF T3 and stock shields
retain their existing appearance. The module system and protection rules are unchanged.

## Appearance

- A transparent blue field with rotating hexagonal seams. One turn takes 1200
  simulation ticks: about two minutes at the ideal 10 ticks/second. Rotation follows
  simulation speed and freezes when paused. The engine supplies interpolated ticks
  modulo 36000; the 1200-tick period keeps rotation continuous across that wrap.
- Health continuously blends red to yellow between 15–35%, holds yellow through 55%,
  then blends yellow to blue between 55–75%. Above 75% it is blue.
- Surface impacts illuminate a local neighborhood of seams and cell interiors for
  0.85 seconds. Impact colours use blue above 65%, yellow at 30–65%, red at or below 30%.
- Up to 32 impact overlays exist per dome. At saturation, the newest hit replaces
  the oldest flash instead of being dropped. Their orientation follows the hit,
  while their geodesic pattern follows the same clock as the main dome.
- A closed geodesic mesh carries 630 hexagons and the 12 pentagons needed to close
  a sphere. Shared cell edges replace projected textures: no wrap seam, overlapping
  grids, or polar texture stretching. Cell sizes vary slightly over the sphere.
- The dome has no depth-writing ShieldFill companion. Both the dome and impact
  overlays blend RGB without modifying scene alpha or depth, preserving shields
  behind and within the custom dome.

## Install / rebuild

Close any running Forged Alliance game and run `./build.ps1 -Install`.
This generates the geodesic SCM and mesh blueprints, compiles the production HLSL functions
with Windows D3DCompiler against Shader Model 2, runs tests and bundles the mod.
The source install also installs the sibling **FireDragon Mod Loader** dependency.
For release packages, install that loader once with its `install.cmd`, then install
the normal Modular Shields package. No game launch arguments, executable decorator,
Python runtime or FAF settings changes are required. The previous Python wrapper
and archive-writing commands have been removed.

The loader is a separate mod under `/mods/FireDragonModLoader`. Its native core is
`bin/FireDragonLoader.dll`; a small x86 `dsound.dll` bootstrap and config sit beside
FAF's live/replay executables. The bootstrap loads the independent core outside
Windows' loader lock. The core scans `firedragonmod.json` files, loads declared DLL
components and appends shader fragments in memory. This mod maps four technique
names to `shaders/UEFT4Hex.fx`; the shared file is loaded once. Official archives,
executables and init scripts are never modified.

Inspect `%LOCALAPPDATA%/FireDragonModLoader/loader-<pid>.log`: expect
`SHADER_ACCEPT ModularShields files=1`, `COMPILED augmented mesh effect` and four
`AVAILABLE ModularHex...` entries.
The simulation log reports `MODULAR_HEX_ACTIVE` when a UEF T4 is attached.
Loader v2 additionally exposes `FireDragonLoader.IsPresent()`, `Version()`,
`LoadedMods()` and `Logs()` in User/UI and Sim Lua. Once every declared resource
is ready, `LoadedMods()` contains `name='ModularShields'`, `version=19`, an empty
DLL list and all four `ModularHex...` shader technique names. Presence alone is
not a shader-readiness check. These are diagnostic/readiness APIs; this adapter
does not automatically disable the mod through them.
The adapter does not make simulation decisions from local native-loader state.
This version requires the native dependency; a missing or failed custom shader
will not silently select a different local simulation path.

For removal, close the game and use the loader's `uninstall.cmd`. It removes only
loader-owned files after checking their hashes. Disable this native-shader version
of Modular Shields when using the game without the loader.

The POC is verified with FAF 3841, whose init clears the shader cache. Other engine
versions/launchers that retain cached effects need an additional cache strategy.
Updater survival, cross-mod dependencies and multiplayer/replay consistency still
need production design. See the loader's README for exact limits.

## Reproducible sandbox test

Enable Modular Shields in a sandbox/skirmish with cheats and enough stored energy
to sustain an additional UEF T4 shield. In the game console, run:

```lua
SimLua import('/mods/ModularShields/lua/ModularShields/Diagnostics/HexDomeTest.lua').Export.Start()
```

This explicitly creates a temporary UEF T4 at the map center for the focus army.
Optional arguments are `(armyIndex, x, z)`. Choose clear, dry terrain with room
for the dome. The demo shows full, half and 15% health for ten seconds each, with
moving impact flashes, then toggles/restarts the shield and removes the test unit.
Only the disposable test shield's HP is controlled. Use this in a test match.

Also verify with a normal built generator and actual enemy fire:

1. Pattern rotates, cell interiors remain transparent, and units below stay readable.
2. Fire at the front, sides and top. Bright seams should line up with the main dome;
   the illuminated neighborhood should follow the hit, fade, and remain bounded
   under rapid fire. Check hits from both projectiles and beams.
3. Place a vanilla shield inside/behind the custom dome and check it remains
   visible through cell interiors. Inspect the entire circumference and pole for
   a wrap seam or blended grids. Let HP cross both colour transitions and regenerate back to blue.
4. Collapse, toggle, drain energy, and recharge. No visible dome while down; the
   custom appearance returns without an HP reset or changed recharge time.
5. Install Range/Power/Regen; test T3-to-T4 upgrade, capture, death and reclaim.
   The dome and impacts must scale correctly, with no persistent flash entities.
6. Compare other faction/tier shields. Check water, fog of war, strategic zoom,
   low/high graphics quality, and many simultaneous shields before wider use.

## Validation boundary

Lua lifecycle tests and direct D3D9 shader compilation are automated. The native
integration harness compiles the full augmented mesh effect and validates all four
techniques on a D3D9 device. A FAF startup with no arguments independently reports
all four techniques in the real process. These checks do not establish visual
quality, multiplayer determinism or GPU cost.
Record interactive findings before expanding this to other factions or modules.

Future upgrade-dependent skins can select a visual profile in `Adapters/HexDome.lua`;
the renderer experiment does not require committing to a new module-system design.
