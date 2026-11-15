local previous = ModBlueprints
local root
for _, mod in pairs(__active_mods or {}) do
    if mod.uid == 'bf55b8d0-2026-4115-9000-000000000001' then root = mod.location end
end
assert(root, 'Modular Shields: missing mod location')
local function load(path)
    local env = setmetatable({}, { __index = _G })
    doscript(root .. '/lua/ModularShields/' .. path,env)
    assert(env.Export, 'Missing export ' .. path)
    return env.Export
end
local R = load('Bootstrap.lua').Build(load)
function ModBlueprints(all)
    previous(all)
    for _, faction in ipairs(R.Config.Factions) do
        local original = assert(all.Unit[faction.Base], 'Missing stock shield ' .. faction.Base)
        for _, tier in ipairs({3,4}) do
            local id = faction.Prefix .. (tier == 3 and '4301' or '4401')
            local placeholder = assert(all.Unit[id], 'Missing placeholder ' .. id)
            local bp = table.deepcopy(original)
            bp.BlueprintId, bp.Source, bp.Mod = id,placeholder.Source,placeholder.Mod
            bp.ScriptModule = string.gsub(placeholder.Source,'_unit%.bp$','_script.lua')
            bp.ScriptClass = string.upper(id)
            bp.Description = 'T' .. tier .. ' Modular Shield'
            bp.General.UnitName = faction.Name .. ' Modular Shield'
            bp.General.UpgradesFrom, bp.General.UpgradesFromBase, bp.General.UpgradesTo = 'none','none',nil
            bp.Economy.BuildableCategory = nil
            bp.Economy.BuildRate = R.Config.InstallRate
            bp.General.CommandCaps = bp.General.CommandCaps or {}
            bp.General.CommandCaps.RULEUCC_Pause = true
            bp.General.CommandCaps.RULEUCC_Stop = true
            if tier == 3 then
                bp.General.UpgradesTo = faction.Prefix .. '4401'
                bp.Economy.BuildableCategory = { faction.Prefix .. '4401' }
            else
                bp.General.UpgradesFrom = faction.Prefix .. '4301'
            end
            bp.Economy.RebuildBonusIds = nil
            bp.Enhancements = nil
            bp.ModularShield = { Chassis = 't' .. tier, Faction = faction.Name }
            bp.Categories = { faction.Name, 'STRUCTURE', 'LAND', 'SHIELD', 'DEFENSE', 'SELECTABLE',
                'RECLAIMABLE', 'VISIBLETORECON', 'OVERLAYDEFENSE', 'SORTDEFENSE',
                'BUILTBYTIER3ENGINEER', 'BUILTBYTIER3COMMANDER', 'MODULARSHIELD', tier == 3 and 'TECH3' or 'EXPERIMENTAL' }
            bp.CategoriesHash = table.hash(bp.Categories)
            bp.TechCategory = tier == 3 and 'TECH3' or 'EXPERIMENTAL'
            local scale = tier == 3 and 1 or 3
            bp.Economy.BuildCostMass = original.Economy.BuildCostMass * scale
            bp.Economy.BuildCostEnergy = original.Economy.BuildCostEnergy * scale
            bp.Economy.BuildTime = original.Economy.BuildTime * scale
            bp.Economy.MaintenanceConsumptionPerSecondEnergy = original.Economy.MaintenanceConsumptionPerSecondEnergy * (tier == 3 and 1 or 2)
            if tier == 4 then
                bp.Defense.Health = original.Defense.Health * 2
                bp.Defense.MaxHealth = bp.Defense.Health
                bp.Defense.Shield.ShieldMaxHealth = original.Defense.Shield.ShieldMaxHealth * 2
                bp.Defense.Shield.ShieldSize = original.Defense.Shield.ShieldSize * 1.25
                bp.Defense.Shield.ShieldRegenRate = original.Defense.Shield.ShieldRegenRate * 1.5
            end
            bp.Display.Abilities = { 'Cumulative module slots: ' .. R.Config.Chassis['t'..tier].Slots,
                'Select to open module panel', 'Engineer assisted module installation' }
            all.Unit[id] = bp
        end
    end
end
