local function Calculate(s, registry, config, neighbors)
    local b = s.Base
    local out = { ShieldMaxHP = b.ShieldMaxHP, ShieldSize = b.ShieldSize, ShieldRegen = b.ShieldRegen,
        RepairBudget = 0, EnergyMultiplier=1, RepairMassMultiplier=1,
        BaseUpkeep = b.Upkeep, ModuleUpkeep = 0, Capabilities = {}, Dormant = {} }
    local function effect(e)
        out[e.Stat] = out[e.Stat] + (e.Op == 'AddBaseFraction' and (b[e.Stat] or 1) * e.Value or e.Value)
    end
    -- Stable order prevents floating-point differences from hash traversal.
    for _, id in ipairs(registry.Order) do
        local instance = s.Installed[id]
        if instance then
            local d = registry.Modules[id]
            local reason = config.Enabled[d.Behavior] == false and { Code = 'DisabledBehavior' }
                or nil
            reason = reason or (d.Operating and s.Rules.Requirements(d.Operating, s.Installed, s.Capabilities))
            if reason then out.Dormant[id] = reason.Code
            else
                for _, e in ipairs(d.Effects) do effect(e) end
                if d.Behavior then out.Capabilities[d.Behavior] = true end
                out.ModuleUpkeep = out.ModuleUpkeep + instance.Quote.Upkeep
            end
        end
    end
    for _, e in ipairs(neighbors or {}) do effect(e) end
    for stat, cap in pairs(config.Caps) do
        out[stat] = math.max((config.Floors or {})[stat] or 0, math.min(out[stat], b[stat] and b[stat]*cap or cap))
    end
    out.PreNeighborUpkeep=out.BaseUpkeep+out.ModuleUpkeep
    out.Upkeep = out.PreNeighborUpkeep*out.EnergyMultiplier
    return out
end
Export = { Calculate = Calculate }

return Export
