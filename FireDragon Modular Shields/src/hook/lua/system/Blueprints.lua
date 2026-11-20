local previous = ModBlueprints
local root
for _, mod in pairs(__active_mods or {}) do
    if mod.uid == 'bf55b8d0-2026-4115-9000-000000000001' then root = mod.location end
end
assert(root, 'FireDragon Modular Shields: missing mod location')
local function load(path)
    local env = setmetatable({}, { __index = _G })
    doscript(root .. '/lua/ModularShields/' .. path,env)
    assert(env.Export, 'Missing export ' .. path)
    return env.Export
end
local R = load('Bootstrap.lua').Build(load)
function ModBlueprints(all)
    previous(all)
    local worker = table.deepcopy(all.Unit.xea3204)
    if worker then
        local placeholder = assert(all.Unit.mds0001)
        worker.BlueprintId,worker.Source,worker.Mod='mds0001',placeholder.Source,placeholder.Mod
        worker.ScriptModule=root..'/units/mds0001/mds0001_script.lua'
        worker.ScriptClass='MDS0001'
        -- Native IssueRepair rejects workers without the REPAIR category.
        worker.Categories={'UEF','AIR','MOBILE','ENGINEER','REPAIR','DUMMYUNIT','INSIGNIFICANTUNIT','INVULNERABLE','UNSELECTABLE','UNSPAWNABLE','UNTARGETABLE'}
        worker.CategoriesHash=table.hash(worker.Categories)
        worker.Economy.BuildRate=0
        worker.Economy.BuildCostMass=0
        worker.Economy.BuildCostEnergy=0
        worker.Economy.BuildTime=1
        worker.Economy.MaxBuildDistance=100
        worker.Economy.NeedToFaceTargetToBuild=false
        worker.General.CapCost=0
        worker.AI={InitialAutoMode=false}
        worker.Intel={VisionRadius=0}
        worker.StrategicIconName=''
        worker.LifeBarRender=false
        worker.LifeBarSize=0
        worker.Display.HideLifebars=true
        worker.Audio={}
        worker.General.BuildBones=nil
        worker.Defense=worker.Defense or {}
        worker.Defense.EconomyThreatLevel=0
        worker.Defense.AirThreatLevel=0
        worker.Defense.SurfaceThreatLevel=0
        worker.Wreckage=nil
        all.Unit.mds0001=worker
    end
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
            bp.General.ConstructionBar = true
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
            -- Native power adjacency buffs select receivers using SIZE categories.
            -- Both modular tiers retain the original footprint/skirt, so keep its size tag.
            for _,category in ipairs(original.Categories or {}) do
                if string.find(category,'^SIZE%d+$') then table.insert(bp.Categories,category) end
            end
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
            -- These modular copies use whole radius units and clean base HP/s.
            -- Stock faction blueprints remain untouched.
            local steps=R.Config.NumberSteps
            local shield=bp.Defense.Shield
            shield.ShieldRegenRate=math.floor(shield.ShieldRegenRate/steps.BaseRegen+.5)*steps.BaseRegen
            shield.ShieldSize=2*math.floor(shield.ShieldSize/(2*steps.BaseRadius)+.5)*steps.BaseRadius
            bp.Display.Abilities = { 'Cumulative module slots: ' .. R.Config.Chassis['t'..tier].Slots,
                'Select to open module panel', 'Engineer assisted module installation' }
            all.Unit[id] = bp
        end
    end
end
