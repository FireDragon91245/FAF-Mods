table.getn=table.getn or function(t) return #t end
categories={MODULARSHIELD=1}
function IsDestroyed(u) return u.Destroyed end
function WaitTicks() coroutine.yield() end
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
local workers={}
local host={EntityId=10,Army=1,Blueprint={SizeX=2},Loadout={Queue={{PaidWork=0,Quote={Work=1000}}}}}
function host:GetPosition() return {9,0,0} end
function host:GetGuards()
    local result={}
    for _,u in ipairs(workers) do if u:GetGuardedUnit()==self then result[#result+1]=u end end
    return result
end
local scans=0
local far=setmetatable({EntityId=1,GetPosition=function() return {25,0,0} end},{__index=host})
local env=setmetatable({}, {__index=_G})
local A=assert(loadfile('src/lua/ModularShields/Adapters/Assistance.lua','t',env))()
function env.import() return {Export=A} end
function env.ClassUnit(base) return function(class) return setmetatable(class,{__index=base}) end end
env.Unit={OnCreate=function(u) u.Created=true end}
assert(loadfile('src/hook/lua/sim/Unit.lua','t',env))()
local function Unit(id,cats,rate)
    local u=setmetatable({EntityId=id,Army=1,Blueprint={CategoriesHash=cats,
        AI={StagingPlatformScanRadius=15},Economy={MaxBuildDistance=15},Display={}},
        AutoModeEnabled=true,Queue={},Rate=rate or 25},{__index=env.Unit})
    function u:GetPosition() return {0,0,0} end
    function u:GetFractionComplete() return 1 end
    function u:IsPaused() return self.Paused end
    function u:GetScriptBit(bit) return bit==4 and self.ProductionOff end
    function u:IsUnitState(state) return self.State==state end
    function u:GetCommandQueue() return self.Queue end
    function u:GetFocusUnit() return self.Focus end
    function u:GetGuardedUnit() local c=self.Queue[1];return c and c.commandType==15 and c.target end
    function u:GetBuildRate() return self.Rate end
    function u:SetBuildRate(rate) self.Rate=rate end
    function u:UpdateConsumptionValues() end
    function u:SetWorkProgress(progress) self.Progress=progress end
    function u:GetAIBrain() return {GetUnitsAroundPoint=function(_,cat,_,radius)
        check(cat==categories.MODULARSHIELD and radius==15,'native station scan range retained')
        scans=scans+1;return {far,host}
    end} end
    function u:ForkThread(fn)
        local thread=coroutine.create(fn);assert(coroutine.resume(thread));return thread
    end
    workers[#workers+1]=u
    return u
end
-- Native IssueGuard appends: replacing the fixture queue would mask the bug.
function env.IssueGuard(list,target)
    local u=list[1];u.Queue[#u.Queue+1]={commandType=15,target=target}
end
function env.IssueMove(list,p)
    local u=list[1];u.Queue[#u.Queue+1]={commandType=2,x=p[1],y=p[2],z=p[3]}
end
function env.IssueClearCommands(list)
    local u=list[1];u.Queue={};u.Focus=nil;u.Clears=(u.Clears or 0)+1
end
local parent=Unit(20,{ENGINEERSTATION=true,PODSTAGINGPLATFORM=true})
parent:OnCreate();check(not parent.ModuleAutoAssistThread,'Kennel tower is not a second engineer')
local drone=Unit(21,{ENGINEER=true,POD=true,STATIONASSISTPOD=true})
drone.Blueprint.Economy.MaxBuildDistance=5
drone:OnCreate();drone.Parent=parent
drone.Queue={{commandType=29,target=parent}};drone.Focus=parent;drone.State='Attached'
check(drone.ModuleAutoAssistThread and coroutine.resume(drone.ModuleAutoAssistThread),'direct-created pod starts scan without OnStopBeingBuilt')
check(drone.Queue[1].commandType==2 and drone.Queue[2].target==host and drone.Clears==1,'idle is replaced by approach and guard for an actually in-range host')
A.AutoDrone(drone)
check(drone.ModuleAutoAssistHost==host and #drone.Queue==2,'owned approach is retained while flying into real build range')
table.remove(drone.Queue,1);drone.State=nil;drone.Focus=nil;drone.GetPosition=function() return {9,0,0} end
check(A.Rate(host,{InstallRate=40,InstallMaxRate=1000})==65,'dispatched drone contributes its real build rate')
check(drone.ModularAssistOwner==host and drone.Rate==0,'host pays module work without duplicate native repair')
host.Loadout.Queue={};A.ReleaseAll(host);A.AutoDrone(drone)
check(not drone.ModuleAutoAssistHost and drone.Rate==25,'completed module returns drone to native automation')
host.Loadout.Queue={{PaidWork=0,Quote={Work=1000}}}
for _,rate in ipairs({20,50,75}) do
    local hive=Unit(30+rate,{ENGINEER=true,ENGINEERSTATION=true,STATIONASSISTPOD=true},rate)
    hive.Queue={{commandType=29}}
    hive:OnCreate();check(hive.ModuleAutoAssistThread and coroutine.resume(hive.ModuleAutoAssistThread),'every Hive tier starts module scan')
    check(hive:GetGuardedUnit()==host,'Hive automatically guards module job')
    check(A.Rate(host,{InstallRate=40,InstallMaxRate=1000})>40,'Hive increases module install rate')
end
A.ReleaseAll(host)
drone.GetPosition=function() return {0,0,0} end;drone.State='Attached';drone.Focus=parent
drone.Queue={{commandType=29}};A.AutoDrone(drone)
check(drone.ModuleAutoAssistMove and #drone.Queue==2,'a new job dispatches a docked pod again')
drone.Queue={{commandType=2,x=99,z=99}};A.AutoDrone(drone)
check(not drone.ModuleAutoAssistHost and not drone.ModuleAutoAssistMove and drone.Queue[1].x==99,'manual move during approach relinquishes ownership without clearing player command')
drone.ModuleAutoAssistHost=nil;drone.Queue={{commandType=2}};drone.Focus=nil;local before=scans
A.AutoDrone(drone);check(scans==before and drone.Queue[1].commandType==2,'manual movement is preserved')
drone.Queue={{commandType=9,target={}}};A.AutoDrone(drone)
check(scans==before and drone.Queue[1].commandType==9,'native repair work is preserved')
drone.Queue={{commandType=29}};drone.Focus=parent
for _,field in ipairs({'Paused','ProductionOff'}) do
    parent[field]=true;A.AutoDrone(drone);check(scans==before,'station pause/production switch prevents dispatch');parent[field]=false
end
parent.AutoModeEnabled=false;A.AutoDrone(drone);check(scans==before,'station automode off prevents dispatch');parent.AutoModeEnabled=true
host.InstallPaused=true;A.AutoDrone(drone);check(not drone.ModuleAutoAssistHost,'paused installation is not acquired');host.InstallPaused=false
host.ModuleUpgrading=true;A.AutoDrone(drone);check(not drone.ModuleAutoAssistHost,'chassis upgrade is left to native assistance');host.ModuleUpgrading=false
local hidden=Unit(500,{ENGINEER=true,STATIONASSISTPOD=true,DUMMYUNIT=true,INSIGNIFICANTUNIT=true})
hidden:OnCreate();check(not hidden.ModuleAutoAssistThread,'aura helpers never acquire module work')
print('PASS: '..checks..' actual Unit creation, docked Kennel dispatch and all Hive tier assistance checks')
