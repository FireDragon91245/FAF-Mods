-- Shared data: no simulation imports, mutable blueprints or per-client settings.
Export = {
    SchemaVersion = 1,
    Chassis = { t3 = { Slots = 4 }, t4 = { Slots = 8 } },
    Factions = {
        { Name = 'UEF', Base = 'ueb4301', Prefix = 'mdeb' },
        { Name = 'AEON', Base = 'uab4301', Prefix = 'mdab' },
        { Name = 'CYBRAN', Base = 'urb4207', Prefix = 'mdrb' },
        { Name = 'SERAPHIM', Base = 'xsb4301', Prefix = 'mdsb' },
    },
    LevelCost = { .10, .14, .19, .25, .32 },
    LevelSeconds = { 14, 18, 23, 28, 33 },
    InstallRate = 40,
    InstallMaxRate = 10000,
    InstallSliceSeconds = .5,
    RemovalSeconds = 5,
    NeighborScanMargin = 16,
    NeighborEdgeTolerance = .05,
    RepairFactor = .75,
    RepairHPPerSecond = 30,
    RepairTargetLimit = 24,
    Caps = { ShieldMaxHP = 4, ShieldSize = 2, ShieldRegen = 5, RepairBudget = 1000,
        EnergyMultiplier = 2, RepairMassMultiplier = 3, ModuleSlots=64 },
    Floors = { EnergyMultiplier = .1, RepairMassMultiplier = .1 },
    -- Feature switches are match-wide; gameplay validation is recorded separately.
    Enabled = { deflector = true, atomized = true, ballistic = true, ground_barrier = true },
    Crash = { MaxBounces = 3, BounceCooldownTicks = 5, BounceDamageFraction = .1,
        BreakupDamageFraction = .75, BounceMaxHPFraction = .03, BreakupMaxHPFraction = .2,
        MinimumDamage = 10, OutwardSpeed = 9, UpwardSpeed = 5, Clearance = 2, BodyLifetimeSeconds = 30 },
    Barrier = { WarmupTicks = 30, ScanMargin = 32, Clearance = 1, ReturnSeconds=1.5,
        MinimumPush=3, HitCooldownTicks=15, DamagePerMass=.05, MinimumDamage=5 },
    Projectiles = { ReflectionOutwardSpeed = 12, ReflectionCooldownTicks = 5, ReflectArtillery=true,
        BallisticIds = {},
        ReflectIds = { adfrocket01=true,tifartillery01=true,cifartillery01=true,
            sifthunthoartilleryshell01=true,sifthunthoartilleryshell02=true } },
}

return Export
