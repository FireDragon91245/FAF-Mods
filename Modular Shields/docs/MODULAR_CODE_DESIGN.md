# Modular Shields: configurable code design

Implementation update: the playtest build is in [README](../README.md). The user clarified that AI support means identical shield behavior against AI and player attackers; AI construction/loadout planning is outside scope. The user authorized implementing the remaining mechanics before in-game playtesting. The earlier proposal and acceptance criteria below are retained as design history.

This is the code design for subsequent implementation, not a working mod. It refines SHIELD_MOD_PLAN.md with the user's cumulative slot rule, engineer-assisted installation, extensible neighbor effects and AI support.

## 1. Core rules and ownership

The generator owns a loadout of individually installed module IDs. `power_1`, `power_2`, and `power_3` are three installed objects using three slots. Each depends on the preceding ID. All three contribute incremental bonuses and recurring costs. No level replaces another or grants a whole cumulative bonus on top of earlier cumulative bonuses.

Initial capacities remain configurable at T3=4 and T4=8. For example, `power_1, power_2, range_1, repair_1` fills T3. Power III needs another free slot. Power V requires five slots for Power I-V and therefore cannot fit T3. A T4 with Power I-V has three slots left for all other purposes. Duplicate installation of the same ID is forbidden unless a future definition explicitly allows instances.

Keep these responsibilities separate:

- **Definitions:** what units/modules/rules exist and their tunable values.
- **Pure rules:** what is eligible, what fits, what it costs, and the resulting stats/capabilities.
- **Simulation services:** payment, work, repairs, collision outcomes and lifecycle transitions.
- **FAF adapters:** native shield creation, native construction/assistance, adjacency events and AI integration.
- **UI and AI clients:** request actions through the same validated service; neither mutates the loadout.

Only one stat reconciler writes effective shield stats. Only one economy service owns each consumption channel. Neighbor rules and individual behavior handlers do not overwrite energy maintenance themselves.

## 2. Configuration and extension packages

Use explicit manifests rather than filesystem scanning or alphabetical hook order:

```
lua/ModularShields/
    Bootstrap.lua
    Config/{Chassis,Balance,Installation,AI,Performance}.lua
    Definitions/{Manifest,Modules,NeighborProviders,NeighborRules}.lua
    Core/{Registry,Validate,Loadout,Requirements,Stats,RuleEvaluator}.lua
    Services/{Generator,InstallJobs,Economy,Neighbors,Reconcile,Sync}.lua
    Behaviors/{Repair,Deflector,Atomized,Ballistic,GroundBarrier}.lua
    AI/{Planner,Scoring,Budget,Placement,Threats,AssistPolicy}.lua
    Adapters/{Shield,Construction,Adjacency,Projectiles,StockAI}.lua
    Extensions/<package name>/{Manifest,Definitions,Handlers}.lua
```

Blueprint loading and simulation consume the same validated definitions using the appropriate loader in each environment. They must not independently guess costs, work or module IDs. UI consumes a presentation projection or synchronized summaries; it does not import simulation-only code to calculate eligibility.

At load time collect manifests, reject duplicate IDs and unknown handlers, validate schemas, and freeze the registry for the match. Sort packages/definitions by explicit priority and ID. Require supported schema versions and declared dependencies. Reject prerequisite cycles, missing references, non-finite/negative costs, invalid work/slot counts, ambiguous stat operations and invalid provider predicates with a useful error. Configuration is fixed for all clients before the match; no runtime hot reload or client-specific settings affecting simulation.

Balance overrides refer to stable definition IDs. Reject conflicting overrides without an explicit precedence rule; do not silently accept whichever mod happens to load last. Restrict custom stat effects to registered, bounded fields. Changing generator capacity downward during a live game is unsupported.

## 3. Module definition contract

Illustrative Lua data, not an already available FAF API:

```lua
return {
    Id = 'power_2',
    Family = 'power',
    Level = 2,
    Slots = 1,
    MaxInstances = 1,
    Chassis = { 't3', 't4' },
    Requires = { AllModules = { 'power_1' } },
    Cost = { Profile = 'stat_level_2' },
    Build = { Profile = 'normal_level_2' },
    Effects = {
        { Stat = 'ShieldMaxHP', Op = 'AddBaseFraction', Value = 0.25 },
    },
    Upkeep = { EnergyBaseFraction = 0.10 },
    AI = {
        Roles = { 'frontline', 'artillery_defense' },
        UtilityTags = { 'capacity' },
        Priority = 50,
    },
    UI = { NameKey = 'module_power_2', Icon = 'power_2' },
}
```

The preceding Power I is retained and contributes its own effects. Percentages refer to the immutable chassis baseline, not the previous recalculated result. Special modules reference `Behavior = 'deflector'` and named policy parameters rather than embedding arbitrary callbacks in every module definition.

Declarative requirements support `AllModules`, `AnyModules`, chassis tags, capabilities, neighbor-rule flags and explicit exclusions. Distinguish **purchase requirements** from **operating requirements**. Legendary module prerequisites must be installed to purchase it; adjacent power support is required at purchase and while operating. Losing that support makes it dormant without deleting its paid slot. Temporary dormancy does not free slots.

UI eligibility returns structured reason codes such as `MissingModule`, `NoFreeSlot`, `InstallBusy` or `MissingAdjacentPower`. A boolean alone is insufficient for UI and AI explanations.

### Adding a module

For an existing effect, add its definition, costs/work profile, localization/icon and AI hints to a registered package. No edits to generator, UI or AI decision branches should be needed. If it introduces a new behavior, add one handler and register its ID as well.

Handler interface:

```
ValidateParameters(definition) -> errors
DescribeEffects(context) -> stat modifiers, capabilities, runtime requirements
OnActivate(context, instance)
OnDeactivate(context, instance, reason)
OnEvent(context, instance, event)
Dispose(context, instance)
```

Handlers get narrow service access (repair scheduler, threat resolver, visuals), not permission to charge arbitrary costs or alter shared blueprints. Pure description/evaluation never changes world state. Activation/deactivation are idempotent, never yield mid-transaction, and clean up their own work. Interception handlers submit a proposed resolution to the common resolver; they never each apply damage to the same projectile.

## 4. Neighbor system: providers, predicates and effects

Store neighbors as entity-ID keyed records. FAF adjacency events drive updates, with bounded reconciliation after completion, capture, give or destruction. Default relation is completed same-army structures with actual edge adjacency. Distance-based auras are a separate configurable relation and must not accidentally count as adjacency.

Provider classification is configurable. Built-in tags cover `power_generator`, `energy_storage`, and `mass_storage`; extension manifests can add blueprint IDs, category predicates or custom tags. Match real blueprint categories and validated resource-production fields through the FAF adapter. Do not assume every unit with an ENERGY-related category produces energy. A unit can match several tags; provider identity still counts once in each distinct-provider predicate.

Illustrative rule data:

```lua
return {
    Id = 'power_support',
    Relation = 'EdgeAdjacent',
    Ownership = 'SameArmy',
    Match = { AnyProviderTag = { 'power_generator', 'energy_storage' } },
    Count = { Mode = 'DistinctProviders', Minimum = 1 },
    Effects = { { Capability = 'legendary_power_support', Value = true } },
}
```

Independent rules can give generators an upkeep discount, energy storage a recovery benefit, and mass storage a repair-efficiency benefit. These are extension examples, **not default balance bonuses**. They illustrate why neighbor rules must not live inside the legendary module handler.

Rules support per-provider contributions, thresholds, `Any`/`All` neighbor-type combinations, tier filters, required modules, capped counts, diminishing returns and mutually exclusive groups. For a combination requiring separate physical neighbors, specify `RequireDistinctProviders = true`: a single modded structure tagged as both generator and storage must not masquerade as two structures.

Each rule declares a stacking group, operation, cap, priority and stable ID. Evaluation uses a snapshot of native provider facts plus base/module stats. A rule cannot read another rule's just-modified output or dynamically produce a provider tag, avoiding feedback loops between neighboring shields. Newly needed complex logic becomes a registered pure predicate with declared inputs, not an unbounded callback in a scan loop.

Recompute outputs in this order:

1. Immutable chassis baseline.
2. Sum incremental effects of completed, active module instances.
3. Evaluate neighbor conditions from the snapshot; collect modifiers and capability gates.
4. Resolve explicit stacking groups, caps and final safety limits.
5. Calculate module maintenance and behavior budgets.
6. Apply custom neighbor economy modifiers once, then normal FAF economy adjacency modifiers once through the adapter.
7. Commit effective stats/capabilities atomically and synchronize the breakdown.

Repair-efficiency neighbor rules can alter the mass-per-HP coefficient, with a positive configured floor. Native and custom adjacency discounts must be labeled separately to avoid accidental double discounts. Mandatory support-provider loss bypasses debounce and deactivates the legendary immediately; cosmetic refreshes can be batched.

## 5. Installation: finite work, normal resources, engineer assistance

Every module has total mass/energy cost and construction work. These are ordinary purchase costs spent over its construction, not an instant charge followed by free progress. Extra recurring upkeep and the new effect begin in the same completion transaction. Existing modules keep their upkeep and benefits while another is being fitted.

An installation job has:

```
JobId, HostId, ModuleId, SlotReservation, State,
TotalWork, PaidWork, MassSpent, EnergySpent,
AssistantIds, QuoteVersion, LoadoutRevision
```

States: `Queued -> Building <-> Paused -> Completed`, with `Cancelled` from any unfinished state. Economy starvation can stall building without cancelling it. One active job per generator; queued jobs reserve slots and track pending prerequisites. Power II may queue behind Power I but cannot start or complete on the strength of an unfinished prerequisite. Removing/cancelling prerequisites invalidates dependent queued jobs and releases their reservations without applying effects.

Preferred backend: a native assisted construction project owned by the generator, represented by an internal work target. It uses engine resource fulfillment and construction progress. An adapter directs engineers guarding the generator to that target during installation and restores normal shield assistance afterward. The internal target is not a neighbor, reclaimable bonus source, capturable module or extra combat object. Its usable construction/focus/placement behavior must be proven on the supported FAF release; do not presume a hidden target automatically supports native assistance.

If that backend cannot preserve these rules, a separate economy-event/work backend must implement the same interface and pass the same tests before use. Never count engineer build rate in a script while native construction is also counting it. Engineers must be alive, controllable, in normal assist range and actually assigned. Busy engineers do not contribute merely because they stand near a shield. No remote assistance or duplicate contribution to shield repair and module work in the same interval.

`workRate = hostInstallBuildRate + sum(validAssistantBuildRates)` subject to normal economy fulfillment. Assistance increases resource draw as it increases speed, without changing total cost. Use a host work-rate floor/ceiling and configured work profiles to keep unassisted times short. Initial full-economy tuning target: roughly 12-20 seconds for early stat levels, 20-35 seconds for later levels and 30-45 seconds for special/legendary modules. These are targets, not validated balance. A small work threshold limits one-tick completion; it must not impose a long artificial delay on paid engineer assistance.

Pause affects the install job, not the dome toggle. Installing never destroys/recreates the shield, resets damage timers, suspends existing repair behavior, or enters the chassis-upgrade state. Ordinary energy starvation can still collapse the shield; installation gets no immunity or free shield upkeep. Expose separate install/repair/shield power controls so players and AI can pause discretionary work to preserve protection.

On completion, verify payment, slot ownership and requirements again, then commit once. Stats preserve absolute HP. Cancellation releases slots/assistants; already consumed resources are not refunded initially, and unused reserved resources are released. Re-queuing cannot convert partial payment into a free module. Host death/capture cancels unfinished work; completed modules transfer with the chassis under the game's ownership rules. A normal give may preserve an unfinished job only if the native backend transfers its economy safely; otherwise cancel consistently and disclose it.

## 6. Balance configuration

Separate purchase cost, construction work and recurring operation. Use named cost profiles keyed to a stable faction/chassis baseline resolved at match start. A module quote is fixed for that job. A completed module keeps its quoted operating coefficients across T3-to-T4 transfer, avoiding silent repricing; new T4 installations use T4 quotes. Effects can use the new chassis baseline after an upgrade. These rules must be explicit in UI and saved state.

Initial cost-profile tuning proposal for incremental stat levels I-V: 10%, 14%, 19%, 25%, 32% of the resolved chassis mass cost, with separately tunable energy fractions. Each level adds only its own configured bonus. Spending more slots on one family increases specialization and total investment; it does not multiply compounded stats. Special module prices and upkeep have separate profiles and need combat testing, especially nuclear protection.

Configure per-family bonuses, caps, level costs, upkeep, repair budgets, energy-shortage priority and AI reserves independently. Do not expose an unused cost formula: UI quotes, native construction blueprints/jobs and AI estimates must read the same resolved quote. Parameter validation enforces finite costs, finite stat caps, nonzero work, and positive repair mass cost unless an explicit free-repair game mode is enabled.

No claim of 'balanced' until practical comparisons establish counterplay: mass spent on a shield loadout must compete with weapons, anti-nukes, power infrastructure and army production. Measure cost plus sustained upkeep and downtime, rather than purchase price alone. Early defaults are playtest inputs.

## 7. AI as a first-class client

Provide simulation APIs used by both human callbacks and AI adapters:

```
ListEligibleModules(generator) -> candidates and locked reasons
QuoteInstall(generator, moduleId) -> costs, work, future upkeep, slot use
PreviewLoadout(generator, installedIds) -> effective stats and capabilities
RequestInstall(generator, moduleId, source) -> job or reason
RequestCancel(generator, jobId, source)
RequestRemove(generator, instanceId, source)
DescribeNeighborNeeds(generator) -> provider requirements and opportunities
```

Security validation stays on human callbacks; AI access is bound to its own brain. Both use identical eligibility, construction payment, assistant work and upkeep logic. Helpers must not accidentally reuse UI-only state.

The planner scores roles rather than copying one maximal loadout everywhere: frontline durability, broad base coverage, repair support, observed air-crash danger, known missile pressure and late-game strategic protection. Use the AI's ordinary scouted intel and remembered threats; do not query hidden enemy weapons to pick a perfect counter. Profiles vary preferences with deterministic simulation randomness, without granting additional resources or vision beyond the selected AI mode.

Budget forecast includes active install drains across the army, future module upkeep, expected repair demand, provider cost/upkeep and a safety reserve for current shields/army production. Reserve budget before issuing jobs. Limit concurrent upgrades, pause optional installs during shortages, and plan power before choosing a costly loadout. Retain useful existing modules; respec only after a meaningful score improvement and cooldown because removals destroy investment.

Plan dependencies with total slot/cost accounting before starting a chain. Save room for prerequisite modules and the legendary's own slot when pursuing that role. For neighbor bonuses, evaluate the cost/benefit of constructing the required provider on a valid adjacent footprint. Do not clutter every shield with every storage type or block engineers' routes. Placement must leave room for needed providers and respect the ground-barrier design.

Engineer assistance uses idle/available builders through the AI's own platoon manager with configurable count and spending limits. Do not steal engineers from urgent defense or production. Release assignments on completion/cancel and periodically reconcile dead/out-of-range assistants.

A stock-AI adapter provides build access, placement and the periodic planner. Custom AIs opt into a registered adapter; one controller owns each generator/job. The baseline planner and M27 or another custom AI must not issue competing commands. Compatibility with a custom AI is a tested integration, not inferred from normal build categories. Unsupported planners can still interact through normal units/commands without a claim of full tactical support.

Fighting the AI also requires counterplay: shield concentration can be met by artillery/anti-shield attacks, attacks from another direction, provider destruction or waiting for collapse. A movement barrier must not cause supported enemy AI to feed tanks endlessly into it. Expose active barrier boundaries/capabilities through simulation-side adapter queries with normal intel restrictions, and let compatible AI retarget or choose ranged attacks. Do not secretly command all enemy AI units from the shield code.

## 8. Deflection requirement: includes the Czar/UFO

The acceptance contract includes all standard FAF crashing aircraft regardless of tier, including the Czar/UFO. Do not preserve the stock crash collider's experimental/transport bounce exclusions on our Deflector shields. Physical body deflection and damage containment are separate checks; a harmless disappearing Czar is not completion of the requested physical deflection.

The installed `units.nx2` source for `UAA0310` confirms a custom `OnKilled` path involving its external factory component and `AirTransport.OnKilled`, plus a `DeathImpact` crash weapon in its blueprint. Test that full path rather than assuming the generic collider hook alone covers it. Recheck against the selected supported FAF release.

Register crash adapters by engine death path and blueprint exceptions. Audit death weapons, crash collision, force effects, debris and carried units. Resolve the intercept once, apply the configured shield hit, deflect the falling body away from the protected interior, and prevent later ground crash damage from the intercepted body leaking under the dome. The guarantee applies to intercepted crashes, including a hit that collapses the shield, rather than deleting every wreck already inside or elsewhere on the map.

Large bodies, slopes, overlapping domes, crashes originating inside a dome and loaded transports require explicit tests. If a special engine path cannot produce safe physical deflection, report that specific incompatibility and keep it as an incomplete release requirement; do not quietly exclude T4 aircraft. Third-party custom aircraft can supply additional crash adapters without modifying module slots, economy or AI planning.

## 9. Verification gates

Before full implementation, prove the native assisted-install backend, Czar deflection/containment, nuke containment and ground-barrier feasibility. Then test the contracts independently:

- Installing Power I-IV uses four slots; V cannot queue into T3; removing I while II exists is rejected; pending slots cannot be double-booked.
- New stat module and new mass-storage neighbor rule require no edits to the central generator, UI decision logic or AI planner.
- A module has no benefit or extra running cost at 99% construction; both appear once at completion. One/multiple engineers accelerate paid work and the live shield continues absorbing hits/regenerating.
- Cancels, pauses, depleted resources and ownership changes neither duplicate work nor grant free effects/refunds. Shield repair and module assistance never count one builder twice.
- Different neighbor types, mixed providers, capped stacking and provider loss produce deterministic outputs; legendary support loss deactivates immediately.
- AI builds useful varied loadouts, pays all costs, reserves prerequisite slots, builds valid providers, assists jobs and preserves enough economy for an army. Fixed-seed matches/replays remain deterministic.
- T4 UFO and other aircraft are physically deflected; subsequent crash/death effects do not damage buildings beneath the intercepted dome. Run actual game scenarios, not only mocked unit calls.

Record measured install times, costs, upkeep, AI spending and simulation overhead during playtests. Configurability makes iteration inexpensive; it does not replace empirical validation.
