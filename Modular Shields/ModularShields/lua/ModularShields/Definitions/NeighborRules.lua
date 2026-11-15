Export = {{ Id = 'power_support', Priority = 0, Relation = 'EdgeAdjacent', Ownership = 'SameArmy',
    AnyProviderTag = { 'power_generator', 'energy_storage' }, Minimum = 1,
    Effects = {{ Capability = 'legendary_power_support', Value = true }} }}

return Export
