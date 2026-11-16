local definitions = {}
-- Each number is the additional benefit of that particular installed level.
-- HP and shield regeneration double on a T4; range and building repair do not.
local families = {
    { 'power', 'ShieldMaxHP', {1000,2500,5000,10000,20000}, 1, true },
    { 'range', 'ShieldSize', {1,2,3,5,10}, 2 },
    { 'regen', 'ShieldRegen', {10,25,50,100,200}, 1, true },
    { 'repair', 'RepairBudget', {10,20,40,80,160}, 1 },
}
for _, family in ipairs(families) do
    for level = 1, 5 do
        local id = family[1] .. '_' .. level
        definitions[table.getn(definitions) + 1] = {
            Id = id, Family = family[1], Level = level, Slots = 1, MaxInstances = 1,
            Chassis = { 't3', 't4' },
            Requires = { AllModules = level > 1 and { family[1] .. '_' .. (level - 1) } or {} },
            Effects = {{ Stat = family[2], Op = 'Add', Value = family[3][level]*family[4],
                ChassisScale=family[5] and {t3=1,t4=2} or nil }},
            CostLevel = level, SecondsLevel = level, UpkeepLevel = level,
            Behavior = family[1] == 'repair' and 'repair' or nil,
            AI = { Priority = 50 - level }, UI = { Name = family[1] .. ' ' .. level },
        }
    end
end
for _, id in ipairs({ 'deflector', 'atomized', 'ballistic', 'impenetrable' }) do
    local legendary = id == 'impenetrable'
    definitions[table.getn(definitions) + 1] = {
        Id = id, Family = id, Level = 1, Slots = 1, MaxInstances = 1,
        Chassis = legendary and { 't4' } or { 't3', 't4' },
        Requires = legendary and { AllModules = { 'deflector', 'atomized', 'ballistic' },
            Capabilities = { 'legendary_power_support' } } or {},
        Operating = legendary and { Capabilities = { 'legendary_power_support' } } or {},
        Effects = {}, Behavior = legendary and 'ground_barrier' or id,
        CostFraction = legendary and .75 or .4, Seconds = legendary and 45 or 35,
        UpkeepFraction = legendary and .5 or .25,
        AI = { Priority = 30 }, UI = { Name = id },
    }
end
Export = definitions

return Export
