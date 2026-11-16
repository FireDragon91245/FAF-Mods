local function Skirt(unit)
    local x0,z0,x1,z1=unit:GetSkirtRect()
    if not (x0 and z0 and x1 and z1) then return nil end
    return {x0,z0,x1,z1}
end

local function EdgeAdjacent(a,b,tolerance)
    local overlapX=math.min(a[3],b[3])-math.max(a[1],b[1])
    local overlapZ=math.min(a[4],b[4])-math.max(a[2],b[2])
    local touchesX=math.abs(a[3]-b[1])<=tolerance or math.abs(b[3]-a[1])<=tolerance
    local touchesZ=math.abs(a[4]-b[2])<=tolerance or math.abs(b[4]-a[2])<=tolerance
    return (touchesX and overlapZ>tolerance) or (touchesZ and overlapX>tolerance)
end

local function Tags(bp,registry,production)
    local tags={}
    local categories=bp.CategoriesHash or {}
    for tag,definition in pairs(registry.Providers) do
        local matches=not definition.Category or categories[definition.Category]
        if definition.BlueprintIds then matches=definition.BlueprintIds[bp.BlueprintId] or false end
        for _,category in ipairs(definition.AllCategories or {}) do matches=matches and categories[category] end
        if definition.AnyCategories then
            local found=false
            for _,category in ipairs(definition.AnyCategories) do if categories[category] then found=true end end
            matches=matches and found
        end
        if matches and (not definition.PositiveEnergyProduction or (production or ((bp.Economy or {}).ProductionPerSecondEnergy or 0))>0) then
            tags[tag]=true
        end
    end
    return tags
end

local function Snapshot(host,registry,config,excluded)
    config=config or {}
    local bounds=Skirt(host)
    local candidates={}
    -- Preserve event-driven candidates, including very large custom providers.
    for id,neighbor in pairs(host.AdjacentUnits or {}) do candidates[id]=neighbor end
    -- Native events can arrive before construction completes, and cheat-spawned
    -- structures can miss the completed-neighbor event. Reconcile physical edges.
    if bounds then
        local margin=config.NeighborScanMargin or 16
        local nearby=GetUnitsInRect(bounds[1]-margin,bounds[2]-margin,bounds[3]+margin,bounds[4]+margin) or {}
        for _,neighbor in ipairs(nearby) do
            if neighbor~=host and not neighbor.Dead and not IsDestroyed(neighbor) then
                local id=neighbor.EntityId or neighbor:GetEntityId()
                if id then candidates[id]=neighbor end
            end
        end
    end
    local facts={}
    for id,neighbor in pairs(candidates) do
        if neighbor~=host and neighbor~=excluded and not neighbor.Dead and not IsDestroyed(neighbor) then
            local bp=neighbor.Blueprint
            if (bp.CategoriesHash or {}).STRUCTURE then
                local skirt=Skirt(neighbor)
                if bounds and skirt and EdgeAdjacent(bounds,skirt,config.NeighborEdgeTolerance or .05) then
                    local cats=bp.CategoriesHash or {}
                    local production=(bp.Economy or {}).ProductionPerSecondEnergy or 0
                    if neighbor.GetProductionPerSecondEnergy then production=neighbor:GetProductionPerSecondEnergy() end
                    facts[table.getn(facts)+1]={Id=id,Unit=neighbor,Tags=Tags(bp,registry,production),EdgeAdjacent=true,EnergyProduction=math.max(0,production),
                        SameArmy=neighbor.Army==host.Army,Completed=neighbor:GetFractionComplete()==1,
                        Tier=cats.EXPERIMENTAL and 't4' or cats.TECH3 and 't3' or cats.TECH2 and 't2' or 't1'}
                end
            end
        end
    end
    table.sort(facts,function(a,b) return a.Id<b.Id end)
    return facts
end

Export={Snapshot=Snapshot,EdgeAdjacent=EdgeAdjacent,Tags=Tags}
return Export
