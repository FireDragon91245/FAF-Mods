local function Snapshot(host, registry)
    local facts = {}
    for id, neighbor in pairs(host.AdjacentUnits or {}) do
        if not neighbor.Dead and not IsDestroyed(neighbor) then
            local bp, tags = neighbor.Blueprint, {}
            for tag, definition in pairs(registry.Providers) do
                local matches=not definition.Category or bp.CategoriesHash[definition.Category]
                if definition.BlueprintIds then matches=definition.BlueprintIds[bp.BlueprintId] or false end
                for _,category in ipairs(definition.AllCategories or {}) do matches=matches and bp.CategoriesHash[category] end
                if definition.AnyCategories then
                    local found=false
                    for _,category in ipairs(definition.AnyCategories) do if bp.CategoriesHash[category] then found=true end end
                    matches=matches and found
                end
                if matches and (not definition.PositiveEnergyProduction or (bp.Economy.ProductionPerSecondEnergy or 0) > 0) then
                    tags[tag] = true
                end
            end
            facts[table.getn(facts)+1] = { Id = id, Tags = tags, EdgeAdjacent = true,
                SameArmy = neighbor.Army == host.Army, Completed = neighbor:GetFractionComplete() == 1,
                Tier=bp.CategoriesHash.EXPERIMENTAL and 't4' or bp.CategoriesHash.TECH3 and 't3' or bp.CategoriesHash.TECH2 and 't2' or 't1' }
        end
    end
    table.sort(facts, function(a,b) return a.Id < b.Id end)
    return facts
end
Export = { Snapshot = Snapshot }

return Export
