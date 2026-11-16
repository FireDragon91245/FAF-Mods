table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
math.atan2=math.atan2 or math.atan
function table.deepcopy(t)
    if type(t)~='table' then return t end
    local copy={};for k,v in pairs(t) do copy[k]=table.deepcopy(v) end;return copy
end
local cache={}
local root='src/lua/ModularShields/'
local tick=100
local effects=0
function import(path)
    if path=='/lua/shield.lua' then return {LargestShieldDiameter=0} end
    if path:find('Adapters/Visuals.lua',1,true) then return {Export={Burst=function() effects=effects+1 end}} end
    local rel=assert(path:match('/lua/ModularShields/(.*)'))
    if not cache[rel] then local env=setmetatable({}, {__index=_G});assert(loadfile(root..rel,'t',env))();cache[rel]=env end
    return cache[rel]
end
function IsDestroyed(e) return not e or e.Destroyed end
function IsEnemy(a,b) return a~=b and a~=-1 and b~=-1 end
function GetGameTick() return tick end
function ForkThread(fn,...) local co=coroutine.create(fn);assert(coroutine.resume(co,...));return co end
function WaitTicks(n) coroutine.yield(n) end
function KillThread(co) if coroutine.status(co)~='dead' then assert(coroutine.close(co)) end end
function Warp(e,p) e.Position={p[1],p[2],p[3]} end
function CreateCollisionDetector()
    return {WatchBone=function() end,EnableTerrainCheck=function() end,Enable=function() end}
end
function GetTerrainHeight() return 0 end
function GetSurfaceHeight() return 0 end
function GetUnitsInRect() return {} end
function ChangeState(e,state) e.State=state end
ScenarioInfo={size={512,512}}
categories={LAND=1,AIR=2,MOBILE=1}
local R=import('/mods/ModularShields/lua/ModularShields/Runtime.lua').Export
local Combat=import('/mods/ModularShields/lua/ModularShields/Services/Combat.lua').Export
local Ground=import('/mods/ModularShields/lua/ModularShields/Behaviors/GroundBarrier.lua').Export
local Assist=import('/mods/ModularShields/lua/ModularShields/Adapters/Assistance.lua').Export
local Transfer=import('/mods/ModularShields/lua/ModularShields/Services/Transfer.lua').Export
local count=0
local function check(v,msg) count=count+1;assert(v,msg) end
local function host(id)
    local h={EntityId=id or 1,Army=1,Position={100,0,100},Blueprint={SizeX=4},ModuleStats={Capabilities={atomized=true,ballistic=true,deflector=true}}}
    local s={Owner=h,Size=40,HP=1000,MaxHP=1000,Up=true,Enabled=true,Recharged=true,OnState={},OffState={},DamageDrainedState={},EnergyDrainedState={},RechargeState={}}
    function s:IsUp() return self.Up end
    function s:GetEntityId() return 1000+h.EntityId end
    function s:GetPosition() return h.Position end
    function s:GetHealth() return self.HP end
    function s:GetMaxHealth() return self.MaxHP end
    function s:SetHealth(_,hp) self.HP=hp end
    function s:ApplyDamage(instigator,damage,vector,kind,spill)
        self.Hits=(self.Hits or 0)+1;self.HP=self.HP-damage;self.LastVector=vector;self.Spill=spill;self.LastInstigator=instigator
        if self.HP<=0 then self.Up=false end
    end
    h.MyShield=s
    function h:GetPosition() return self.Position end
    function h:GetGuards() return self.Guards or {} end
    h.Loadout={Queue={{PaidWork=0,Quote={Work=100}}}}
    return h
end
local function projectile(id,cats)
    -- FAF Projectile does not cache EntityId; the native getter is available.
    local p={NativeId=id,Army=2,Position={80,5,100},Blueprint={BlueprintId='test',CategoriesHash=cats or {MISSILE=true}},DamageData={DamageAmount=50},Velocity={1,-1,0}}
    function p:GetEntityId() return self.NativeId end
    function p:GetPosition() return self.Position end
    function p:GetVelocity() return table.unpack(self.Velocity) end
    function p:SetVelocity(x,y,z) self.Velocity={x,y,z} end
    function p:TrackTarget(v) self.Tracking=v end
    function p:SetCollision(v) self.Collision=v end
    function p:SetAcceleration(v) self.Acceleration=v end
    function p:SetTurnRate(v) self.TurnRate=v end
    function p:SetNewTargetGround(v) self.Target=v end
    function p:SetLocalAngularVelocity() end
    function p:SetLifetime(v) self.Lifetime=v end
    function p:Destroy() self.Destroyed=true end
    return p
end
local h=host()
local nuke=projectile(10,{STRATEGIC=true,MISSILE=true})
nuke.InnerRing={Damage=700};nuke.OuterRing={Damage=400}
check(Combat.Classify(nuke)=='nuclear','Nuclear classifier separate from ballistics')
check(Combat.Resolve(nuke,h,'nuclear'),'Nuke is intercepted')
check(nuke.Destroyed and nuke.DamageData.DamageAmount==0 and not nuke.InnerRing and not nuke.OuterRing,'Nuke destroyed and all instance damage paths cleared')
check(h.MyShield.HP==-100 and not h.MyShield.Up and effects==1,'Whole blast contained even when hit collapses shield')
check(not Combat.Resolve(nuke,host(2),'nuclear'),'Overlapping dome cannot resolve twice')
local friendly=projectile(11);friendly.Army=1
check(not Combat.Resolve(friendly,host(),'ballistic') and not friendly.Destroyed,'Friendly missiles keep stock behavior')
local ordinary=projectile(12,{DIRECTFIRE=true})
check(not Combat.Resolve(ordinary,host(),'ordinary'),'Ordinary shield retains ordinary behavior')
h=host();h.BarrierActive=true
check(Combat.Resolve(ordinary,h,'ordinary'),'Legendary intercepts otherwise piercing ordinary projectile')
local reflect=projectile(13,{INDIRECTFIRE=true});reflect.Blueprint.BlueprintId='/projectiles/TIFArtillery01/TIFArtillery01_proj.bp'
check(Combat.Classify(reflect)=='reflect','Explicit physical projectile policy uses normalized blueprint ID')
h=host()
check(Combat.Resolve(reflect,h,'reflect') and not reflect.Destroyed and reflect.Tracking==false,'Reflection preserves projectile and disables old tracking')
check(reflect.Velocity[1]<0 and reflect.TurnRate==0,'Reflected velocity points out of dome')
check(Combat.Try(reflect,h.MyShield),'Reflection cooldown ignores immediate recollision')
check(not reflect.ModularResolution,'Reflected shots retain ordinary damage and attacker attribution')
local expanded=projectile(52,{INDIRECTFIRE=true})
expanded.Blueprint.BlueprintId='/projectiles/AIFQuanticCluster01/AIFQuanticCluster01_proj.bp'
check(Combat.Classify(expanded)=='reflect','Artillery outside the former five-projectile allowlist is reflected')
local flak=projectile(53,{ANTIAIR=true});flak.Blueprint.General={Category='Artillery'}
check(Combat.Classify(flak)=='ordinary','Anti-air flak does not enter the ground-artillery reflect pool')
local nuclearShell=projectile(54,{INDIRECTFIRE=true});nuclearShell.InnerRing={Damage=1000};nuclearShell.OuterRing={Damage=1000}
check(Combat.Classify(nuclearShell)=='nuclear','Nuclear artillery keeps nuclear containment semantics')
nuclearShell.InnerRing=nil;nuclearShell.OuterRing=nil;nuclearShell.DamageData.NukeInnerRingDamage=1000
check(Combat.Classify(nuclearShell)=='nuclear','Weapon-provided nuclear rings take precedence over artillery reflection')
-- Swept tracking catches a missile which moves through an entire dome in a tick.
h=host();Combat.Register(h)
local fast=projectile(14);fast.Position={50,0,100};Combat.Track(fast);fast.Position={150,0,100}
check(fast.ModularTrackId==14 and fast.EntityId==nil,'Native projectile getter supplies deterministic tracking ID')
check(Combat.Try(fast) and fast.Destroyed,'Swept collision catches fast/piercing missile')
check(pcall(Combat.Forget,fast) and not fast.ModularTrackId,'Tracked projectile cleanup works without cached EntityId')
local cosmetic=projectile(90,{})
cosmetic.Blueprint.BlueprintId='/effects/entities/UnitTeleport01/UnitTeleport01_proj.bp'
check(pcall(Combat.Track,cosmetic) and not cosmetic.ModularTrackId,'Commander teleport effects are excluded from threat tracking')
check(pcall(Combat.Forget,cosmetic),'Untracked effect cleanup does not index a nil ID')
Combat.Unregister(h)
-- Each aircraft body, including experimentals/transports, shares bounce count.
local plane={Army=2,DeathCrashDamage=8000,Position={80,5,100},Trash={Add=function() end},Blueprint={BlueprintId='uaa0310',CategoriesHash={EXPERIMENTAL=true,TRANSPORTATION=true}}}
function plane:DetachFrom() self.Detached=true end
function plane:AttachBoneTo(_,parent) self.Attached=parent end
function plane:Destroy() self.Destroyed=true end
local collider=projectile(15,{HELPER=true});collider.Plane=plane;collider.PlaneBone=0
local cargo={DeathCrashDamage=100};plane.cargoCache={cargo}
h=host();h.MyShield.HP=100000;h.MyShield.MaxHP=100000
check(Combat.Resolve(collider,h,'crash'),'Czar/transport uses the same deflection path')
check(plane.Attached==collider and collider.Velocity[1]<0 and collider.Velocity[2]>0,'Falling body physically attached and deflected out/up')
check(plane.DeathCrashDamage==0 and plane.ModularCrashContained,'First bounce suppresses all remaining ground crash damage')
check(cargo.ModularCrashContained and cargo.DeathCrashDamage==0 and cargo.DeathWeaponEnabled==false,'Deferred transport cargo death paths are contained')
local bounceDamage=100000-h.MyShield.HP
check(Combat.Resolve(collider,h,'crash') and h.MyShield.Hits==1,'Same contact cannot count twice')
tick=tick+R.Config.Crash.BounceCooldownTicks
check(Combat.Resolve(collider,h,'crash') and plane.ModularBounceCount==2,'A later landing counts as second bounce')
tick=tick+R.Config.Crash.BounceCooldownTicks
local before=h.MyShield.HP
check(Combat.Resolve(collider,h,'crash') and plane.Destroyed and collider.Destroyed,'Third bounce breaks up body without normal impact')
check(before-h.MyShield.HP>bounceDamage and effects==4,'Breakup causes larger shield damage and independent visual effect')
-- Real assigned engineers count once; paused, busy, remote and other-army ones do not.
h=host()
local function engineer(id,x)
    local e={EntityId=id,Army=1,Position={x or 101,0,100},Blueprint={CategoriesHash={ENGINEER=true},Economy={MaxBuildDistance=10}}}
    function e:GetGuardedUnit() return self.Assigned and h end
    function e:GetFocusUnit() return nil end
    function e:GetPosition() return self.Position end
    function e:GetFractionComplete() return 1 end
    function e:GetCommandQueue() return self.Busy and {1,2,3} or {1} end
    function e:IsPaused() return self.Paused end
    function e:SetPaused(v) self.Paused=v end
    function e:GetBuildRate() return self.NativeRate or 20 end
    function e:SetBuildRate(rate) self.NativeRate=rate end
    function e:UpdateConsumptionValues() self.NativeDraw=self.ActiveConsumption and 10 or 0 end
    function e:SetWorkProgress(progress) self.WorkProgress=progress end
    function e:ClearFocusEntity() self.FocusCleared=(self.FocusCleared or 0)+1 end
    e.Assigned=true;return e
end
local e1,e2,remote,busy,paused,enemy=engineer(20),engineer(21),engineer(22,200),engineer(23),engineer(24),engineer(25)
busy.Busy=true;paused.Paused=true;enemy.Army=2
h.Guards={e1,e2,remote,busy,paused,enemy}
check(Assist.Rate(h,R.Config)==80 and h.ModuleAssistantCount==2,'Only two valid assigned in-range engineers accelerate work')
check(not e1.Paused and not e2.Paused and e1.NativeRate==0 and e2.NativeRate==0,'Claimed assistants block native work without a disabled icon')
e2.Assigned=false
check(Assist.Rate(h,R.Config)==60 and not e2.Paused,'Reassigned engineer is released immediately')
e1.Paused=true
check(Assist.Rate(h,R.Config)==40,'Player pause withdraws scripted contribution')
Assist.ReleaseAll(h)
check(e1.Paused and paused.Paused,'Cleanup preserves player pause settings')
-- Native guard commands keep their target while native focus and work pause.
h=host()
function h:GetSkirtRect() return 94,94,106,106 end
local edge=engineer(26,116)
function edge:GetGuardedUnit() return h end -- deliberately stale after stop
function edge:GetCommandQueue() return self.Command and {self.Command} or {} end
edge.Command={commandType=15,targetId=h.EntityId}
h.Guards={edge}
check(Assist.Rate(h,R.Config)==60 and not edge.Paused,'Assistant range is measured from the native construction skirt')
edge.Command={commandType=2,targetId=h.EntityId}
check(Assist.Rate(h,R.Config)==40 and not edge.Paused,'A new active move order withdraws work despite stale native focus')
edge.Command={commandType=20,target=h}
check(Assist.Rate(h,R.Config)==60,'A native repair order can contribute to fitting')
edge.Command=nil
check(Assist.Rate(h,R.Config)==40 and not edge.Paused,'Stop withdraws the contribution even if native focus still points at the generator')
edge.Command={commandType=15,target=h};Assist.Rate(h,R.Config)
edge.Position={117,0,100}
check(Assist.Rate(h,R.Config)==40 and not edge.Paused,'Leaving the construction skirt range releases the assistant')
edge.Position={101,0,100};Assist.Rate(h,R.Config)
edge.Dead=true
check(Assist.Rate(h,R.Config)==40 and not edge.ModularAssistOwner,'Dead assistants release their scripted claim')
Assist.ReleaseAll(h)
-- Native chassis replacement keeps quotes, partial jobs, HP and recharge state.
h=host();h.Loadout.Queue={}
local idle=engineer(27)
idle.ActiveConsumption=true
function idle:OnPrepareArmToBuild() self.Opened=true end
function idle:BuildManipulatorSetEnabled(value) self.ArmEnabled=value end
function idle:StartBuildingEffects() self.NativeEffects=true end
local originalPrepare,originalEffects=idle.OnPrepareArmToBuild,idle.StartBuildingEffects
h.Guards={idle}
local originalSet,originalUpdate=idle.SetBuildRate,idle.UpdateConsumptionValues
check(Assist.Rate(h,R.Config)==40 and h.ModuleAssistantCount==0 and not idle.ModularAssistOwner,'Idle guards retain native chassis repair without contributing module work')
check(idle.SetBuildRate==originalSet and idle.UpdateConsumptionValues==originalUpdate,'No module job leaves native chassis work and resource consumption untouched')
idle:OnPrepareArmToBuild();idle:StartBuildingEffects()
check(idle.Opened and idle.NativeEffects,'Native chassis repair keeps normal arm animation and effects')
h.Loadout.Queue={{PaidWork=40,Quote={Work=100}}};Assist.Rate(h,R.Config)
check(idle.WorkProgress==.4,'Joining an installation midway immediately shows its current progress')
check(idle.Opened and idle.ArmEnabled and idle.ModularAssistActive and not idle.Paused,'Module work opens and enables the build arm without pausing')
idle:SetBuildRate(50)
check(idle.NativeRate==0 and Assist.Rate(h,R.Config)==90,'Build-rate buffs update scripted assistance while native repair remains blocked')
h.Loadout.Queue={};Assist.Rate(h,R.Config)
check(not idle.ModularAssistOwner and not idle.ModularAssistActive and idle.NativeRate==50,'Completion restores the latest buffed native chassis repair rate')
check(idle.WorkProgress==0,'Completion clears the assistant native bar while it waits for the next module')
idle.WorkProgress=.8;Assist.Rate(h,R.Config)
check(idle.WorkProgress==.8,'Idle chassis repair retains its native progress bar')
idle.Assigned=false;Assist.Rate(h,R.Config)
check(not idle.ModularAssistOwner and idle.NativeRate==50 and idle.SetBuildRate==originalSet and idle.UpdateConsumptionValues==originalUpdate,'Reassignment restores the latest buffed rate and original native methods')
check(idle.OnPrepareArmToBuild==originalPrepare and idle.StartBuildingEffects==originalEffects,'Reassignment restores the original native animation and effect callbacks')
-- A pause/stall releases module ownership so builders can repair chassis normally.
h.Loadout.Queue={{PaidWork=25,Quote={Work=100}}};idle.Assigned=true;Assist.Rate(h,R.Config)
h.InstallPaused=true;Assist.Rate(h,R.Config)
check(not idle.ModularAssistOwner and idle.NativeRate==50,'Pausing modules restores native chassis repairs')
h.InstallPaused=false;Assist.Rate(h,R.Config);h.Loadout.Queue[1].State='WaitingForSlots';Assist.Rate(h,R.Config)
check(not idle.ModularAssistOwner and idle.NativeRate==50,'Waiting for module slots does not suppress chassis repairs')
local source=host()
source.Loadout=R.Core.New('t3',{Mass=1000,Energy=10000,Upkeep=100,ShieldMaxHP=1000,ShieldSize=40,ShieldRegen=100})
source.Loadout.Installed.power_1={Id='power_1',Quote={Upkeep=10,Mass=100,Energy=1000,Work=560}}
local job=assert(R.Core.RequestInstall(source.Loadout,'power_2',R.Registry,R.Config))
job.PaidWork=100;source.MyShield.HP=350;source.MyShield.RegenThreadStartTick=tick+30
source.MyShield.DepletedByDamage=true;source.MyShield.Up=false;source.MyShield.ModularChargeDeadline=tick+70
local snapshot=Transfer.Snapshot(source,true)
local target=host(2)
target.Loadout=R.Core.New('t4',{Mass=3000,Energy=30000,Upkeep=200,ShieldMaxHP=2000,ShieldSize=50,ShieldRegen=150})
target.Loadout.Rules=R.Core
function target:ReconcileModules() self.Stats=R.Stats.Calculate(self.Loadout,R.Registry,R.Config);self.MyShield.MaxHP=self.Stats.ShieldMaxHP end
Transfer.Restore(target,snapshot)
check(target.Loadout.Installed.power_1.Quote.Upkeep==10 and target.Stats.Upkeep==210,'Upgrade preserves old quoted upkeep instead of repricing')
check(target.Stats.ShieldMaxHP==4000 and target.MyShield.HP==350,'Upgrade scales staged effects and preserves absolute HP')
check(target.Loadout.Queue[1].PaidWork==100 and target.Loadout.Queue[1].Quote.Mass==100,'Partial job/quote transferred')
check(target.MyShield.State==target.MyShield.DamageDrainedState and target.MyShield.ModularResumeCharge==7,'Collapsed dome retains remaining recharge delay')
check(#Transfer.Snapshot(source,false).Queue==0,'Capture/give excludes unfinished work')
-- Ground barrier: grandfather interior units, push back enemies, respect friends.
h=host();h.BarrierActive=true
local enemies={}
function h:GetAIBrain() return {GetUnitsAroundPoint=function() return enemies end} end
local function ground(id,x,army)
    local u={EntityId=id,Army=army or 2,Position={x,0,100},Blueprint={SizeX=2,SizeZ=2}}
    function u:GetPosition() return self.Position end
    function u:CanPathTo() return true end
    function u:GetCurrentLayer() return 'Land' end
    function u:IsUnitState() return false end
    return u
end
local insider,outside,friend=ground(30,100),ground(31,125),ground(32,125,1)
enemies={insider,outside,friend};Ground.Tick(h,R.Config.Barrier)
check(insider.Position[1]==100,'Units inside at activation may leave')
outside.Position={115,0,100};friend.Position={115,0,100};Ground.Tick(h,R.Config.Barrier)
check(outside.Position[1]==125 and friend.Position[1]==115,'Enemy is returned outside; friendly units retain access')
insider.Position={125,0,100};Ground.Tick(h,R.Config.Barrier);insider.Position={115,0,100};Ground.Tick(h,R.Config.Barrier)
check(insider.Position[1]==125,'Grandfathered unit cannot re-enter after exiting')
local teleported=ground(33,100);enemies[#enemies+1]=teleported;Ground.Tick(h,R.Config.Barrier)
check(math.abs(teleported.Position[1]-100)>20,'New transport/teleport arrivals are ejected')
h.BarrierActive=false;Ground.Tick(h,R.Config.Barrier)
check(not h.BarrierRecords,'Collapse clears ground restrictions immediately')
h=host();h.BarrierActive=true
local heavy=ground(60,125);heavy.Blueprint.Physics={MaxSpeed=4};heavy.Blueprint.Economy={BuildCostMass=1000}
enemies={heavy};function h:GetAIBrain() return {GetUnitsAroundPoint=function() return enemies end} end
Ground.Tick(h,R.Config.Barrier);heavy.Position={115,0,100};Ground.Tick(h,R.Config.Barrier)
check(h.MyShield.HP==950 and h.MyShield.Hits==1,'A weighted ground crossing charges the shield once, even when both inside and swept tests detect it')
check(heavy.Position[1]>=128,'Push distance gives a speed-four unit at least 1.5 seconds of return travel')
heavy.Position={115,0,100};Ground.Tick(h,R.Config.Barrier)
check(h.MyShield.Hits==1 and heavy.Position[1]>=128,'Repeated contact still ejects the unit but does not spam shield damage during cooldown')
tick=tick+R.Config.Barrier.HitCooldownTicks;heavy.Position={115,0,100};Ground.Tick(h,R.Config.Barrier)
check(h.MyShield.HP==900,'A later crossing after cooldown pays its weighted shield impact again')
local light=ground(61,115);light.Blueprint.Economy={BuildCostMass=250}
enemies={light};Ground.Tick(h,R.Config.Barrier)
check(h.MyShield.HP==887.5,'Lighter units cause proportionally less shield damage')
tick=tick+R.Config.Barrier.HitCooldownTicks;h.MyShield.HP=10
local follower=ground(62,115);enemies={heavy,follower};heavy.Position={115,0,100}
Ground.Tick(h,R.Config.Barrier)
check(not h.BarrierActive and follower.Position[1]==115,'A collapsing shield immediately stops pushing subsequent units')
-- Live aircraft use the spherical dome rather than a terrain-height cylinder.
h=host();h.BarrierActive=true
local bomber=ground(65,140)
bomber.Position[2]=10;bomber.Blueprint.Air={MaxAirspeed=10};bomber.Blueprint.Economy={BuildCostMass=1000}
function bomber:GetCurrentLayer() return 'Air' end
function bomber:CanPathTo() error('Aircraft do not use land pathability') end
local high=ground(66,140)
high.Position[2]=30
function high:GetCurrentLayer() return 'Air' end
enemies={bomber,high};function h:GetAIBrain() return {GetUnitsAroundPoint=function() return enemies end} end
Combat.Register(h);Ground.Tick(h,R.Config.Barrier)
bomber.Position={115,10,100};high.Position={100,30,100};Ground.Tick(h,R.Config.Barrier)
check(bomber.Position[1]>134 and bomber.Position[2]==10,'Low bombers are pushed out with flight altitude preserved and 1.5 seconds of return travel')
check(h.MyShield.HP==950 and h.MyShield.Hits==1,'Aircraft crossing pays the same weighted shield impact as ground units')
check(high.Position[1]==100 and high.Position[2]==30,'Aircraft flying above the dome remain outside its volume')
bomber.Position={115,10,100};Ground.Tick(h,R.Config.Barrier)
check(h.MyShield.Hits==1 and bomber.Position[1]>134,'Aircraft cannot spam impact damage during the per-unit cooldown')
check(Combat.GroundExterior(high,{100,30,100}) and not Combat.GroundExterior(bomber,{100,10,100}),'Overlapping barrier placement uses a sphere for air units')
tick=tick+15;bomber.Position={140,10,100};Ground.Tick(h,R.Config.Barrier)
bomber.Position={60,10,100};Ground.Tick(h,R.Config.Barrier)
check(h.MyShield.Hits==2 and bomber.Position[2]==10,'Swept air crossing catches a bomber that traverses the entire dome between updates')
Combat.Unregister(h)
-- Actual generator activation state machine, including warmup and provider/power loss.
function ClassUnit(parent) return function(def) return setmetatable(def,{__index=parent}) end end
State=ClassUnit
local Generator=import('/mods/ModularShields/lua/ModularShields/Services/Generator.lua').Export.MakeGenerator({UpgradingState={}})
h=host();h.Loadout={Capabilities={legendary_power_support=true}};h.ModuleStats={Capabilities={ground_barrier=true},Dormant={}}
local energy=100
function h:GetAIBrain() return {GetEconomyStored=function() return energy end} end
Generator.UpdateBarrierState(h)
check(not h.BarrierActive and h.BarrierReason=='WarmingUp','Legendary starts with warmup')
tick=tick+R.Config.Barrier.WarmupTicks;Generator.UpdateBarrierState(h)
check(h.BarrierActive and h.BarrierReason=='Active','Legendary activates after warmup')
h.Loadout.Capabilities.legendary_power_support=nil;Generator.UpdateBarrierState(h)
check(not h.BarrierActive and h.BarrierReason=='MissingAdjacentPower' and not h.BarrierReadyTick,'Provider loss drops barrier immediately')
h.Loadout.Capabilities.legendary_power_support=true;Generator.UpdateBarrierState(h)
check(not h.BarrierActive and h.BarrierReason=='WarmingUp','Provider restoration requires fresh warmup')
energy=0;Generator.UpdateBarrierState(h)
check(not h.BarrierActive and h.BarrierReason=='NoPower','Power loss drops barrier')
energy=100;h.MyShield.Up=false;Generator.UpdateBarrierState(h)
check(not h.BarrierActive and h.BarrierReason=='ShieldDown','Collapsed dome cannot keep barrier')
-- The concrete projectile guard stops subclass side effects before they begin.
local sideEffects=0
ClassProjectile=ClassUnit
local Guard=import('/mods/ModularShields/lua/ModularShields/Adapters/ProjectileHook.lua').Export
local Wrapped=Guard.Wrap({OnImpact=function() sideEffects=sideEffects+1 end})
local guarded=projectile(50);guarded.ModularResolution={HostId=1}
Wrapped.OnImpact(guarded,'Terrain')
check(sideEffects==0,'Concrete guard prevents custom impact/death effects after interception')
local unguarded=projectile(51);unguarded.ModularPrevious={300,0,300};unguarded.Position={301,0,300}
Wrapped.OnImpact(unguarded,'Terrain')
check(sideEffects==1,'Unintercepted projectile keeps concrete subclass behavior')
local Impact=import('/mods/ModularShields/lua/ModularShields/Adapters/Impact.lua').Export
local ripple=0
local shield=host().MyShield
function shield:CreateImpactEffect() ripple=ripple+1;self.ModularImpactSerial=(self.ModularImpactSerial or 0)+1 end
Impact.Apply(shield,nil,1,{1,0,0})
check(ripple==1,'Special interception guarantees shield impact effect despite native throttle')
local nativeApply=shield.ApplyDamage
function shield:ApplyDamage(...) nativeApply(self,...);self:CreateImpactEffect() end
Impact.Apply(shield,nil,1,{1,0,0})
check(ripple==2,'Existing native impact ripple is not duplicated')
print('PASS: '..count..' gameplay/lifecycle contract checks')

