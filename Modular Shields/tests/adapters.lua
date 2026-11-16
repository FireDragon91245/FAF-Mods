-- Compatibility shims for the FAF Lua 5.0 APIs used by production code.
table.getn = table.getn or function(t) return #t end
math.mod = math.mod or math.fmod
local root='src/lua/ModularShields/'
local modules={}
local shieldLibrary={LargestShieldDiameter=0}
function import(path)
    if path=='/lua/shield.lua' then return shieldLibrary end
    local relative=assert(path:match('/lua/ModularShields/(.*)'))
    if not modules[relative] then
        local env=setmetatable({}, {__index=_G})
        assert(loadfile(root..relative,'t',env))()
        modules[relative]=env
    end
    return modules[relative]
end
function IsDestroyed(s) return s.Destroyed end
local tick=100
function GetGameTick() return tick end
function ResumeThread(thread) thread.Resumes=(thread.Resumes or 0)+1 end
local R=import('/mods/ModularShields/lua/ModularShields/Runtime.lua').Export
local adapter=import('/mods/ModularShields/lua/ModularShields/Adapters/Shield.lua').Export
local count=0
local function check(v,msg) count=count+1;assert(v,msg) end
local shield={HP=300,MaxHP=1000,RegenThread={},RegenThreadSuspended=true,RegenThreadStartTick=150,ShieldRechargeTime=25}
function shield:GetHealth() return self.HP end
function shield:GetMaxHealth() return self.MaxHP end
function shield:SetMaxHealth(n) self.MaxHP=n end
function shield:SetHealth(_,n) self.HP=n end
function shield:IsUp() return true end
function shield:SetCollisionShape(_,_,_,_,n) self.CollisionRadius=n end
function shield:SetDrawScale(n) self.DrawScale=n end
function shield:UpdateShieldRatio() end
local host={MyShield=shield}
function host:ClearFocusEntity() self.FocusClears=(self.FocusClears or 0)+1 end
function host:SetEnergyMaintenanceConsumptionOverride(n) self.Upkeep=n end
function host:UpdateConsumptionValues() self.ConsumptionUpdated=true end
adapter.Apply(host,{ShieldMaxHP=2000,ShieldSize=50,ShieldRegen=40,Upkeep=200})
check(shield.HP==300 and shield.MaxHP==2000,'Capacity expansion preserves absolute damage')
check(shield.RegenThreadStartTick==150 and shield.ShieldRechargeTime==25,'Preserve damage/recharge timers')
check(shield.CollisionRadius==25 and shield.DrawScale==50 and shieldLibrary.LargestShieldDiameter==50,'Collision/visual/overlap geometry agrees')
check(host.FocusClears==1,'Applying module stats removes the native dome-repair focus')
host.ModuleUpgrading=true;adapter.Apply(host,{ShieldMaxHP=2000,ShieldSize=50,ShieldRegen=40,Upkeep=200})
check(host.FocusClears==1,'Native chassis upgrades retain their build focus')
host.ModuleUpgrading=false
adapter.Apply(host,{ShieldMaxHP=200,ShieldSize=40,ShieldRegen=20,Upkeep=100})
check(shield.HP==200,'Capacity reduction clamps health')
local Jobs=import('/mods/ModularShields/lua/ModularShields/Services/InstallJobs.lua').Export
local pending
function CreateEconomyEvent(owner,energy,mass,time,callback)
    local event={Owner=owner,Energy=energy,Mass=mass,Time=time,Callback=callback}
    pending=event;return event
end
function RemoveEconomyEvent(_,event) event.Removed=true end
function WaitTicks(ticks) coroutine.yield(ticks) end
function KillThread(co) if coroutine.status(co)~='dead' then assert(coroutine.close(co)) end end
local function newHost()
    local h={Army=1,Blueprint={SizeX=4},Loadout=R.Core.New('t3',{Mass=1000,Energy=10000,Upkeep=100,ShieldMaxHP=10000,ShieldSize=40,ShieldRegen=100})}
    h.Loadout.Rules=R.Core
    function h:ForkThread(fn) local co=coroutine.create(fn);assert(coroutine.resume(co));return co end
    function h:GetGuards() return self.Guards or {} end
    function h:GetPosition() return {0,0,0} end
    function h:SetWorkProgress(progress) self.WorkProgress=progress end
    function h:PublishModules()
        self.Publications=(self.Publications or 0)+1
        self.PublishedProgress=self.Loadout.Queue[1] and self.Loadout.Queue[1].PaidWork/self.Loadout.Queue[1].Quote.Work or 0
    end
    function h:ReconcileModules() self.Stats=R.Stats.Calculate(self.Loadout,R.Registry,R.Config) end
    return h
end
host=newHost()
local job=assert(R.Core.RequestInstall(host.Loadout,'power_1',R.Registry,R.Config))
Jobs.Start(host,R)
assert(coroutine.resume(host.ModuleThread))
check(pending.Mass>0 and pending.Energy>0,'Every work slice consumes both resources')
local event=pending
event.Callback(host,0)
check(job.PaidWork==0 and not host.Loadout.Installed.power_1,'Resource stall grants no work/effect')
tick=tick+2
event.Callback(host,.5)
check(job.PaidWork>0 and job.PaidWork<job.Quote.Work,'Only fulfilled work counts')
check(host.WorkProgress==job.PaidWork/job.Quote.Work and host.PublishedProgress==host.WorkProgress,'Paid progress updates native bar and UI snapshot during the slice')
local paid=job.PaidWork
Jobs.Stop(host)
check(host.WorkProgress==paid/job.Quote.Work,'Pausing preserves native work progress')
event.Callback(host,1)
check(job.PaidWork==paid and event.Removed,'Stopped event cannot mutate paid work')
Jobs.Start(host,R)
assert(coroutine.resume(host.ModuleThread))
local totalM,totalE=event.Mass*.5,event.Energy*.5
local co=host.ModuleThread
while coroutine.status(co)~='dead' do
    local e=pending
    e.Callback(host,1);totalM=totalM+e.Mass;totalE=totalE+e.Energy
    assert(coroutine.resume(co))
end
check(host.Loadout.Installed.power_1 and #host.Loadout.Queue==0,'Paid completion commits once')
check(host.WorkProgress==0 and host.PublishedProgress==0,'Completion clears native bar and publishes idle immediately')
host.ModuleUpgrading=true;host.WorkProgress=.37;Jobs.UpdateProgress(host)
check(host.WorkProgress==.37,'Module publication never overwrites a native chassis upgrade bar')
check(math.abs(totalM-job.Quote.Mass)<1e-7 and math.abs(totalE-job.Quote.Energy)<1e-7,'Pause/resume preserves exact total price')
check(host.Stats.ShieldMaxHP==11000 and host.Stats.Upkeep==105,'Benefits and upkeep commit together')
-- Exercise the paid-event backend with an actual contributing engineer and
-- a reassignment halfway through its current economy slice.
host=newHost()
local engineer={EntityId=80,Army=1,Blueprint={CategoriesHash={ENGINEER=true},Economy={MaxBuildDistance=10}}}
host.EntityId=100
function engineer:GetGuardedUnit() return not self.Paused and not self.Reassigned and host or nil end
function engineer:GetFocusUnit() return nil end
function engineer:GetPosition() return {1,0,0} end
function engineer:GetFractionComplete() return 1 end
function engineer:GetCommandQueue() return {{commandType=15,targetId=self.Reassigned and 999 or host.EntityId}} end
function engineer:IsPaused() return self.Paused end
function engineer:SetPaused(p) self.Paused=p end
function engineer:GetBuildRate() return self.NativeRate or 40 end
function engineer:SetBuildRate(rate) self.NativeRate=rate end
function engineer:UpdateConsumptionValues() self.NativeDraw=self.ActiveConsumption and 10 or 0 end
function engineer:SetWorkProgress(progress) self.WorkProgress=progress end
host.Guards={engineer}
local beamCount,beamDestroyed=0,0
function AttachBeamEntityToEntity(source,bone,target,targetBone,army,path)
    assert(source==engineer and target==host and path=='/effects/emitters/build_beam_01_emit.bp')
    beamCount=beamCount+1
    return {Destroy=function() beamDestroyed=beamDestroyed+1 end}
end
engineer.Trash={Add=function() end}
job=assert(R.Core.RequestInstall(host.Loadout,'power_1',R.Registry,R.Config))
Jobs.Start(host,R);assert(coroutine.resume(host.ModuleThread))
check(host.ModuleWorkRate==80 and not engineer.Paused and engineer.NativeRate==0,'Assisted installation uses combined rate without pausing the engineer')
for n=1,12 do
    tick=tick+1;assert(coroutine.resume(host.ModuleThread))
end
check(host.ModuleWorkRate==80 and host.ModuleAssistantCount==1 and not engineer.Paused,'Queued guard remains assigned while native work rate stays zero')
check(beamCount==1 and beamDestroyed==0,'Assistant keeps one continuous owned construction beam across work ticks')
event=pending
check(math.abs(event.Mass/(event.Time)-(job.Quote.Mass/(job.Quote.Work/40))*2)<1e-8,'Assistance doubles resource draw along with work speed')
event.Callback(host,.5)
check(engineer.WorkProgress==host.WorkProgress and engineer.WorkProgress>0,'Assisting engineer mirrors the generator native bar on paid progress')
local stalledProgress=engineer.WorkProgress
event.Callback(host,.5)
check(engineer.WorkProgress==stalledProgress,'Resource stalls leave both native progress bars at paid progress')
engineer.Reassigned=true
totalM,totalE=event.Mass*.5,event.Energy*.5
co=host.ModuleThread;assert(coroutine.resume(co))
check(host.ModuleWorkRate==40 and not engineer.Paused and event.Removed,'Reassignment settles the partial event and restores native work')
check(beamDestroyed==1 and not engineer.ModularNativeWork,'Reassignment destroys only the scripted beam and clears captured rate')
check(engineer.WorkProgress==0,'Reassignment clears the engineer module progress bar')
while coroutine.status(co)~='dead' do
    local e=pending;e.Callback(host,1);totalM=totalM+e.Mass;totalE=totalE+e.Energy
    assert(coroutine.resume(co))
end
check(math.abs(totalM-job.Quote.Mass)<1e-7 and math.abs(totalE-job.Quote.Energy)<1e-7,'Changing assistants preserves the fixed total purchase cost')
host=newHost();host.Loadout.BonusSlots=1
for level=1,4 do
    local fit=assert(R.Core.RequestInstall(host.Loadout,'power_'..level,R.Registry,R.Config));fit.PaidWork=fit.Quote.Work
    assert(not R.Core.Complete(host.Loadout,fit,R.Registry,R.Config))
end
assert(R.Core.RequestInstall(host.Loadout,'power_5',R.Registry,R.Config))
Jobs.Start(host,R);assert(coroutine.resume(host.ModuleThread))
event=pending;event.Callback(host,.5);paid=host.Loadout.Queue[1].PaidWork
host.Loadout.BonusSlots=0;co=host.ModuleThread;assert(coroutine.resume(co))
check(host.Loadout.Queue[1].State=='WaitingForSlots' and event.Removed,'Losing mass storage settles the event and waits for capacity')
check(host.Loadout.Queue[1].PaidWork==paid and #host.Loadout.Queue==1,'Storage loss preserves paid progress and queued modules')
host.Loadout.BonusSlots=1;assert(coroutine.resume(co))
check(host.Loadout.Queue[1].State=='Building' and pending~=event,'Restoring mass storage resumes the same installation')
Jobs.Stop(host)
local repair=import('/mods/ModularShields/lua/ModularShields/Behaviors/Repair.lua').Export
categories={STRUCTURE=1}
local mass=1
local target={EntityId=2,Army=1,HP=50,Blueprint={Economy={BuildCostMass=100}}}
function target:GetPosition() return {1,0,0} end
function target:GetMaxHealth() return 100 end
function target:GetHealth() return self.HP end
function target:GetFractionComplete() return 1 end
function target:SetHealth(_,hp) self.HP=hp end
local brain={}
function brain:GetUnitsAroundPoint() return {target} end
function brain:TakeResource(_,requested) local paid=math.min(mass,requested);mass=mass-paid;return paid end
host={Sync={},Army=1,EntityId=1,MyShield={IsUp=function() return true end,GetPosition=function() return {0,0,0} end},ModuleStats={ShieldSize=40,RepairBudget=30},GetAIBrain=function() return brain end}
repair.Tick(host,R)
check(math.abs(target.HP-(50+1/.75))<1e-7 and mass==0,'Repair only delivers HP paid with actual mass')
check(host.Sync.ModularShieldRepairMass==1,'Native display attribution reports exact paid mass with no second withdrawal')
local hp=target.HP;repair.Tick(host,R)
check(target.HP==hp,'Empty mass storage gives no free healing')
check(host.Sync.ModularShieldRepairMass==0,'Resource starvation clears native repair attribution')
target.Army=2;mass=100;repair.Tick(host,R)
check(target.HP==hp and mass==100,'Different army receives no repair or charge')
host.Sync.ModularShieldRepairMass=20;host.RepairPaused=true;repair.Tick(host,R)
check(host.Sync.ModularShieldRepairMass==0,'Pausing repair clears native consumption attribution')
print('PASS: '..count..' adapter contract checks')
