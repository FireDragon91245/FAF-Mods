Export = {
    { Id='power_support',Priority=0,Relation='EdgeAdjacent',Ownership='SameArmy',
      AnyProviderTag={'power_generator'},Tiers={'t2','t3','t4'},Minimum=1,
      Effects={{Capability='legendary_power_support',Value=true}} },
    { Id='power_regeneration',Priority=1,Relation='EdgeAdjacent',Ownership='SameArmy',
      AnyProviderTag={'power_generator'},Minimum=1,ScaleBy='EnergyProduction',
      Effects={{Stat='ShieldRegen',Op='Add',Value=.01}} },
    { Id='storage_capacity',Priority=1,Relation='EdgeAdjacent',Ownership='SameArmy',
      AnyProviderTag={'energy_storage'},Minimum=1,PerProvider=true,
      Effects={{Stat='ShieldMaxHP',Op='AddBaseFraction',Value=.1}} },
    { Id='storage_slots',Priority=1,Relation='EdgeAdjacent',Ownership='SameArmy',
      AnyProviderTag={'mass_storage'},Minimum=1,PerProvider=true,
      Effects={{Stat='ModuleSlots',Op='Add',Value=1}} },
}

return Export
