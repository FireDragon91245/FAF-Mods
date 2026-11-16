local function Contains(list,id)
    for _,v in ipairs(list or {}) do if v==id then return true end end
    return false
end
local function Evaluate(registry,facts,installed)
    local caps,groups,order={},{},{}
    local sorted={};for _,f in ipairs(facts) do sorted[table.getn(sorted)+1]=f end
    table.sort(sorted,function(a,b) return a.Id<b.Id end)
    for _,rule in ipairs(registry.Rules) do
        local valid=true
        for _,id in ipairs(rule.RequiredModules or {}) do if not (installed or {})[id] then valid=false end end
        local matches,seen={},{}
        for _,f in ipairs(sorted) do
            if f.Completed and f.SameArmy and f.EdgeAdjacent and not seen[f.Id] and
                (not rule.Tiers or Contains(rule.Tiers,f.Tier)) then
                local found=not rule.AnyProviderTag and not rule.AllProviderTags
                for _,tag in ipairs(rule.AnyProviderTag or {}) do if f.Tags[tag] then found=true end end
                if not rule.AnyProviderTag then
                    for _,tag in ipairs(rule.AllProviderTags or {}) do if f.Tags[tag] then found=true end end
                end
                if found then seen[f.Id]=true;matches[table.getn(matches)+1]=f end
            end
        end
        local required=rule.AllProviderTags or {}
        local function MatchTag(index,used)
            if index>table.getn(required) then return true end
            for _,f in ipairs(matches) do
                if f.Tags[required[index]] and (not rule.RequireDistinctProviders or not used[f.Id]) then
                    used[f.Id]=true
                    if MatchTag(index+1,used) then return true end
                    used[f.Id]=nil
                end
            end
            return false
        end
        local count=table.getn(matches)
        if valid and count>=rule.Minimum and MatchTag(1,{}) then
            count=math.min(count,rule.MaximumCount or count)
            local scale=1
            if rule.PerProvider then
                scale=0
                -- FAF's ^ operator is XOR, unlike stock Lua exponentiation.
                -- Iterative weights work in both runtimes, including diminishing rules.
                local weight=1
                for n=1,count do
                    scale=scale+weight
                    weight=weight*(rule.Diminishing or 1)
                end
            end
            if rule.ScaleBy then
                scale=0
                for n=1,count do scale=scale+math.max(0,matches[n][rule.ScaleBy] or 0) end
            end
            for _,e in ipairs(rule.Effects) do
                if e.Capability then caps[e.Capability]=e.Value
                else
                    local key=(rule.StackingGroup or rule.Id)..':'..e.Stat..':'..e.Op
                    local g=groups[key]
                    local value=e.Value*scale
                    if not g then
                        g={Stat=e.Stat,Op=e.Op,Value=value,Minimum=rule.EffectMinimum,Maximum=rule.EffectMaximum}
                        groups[key]=g;order[table.getn(order)+1]=key
                    elseif rule.Stacking=='Max' then g.Value=math.max(g.Value,value)
                    elseif rule.Stacking=='Min' then g.Value=math.min(g.Value,value)
                    elseif rule.Stacking=='Exclusive' then g.Value=value
                    else g.Value=g.Value+value end
                end
            end
        end
    end
    table.sort(order)
    local effects={}
    for _,key in ipairs(order) do
        local g=groups[key]
        if g.Minimum and g.Value<g.Minimum then g.Value=g.Minimum end
        if g.Maximum and g.Value>g.Maximum then g.Value=g.Maximum end
        effects[table.getn(effects)+1]={Stat=g.Stat,Op=g.Op,Value=g.Value}
    end
    return caps,effects
end
Export={Evaluate=Evaluate}
return Export
