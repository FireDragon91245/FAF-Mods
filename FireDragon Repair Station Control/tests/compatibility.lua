local w=assert(loadfile('tests/support/Fixture.lua'))()()
local C,P,env=w.C,w.P,w.env
local host=w:Unit(100,1,{MODULARSHIELD=true});host.Loadout={Queue={{PaidWork=0,Quote={Work=100}}}}
local parent=w:Unit(101,1,{ENGINEERSTATION=true});parent.Blueprint.AI.StagingPlatformScanRadius=25
local drone=w:Unit(102,1,{POD=true,ENGINEER=true});drone.Parent=parent
local helper=w:Unit(103,1,{ENGINEER=true,INSIGNIFICANTUNIT=true});helper.ModuleHost=host;helper.State='Building'
local project=w:Unit(104);project.Fraction=.5
w.nearby={helper,project};w.shields={host}
local A=assert(loadfile('../FireDragon Modular Shields/src/lua/ModularShields/Adapters/Assistance.lua','t',env))()
C.Track(drone);w:Settings(1,true,true)
C.Track(helper);assert(not w.workerSettings[helper.EntityId],'Invisible helpers are not managed workers')
C.Track(helper);assert(not helper.RepairStationControlThread)
A.AutoDrone(drone);C.Update(drone)
assert(drone.ModuleAutoAssistHost==host and drone:GetGuardedUnit()==host and w.clears==0)
host.Guards={drone};function host:GetGuards() return self.Guards end
assert(A.Rate(host,{InstallRate=40,InstallMaxRate=1000})==65)
assert(drone.ModularAssistOwner==host and drone.NativeRate==0)
C.Update(drone)
assert(drone.ModularAssistOwner==host and drone.NativeRate==0 and w.clears==0)
host.Loadout.Queue={};A.ReleaseAll(host);A.AutoDrone(drone)
assert(not drone.ModularAssistOwner and not drone.ModuleAutoAssistHost and drone.NativeRate==25)
C.Update(drone);assert(drone.NativeAuto,'Native selection resumes after the module claim')
drone.Queue={};drone.Focus=nil;parent.AutoModeEnabled=false;C.Update(drone)
assert(not next(drone.Queue),'Do not bypass a disabled Kennel')
parent.AutoModeEnabled=true;drone.ModularAssistOwner=host;C.Update(drone)
assert(not next(drone.Queue),'Scripted claim is work even without a native queue')
drone.ModularAssistOwner=nil
function env.ClassUnit(base) return function(t) return setmetatable(t,{__index=base}) end end
local function loadHook(path) assert(loadfile(path,'t',env))() end
for i,reverse in ipairs({false,true}) do
    env.Unit={OnCreate=function(u) u.Created=true end,
        OnStartReclaim=function(u,t) u.EntityBeingReclaimed=t end,
        OnStopReclaim=function(u) u.EntityBeingReclaimed=nil end,
        OnAutoModeOn=function(u) u.AutoModeEnabled=true end,
        OnAutoModeOff=function(u) u.AutoModeEnabled=false end,
        OnDestroy=function(u) u.Dead=true end}
    local shield='../FireDragon Modular Shields/src/hook/lua/sim/Unit.lua'
    local rsc='src/hook/lua/sim/Unit.lua'
    loadHook(reverse and rsc or shield);loadHook(reverse and shield or rsc)
    local u=w:Unit(200+i,1,{ENGINEERSTATION=true});setmetatable(u,{__index=env.Unit})
    u:OnCreate();assert(u.Created and u.RepairStationControlThread and u.NativeAuto)
    local target={IsUnit=true};u:OnStartReclaim(target)
    assert(target.ModularReclaimers[u.EntityId]==u)
    u:OnStopReclaim(target);assert(not target.ModularReclaimers[u.EntityId])
    u:SetAutoMode(false);assert(not u.AutoModeEnabled and not u.NativeAuto)
    u:SetAutoMode(true);assert(u.AutoModeEnabled and u.NativeAuto)
    u:OnDestroy();assert(u.Dead)
end
print('PASS: actual shield dispatch/claim lifecycle and both Unit hook load orders with native acquisition retained')

-- Real pods sit on AssistCommander (29), not an empty queue. Exercise appended
-- native orders, both selectors' update orders, and every restriction setting.
for _,settings in ipairs({{false,false},{true,false},{false,true},{true,true}}) do
 for _,rscFirst in ipairs({false,true}) do
    local w=assert(loadfile('tests/support/Fixture.lua'))()()
    local A=w.env.import('/mods/FireDragon Modular Shields/lua/ModularShields/Adapters/Assistance.lua').Export
    local host=w:Unit(600,1,{MODULARSHIELD=true})
    host.Loadout={Queue={{PaidWork=0,Quote={Work=1000}}}}
    local parent=w:Unit(601,1,{ENGINEERSTATION=true})
    local drone=w:Unit(602,1,{POD=true,ENGINEER=true,STATIONASSISTPOD=true});drone.Parent=parent
    local hive=w:Unit(603,1,{ENGINEER=true,ENGINEERSTATION=true,STATIONASSISTPOD=true})
    w.shields={host};w.nearby={host}
    local nativeGuard=w.env.IssueGuard
    w.env.IssueGuard=function(list,target)
        assert(#list[1].Queue==0 or (#list[1].Queue==1 and list[1].Queue[1].commandType==2),
            'Module work must replace idle, optionally approach, then append guard')
        nativeGuard(list,target)
    end
    w.C.Track(drone);w.C.Track(hive);w:Settings(1,settings[1],settings[2])
    drone.Queue={{commandType=29,target=parent}};drone.State='Attached'
    hive.Queue={{commandType=29}}
    for _,u in ipairs({drone,hive}) do
        if rscFirst then w.C.Update(u) end
        A.AutoDrone(u);w.C.Update(u);A.AutoDrone(u)
        assert(u.ModuleAutoAssistHost==host and u:GetGuardedUnit()==host,'Both selectors preserve automatic module work')
        if u.Queue[1].commandType==2 then table.remove(u.Queue,1);u.State=nil end
    end
    function host:GetGuards() return {drone,hive} end
    assert(A.Rate(host,{InstallRate=40,InstallMaxRate=1000})==90,'Both workers speed module installation with every filter setting')
    w.C.Update(drone);w.C.Update(hive)
    assert(drone.ModularAssistOwner==host and hive.ModularAssistOwner==host)
    host.Loadout.Queue={};A.ReleaseAll(host);A.AutoDrone(drone);A.AutoDrone(hive)
    assert(not drone.ModuleAutoAssistHost and not hive.ModuleAutoAssistHost and drone.NativeRate==25 and hive.NativeRate==25)
 end
end
print('PASS: docked Kennel and Hive module assistance with all four restriction settings and both selector update orders')
