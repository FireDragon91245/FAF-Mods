local function Calculate(s, registry, config, neighbors)
    local debug=config.Debug or {}
    local b = {}
    for key,value in pairs(s.Base) do b[key]=value end
    b.ShieldMaxHP=b.ShieldMaxHP*(debug.HPMultiplier or 1)
    local out = { ShieldMaxHP = b.ShieldMaxHP, ShieldSize = b.ShieldSize, ShieldRegen = b.ShieldRegen,
        RepairBudget = 0, EnergyMultiplier=1, RepairMassMultiplier=1,
        ModuleSlots=(s.Chassis and config.Chassis[s.Chassis].Slots or 0)+(debug.AdditionalSlots or 0),
        BaseUpkeep = b.Upkeep, ModuleUpkeep = 0, Capabilities = {}, Dormant = {} }
    local function effect(e)
        local value=e.Value*(e.ChassisScale and e.ChassisScale[s.Chassis] or 1)
        out[e.Stat] = out[e.Stat] + (e.Op == 'AddBaseFraction' and (b[e.Stat] or 1) * value or value)
    end
    local function clamp()
        for stat,cap in pairs(config.Caps) do
            local limit=b[stat] and b[stat]*cap or cap
            if stat=='ModuleSlots' then limit=limit+(debug.AdditionalSlots or 0) end
            out[stat]=math.max((config.Floors or {})[stat] or 0,math.min(out[stat],limit))
        end
    end
    -- Storage capacity is known before selecting active equipment. Extra paid
    -- modules remain installed but dormant until their slots return.
    for _,e in ipairs(neighbors or {}) do if e.Stat=='ModuleSlots' then effect(e) end end
    clamp()
    local active,used={},0
    for _,id in ipairs(registry.ActivationOrder or registry.Order) do
        local instance=s.Installed[id]
        if instance then
            local d=registry.Modules[id]
            local reason=config.Enabled[d.Behavior]==false and {Code='DisabledBehavior'} or nil
            reason=reason or (d.Operating and s.Rules.Requirements(d.Operating,s.Installed,s.Capabilities))
            local dependency=s.Rules.Requirements(d.Requires,active,s.Capabilities)
            if dependency then reason=reason or {Code='DependencyInactive'} end
            if not reason and used+d.Slots>out.ModuleSlots then reason={Code='OverCapacity'} end
            if reason then out.Dormant[id]=reason.Code
            else
                active[id]=true;used=used+d.Slots
                for _,e in ipairs(d.Effects) do effect(e) end
                if d.Behavior then out.Capabilities[d.Behavior]=true end
                out.ModuleUpkeep=out.ModuleUpkeep+instance.Quote.Upkeep
            end
        end
    end
    clamp()
    local moduleHP,moduleRegen=out.ShieldMaxHP-b.ShieldMaxHP,out.ShieldRegen-b.ShieldRegen
    for _,e in ipairs(neighbors or {}) do if e.Stat~='ModuleSlots' then effect(e) end end
    clamp()
    out.ShieldRegen=out.ShieldRegen+(debug.AdditionalRegen or 0)
    moduleRegen=moduleRegen+(debug.AdditionalRegen or 0)
    if out.Capabilities.repair then out.RepairBudget=out.RepairBudget+(debug.AdditionalRepair or 0) end
    out.BaseHP=b.ShieldMaxHP;out.ModuleHP=moduleHP;out.NeighborHP=out.ShieldMaxHP-b.ShieldMaxHP-moduleHP
    out.BaseRegen=b.ShieldRegen;out.ModuleRegen=moduleRegen;out.NeighborRegen=out.ShieldRegen-b.ShieldRegen-moduleRegen
    out.PreNeighborUpkeep=out.BaseUpkeep+out.ModuleUpkeep
    out.Upkeep = out.PreNeighborUpkeep*out.EnergyMultiplier
    out.IgnoreResources=debug.IgnoreResources==true
    if out.IgnoreResources then out.Upkeep=0 end
    return out
end
Export = { Calculate = Calculate }

return Export
