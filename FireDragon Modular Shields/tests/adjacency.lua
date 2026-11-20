table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
local root='src/lua/ModularShields/'
local function load(path)
    local env=setmetatable({}, {__index=_G})
    return assert(loadfile(root..path,'t',env))()
end
local R=load('Bootstrap.lua').Build(load)
local Adjacency=load('Adapters/Adjacency.lua')
local count=0
local function check(value,message) count=count+1;assert(value,message) end
function IsDestroyed(unit) return unit.Destroyed end
local nearby,bounds={},nil
function GetUnitsInRect(x0,z0,x1,z1) bounds={x0,z0,x1,z1};return nearby end
local function structure(id,rect,kind,tier,production)
    local u={EntityId=id,Army=1,Rect=rect,Fraction=1,Blueprint={BlueprintId='test_'..id,
        CategoriesHash={STRUCTURE=true},Economy={ProductionPerSecondEnergy=production or 0}}}
    u.Blueprint.CategoriesHash[kind]=true
    u.Blueprint.CategoriesHash[tier or 'TECH2']=true
    function u:GetSkirtRect() return self.Rect[1],self.Rect[2],self.Rect[3],self.Rect[4] end
    function u:GetFractionComplete() return self.Fraction end
    return u
end
-- Matches the stock UEF shield skirt (6x6), T2 power (6x6), and T3 power (8x8).
local host=structure(1,{61,61,67,67},'SHIELD','TECH3')
local t2=structure(2,{67,61,73,67},'ENERGYPRODUCTION','TECH2',500)
local t3=structure(3,{53,60,61,68},'ENERGYPRODUCTION','TECH3',2500)
local storage=structure(4,{63,59,65,61},'ENERGYSTORAGE','TECH1')
local mass=structure(5,{63,67,65,69},'MASSSTORAGE','TECH1')
local function snapshot(excluded) return Adjacency.Snapshot(host,R.Registry,R.Config,excluded) end
local function support(excluded)
    local facts=snapshot(excluded)
    local caps=R.Neighbors.Evaluate(R.Registry,facts)
    return caps.legendary_power_support or false,facts
end
nearby={t2}
local active,facts=support()
check(active and #facts==1 and facts[1].Tags.power_generator,'T2 power qualifies without any native adjacency cache')
check(host.AdjacentUnits==nil,'Geometry reconciliation does not forge native callback state')
check(bounds[1]==45 and bounds[2]==45 and bounds[3]==83 and bounds[4]==83,'Bounded scan uses native four-value skirt rectangle')
nearby={t3};active,facts=support()
check(active and facts[1].Tier=='t3','Larger T3 power shares a real edge and qualifies')
nearby={storage};active,facts=support()
check(not active and facts[1].Tags.energy_storage,'Energy storage adds capacity but cannot satisfy legendary power')
nearby={mass};active,facts=support()
check(not active and facts[1].Tags.mass_storage,'Mass storage is classified but does not supply legendary power')
t2.Fraction=.5;nearby={t2}
check(not support(),'Unfinished provider does not qualify')
t2.Fraction=1
check(support(),'Completion is discovered even when the native completion callback was missed')
t2.Army=2
check(not support(),'Other-army provider does not qualify')
t2.Army=1
check(support(),'Provider ownership restoration is reconciled')
t2.Dead=true
check(not support(),'Dead provider drops support')
t2.Dead=false;t2.Destroyed=true
check(not support(),'Destroyed provider drops support')
t2.Destroyed=false
check(not support(t2),'Removal callback excludes an otherwise still-alive adjacent provider immediately')
check(support(),'Later reconciliation can restore actual valid support')
host.AdjacentUnits={[t2.EntityId]=t2};nearby={host,t2,t2}
active,facts=support()
check(active and #facts==1,'Callback/query overlap counts each physical provider once')
t2.Rect={67.5,61,73.5,67}
check(not support(),'A visible half-unit gap is not adjacency, even with a stale native record')
t2.Rect={67,67,73,73}
check(not support(),'Corner-only touching is not adjacency')
t2.Rect={65,61,71,67}
check(not support(),'Overlapping cheat-spawned footprints do not count as edge adjacency')
t2.Rect={70,70,76,76}
check(not support(),'A structure elsewhere under the dome does not qualify')
t2.Rect={67,62,73,68}
check(support(),'Partial side overlap qualifies')
t2.Blueprint.Economy.ProductionPerSecondEnergy=0
check(not support(),'ENERGYPRODUCTION category alone does not imply actual production')
t2.Blueprint.Economy.ProductionPerSecondEnergy=500
nearby={};host.AdjacentUnits=nil
check(not support(),'Removed providers do not linger in a cached snapshot')
check(Adjacency.EdgeAdjacent({0,0,6,6},{6.001,1,12.001,7},.05),'Small floating-point skirt error is tolerated')
check(not Adjacency.EdgeAdjacent({0,0,6,6},{6,6,12,12},.05),'Tolerance does not turn a point contact into a shared edge')
t2.Rect={67,61,73,67};t2.Blueprint.CategoriesHash.TECH2=nil;t2.Blueprint.CategoriesHash.TECH1=true;nearby={t2}
check(not support(),'Completed T1 generators cannot supply Impenetrable')
t2.Blueprint.CategoriesHash.TECH1=nil;t2.Blueprint.CategoriesHash.TECH2=true
function t2:GetProductionPerSecondEnergy() return 800 end
local live=snapshot()
check(live[1].EnergyProduction==800,'Neighbor snapshots use live production rather than static blueprint output')
t2.Blueprint.Economy.ProductionPerSecondEnergy=0
check(support(),'Script-produced energy qualifies when the blueprint has no static production')
host.Loadout={}
function host:ReconcileModules() self.Refreshes=(self.Refreshes or 0)+1 end
nearby={host,host};t2.AdjacentUnits={[host.EntityId]=host}
Adjacency.NotifyCompletion(t2,R.Config)
check(host.Refreshes==1,'Provider completion refreshes its shared-edge host immediately and deduplicates cache/query matches')
t2.Fraction=.99;Adjacency.NotifyCompletion(t2,R.Config)
check(host.Refreshes==1,'Completion notification waits for actual native completion')
t2.Fraction=1;t2.Army=2;Adjacency.NotifyCompletion(t2,R.Config)
check(host.Refreshes==1,'Enemy provider completion cannot refresh a friendly shield')
t2.Army=1;t2.Rect={67,67,73,73};Adjacency.NotifyCompletion(t2,R.Config)
check(host.Refreshes==1,'Corner-only providers do not trigger a shield refresh')
print('PASS: '..count..' physical-adjacency contract checks')
