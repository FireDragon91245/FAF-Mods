# Modular Shields — playtest build

Standalone simulation mod implementing SHIELD_MOD_PLAN.md and MODULAR_CODE_DESIGN.md,
with the user's clarified scope: shields handle AI-controlled attackers exactly as
player-controlled attackers. The mod does not make an AI build, equip or plan shields.

All built-in module families are implemented and enabled. This is ready for FAF
playtesting; the automated checks do not certify engine behavior, balance or multiplayer.
The packaged folder can be copied into the FAF mod directory below.

## Install

Extract/copy the complete `ModularShields` folder into:

`C:/Users/Rick/Documents/My Games/Gas Powered Games/Supreme Commander Forged Alliance/mods/`

Keep that folder name: the virtual import path is `/mods/ModularShields/`.
Enable **Modular Shields (playtest)** in the FAF simulation mod list. Start with only
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

Select one modular generator to open its panel. Click an eligible module to queue
installation. Click an installed module to remove it. Removing equipment is free,
gives no refund and is rejected while an installed dependent still needs it.
The panel reports the dependent ID. Use the queue tab to cancel any pending job.
Module fitting/removal uses the native buttons in the side panel; the bottom
command bar provides the chassis upgrade. Locked module buttons show their reason.
Paid progress updates live in the panel and the generator's native construction
bar. Pausing retains progress; completion/cancellation clears the finished job and
queue buttons. The native bar remains available with the module panel closed.

T3 has four slots; T4 has eight. Power, Range, Regen and Repair each have five
incremental levels. Every completed level occupies its own slot, retains its own
quoted upkeep and requires the previous level. Pending jobs reserve slots too.
Power I-IV fills T3; Power V requires T4. Nothing grants free capacity healing.

Installations spend normal mass and energy through native economy events. The
scripted work backend samples actual fulfillment and counts only paid work.
Engineers assigned to guard/repair the host, in normal build range, contribute their
build rates. While contributing, their native work is paused; the installation pays
for their work through the host's event. Continuous construction beams indicate
module work, and the panel reports contributing engineers and their combined rate.
The native pause prevents simultaneously repairing the shield and fitting equipment.
Active guard/repair orders remain intact throughout the installation. Unassigned, distant, busy, previously
paused and other-army engineers do not contribute. Reassign or manually unpause a
contributing engineer to withdraw it. Completion, cancellation, host death, transfer
and installation pause release assistants without rewriting their command queues.

Assistance increases speed and resource demand, keeping the total quote fixed.
At resource starvation engineers are reconciled every tick. Partial paid progress
survives pausing; cancellation gives no refund. Effects and recurring upkeep begin
together at completion. Install and repair-aura pause controls are separate from
the native shield toggle. Existing shield absorption and regeneration continue.

Power adds shield HP; Range changes diameter; Regen changes active regeneration.
All effects use the immutable chassis baseline. Stats update the existing shield's
HP ceiling, collision sphere, meshes, regeneration and overlap-search diameter.
Current HP is clamped without filling newly added capacity or resetting damage delay.
Maintenance uses FAF consumption updates and keeps native economy adjacency.

Repair shares a bounded total HP/s budget among eligible same-army completed damaged
structures inside the dome. It excludes the generator and zero-mass targets.
Mass cost is `restored HP * 0.75 * target mass cost / target max HP`, modified by
configured neighbor efficiency. Actual mass is withdrawn before healing, without
yielding between payment and delivery. Empty storage delivers no free repair.

## Protection behavior

**Deflector:** extends the existing falling-aircraft ShieldCollider mechanism,
including Czar and transports. The body attaches to the helper and is pushed outward
and upward. A bounce causes a small shield hit; the third separated shield impact
causes a larger shield hit and an independent visual-only breakup. The intercepted
body's remaining crash damage is suppressed immediately, even if the first hit
collapses the shield. Deferred transport cargo death paths are marked for containment.
Shield impact ripples are guaranteed even when native cosmetic throttling skips one.

The Deflector also physically reflects the explicitly configured slow projectiles:
Aeon ADFRocket01, UEF TIFArtillery01, Cybran CIFArtillery01, and Seraphim
SIFThunthoArtilleryShell01/02. Reflection disables tracking/turning, preserves original
attacker ownership and ordinary damage/friendly-fire rules, and has a short
recollision cooldown. Deflected shots remain capable of ordinary damage elsewhere.

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
same-army edge-adjacent energy generator/storage. The paid module remains installed
and dormant when support is lost. While powered with an operational dome, it warms
up for three seconds, then enables broad projectile interception and ground denial.
Support loss, power loss, shield collapse and destruction deactivate the barrier.
Restoration requires a fresh warmup.

T1, T2 and T3 power generators qualify, as does energy storage. Complete the
structure and place it with its green build footprint sharing a side with the
generator footprint: corner-only contact, a gap, or merely being under the dome
does not qualify. The panel's adjacent-power count reports detected providers.
Physical skirt edges are reconciled once per second as well as on native events,
including cheat-spawned structures and events received before construction completes.
The stock SIZE category is preserved for normal FAF power-adjacency discounts.

Ground denial returns enemy mobile land/seabed units to their last safe exterior
position, or chooses a pathable, unoccupied exterior point. It runs every simulation
tick, accounts for unit size, checks observed swept crossings, and avoids placing a
unit inside another active hostile barrier. Units inside on activation/radius change
can leave; after leaving they cannot re-enter. Newly observed enemy teleport/unload
arrivals inside are ejected. Friends retain access. Naval/air movement is unaffected.
Movement commands remain intact, so repeated move orders can visibly push against
the field. This is a scripted force field, with no native pathfinding wall.

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

`lua/ModularShields/Config.lua` owns capacities, costs/work profiles, safety limits,
repair coefficients, feature switches, bounce policy, reflection allowlist and barrier
warmup/scan settings. All feature switches default to enabled; empirical validation
is recorded in PLAYTEST.md rather than used to disable implementation.

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
energy-storage and mass-storage bonuses are configurable, and none are enabled by
default beyond the legendary power-support requirement.

Third-party custom death paths and custom projectiles can require additional adapters.
The supported baseline is the installed FAF source audited in research/sources.json;
no FAF release has yet been certified by an in-game run. Balance, terrain/pathfinding
edge cases, dense overlaps, visual scale, compatibility and late-game simulation cost
are the focus of the upcoming playtest.

## Verification

From the workspace root run `./tests/run.ps1` (PowerShell, Lua and luac on PATH).
This runs pure rules, adapter/economy, blueprint and gameplay/lifecycle checks, then
parses every Lua/blueprint source. The engine mocks cover once-only interceptions,
paid work and starvation, assistant release, body bounce/breakup, deferred cargo,
upgrade transfer, ground behavior, neighbor rules and legendary activation.
UI checks also exercise native-control layout, persistent buttons and the secured
simulation callback for fitting, removal, cancellation and pausing, including FAF's
recursive unit-data merge and cleanup of completed/cancelled queue controls.

Follow PLAYTEST.md in FAF before making gameplay, multiplayer or performance claims.
