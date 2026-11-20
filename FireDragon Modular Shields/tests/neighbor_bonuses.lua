table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
local root='src/lua/ModularShields/'
local function load(path) local env=setmetatable({}, {__index=_G});return assert(loadfile(root..path,'t',env))() end
local R=load('Bootstrap.lua').Build(load)
local count=0
local function check(v,message) count=count+1;assert(v,message) end
local s=R.Core.New('t4',{Mass=1000,Energy=10000,Upkeep=100,ShieldMaxHP=10000,ShieldSize=40,ShieldRegen=100});s.Rules=R.Core
for _,id in ipairs({'power_1','regen_1','regen_2'}) do
    local job=assert(R.Core.RequestInstall(s,id,R.Registry,R.Config));job.PaidWork=job.Quote.Work
    assert(not R.Core.Complete(s,job,R.Registry,R.Config))
end
local function fact(id,tag,tier,production)
    return {Id=id,Tags={[tag]=true},Tier=tier,EnergyProduction=production or 0,Completed=true,SameArmy=true,EdgeAdjacent=true}
end
local facts={fact(1,'power_generator','t2',800),fact(2,'power_generator','t3',2000),
    fact(3,'energy_storage','t1'),fact(4,'mass_storage','t1'),fact(5,'mass_storage','t1')}
local caps,effects=R.Neighbors.Evaluate(R.Registry,facts,s.Installed)
local stats=R.Stats.Calculate(s,R.Registry,R.Config,effects)
check(caps.legendary_power_support,'T2+ generators supply legendary support')
check(stats.NeighborRegen==28 and stats.BaseRegen==100 and stats.ModuleRegen==70,'Generator regen scales with summed energy production, independently of staged module regeneration')
check(stats.ShieldRegen==198,'Total out-of-combat regeneration sums all three sources')
check(stats.BaseHP==10000 and stats.ModuleHP==2000 and stats.NeighborHP==1000 and stats.ShieldMaxHP==13000,'HP breakdown is additive and energy storage adds ten percent of base')
check(stats.ModuleSlots==10,'Each physical mass storage adds one module slot')
s.BonusSlots=stats.ModuleSlots-R.Config.Chassis[s.Chassis].Slots
check(R.Core.Capacity(s,R.Config)==10,'Rules and work use the expanded capacity')
check(stats.EnergyMultiplier==1,'Custom power regen does not duplicate native upkeep adjacency')
caps=R.Neighbors.Evaluate(R.Registry,{fact(1,'power_generator','t1',20),fact(2,'energy_storage','t1')})
check(not caps.legendary_power_support,'T1 generation and energy storage cannot satisfy Impenetrable')
local _,one=R.Neighbors.Evaluate(R.Registry,{facts[1]})
local _,two=R.Neighbors.Evaluate(R.Registry,{facts[2]})
check(R.Stats.Calculate(s,R.Registry,R.Config,one).NeighborRegen==8 and R.Stats.Calculate(s,R.Registry,R.Config,two).NeighborRegen==20,'800 energy produces less regen than 2000 energy')
local _,duplicate=R.Neighbors.Evaluate(R.Registry,{facts[1],facts[1]})
check(R.Stats.Calculate(s,R.Registry,R.Config,duplicate).NeighborRegen==8,'Duplicate provider facts cannot multiply a generator bonus')
facts[2].Completed=false
local _,unfinished=R.Neighbors.Evaluate(R.Registry,facts)
check(R.Stats.Calculate(s,R.Registry,R.Config,unfinished).NeighborRegen==8,'Unfinished neighboring generators provide no regen')
local six={}
for n=1,6 do six[#six+1]=fact(n,'mass_storage','t1');six[#six+1]=fact(n+6,'energy_storage','t1') end
local _,sixEffects=R.Neighbors.Evaluate(R.Registry,six)
local sixStats=R.Stats.Calculate(s,R.Registry,R.Config,sixEffects)
check(sixStats.ModuleSlots==14,'Six mass storages add exactly six slots to a T4')
check(math.abs(sixStats.NeighborHP-6000)<.000001,'Six energy storages add exactly sixty percent of base HP')
local rules={Rules={{Id='diminishing',Minimum=1,PerProvider=true,Diminishing=.5,AnyProviderTag={'mass_storage'},
    Effects={{Stat='ModuleSlots',Op='Add',Value=1}}}}}
local _,diminishing=R.Neighbors.Evaluate(rules,six)
check(diminishing[1].Value==1.96875,'Diminishing weights use a geometric sum without dialect-dependent exponent operators')
-- Actual native adapter: only base + neighbor go through the damage-delayed thread.
local library={LargestShieldDiameter=0}
function import(path) if path:find('Behaviors/Repair.lua',1,true) then return {Export=load('Behaviors/Repair.lua')} end;return library end
function IsDestroyed(u) return u.Destroyed end
local tick=100
function GetGameTick() return tick end
local shield={HP=5000,MaxHP=10000,RegenThreadStartTick=200,Up=true}
function shield:GetHealth() return self.HP end
function shield:GetMaxHealth() return self.MaxHP end
function shield:SetMaxHealth(value) self.MaxHP=value end
function shield:SetHealth(_,value) self.HP=value end
function shield:IsUp() return self.Up end
function shield:SetCollisionShape() end
function shield:SetDrawScale() end
function shield:UpdateShieldRatio() end
local h={MyShield=shield,ModuleStats=stats}
function h:SetEnergyMaintenanceConsumptionOverride(value) self.Upkeep=value end
function h:UpdateConsumptionValues() end
local A=load('Adapters/Shield.lua')
A.Apply(h,stats)
check(shield.RegenRate==128,'Native regen excludes module regeneration to prevent double healing')
for n=1,10 do A.TickRegen(h) end
check(shield.HP==5070 and shield.RegenThreadStartTick==200,'Modules heal continuously during damage delay without changing the native timer')
local T=load('Services/Telemetry.lua')
local live=T.Snapshot(h)
check(live.BaseRegen==0 and live.NeighborRegen==0 and live.ModuleRegen==70 and live.Regen==70,'Live source rows zero delayed regen and retain module regen under fire')
tick=201;live=T.Snapshot(h)
check(live.BaseRegen==100 and live.NeighborRegen==28 and live.Regen==198,'Live source rows restore vanilla and neighbor bonuses after damage delay')
shield.Up=false;local before=shield.HP;A.TickRegen(h)
check(shield.HP==before and T.Snapshot(h).Regen==0,'Module regeneration cannot resurrect a collapsed or disabled dome')
shield.Up=true;shield.HP=shield.MaxHP-1;A.TickRegen(h)
check(shield.HP==shield.MaxHP and T.Snapshot(h).ModuleRegen==0,'Module regeneration clamps to max health and reports zero while full')
-- Removing an independent module can free a slot ahead of a suspended install.
local q=R.Core.New('t3',s.Base);q.Rules=R.Core
for _,id in ipairs({'power_1','power_2','regen_1','repair_1'}) do
    local job=assert(R.Core.RequestInstall(q,id,R.Registry,R.Config));job.PaidWork=job.Quote.Work
    assert(not R.Core.Complete(q,job,R.Registry,R.Config))
end
q.BonusSlots=1;local pending=assert(R.Core.RequestInstall(q,'regen_2',R.Registry,R.Config))
pending.State='WaitingForSlots';pending.PaidWork=20;q.BonusSlots=0
local stopped,started=false,false
function ClassUnit(base) return function(def) return setmetatable(def,{__index=base}) end end
State=ClassUnit
function import(path)
    if path:find('Runtime.lua',1,true) then return {Export=R} end
    if path:find('InstallJobs.lua',1,true) then return {Export={Stop=function() stopped=true end,Start=function() started=true end}} end
    return {Export={}}
end
local G=load('Services/Generator.lua').MakeGenerator({UpgradingState={}})
local owner={Loadout=q,ReconcileModules=function() end}
G.ModuleAction(owner,'remove','repair_1')
check(stopped and started and q.Queue[1].Kind=='Remove' and q.Queue[2]==pending,'Slot-freeing removal runs before an installation waiting for capacity')
check(pending.PaidWork==20 and q.Installed.repair_1,'Prioritizing removal retains paid installation work and equipment until removal completes')
local stored=R.Core.New('t3',s.Base);stored.Rules=R.Core;stored.BonusSlots=1
for _,id in ipairs({'power_1','power_2','regen_1','regen_2','repair_1'}) do
    local job=assert(R.Core.RequestInstall(stored,id,R.Registry,R.Config));job.PaidWork=job.Quote.Work
    assert(not R.Core.Complete(stored,job,R.Registry,R.Config))
end
local expanded=R.Stats.Calculate(stored,R.Registry,R.Config,{{Stat='ModuleSlots',Op='Add',Value=1}})
local reduced=R.Stats.Calculate(stored,R.Registry,R.Config,{})
check(expanded.RepairBudget==10 and reduced.RepairBudget==0 and reduced.Dormant.repair_1=='OverCapacity','Storage loss makes excess modules dormant instead of retaining free effects')
check(stored.Installed.repair_1 and R.Core.Used(stored,R.Registry)==5,'Dormancy preserves paid equipment')
local restored=R.Stats.Calculate(stored,R.Registry,R.Config,{{Stat='ModuleSlots',Op='Add',Value=1}})
check(restored.RepairBudget==10 and not restored.Dormant.repair_1,'Restored storage reactivates dormant equipment')
print('PASS: '..count..' neighbor and combat-regeneration checks')
