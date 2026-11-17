Upgrade and cancellation clicks update immediately and reconcile with the simulation, including dependent queue cancellation and cancelling requests that have not yet received a job ID. The window remembers its geometry per FAF profile, with horizontal and vertical scrolling when resized.

Requires **FireDragon Mod Loader v6** installed and enabled as a normal FAF mod (shared core dependency).

# Modular Shields

Version 19 declares its custom UEF T4 shaders in `firedragonmod.json` for the
independent FireDragon Mod Loader. Install that dependency once; no launch settings are needed. See
[UEF T4 visual test](docs/UEF_T4_HEX_TEST.md) for shader installation, the sandbox
demo, health colours, rollback and validation limits.

Standalone simulation mod implementing docs/SHIELD_MOD_PLAN.md and docs/MODULAR_CODE_DESIGN.md,
with the user's clarified scope: shields handle AI-controlled attackers exactly as
player-controlled attackers. The mod does not make an AI build, equip or plan shields.

All built-in module families are implemented and enabled. This is ready for FAF
playtesting; the automated checks do not certify engine behavior, balance or multiplayer.
The packaged folder can be copied into the FAF mod directory below.

## Project layout

| Path | Purpose |
| --- | --- |
| `src/` | Mod sources (bundled as the `ModularShields` mod folder) |
| `tests/` | Lua test suites with engine mocks |
| `scripts/` | Asset generators (module icons) |
| `docs/` | Design and planning documents |
| `artifacts/` | Generated assets (git-ignored) |
| `dist/` | Build output (git-ignored) |

Requirements: PowerShell, `lua`/`luac` 5.4 on PATH, Python 3 with Pillow.

```powershell
./test.ps1                 # all tests + syntax checks (-Filter gameplay for a subset)
./build.ps1                # generate icons if missing, test, bundle into dist/
./build.ps1 -Install       # ...and mirror into the FAF mods folder
./build.ps1 -Regenerate    # force icon regeneration
```

Bump `version` in `src/mod_info.lua` for every release.

## Install

Run `./build.ps1 -Install`, or extract/copy the complete `dist/ModularShields` folder into:

`C:/Users/Rick/Documents/My Games/Gas Powered Games/Supreme Commander Forged Alliance/mods/`

Keep that folder name: the virtual import path is `/mods/ModularShields/`.
Enable **Modular Shields** in the FAF simulation mod list. Start with only
this mod enabled. All multiplayer clients need identical simulation files.

Use T3 engineers to build the standalone faction generators. Sandbox unit IDs:

- UEF: `mdeb4301` (T3), `mdeb4401` (T4).
- Aeon: `mdab4301`, `mdab4401`.
- Cybran: `mdrb4301`, `mdrb4401`.
- Seraphim: `mdsb4301`, `mdsb4401`.

They reuse installed stock faction scripts, models and icons. No reference-mod art
or game assets are redistributed. Stock generators and their upgrade chains remain
unchanged. The new T3 generators have their own native T4 upgrade button.

## Fitting and economy

Select one modular generator to open the image dock at the bottom center, above
FAF's native construction UI. The **Modules** row contains installed equipment and
pending jobs; **Upgrades** shows the next level of each family and available special
modules. Locked icons remain visible with an explanatory hover popup.

Left-click an upgrade icon to queue it. Its icon moves to Modules, becomes gray and
shows paid installation progress. Right-click a pending icon to cancel it; queued
dependents cancel with their prerequisite. Right-click installed equipment to queue
removal. Removal takes five seconds at the base work rate, can be assisted, costs
no resources and gives no refund. Its effect, upkeep and occupied slot remain until
removal finishes. Right-click a removing icon to cancel removal and keep the module.
Installed or queued dependents prevent removing their prerequisite.

The blue readout is live shield HP / maximum HP. Green shows actual current shield
regeneration, including full/offline/damage-delay states. Red shows average actual
shield HP lost over the last five seconds; regeneration does not hide damage.
Hover popups show blue capacity changes, green regeneration/repair changes, cyan
radius changes, orange special protection effects and gold costs/upkeep. Equipped
module tooltips preview losses on removal. The pause and repair-aura icons at the
top right have their own hover help. Chassis upgrading remains in the native bar.

Each module has a faction-specific geometric icon, with level pips and distinct
family symbols. Textures are deterministic rasterizations of vector primitives,
not AI imagery. `build.ps1` generates them with `scripts/generate_module_icons.py`
(Pillow) when missing: 96 SVG sources and 192 full-color/dim DDS assets go to
`artifacts/module-icons`, and the DDS files are bundled into the mod.
No reference-mod or stock artwork is redistributed.

T3 has four base slots; T4 has eight. Each completed, own edge-adjacent mass
storage adds one slot. Power, Range, Regen and Repair each have five
incremental levels. Every completed level occupies its own slot, retains its own
quoted upkeep and requires the previous level. Pending jobs reserve slots too.
Power I-IV fills an unsupported T3; attached mass storage can make room for V.
Nothing grants free capacity healing. Losing storage retains paid modules, but excess modules become dormant in a stable
prerequisite-aware order; restoring capacity reactivates them. Extra
queued installations wait for actual free capacity and retain paid progress; a
removal can run ahead of a waiting install to free a slot. The equipped icons wrap
into extra rows when more than eight modules are fitted.

Installations spend normal mass and energy through native economy events. The
scripted work backend samples actual fulfillment and counts only paid work.
Engineers assigned to guard/repair the host, in normal build range, contribute their
build rates. The host pays for their work through its economy event. Engineers
extend their build arms and show continuous beams during module installation;
they are not paused and do not display a disabled icon. The panel reports their
count and combined rate. Outside active module jobs, guards retain normal chassis
HP repair, its animations and native resource costs. Dome HP is never exposed as
native builder repair work. Normal shield
regeneration and generator upkeep continue. Unassigned, distant, busy, player-paused
and other-army engineers do not contribute. Reassigning restores normal construction
and the latest buffed build rate. Guard orders remain intact between module jobs;
native assistance is restored for chassis upgrading, host destruction or transfer.

Assistance increases speed and resource demand, keeping the total quote fixed.
At resource starvation engineers are reconciled every tick. Partial paid progress
survives pausing; cancellation gives no refund. Effects and recurring upkeep begin
together at completion. Install and repair-aura pause controls are separate from
the native shield toggle. Existing shield absorption and regeneration continue.

Power adds shield HP; Range changes diameter. Regen modules continuously repair
an operational shield, including while taking damage. Vanilla chassis regeneration
and neighboring generator bonuses resume only after the native damage delay.
All three source rows report actual current HP/s, so full/offline shields show zero.
The three HP rows separately show base, module and storage capacity contributions.
All effects use the immutable chassis baseline. Stats update the existing shield's
HP ceiling, collision sphere, meshes, regeneration and overlap-search diameter.
Current HP is clamped without filling newly added capacity or resetting damage delay.
Maintenance uses FAF consumption updates and keeps native economy adjacency.

Repair shares a bounded total HP/s budget among eligible same-army completed damaged
structures inside the dome. It excludes the generator and zero-mass targets.
Mass cost is `restored HP * 0.75 * target mass cost / target max HP`, modified by
configured neighbor efficiency. Actual mass is withdrawn before healing, without
yielding between payment and delivery. Empty storage delivers no free repair.
Actual aura mass spending also appears in the native selected-unit resource panel;
this is display attribution of the original withdrawal, without a second charge.
Newly completed adjacent power/storage providers trigger a shield refresh on the
next simulation tick, including the live capacity label in the native unit view.

## Protection behavior

**Deflector:** extends the existing falling-aircraft ShieldCollider mechanism,
including Czar and transports. The body attaches to the helper and is pushed outward
and upward. A bounce causes a small shield hit; the third separated shield impact
causes a larger shield hit and an independent visual-only breakup. The intercepted
body's remaining crash damage is suppressed immediately, even if the first hit
collapses the shield. Deferred transport cargo death paths are marked for containment.
Shield impact ripples are guaranteed even when native cosmetic throttling skips one.

The Deflector physically reflects non-nuclear ground-artillery shells across all
four factions, including indirect-fire mortar, fragmentation, cluster, sensor,
heavy/experimental and naval artillery families. Anti-air flak, missiles/rockets and
nuclear shells retain their own interception policies; the explicit ADFRocket01
reflection exception remains supported. Concrete impact/split guards cover the
expanded stock shell families. Reflection preserves original attacker ownership,
ordinary damage/friendly-fire rules and a short recontact cooldown. Reflected shots
can damage other targets normally.

**Atomized:** intercepts strategic nuclear missiles, tactical nukes and projectiles
with nuclear rings. It claims the interception once, disables collision/tracking,
clears instance damage/rings and destroys the projectile without calling its impact
or death handler. Shield damage is derived from the original direct/ring damage;
independent emitters make the explosion visual. No original blast, force, split or
DoT path runs. The entire intercepted blast is contained even when it collapses the
dome; subsequent missiles pass while it is down. Nearby detonations whose missiles
never intersect this dome keep their normal behavior.

**Ballistic:** intercepts non-nuclear missile and rocket families, including the
explicit standard families in `WEAPON_COVERAGE.csv`. A shared swept-path check covers
projectiles whose native collision flags skip shields. Guards on concrete projectile
scripts run before faction-specific splitting or impact effects. Unintercepted
weapons and ordinary shields retain their normal behavior.

**Impenetrable:** T4-only, requires Deflector, Atomized, Ballistic and a completed
same-army edge-adjacent T2-or-higher power generator. Energy storage and T1
generators do not satisfy this requirement. The paid module remains installed
and dormant when support is lost. While powered with an operational dome, it warms
up for three seconds, then enables broad projectile interception and ground/air denial.
Support loss, power loss, shield collapse and destruction deactivate the barrier.
Restoration requires a fresh warmup.

Power support requires a completed own T2, T3 or experimental energy generator,
with positive production, sharing a physical skirt edge with the shield. Corners,
gaps, mere proximity under the dome, other-army generators, T1 power and all storage
do not qualify. The Impenetrable hover popup lists Deflector, Atomized and Ballistic
separately, each with installed/missing state, plus T4, adjacency and warmup rules.

All completed, same-army edge-adjacent power generators (including T1 for this bonus)
add non-combat shield regeneration based on live energy production: 0.01 HP/s per
energy/s, so 800 energy/s adds 8 HP/s and 2000 adds 20 HP/s. Each energy storage adds
10% of immutable chassis shield capacity. Each mass storage adds one module slot.
Balance these values in `Definitions/NeighborRules.lua`; the existing stat caps
still apply. Normal native power-adjacency upkeep discounts remain active and are
not applied a second time. The dock shows provider counts, live energy production,
base/extra slots, the upkeep multiplier and the separate effective HP/regen sources.
Physical edges are reconciled once per second and on native adjacency events.
Mass and energy storage connections use the same faction-specific adjacency
nodes/beams as vanilla generators. Links appear for completed own edge-adjacent
storage and are cleaned up on separation, destruction or ownership change.

Storage bonuses stack linearly: six mass storages add six slots; six energy
storages add 60% of base capacity. Per-provider diminishing weights use iterative
multiplication for compatibility with FAF's Lua dialect (`^` is XOR there).

Ground denial returns enemy mobile land/seabed units to their last safe exterior
position, or chooses a pathable, unoccupied exterior point. It runs every simulation
tick, accounts for unit size, checks observed swept crossings, and avoids placing a
unit inside another active hostile barrier. Units inside on activation/radius change
can leave; after leaving they cannot re-enter. Newly observed enemy teleport/unload
arrivals inside are ejected. Friends retain access. Naval movement is unaffected.
Low aircraft are blocked by the actual spherical dome, with swept crossings and
speed-scaled outward displacement at their current flight altitude. Aircraft above
the dome can fly over it. Ground and air impacts use the same weighted cost/cooldown.
Each successful enemy push charges shield HP proportional to physical mass, or
blueprint mass cost when no physical mass is defined: max(5, mass * 0.05). The shield
impact effect plays. Outward displacement targets about 1.5 seconds of walking
plus clearance, using the unit's maximum speed. Each unit/host pair can charge only
once per 15 ticks; repeated forced contact still ejects units during that cooldown.
A collapsed shield stops pushing immediately. Tune these values in Config.Barrier.
Movement commands remain intact. This is a scripted field, with no pathfinding wall.

All threat decisions use army hostility and live shield capabilities. There is no
human/AI controller distinction, hidden-intel scan or enemy command manipulation.

## Upgrades and ownership

Native T3-to-T4 upgrading preserves completed modules, their original paid upkeep
quotes, pending job quotes/progress, pause controls, shield toggle, absolute shield
HP, regeneration delay and remaining recharge time. Effects use the new T4 baseline.
Module work pauses while the chassis upgrades and resumes afterward; native engineer
assistance remains available for the chassis upgrade itself. Matching footprint/skirt
geometry is retained. A cancelled chassis upgrade resumes module work on the T3.

Give/capture preserves completed equipment and shield state. Unfinished installations
are cancelled consistently because their economy events belong to the old owner.
No spent resources are refunded and no assistants remain claimed by the old host.

## Configuration and extensions

`src/lua/ModularShields/Config.lua` owns capacities, costs/work profiles, safety limits,
repair coefficients, feature switches, bounce policy, reflection allowlist and barrier
warmup/scan settings. All feature switches default to enabled; empirical validation
is recorded in docs/PLAYTEST.md rather than used to disable implementation.

Definitions use stable IDs in `Definitions/Modules.lua`. Add a stat module there with
its quote, prerequisites and presentation hints. Explicit package manifests are
collected in Bootstrap.lua; blueprint loading and simulation use the same registry.
The registry rejects duplicate IDs, unknown handlers, invalid values, missing
references, prerequisite cycles and conflicting neighbor stacking definitions.
Definitions are fixed at match startup; there is no runtime hot reload.

NeighborProviders supports category tests, explicit blueprint sets, combinations of
categories and positive energy-production requirements. NeighborRules supports any/all
provider tags, distinct physical providers, tier/module filters, thresholds, count
caps, diminishing contributions, additive/min/max/exclusive stacking groups and effect
bounds. Effects can modify bounded shield stats, energy upkeep and repair mass
coefficients. Rule inputs are snapshots, avoiding feedback loops. Extra generator,
energy-storage and mass-storage bonuses are enabled by default as described above;
production-weighted scaling is supported in declarative neighbor rules.

Third-party custom death paths and custom projectiles can require additional adapters.
The supported baseline is the installed FAF source audited during development;
no FAF release has yet been certified by an in-game run. Balance, terrain/pathfinding
edge cases, dense overlaps, visual scale, compatibility and late-game simulation cost
are the focus of the upcoming playtest.

## Verification

From the project root run `./test.ps1` (PowerShell, Lua and luac on PATH).
This runs pure rules, adapter/economy, blueprint and gameplay/lifecycle checks, then
parses every Lua/blueprint source. The engine mocks cover once-only interceptions,
paid work and starvation, assistant release, body bounce/breakup, deferred cargo,
upgrade transfer, ground/air behavior, neighbor rules and legendary activation.
UI checks also exercise image layout, persistent controls and the secured
simulation callback for fitting, removal, cancellation and pausing, including FAF's
recursive unit-data merge and cleanup of completed/cancelled queue controls.

Follow docs/PLAYTEST.md in FAF before making gameplay, multiplayer or performance claims.
