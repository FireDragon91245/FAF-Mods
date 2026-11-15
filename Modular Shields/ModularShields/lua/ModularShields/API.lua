-- Simulation-only API. UI receives synchronized summaries instead.
local R = import('/mods/ModularShields/lua/ModularShields/Runtime.lua').Export
local function ListEligibleModules(host)
    local rows = {}
    for _, id in ipairs(R.Registry.Order) do
        rows[table.getn(rows)+1] = { Id = id, Reason = R.Core.Eligible(host.Loadout,id,R.Registry,R.Config,true),
            Quote = host.Loadout.Installed[id] and host.Loadout.Installed[id].Quote or R.Core.Quote(host.Loadout,id,R.Registry,R.Config) }
    end
    return rows
end
local function PreviewLoadout(host, ids)
    local state = R.Core.New(host.Loadout.Chassis,host.Loadout.Base)
    state.Rules, state.Capabilities = R.Core,host.Loadout.Capabilities
    -- Validate full proposed dependency graph in definition order by repeated passes.
    local pending = {}
    for _, id in ipairs(ids) do
        if not R.Registry.Modules[id] then return nil,{Code='UnknownModule',Module=id} end
        if pending[id] then return nil,{Code='AlreadyInstalled',Module=id} end
        pending[id] = true
    end
    for _ = 1,table.getn(ids) do
        local changed = false
        for _, id in ipairs(R.Registry.Order) do
            if pending[id] and not R.Core.Eligible(state,id,R.Registry,R.Config,false) then
                local quote = host.Loadout.Installed[id] and host.Loadout.Installed[id].Quote
                    or R.Core.Quote(state,id,R.Registry,R.Config)
                state.Installed[id] = { Id=id,Quote=quote };pending[id]=nil;changed=true
            end
        end
        if not changed then break end
    end
    for _, id in ipairs(ids) do
        if pending[id] then return nil,R.Core.Eligible(state,id,R.Registry,R.Config,false) end
    end
    local facts=import('/mods/ModularShields/lua/ModularShields/Adapters/Adjacency.lua').Export.Snapshot(host,R.Registry)
    local caps,effects=R.Neighbors.Evaluate(R.Registry,facts,state.Installed)
    state.Capabilities=caps
    return R.Stats.Calculate(state,R.Registry,R.Config,effects)
end
Export = { ListEligibleModules=ListEligibleModules, PreviewLoadout=PreviewLoadout,
    QuoteInstall=function(host,id) return R.Core.Quote(host.Loadout,id,R.Registry,R.Config) end,
    RequestInstall=function(host,id,brain)
        if brain ~= host:GetAIBrain() then return nil,{Code='NotOwner'} end
        return host:RequestModuleInstall(id)
    end,
    RequestCancel=function(host,id,brain) if brain==host:GetAIBrain() then return host:ModuleAction('cancel',id) end end,
    RequestRemove=function(host,id,brain) if brain==host:GetAIBrain() then return host:ModuleAction('remove',id) end end,
    DescribeNeighborNeeds=function(host) return { LegendaryPowerSupport=host.Loadout.Capabilities.legendary_power_support or false } end,
}
return Export
