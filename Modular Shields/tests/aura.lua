table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
function IsDestroyed(u) return not u or u.Destroyed end
categories={ALLUNITS=1,MODULARSHIELD=2}
local checks=0
local tick=10
function GetGameTick() return tick end
local function check(v,msg) checks=checks+1;assert(v,msg) end
local function load(path)
    local env=setmetatable({}, {__index=_G});assert(loadfile('src/'..path,'t',env))();return env
end
local repair=load('lua/ModularShields/Behaviors/Repair.lua').Export
local assist=load('lua/ModularShields/Adapters/Assistance.lua').Export
local target={Army=1,EntityId=2,HP=50,Fraction=1,Blueprint={Economy={BuildTime=500,BuildCostMass=100}}}
function target:GetFractionComplete() return self.Fraction end
function target:GetMaxHealth() return 100 end
function target:GetHealth() return self.HP end
function target:GetPosition() return self.Position or {1,0,0} end
function target:SetHealth(_,hp) self.HP=hp end
local targets={target}
local brain={GetUnitsAroundPoint=function(_,category) check(category==1,'aura includes all unit types');return targets end}
local host={Army=1,EntityId=1,HP=20,ModuleStats={RepairBudget=30,ShieldSize=56},
    MyShield={IsUp=function() return true end,GetPosition=function() return {0,0,0} end},GetAIBrain=function() return brain end}
local runtime={Config={RepairFactor=.75,Debug={IgnoreResources=false}}}
local helpers,events={},{}
function WaitTicks(n) coroutine.yield(n) end
function CreateUnitHPR(id,army)
    check(id=='mds0001' and army==1,'one owned helper per target')
    local u={Queue={},NativeM=0,NativeE=0,Fulfilled=1}
    function u:ForkThread(fn,...)
        local args={...};self.Thread=coroutine.create(function() fn(self,table.unpack(args)) end)
        assert(coroutine.resume(self.Thread))
    end
    function u:SetBuildRate(rate) self.Rate=rate end
    function u:GetCommandQueue() return self.Queue end
    function u:UpdateConsumptionValues() self.Updated=(self.Updated or 0)+1 end
    function u:GetConsumptionPerSecondMass() return self.NativeM end
    function u:GetConsumptionPerSecondEnergy() return self.NativeE end
    function u:GetResourceConsumed() return self.Fulfilled end
    function u:Destroy() self.Destroyed=true end
    helpers[#helpers+1]=u;return u
end
function IssueRepair(units,u) units[1].Queue={1};units[1].Target=u end
function IssueClearCommands(units) units[1].Queue={} end
function CreateEconomyEvent(owner,energy,mass,time,callback)
    local e={Owner=owner,Energy=energy,Mass=mass,Time=time,Callback=callback};events[#events+1]=e;return e
end
function RemoveEconomyEvent(_,e) e.Removed=true end
local function step(u) tick=tick+1;assert(coroutine.resume(u.Thread)) end
repair.Tick(host,runtime)
local h=helpers[1];local e=events[1]
check(target.HP==50 and e.Owner==h and e.Time==.1,'completed units use helper-owned paid 100ms slices')
check(e.Mass==2.25 and e.Energy==0,'preserve existing mass repair price without a second host charge')
e.Callback(h,0);check(target.HP==50,'resource stall gives no free health')
e.Callback(h,.5);check(target.HP==51.5,'fulfilled half slice buys only half the HP')
local m,energy,rm,re=repair.Consumption(host)
check(m==11.25 and energy==0 and rm==22.5 and re==0,'aggregate actual and requested repair consumption')
e.Callback(h,.5);check(target.HP==51.5,'duplicate callbacks cannot heal twice')
e.Callback(h,1);check(target.HP==53,'paid slice is smooth 3 HP rather than a 30 HP burst')
step(h);check(#events==2 and e.Removed,'continuous work settles its previous event')
local stale=events[2]
host.RepairPaused=true;step(h)
check(h.Destroyed and stale.Removed,'pause destroys worker and cancels its resource event')
stale.Callback(h,1);check(target.HP==53,'cancelled late callback cannot heal')
host.RepairPaused=false;runtime.Config.Debug.IgnoreResources=true;repair.Tick(host,runtime)
h=helpers[2];check(target.HP==56 and #events==2,'Ignore Resources heals a tick without any economy event')
step(h);check(target.HP==59,'free repair remains paced by simulation ticks')
runtime.Config.Debug.IgnoreResources=false;step(h)
check(#events==3 and target.HP==59,'turning costs back on requires payment before more healing')
repair.Stop(host)
-- Native building shares the same worker map and ledger, including idle retries.
target.Fraction=.2;target.HP=20;target.Position={10,4.75,0};repair.Tick(host,runtime)
h=helpers[3]
check(h.Target==target and h.Rate==150 and not h.Destroyed,'native construction worker remains alive inside radius')
h.NativeM=15;h.NativeE=150;h.Fulfilled=.5
m,energy,rm,re=repair.Consumption(host)
check(m==7.5 and energy==75 and rm==15 and re==150,'native construction mass and energy are attributed to shield')
h.Queue={};step(h);check(#h.Queue==1,'dropped native repair orders are retried after builder handoff')
runtime.Config.Debug.IgnoreResources=true;step(h);check(h.ModuleFree and h.Updated>=2,'cheat change refreshes native worker consumption')
-- Reclaiming takes precedence; self and full-health units do not consume slots.
local reclaimer={EntityBeingReclaimed=target}
target.ModularReclaimers={[90]=reclaimer};step(h)
check(h.Destroyed,'construction stops when its target is reclaimed')
target.ModularReclaimers=nil;runtime.Config.Debug.IgnoreResources=false
local other=setmetatable({Army=1,EntityId=900,HP=40,Fraction=1,Blueprint={Economy={BuildCostMass=100}},MyShield={HP=300}}, {__index=target})
target.Fraction=1;target.HP=100;targets={host,other}
function host:GetFractionComplete() return 1 end
function host:GetHealth() return self.HP end
function host:GetMaxHealth() return 100 end
function host:GetPosition() return {0,0,0} end
host.SetHealth=function() error('self repair is forbidden') end
for i=1,60 do targets[#targets+1]=setmetatable({EntityId=i+100,Army=1,HP=100,Fraction=1},{__index=target}) end
repair.Tick(host,runtime)
h=host.ModuleRepairHelpers[900];e=events[#events];e.Callback(h,1)
check(other.HP==43 and host.HP==20 and other.MyShield.HP==300,'other generator chassis receives smooth repair; source and dome excluded')
repair.Stop(host)
-- Zero-price targets still advance without waiting on an empty economy event.
local zero=setmetatable({EntityId=901,Army=1,HP=20,Fraction=1,Blueprint={Economy={BuildCostMass=0}}},{__index=target})
targets={zero};local eventCount=#events;repair.Tick(host,runtime)
check(zero.HP==23 and #events==eventCount,'zero-price chassis repairs do not stall or create phantom consumption')
repair.Stop(host)
-- Automatic station drones see module jobs, and preserve explicit new commands.
local parent={AutoModeEnabled=true,Blueprint={AI={StagingPlatformScanRadius=25}},GetPosition=target.GetPosition,
    IsPaused=function(u) return u.Paused end,GetScriptBit=function(u) return u.ProductionOff end}
local shield={Army=1,EntityId=5,Loadout={Queue={{}}},Blueprint={SizeX=1},GetPosition=target.GetPosition}
local drone={Army=1,AutoModeEnabled=true,Parent=parent,Queue={},IsPaused=function() return false end,
    Blueprint={CategoriesHash={POD=true},Economy={MaxBuildDistance=15}},GetFocusUnit=function(u) return u.Focus end,
    GetPosition=target.GetPosition,
    IsUnitState=function(u,state) return u.State==state end}
function drone:GetCommandQueue() return self.Queue end
function drone:GetAIBrain() return {GetUnitsAroundPoint=function(_,cat,center,radius) check(cat==2 and radius==25,'station scan uses configured assist range');return {shield} end} end
function IssueGuard(units,t) units[1].Queue={{commandType=15,target=t}} end
function IssueClearCommands(units) units[1].Queue={};units[1].Cleared=(units[1].Cleared or 0)+1 end
assist.AutoDrone(drone)
check(drone.ModuleAutoAssistHost==shield and drone.Queue[1].target==shield,'idle automatic drone guards active module job')
assist.AutoDrone(drone)
check(not drone.Cleared,'ongoing module job keeps drone order')
drone.Queue={{commandType=2,target={}}};assist.AutoDrone(drone)
check(not drone.ModuleAutoAssistHost and not drone.Cleared and drone.Queue[1].commandType==2,'player move takes precedence over automatic assistance')
drone.Queue={};assist.AutoDrone(drone);shield.Loadout.Queue={};assist.AutoDrone(drone)
check(not drone.ModuleAutoAssistHost and drone.Cleared==1,'completion releases automatic guard for native station work')
parent.AutoModeEnabled=false;shield.Loadout.Queue={{}};assist.AutoDrone(drone)
check(not drone.ModuleAutoAssistHost,'disabled station automation does not dispatch drones')
print('PASS: '..checks..' aura, reclaim and drone checks')
