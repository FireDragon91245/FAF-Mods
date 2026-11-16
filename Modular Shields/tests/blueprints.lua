-- Compatibility shims for the FAF Lua 5.0 APIs used by production code.
table.getn = table.getn or function(t) return #t end
math.mod = math.mod or math.fmod
-- RuleInit's Lua math library does not provide the modern math.huge constant.
local originalHuge=math.huge
math.huge=nil
local root='ModularShields'
local count=0
local function check(v,msg) count=count+1;assert(v,msg) end
function table.deepcopy(t)
    if type(t)~='table' then return t end
    local copy={};for k,v in pairs(t) do copy[k]=table.deepcopy(v) end;return copy
end
function table.hash(t) local h={};for _,v in ipairs(t) do h[v]=true end;return h end
__active_mods={{uid='bf55b8d0-2026-4115-9000-000000000001',location=root}}
function doscript(path,env) return assert(loadfile(path,'t',env))() end
local called=false
ModBlueprints=function() called=true end
assert(loadfile(root..'/hook/lua/system/Blueprints.lua'))()
local all={Unit={}}
local factions={{'UEF','ueb4301','mdeb'},{'AEON','uab4301','mdab'},{'CYBRAN','urb4207','mdrb'},{'SERAPHIM','xsb4301','mdsb'}}
for _,f in ipairs(factions) do
    all.Unit[f[2]]={BlueprintId=f[2],Source='/units/'..f[2]..'/'..f[2]..'_unit.bp',
        ScriptClass=f[2]:upper(),General={UpgradesTo='stock_successor',Icon='land'},
        Categories={'STRUCTURE','SIZE12'},
        Economy={BuildCostMass=1000,BuildCostEnergy=10000,BuildTime=1000,MaintenanceConsumptionPerSecondEnergy=100},
        Defense={Health=1000,Shield={ShieldMaxHealth=10000,ShieldSize=40,ShieldRegenRate=100}},
        Display={MeshBlueprint='/units/stock_mesh'},Footprint={SizeX=3,SizeZ=3},Physics={SkirtSizeX=6,SkirtSizeZ=6}}
    for _,suffix in ipairs({'4301','4401'}) do
        local id=f[3]..suffix
        all.Unit[id]={Source='/mods/ModularShields/units/'..id..'/'..id..'_unit.bp',Mod='test'}
    end
end
ModBlueprints(all)
check(called,'Previous blueprint hook remains chained')
-- These blueprint capability names are present in the installed stock units.
-- Upgrade orders are enabled by the upgrade links, not a RULEUCC_Upgrade cap.
local validCaps={RULEUCC_Attack=true,RULEUCC_CallTransport=true,RULEUCC_Capture=true,
    RULEUCC_Dive=true,RULEUCC_Dock=true,RULEUCC_Ferry=true,RULEUCC_Guard=true,
    RULEUCC_Move=true,RULEUCC_Nuke=true,RULEUCC_Overcharge=true,RULEUCC_Patrol=true,
    RULEUCC_Pause=true,RULEUCC_Reclaim=true,RULEUCC_Repair=true,RULEUCC_RetaliateToggle=true,
    RULEUCC_Sacrifice=true,RULEUCC_SiloBuildNuke=true,RULEUCC_SiloBuildTactical=true,
    RULEUCC_Stop=true,RULEUCC_Tactical=true,RULEUCC_Transport=true}
for _,f in ipairs(factions) do
    local t3,t4=all.Unit[f[3]..'4301'],all.Unit[f[3]..'4401']
    check(t3.ModularShield.Chassis=='t3' and t4.ModularShield.Chassis=='t4','Both chassis generated: '..f[1])
    check(t3.General.ConstructionBar and t4.General.ConstructionBar,'Both tiers enable the native construction progress bar: '..f[1])
    check(t3.CategoriesHash.SIZE12 and t4.CategoriesHash.SIZE12,'Native adjacency receiver size retained: '..f[1])
    check(t3.Defense.Shield.ShieldMaxHealth==10000 and t4.Defense.Shield.ShieldMaxHealth==20000,'Immutable stock baseline: '..f[1])
    check(t3.Footprint.SizeX==t4.Footprint.SizeX and t3.Display.MeshBlueprint=='/units/stock_mesh','Stock mesh and footprint retained: '..f[1])
    check(all.Unit[f[2]].General.UpgradesTo=='stock_successor','Stock upgrade chain untouched: '..f[1])
    check(t3.ScriptModule:match('/mods/ModularShields/units/') and t4.CategoriesHash.EXPERIMENTAL,'Own script/category metadata: '..f[1])
    check(t3.General.UpgradesTo==t4.BlueprintId and t4.General.UpgradesFrom==t3.BlueprintId,'Native modular upgrade chain: '..f[1])
    for _,unit in ipairs({t3,t4}) do
        for name in pairs(unit.General.CommandCaps) do check(validCaps[name],'Unsupported blueprint command capability: '..name) end
    end
    check(t3.General.Icon==all.Unit[f[2]].General.Icon and t4.General.Icon==all.Unit[f[2]].General.Icon,'Native General.Icon enum retained: '..f[1])
end
print('PASS: '..count..' blueprint contract checks')
math.huge=originalHuge
