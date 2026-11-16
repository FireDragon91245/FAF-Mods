# Modular Shields: research and implementation plan

Implementation update: the playtest build is in [README](../README.md). The user clarified that AI support means identical shield behavior against AI and player attackers; AI construction/loadout planning is outside scope. The user authorized implementing the remaining mechanics before in-game playtesting. The earlier proposal and acceptance criteria below are retained as design history.

Research date: 15 November 2026. This is a design proposal, not implemented gameplay.

The code-level contract is specified in [MODULAR_CODE_DESIGN.md](MODULAR_CODE_DESIGN.md). It incorporates cumulative level slots, assisted installation, extensible neighbor rules and AI behavior. Where earlier research examples describe another mod, they are observations rather than requirements for this mod.

## Recommendation

Build a standalone simulation mod with new modular T3 and T4 generators for the four standard factions. Use internal module slots, a simulation-owned loadout, and a dedicated shield behavior class. Borrow reviewed patterns from the downloaded Modular Experimental Shields mod rather than extending its physical socket and shared adjacency system wholesale.

Prioritize an early prototype of nuclear containment, aircraft crash containment, and ground-unit blocking. Ordinary shield stats and modules are straightforward; those three behaviors determine whether the full design can meet its promises.

## 1. What was found and prepared

The FAF client had already unpacked the seven shield-related mods in:

`C:/Users/Rick/Documents/My Games/Gas Powered Games/Supreme Commander Forged Alliance/mods`

They were copied locally, including assets, for inspection; that research copy is not kept in this repository. No installed mod was edited, activated, or replaced. The project directory was empty when this investigation began.

The audit used selected files extracted from the installed FAF `.nx2` archives and current upstream source files pinned to FAF develop commit `ed82c657b30650a139c7ff6ee064f063184dfe66` (15 November 2026).

The local `fa_path.lua` reports game 3817/client 2025.1.0 and the game archives are dated January 2025. That is installation metadata, not proof of the release currently selected for play. Do not equate the develop snapshot with FAF's released game version. Choose the supported release and verify its APIs before implementation.

### Downloaded mod findings

**Modular Experimental Shields** (`ModularShields-v0.1.0`, but metadata says release 0.4.0/version 16)

- `lua/Config.lua`: twelve sockets; four module types: Range, Capacity, Recovery, Regen; faction-specific T4 generators and costs; deterministic stat calculation.
- `lua/ExperimentalShield.lua:269`: recalculates live stats, preserves absolute current HP, adjusts collision and both visual meshes, wakes suspended regeneration, updates the largest shield diameter used by overlap queries, and changes energy upkeep.
- `lua/ShieldModule.lua`: modules are separate physical structures. They register through adjacency, can serve multiple touching shields, disconnect on destruction, and check host ownership/position.
- `lua/ModuleOrders.lua` and `hook/lua/SimCallbacks.lua`: UI requests become simulation-selected build orders; callback passes units through FAF's `SecureUnits` rather than trusting a UI army number. Native construction handles payment and assistance.
- Ownership transfer and cleanup have explicit handling. Removal is represented by removing/destroying/reclaiming module structures, rather than a general internal equipment system.
- Useful starting patterns, but no requested repair aura, module level dependency graph, nuclear/crash containment, or ground barrier. Its recovery module shortens collapse downtime; this is distinct from your regeneration module.
- MIT license covers original code/documentation; its license explicitly excludes referenced game assets from that grant.

**Advanced Shields 2026** (version 2)

- Adds faction T4 structures with explicit blueprints and faction shield scripts. Useful references for model scale, build menus, wrecks, effects and animations.
- Primarily fixed-stat units, not a modular behavior system.
- Example: Seraphim `units/sysw5/SYSW5_unit.bp` specifies 63,000 shield HP, diameter 77 and 2,500 energy/second upkeep. These are that mod's choices, not recommended balance targets.

**Experimental Shields** (version 13)

- Adds experimental structures and a global `hook/lua/shield.lua` override allowing hostile strategic missiles to collide with shields.
- Also overrides `GetOverlappingShields` to return no shields. This removes normal overlap processing for the hooked shield class, not just the new generators.
- A collision change alone does not prove nuclear blast containment.
- Its metadata comments mention Survival Mayhem/BO dependencies although `requires` is empty. Inspected unit scripts use standard faction imports; treat the dependency claim as unresolved until all asset references are checked.

**Nuclear Repulsor Shields** (version 23)

- Uses the same global strategic-missile collision and disabled-overlap approach.
- Adds shield tiers, AI integration, and nuclear death weapons. `hook/lua/sim/defaultweapons.lua` defines `ShieldDeathWeapon`; its `NukeDamage.lua` implements damage rings for those weapons. That is not a shield-local containment layer for incoming nukes.
- Hooks an Aeon nuclear visual projectile with an old version check. New code should use the target release's current projectile hierarchy.
- Nomads scripts import Nomads classes. Nomads support should be optional and explicitly gated.

**Nuclear Repulsor Shields Tweaks** (version 1)

- Depends on Nuclear Repulsor Shields.
- `hook/lua/system/Blueprints.lua` repairs upgrade chains and Nomads stealth/color behavior. It checks matching footprints before linking upgrades; retain that principle.

**PJ Smart Shields** (version 19)

- A shared manager puts eligible shields into low-power watch mode, retaining an invisible collision sphere and waking through projectile/beam collision callbacks.
- Useful lifecycle and shared-manager patterns. It caches full upkeep from the blueprint, then restores it later. That can overwrite dynamic module upkeep; compatibility needs one agreed source for current upkeep or an explicit adapter.
- Idle mode is outside your requested feature set and should not be added automatically.

**Ultra Shields** (version 3.5)

- Legacy fixed-stat shields, upgrade chains and AI lists. Useful historical blueprint references, not a foundation for custom simulation behaviors.
- Actual shield content is nested under `mods/shields/` inside the installed outer mod. Confirm virtual mount paths before assuming this packaging loads correctly today.

Only Modular Experimental Shields supplied a standalone license file in the reviewed folders. Preserve attribution and verify redistribution rights before copying other authors' code/assets into a release. References can remain local research material.

## 2. Engine findings that affect the design

### Normal shields already block many weapons

FAF `lua/shield.lua:777` handles projectile collision; `OnCollisionCheckWeapon` handles beams. The default bubble explicitly excludes strategic missile projectiles but otherwise admits hostile projectiles, subject to its special cases. Therefore ordinary beams and many tactical missiles are already blocked. Do not market Ballistic as enabling something every stock bubble already does.

Define Ballistic through a tested coverage list: tactical missile families, cruise missiles, slow rockets, artillery exceptions and shield-piercing projectiles. Inspect projectile physics/category flags as well as the shield callback. Speed alone is not a reliable weapon classification. Unusual weapon-mod families need explicit adapters.

### Aircraft already interact with shields

`projectiles/ShieldCollider/ShieldCollider_script.lua` follows crashing planes. On shield impact it can bounce the aircraft, damages the shield up to 20% of maximum shield HP, and subtracts the absorbed amount from the plane's remaining crash damage. Some large aircraft/transports are excluded from the momentum system.

This means a bounce can still leave damaging wreckage headed inside the shield. Your Deflector needs a stronger, tested guarantee for covered crashes. Static reclaim wrecks and cosmetic debris are different objects from a dying plane and its crash collider.

### Nukes have separate damage paths

`lua/sim/Projectile.lua:735` invokes inner and outer nuclear damage rings. `lua/sim/NukeDamage.lua` can invoke a custom `DamageArea` implementation; `lua/sim/DamageArea.lua` explicitly bypasses bubble absorption for nuclear damage. `lua/sim/projectiles/NukeProjectile.lua` also adds impact visuals and force rings.

Consequently, changing the collision return value and calling the ordinary impact handler is insufficient. An intercepted nuke needs a dedicated outcome that prevents all original damage paths, applies damage once to the shield, and creates visuals without starting the original blast/force threads. Some faction/mod projectile subclasses can override these methods; audit every supported family.

### Shield spheres do not form navigation walls

FAF's crash collider comments explain that shields detect projectiles. No reviewed source establishes a native shield sphere that blocks moving ground units. Ground denial requires a separate simulation mechanism and is the main feasibility risk. A full smooth pathfinding obstacle cannot be promised from these Lua hooks alone.

### Live stat changes need lifecycle handling

Setting `Size` alone does not resize an already active dome. FAF's deprecated `SetSize` only assigns that field. Collision sphere, mesh scales, current health, regeneration thread, overlap query radius and UI state must agree. Preserve normal shield overlap/spillover behavior and collapse timers.

## 3. Proposed gameplay contract

These are starting design choices, not final balance commitments.

- T3: four internal slots. T4: eight internal slots and higher base shield HP/range/regen. All seven requested module families are mixable within capacity; Impenetrable is an additional T4-only module.
- Each level is a separate installed module occupying one additional slot. Power II requires Power I and keeps it installed; Power III requires both lower levels, and so on. No free jump to a higher level and no level replaces a lower level.
- Configure up to five levels for Repair, Range, Power and Regen initially; one level for Deflector, Atomized and Ballistic. Four T3 slots make level V impossible there even if that is its only module family. Five levels in a T4 use five of its eight slots.
- Every module/level costs mass, energy and installation time. Range, HP and regen increases also raise continuing energy consumption. Special protection modules also have explicit energy upkeep.
- Range changes geometry only; it does not increase shield HP. Power increases maximum shield HP. Regen raises active healing rate, not automatically the collapse restart speed.
- Installation is a cancellable, paid construction job with normal mass/energy build costs, finite work, and engineer assistance. Reserve its slot and validate requirements both when queued and when completed. One active job per generator avoids concurrent changes bypassing capacity. Existing shield protection, installed modules and shield regeneration continue throughout installation, subject to ordinary damage and power availability. A new module's bonus and extra upkeep start together only when construction completes.
- Remove modules individually. Proposed initial rule: removal is free, gives no refund, and immediately removes benefits. Reject removing a prerequisite while a dependent module remains; explain which module must be removed first. No silent removal of paid equipment.
- Preserve absolute shield HP on fitting/removal, clamped to the new maximum. Never recreate a fresh full-health shield to update stats. Increasing capacity gives no instant healing.
- T3-to-T4 upgrades preserve installed modules and current HP subject to validation; final footprint and native upgrade behavior must support the chosen transfer mechanism. Never overwrite someone else's stock upgrade chain silently.
- Start with new standalone unit IDs/build entries, without requiring the reference mods. Faction presentation can vary; core module rules remain shared. Nomads is a later optional adapter.

Eight T4 slots allow level I of all seven families plus the legendary module, with no room for higher levels. With four T3 slots, players must choose a role. A T4 fitted with all three special prerequisite modules has five slots left before the legendary is installed, then four afterward. All completed levels remain paid, occupied slots and contribute their own configured incremental stats and upkeep.

## 4. Module behavior

### Repair

Run only while the shield is actually operational. Query completed, damaged structures belonging to the same army inside the dome; exclude wrecks, foundations and the generator itself initially. Allied repairs can become an explicit option later. Check dome geometry/height, rather than assuming every building in the horizontal radius is protected.

Use a bounded total repair budget shared among targets, with deterministic rotation and entity-ID ordering. More targets must divide that budget rather than multiply it without limit.

For target `u`, calculate `massPerHP(u) = repairFactor * BuildCostMass(u) / MaxHealth(u)`. Then charge `actualRestoredHP * massPerHP(u)`. This uses FAF's mass resource, corresponding to the requested metal. Set `repairFactor` explicitly; the inspected native repair calculation uses a 0.75 ratio, which is a useful initial reference rather than an obligation.

Pay before applying health. Clamp to remaining damage and recheck target existence/range/army. Prefer an audited native economy event or a dedicated repair consumer whose fulfilled resource fraction controls delivered healing. Prototype resource allocation before selecting the final mechanism: calling `SetHealth` and merely declaring a mass rate would allow free repair during a stall. Keep repair drain separate from shield maintenance and module installation so those systems cannot overwrite each other. Cancel/reconcile pending payments on target death, capture, full repair, or range loss.

### Range, Power and Regen

Compute all effective stats from immutable base stats plus the validated loadout. Never repeatedly multiply already-modified values. Each separately installed level contributes its configured incremental bonus. Use bounded bonuses and explicit stacking formulas. Default upkeep model before discounts:

`E = Ebase + sum(completedModuleQuotedEnergyUpkeep) + activeBehaviorEnergyDraw`

Range, Power and Regen level profiles all have positive extra upkeep, so larger area, HP and regeneration always increase pre-discount energy consumption. Their increments and scaling curves are configurable; a module's quote resolves its contribution without charging a second implicit stat surcharge. Preserve ordinary energy adjacency discounts through FAF's consumption system. Repair mass is calculated separately. UI shows base, module contribution, custom neighbor modifier, native adjacency modifier and actual draw.

### Deflector

Intercept crash-collider events at the modular shield. Coverage must include all standard FAF falling aircraft, including the T4 Aeon Czar/UFO, other experimentals, transports and loaded transports; do not inherit FAF's exclusion of large aircraft from physical deflection. Resolve crash damage once, prevent the intercepted wreck from subsequently dealing ground crash damage inside the protected dome, and deflect the falling body away without destroying unrelated reclaim objects. Audit secondary death weapons and transported cargo separately. A crash can damage or collapse the shield, but a successfully intercepted body must not leak its remaining crash damage underneath. Use baseline FAF behavior for shields without the module. Third-party aircraft need adapter coverage when they use custom death paths.

For slow physical projectiles, start with an explicit blueprint/category allowlist. Reflection must disable old target tracking, avoid immediate re-collision loops, preserve attacker attribution, and define whether redirected shots can hurt other units. A safe interception visual can ship before true damaging reflection, but that must be labeled as a reduced feature, not called complete deflection.

### Atomized

At first valid interception, atomically mark the projectile resolved. Disable its normal impact/damage/force outcomes, charge the intercepting shield a configured nuclear hit derived from the projectile's damage data, and create a dome impact/nuclear visual. Do not mutate shared projectile blueprints.

Proposed initial rule: an operational shield contains the entire intercepted blast even if that hit collapses it. Following missiles then pass until the shield recovers. This gives an unambiguous 'nuke hits shield, not buildings' contract. Finite shield HP and expensive recovery remain meaningful; whether an under-strength shield should instead leak a blast is a separate balance choice.

Never globally replace nuclear damage or make ordinary shields nuclear-proof. One missile must resolve once even when several domes overlap. An un-intercepted nuke retains stock behavior, including blast damage to structures covered by an ordinary dome. Nearby detonations outside the dome are not automatically contained by this initial module contract.

### Ballistic

Guarantee interception for the agreed non-strategic missile/rocket families, including explicitly supported shield-piercing exceptions. Keep the strategic classifier separate, so ballistic protection cannot accidentally include nukes. Default projectile behavior remains the fallback. Build a weapon coverage matrix before deciding how much this adds beyond standard FAF shields.

### Legendary Impenetrable

Unlock when Deflector, Atomized and Ballistic are installed; proposed T4-only, consuming one extra slot. It adds ground denial and the broad supported threat policy, while retaining finite shield HP. 'Impenetrable' describes coverage while active, not invulnerability or unlimited protection against arbitrary third-party scripts.

Require a completed same-army energy storage or energy-producing structure in true edge adjacency to the generator. A nearby object somewhere inside the dome is insufficient. Use `OnAdjacentTo`/`OnNotAdjacentTo` and reconcile adjacency on completion, ownership changes and destruction. A storage satisfies adjacency; sufficient army energy must still exist to run the shield.

Express this requirement as a rule in the general neighbor-effects system, rather than hard-coding generator/storage checks in the legendary handler. That system must also support different bonuses from power generators, energy storage, mass storage and custom provider tags, including capped stacking and combinations of neighbor types.

When adjacency is lost, leave the paid legendary module installed but dormant; its ordinary modules continue to function. Remove the ground barrier immediately and show the reason. Restore the legendary only after prerequisites, adjacency and power are valid, with a defined warmup to avoid flickering exploits.

Proposed targeting: deny enemy ground movement; friendly units retain access. Test whether engine obstacles permit that distinction. Ground units already inside at activation are allowed to leave and must not be killed or trapped. Air, naval, submerged units, teleportation and transport drops need explicit policies: the name alone cannot guarantee they are blocked. These remain acceptance decisions before a full 'stops everything' release claim.

## 5. Simulation architecture

Proposed source layout:

```
mod_info.lua
units/<new faction T3/T4 ids>/
lua/ModularShields/Config/
lua/ModularShields/Definitions/
lua/ModularShields/Core/
lua/ModularShields/Services/
lua/ModularShields/Behaviors/
lua/ModularShields/AI/
lua/ModularShields/Adapters/
lua/ModularShields/Extensions/
hook/lua/SimCallbacks.lua
hook/lua/ui/game/<minimal module panel hooks>
```

Definitions contain module IDs, levels, slot cost, prerequisites, allowed chassis, purchase costs, construction work, post-completion upkeep, effect-handler IDs and AI hints. Each level has its own ID and slot. Loadout is the simulation's authoritative state; the UI never decides whether a purchase is valid. The detailed registry, service and neighbor-rule contracts are in MODULAR_CODE_DESIGN.md.

Use the target release's shield creation path to attach a dedicated modular shield class. If that requires a global bridge hook, it must immediately delegate to the original implementation unless the owner is one of our generators. The same restriction applies to projectile adapters. Chain prior hooks and leave global overlap logic intact.

Callbacks must secure actual controllable units and validate requested action, generator type, life/completion state, loadout revision, capacity, prerequisites and payment. A queue can display pending actions, but none grant benefits before completion. Use a monotonic revision to reject stale UI requests. Sort entity processing and use fixed simulation ticks; never use wall-clock time, UI randomness or unsynchronized state for outcomes.

The shield's operational state, effective loadout, repair budget, power use and legendary eligibility feed a single reconciler. Each transition is handled explicitly: install, cancel, remove, upgrade, toggle, energy stall/recovery, damage collapse/recharge, capture, give, kill and destroy. Track all threads, emitters, helper consumers and obstacle entities for cleanup. Audit save/load reconstruction if saves are supported.

The UI reads synchronized state and shows occupied slots, levels, dependencies, effective radius/diameter, current/max HP, regeneration, upkeep, repair mass usage and legendary lock/dormancy reason. It submits requests only. Multiplayer players need identical simulation content; UI work supports the simulation rather than replacing it.

## 6. Ground barrier feasibility gate

Prototype two alternatives before committing:

1. An arc/ring of temporary obstacle entities while legendary protection is active. Test dynamic pathfinding updates, unequal terrain, radius changes, build placement, exits, collision gaps, crush behavior and whether allies can pass. A conventional obstacle may block allies too.
2. A deterministic perimeter crossing detector that returns enemy ground units to their last valid exterior position. This can enforce access in Lua but is an approximation: pathfinding may continually push units into the boundary. It requires swept crossing checks, safe terrain placement, large/fast-unit handling, overlap ordering and anti-jitter rules.

Neither is accepted merely because a single test tank stops. If neither meets the movement contract at acceptable simulation cost, document that limitation and revisit the legendary behavior before implementation continues. Do not silently substitute periodic damage or temporary stun for a true barrier.

Radius growth must not trap units or place obstacles through buildings; shrink and collapse must release everything immediately. Units spawning, teleporting, unloading, or already inside bypass a simple boundary-crossing test and need their own policy/adapters.

## 7. Implementation sequence and acceptance gates

### Phase 0 — release selection and risky prototypes

Select an installed/released FAF target, map its actual imports and shield API, and create a small debug scenario. Verify a custom generator/shield, an ordinary tactical hit and beam hit, crash containment, one nuke containment, and both ground-barrier approaches. Include overlapping domes and low-power states. Outcome: documented feasibility and explicit remaining coverage limits.

### Phase 1 — modular foundation

Implement one faction's T3/T4 units, internal slots, cumulative level dependency validation, assisted installation payment/work/cancellation, removal, deterministic stat recomputation, neighbor-rule evaluation and a basic module panel. Add Range, Power and Regen. Acceptance: no free healing, no unpaid modules, no slot overflow through queued clicks, no reset of collapse/recharge timers, correct economy display and footprint-safe T3-to-T4 transfer. Power I-IV fills T3; Power V is rejected. Engineer assistance accelerates paid progress without switching the shield off, and completed modules continue to work during installation. Introduce the common AI planning API now, not after gameplay is finished.

### Phase 2 — repair economy

Add bounded repair scheduling and paid delivered healing. Acceptance: mass tracks actual restored HP for differently priced structures; full-health targets cost no repair mass; starvation slows/stops repair; target death/army/range changes cleanly stop the work. Multiple generators must not overspend or heal past maximum.

### Phase 3 — interception

Add Deflector, Ballistic and Atomized through shared classification and once-only impact resolution. Cover each standard faction's applicable projectile families and every standard FAF aircraft crash, explicitly including the Czar/UFO. Acceptance: physical deflection and no remaining crash damage under the dome, no hidden blast/force/DoT leakage, no double-hit on overlaps, no accidental friendly interception, normal shields and un-intercepted weapons behave normally.

### Phase 4 — legendary

Add prerequisite checks, paid installation, adjacency state, activation/warmup, and the ground mechanism proven in Phase 0. Acceptance: provider construction/death/capture changes eligibility correctly; lost power or collapsed dome removes the barrier immediately; pre-existing units can exit; covered threats obey the published contract.

### Phase 5 — factions, integration and release

Finish four-faction presentation/build access, adaptive AI planners/adapters and UI polish. AI uses the same paid install/assist API, preserves army-building budgets, chooses different roles from observed threats, and considers adjacency providers. Test with other mods one at a time, starting with PJ Smart Shields and common weapon packs. Add adapters only where warranted. Preserve licenses, make a standalone package, run replay/desync checks and benchmark representative late-game loads. Nomads support follows as an optional integration.

## 8. Validation required before release

- Pure logic checks: registry/schema errors, dependency graph validity, cumulative slot accounting, purchase/remove/cancel sequences, clamped HP, stat recomputation, neighbor stacking/caps and upkeep monotonicity before neighbor discounts.
- In-game combat scenarios: beams, direct fire, artillery, tactical/shield-piercing missiles, each standard nuke family, shield collapse on interception, experimental/transport crashes, crashes originating inside the dome, overlap and friendly/neutral ownership.
- Economy/lifecycle: mass starvation, energy stall, damaged capacity installation, range shrink during repair, pending job cancellation, capture/give/reclaim, provider loss and generator death. Verify assistants deliver work once, pay normal construction costs, leave shields operational, and release/retarget correctly after completion or cancellation.
- AI: stock AI builds/fits/assists shields through normal economy and ownership rules; role changes use known threats; upkeep forecasts preserve army production; provider construction has a budget; cancellation/reconfiguration does not oscillate; selected custom AI adapters do not issue duplicate jobs or steal busy engineers.
- Movement: groups, fast and large units, slope/water edges, mixed allied/enemy traffic, overlapping barriers, activation around existing units, radius changes, transport/teleport policy and repeated path commands.
- Multiplayer: two-client synchronized play, replay determinism, shared-army commands, repeated callbacks and mass module changes in one tick.
- Performance: measure simulation time with many shields, dense repair targets and projectile-heavy fights. Stagger bounded repair scans; avoid every shield scanning every unit/projectile each tick. Barrier scans require a separate budget and benchmark.

This investigation is static source review. No gameplay, multiplayer, balance, or performance test has been run, and none of the downloaded implementations should be considered proven merely because their code advertises a feature.

## Primary upstream references

- [Pinned FAF shield implementation](https://github.com/FAForever/fa/blob/ed82c657b30650a139c7ff6ee064f063184dfe66/lua/shield.lua)
- [Pinned projectile damage implementation](https://github.com/FAForever/fa/blob/ed82c657b30650a139c7ff6ee064f063184dfe66/lua/sim/Projectile.lua)
- [Pinned crash shield collider](https://github.com/FAForever/fa/blob/ed82c657b30650a139c7ff6ee064f063184dfe66/projectiles/ShieldCollider/ShieldCollider_script.lua)
- [Pinned nuclear projectile](https://github.com/FAForever/fa/blob/ed82c657b30650a139c7ff6ee064f063184dfe66/lua/sim/projectiles/NukeProjectile.lua)
- [Pinned nuclear damage area](https://github.com/FAForever/fa/blob/ed82c657b30650a139c7ff6ee064f063184dfe66/lua/sim/DamageArea.lua)
- [Pinned structure adjacency](https://github.com/FAForever/fa/blob/ed82c657b30650a139c7ff6ee064f063184dfe66/lua/sim/units/StructureUnit.lua)
