local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
local function positive(n, label, zero)
    assert(finite(n) and (zero and n >= 0 or n > 0), 'Invalid ' .. label)
end
local function Build(config, packages, load)
    positive(config.InstallRate,'host work rate')
    positive(config.InstallMaxRate,'maximum work rate')
    assert(config.InstallMaxRate>=config.InstallRate,'Maximum work rate below host rate')
    positive(config.InstallSliceSeconds,'work slice')
    positive(config.RepairFactor,'repair mass factor')
    for _,chassis in pairs(config.Chassis) do positive(chassis.Slots,'chassis slots');assert(math.mod(chassis.Slots,1)==0,'Nonintegral slot capacity') end
    for stat,cap in pairs(config.Caps) do positive(cap,stat..' cap') end
    local r = { Modules = {}, Order = {}, Providers = {}, Rules = {} }
    local handlers = { repair = true, deflector = true, atomized = true, ballistic = true, ground_barrier = true }
    local packageIds = {}
    table.sort(packages, function(a,b) if a.Priority == b.Priority then return a.Id < b.Id end return a.Priority < b.Priority end)
    for _, p in ipairs(packages) do
        assert(p.SchemaVersion == 1 and not packageIds[p.Id], 'Invalid/duplicate package ' .. p.Id)
        for _, dep in ipairs(p.Dependencies or {}) do assert(packageIds[dep], 'Missing package dependency ' .. dep) end
        packageIds[p.Id] = true
        for _, d in ipairs(load(p.Modules)) do
            assert(type(d.Id) == 'string' and not r.Modules[d.Id], 'Duplicate module ' .. tostring(d.Id))
            assert(not d.Behavior or handlers[d.Behavior], 'Unknown handler ' .. tostring(d.Behavior))
            positive(d.Slots, d.Id .. ' slots'); assert(math.mod(d.Slots, 1) == 0 and d.MaxInstances == 1, 'Invalid instance contract')
            assert(table.getn(d.Chassis) > 0, 'Missing chassis')
            for _, c in ipairs(d.Chassis) do assert(config.Chassis[c], 'Unknown chassis ' .. c) end
            positive(d.CostFraction or config.LevelCost[d.CostLevel], d.Id .. ' cost', true)
            positive(d.Seconds or config.LevelSeconds[d.SecondsLevel], d.Id .. ' time')
            positive(d.UpkeepFraction, d.Id .. ' upkeep', true)
            for _, e in ipairs(d.Effects) do
                assert(config.Caps[e.Stat] and (e.Op == 'Add' or e.Op == 'AddBaseFraction'), 'Invalid effect ' .. d.Id)
                positive(e.Value, d.Id .. ' effect', true)
            end
            r.Modules[d.Id] = d; r.Order[table.getn(r.Order) + 1] = d.Id
        end
        for _, d in ipairs(load(p.Providers)) do
            assert(not r.Providers[d.Id] and (type(d.Category) == 'string' or d.BlueprintIds or d.AllCategories or d.AnyCategories), 'Invalid provider ' .. d.Id)
            r.Providers[d.Id] = d
        end
        for _, rule in ipairs(load(p.Rules)) do
            assert(rule.Relation == 'EdgeAdjacent' and rule.Ownership == 'SameArmy', 'Unsupported relation')
            positive(rule.Minimum, 'rule threshold')
            assert(math.mod(rule.Minimum,1)==0,'Nonintegral provider threshold')
            if rule.MaximumCount then positive(rule.MaximumCount,'provider cap') end
            if rule.EffectMinimum then assert(finite(rule.EffectMinimum),'Invalid rule minimum') end
            if rule.EffectMaximum then assert(finite(rule.EffectMaximum),'Invalid rule maximum') end
            if rule.EffectMinimum and rule.EffectMaximum then assert(rule.EffectMinimum<=rule.EffectMaximum,'Inverted effect bounds') end
            if rule.Diminishing then positive(rule.Diminishing,'diminishing factor',true);assert(rule.Diminishing<=1,'Invalid diminishing factor') end
            assert(not rule.Stacking or rule.Stacking=='Sum' or rule.Stacking=='Max' or rule.Stacking=='Min' or rule.Stacking=='Exclusive','Invalid stacking operation')
            for _, tag in ipairs(rule.AnyProviderTag or {}) do assert(r.Providers[tag], 'Unknown provider ' .. tag) end
            for _, tag in ipairs(rule.AllProviderTags or {}) do assert(r.Providers[tag], 'Unknown provider ' .. tag) end
            for _, e in ipairs(rule.Effects) do
                assert((e.Capability and type(e.Value) == 'boolean') or
                    (config.Caps[e.Stat] and (e.Op == 'Add' or e.Op == 'AddBaseFraction') and finite(e.Value)), 'Invalid neighbor effect')
            end
            for _, prior in ipairs(r.Rules) do
                assert(prior.Id ~= rule.Id, 'Duplicate rule ' .. rule.Id)
                if rule.StackingGroup and rule.StackingGroup==prior.StackingGroup then
                    assert(rule.Stacking==prior.Stacking and rule.EffectMinimum==prior.EffectMinimum and rule.EffectMaximum==prior.EffectMaximum,'Conflicting stacking group '..rule.StackingGroup)
                end
            end
            r.Rules[table.getn(r.Rules) + 1] = rule
        end
    end
    local visiting, visited = {}, {}
    local function visit(id)
        assert(r.Modules[id], 'Missing module ' .. id)
        assert(not visiting[id], 'Prerequisite cycle ' .. id)
        if visited[id] then return end
        visiting[id] = true
        for _, dep in ipairs((r.Modules[id].Requires or {}).AllModules or {}) do visit(dep) end
        for _, dep in ipairs((r.Modules[id].Requires or {}).AnyModules or {}) do visit(dep) end
        for _, dep in ipairs((r.Modules[id].Requires or {}).Excludes or {}) do assert(r.Modules[dep],'Missing exclusion '..dep) end
        visiting[id] = nil; visited[id] = true
    end
    table.sort(r.Order)
    for _, id in ipairs(r.Order) do visit(id) end
    for _,rule in ipairs(r.Rules) do
        for _,id in ipairs(rule.RequiredModules or {}) do assert(r.Modules[id],'Missing neighbor-rule module '..id) end
    end
    table.sort(r.Rules, function(a,b) if a.Priority == b.Priority then return a.Id < b.Id end return a.Priority < b.Priority end)
    return r
end
Export = { Build = Build }

return Export
