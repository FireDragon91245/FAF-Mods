# FAF playtest checklist

Native engine smoke checks now pass for generator creation, real projectile
registration/destruction, native module-button construction/handler dispatch and
resource-paid installation progress. An engine frame export also shows the test
enemy ground model rendering. Full interactive combat/playtesting is still pending.
All built-in features are implemented and enabled.
Version 7 also passed native engine checks for sustained engineer assistance and
beams, live paid progress/native construction bar, completion/release, queue reuse
and cancellation of dependent jobs with UI synchronization. These used an isolated
diagnostic replay with a shortened quote; they do not establish multiplayer replay
determinism. Temporary diagnostic hooks are excluded from the installed build.
Record FAF release, map, other mods, replay path, logs and measured results here.
AI compatibility means identical behavior against AI/player units and weapons;
AI shield construction/planning is outside the requested scope.

## First pass: construction and fitting

1. Enable only Modular Shields (playtest). Build/spawn all eight faction chassis.
   Verify models, shield animations, faction icons, build access and bottom-center dock positioning.
2. Damage a dome and fit Power I. Current HP must not jump. Range must resize both
   mesh and collision. Regen must heal after the normal damage delay.
3. Queue Power I-IV on T3; V must be refused. Removing I while II remains must name
   the dependent. Remove descending levels; verify slots, clamped HP and upkeep.
4. Left-click upgrade images; right-click pending images to cancel or equipped images
   to queue a five-second base removal. Verify modules retain benefits/slots until
   removal completes, cancellation retains the module and prerequisite locks apply.
   Install with zero, one and several guarding engineers. Engineers contributing to
   module work show continuous build beams and remain counted throughout the job;
   their build arms are extended without a disabled icon. Idle guards must not repair
   the shield or draw construction resources. Measure time and total
   mass/energy: assistance accelerates spending without changing the quote. Check
   distant, busy, already paused, reassigned and manually paused engineers.
   Check that guarding engineers retain their orders after each completion.
   Assisting builders must show the same native progress bar as the generator.
   Add a builder midway, stall resources, then cancel or reassign it: its bar
   should start at current paid progress, stop during stalls and clear on leaving.
5. Pause/resume, cancel/requeue, and stall mass/energy at partial progress. Existing
   shields/modules must keep working subject to normal power rules. No free effects,
   double work or refunds. Confirm maintenance changes in the economy display.
   Watch the live percentage and native construction bar with the side panel open
   and closed. Cancel a queue with dependent jobs, then complete a new job: no old
   percentage or cancel-button label should remain. Hover equipped/available icons during the job; test right-click cancel and timed removal.
6. Test repair on differently priced structures, foundations, full-health targets,
   other-army allies, overlapping auras and empty mass storage. Verify the shared HP
   budget, mass spent per delivered HP and target/range/death cleanup.

## Second pass: protection

1. Shoot normal direct fire, beams, artillery and tactical missiles at an ordinary
   shield and a modular shield. Check hostile AI and human ownership in both directions.
2. Fit Ballistic and test every relevant family in WEAPON_COVERAGE.csv, particularly
   Cybran split missiles and native shield-skipping paths. Unintercepted weapons must
   retain their original split/damage behavior; friendly missiles must pass normally.
3. Fit Atomized. Test all standard land/sub-launched nukes, UEF tactical nuke and
   Seraphim experimental missile. Watch for the visual explosion/ripple and record
   shield damage. Buildings below must take no damage from an intercepted missile.
   Repeat with insufficient shield HP, overlapping domes and a following missile.
   Check no hidden force/DoT/split damage. Detonations outside the dome remain normal.
4. Fit Deflector. Crash small planes, gunships, transports, loaded transports,
   Soul Ripper, Ahwassa and explicitly the Czar onto the dome. Verify physical body
   motion outward/upward, a small first shield hit and no later ground damage beneath
   it. Repeated landings on shields must break up on the third separated impact,
   showing a visual-only explosion and a larger shield hit. Test slopes, overlapping
   fields, crashes starting inside, and shield collapse on the first bounce.
5. Fire the configured slow physical projectiles and watch reflection. Tracking must
   stop, repeated same-contact hits must not drain the shield, and original attacker
   attribution/ordinary damage rules must remain intact.

## Third pass: legendary and upgrades

1. On T4 fit the three special prerequisites, add true edge-adjacent completed power
   then install Impenetrable. T1 power and storage must not qualify. A nearby object without actual edge
   adjacency and another army's provider must not qualify.
   Check the panel's qualified-power count with T2/T3 power; storage must be excluded,
   including cheat-spawned providers and providers built before/after the shield.
2. Watch three-second activation warmup. Remove/capture/destroy support, empty power,
   toggle/collapse the shield and restore each condition. Paid legendary remains
   installed/dormant and requires a new warmup before reactivation.
3. Drive enemy AI/human units at it: groups, scouts, large experimentals, amphibious
   units, sloped terrain, cluttered boundaries and overlapping shields. Check safe
   exterior placement and simulation cost. Friends must pass. Units originally inside
   can leave and cannot re-enter. Test radius changes, teleport and transport arrivals.
4. Upgrade a damaged, fitted T3 to T4, including a partially paid module job. Verify
   IDs/quotes/progress, absolute HP, toggle, regeneration/recharge delay and resumed
   module work. Cancel a chassis upgrade and check T3 resumes its job. Reclaim both
   chassis and wrecks and check occupancy-grid cleanup.
5. Give/capture fitted generators, including stalled jobs. Completed equipment and
   shield state transfer; unfinished jobs cancel and claimed engineers release.

## Final pass

Run a two-client match and replay, rapid repeated callbacks, dense shield overlaps
and a projectile-heavy late-game scenario. Record desyncs, unit counts, simulation
speed, mass/energy totals and visual issues. Then add PJ Smart Shields and weapon
mods one at a time. Do not claim compatibility or balance before recording results.

## Version 11 balance and source breakdown

- Compare 800 and 2000 E/s neighboring generators: expect +8 and +20 non-combat
  HP/s. Verify ordinary native upkeep adjacency still applies.
- Attach energy storage: each adds 10% of chassis base capacity without free healing.
  Attach mass storage: each adds one slot. Fit beyond the base capacity, remove the
  storage and restore it. Paid equipment/progress must survive; unfinished jobs
  wait only when their next installed slot cannot fit. Removals can free capacity.
- Fire repeatedly at a damaged shield with Regen modules. Only module HP/s should
  continue through damage delay. Stop firing: vanilla and neighboring power HP/s
  resume after the normal delay. Verify all six source rows and live total readings.
- Hover Impenetrable: all three prerequisites, T4 and T2+ generator-only adjacency
  must be explicit. Test T1, energy storage, corner contact, unfinished and enemy power.
- Reflect mortars, cluster and heavy artillery from every faction; nuclear shells
  must still use Atomized, and anti-air flak must retain ordinary behavior.
- Send light, heavy and experimental ground units into Impenetrable. Verify weighted
  shield costs, impact visuals, approximately 1.5 seconds of return travel and no
  repeated damage within the per-unit 15-tick cooldown. Collapse stops denial.

## Version 12 storage regression

- Attach six mass storages: expect exactly +6 slots (T3 total 10, T4 total 14).
- Attach six energy storages: expect exactly +60% of chassis base HP, subject to
  the existing cap. Repeated reconciliation must not accumulate extra bonuses.
- Both storage types should show vanilla faction adjacency links. Verify all four
  factions, storage completion, removal/capture, host destruction and upgrading.
  Existing native links should be reused; repeated updates must not duplicate them.
