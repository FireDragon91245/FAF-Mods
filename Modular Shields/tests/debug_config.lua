table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
local function load(path)
    local env=setmetatable({}, {__index=_G})
    return assert(loadfile('src/lua/ModularShields/'..path,'t',env))()
end
local R=load('Bootstrap.lua').Build(load)
local Schema=load('DebugParameters.lua')
local Exchange=assert(loadfile('../FireDragon Mod Loader/src/lua/FireDragon/InformationExchange.lua'))()
local count=0
local function check(value,message) count=count+1;assert(value,message) end
local function rejects(fn) check(not pcall(fn),'invalid parameter rejected before commit') end
local Transport=assert(loadfile('../FireDragon Mod Loader/src/lua/FireDragon/ExchangeTransport.lua'))()
local simBus,uiBus=Exchange.New(),Exchange.New()
local sent,applied,packets={},{},{}
local actor={player=0,army=1,actor=true,cheats=true}
local server=Transport.Attach(simBus,{realm='Sim',clock=function() return 0 end,
    send=function(packet) table.insert(packets,packet) end})
local client=Transport.Attach(uiBus,{realm='UI',session='debug-test',clock=function() return 0 end,
    send=function(packet) table.insert(sent,packet) end})
local function sync()
    local commands=sent;sent={}
    for _,packet in ipairs(commands) do server.Receive(packet,actor) end
    server.Flush()
    for _,packet in ipairs(packets) do client.Receive(packet) end
    packets={}
end
local jobs={Start=function() end,Stop=function(host) host.Stopped=(host.Stopped or 0)+1 end}
local env=setmetatable({IsDestroyed=function(host) return host.Dead end}, {__index=_G})
env.import=function(path)
    if path:find('InformationExchange.lua',1,true) then return {Export=simBus} end
    if path:find('DebugParameters.lua',1,true) then return {Export=Schema} end
    if path:find('Runtime.lua',1,true) then return {Export=R} end
    if path:find('InstallJobs.lua',1,true) then return {Export=jobs} end
    error(path)
end
assert(loadfile('src/lua/ModularShields/Services/DebugConfig.lua','t',env))()
local sim=env.Export
sim.InitSim();sync()
check(simBus.HasConfig(Schema.Key) and uiBus.Get(Schema.Key).HPMultiplier==1,'single Sim publication discovers in UI')
check(sim.InitUI==nil and sim.OnSync==nil and sim.HandleCallback==nil,'shield mod has no UI transport implementation')
for _,id in ipairs({8,2}) do
    sim.Track({EntityId=id,ReconcileModules=function(self) table.insert(applied,self.EntityId) end})
end
local live=uiBus.View(Schema.Key)
live.HPMultiplier=3
check(#sent==1 and uiBus.Get(Schema.Key).HPMultiplier==1,'UI submits nonoptimistic config update')
sync()
check(R.Config.Debug.HPMultiplier==3 and applied[1]==2 and applied[2]==8,'accepted shared transport update applies in entity order')
check(#sent==0 and uiBus.Get(Schema.Key).HPMultiplier==3,'authoritative sync never echoes')
for key,value in pairs({HPMultiplier=0,AdditionalRegen=10001,IgnoreResources=1,unknown=true}) do
    uiBus.SetPath(Schema.Key,{key},value);sync()
    check(uiBus.ConfigStatus(Schema.Key).error=='invalid_value','remote schema validation rejects '..key)
end
check(uiBus.Get(Schema.Key).HPMultiplier==3,'rejection leaves authoritative value intact')
rejects(function() simBus.SetPath(Schema.Key,{'HPMultiplier'},1.5) end)
actor.cheats=false
live.IgnoreResources=true;sync()
check(not R.Config.Debug.IgnoreResources and not uiBus.Get(Schema.Key).IgnoreResources,'generic cheat gate prevents simulation change')
check(uiBus.ConfigStatus(Schema.Key).denied,'generic config status exposes denial')
actor.cheats=true;actor.actor=false
live.HPMultiplier=4;sync()
check(R.Config.Debug.HPMultiplier==3,'observer cannot edit settings')
actor.actor=true
simBus.SetPath(Schema.Key,{'AdditionalSlots'},10);sync()
check(R.Config.Debug.AdditionalSlots==10 and uiBus.Get(Schema.Key).AdditionalSlots==10,'sim mods edit once and all UI mirrors update')

local state=R.Core.New('t3',{Mass=1000,Energy=10000,Upkeep=100,ShieldMaxHP=10000,ShieldSize=40,ShieldRegen=100})
state.Rules=R.Core
R.Config.Debug=Schema.Defaults()
R.Config.Debug.HPMultiplier=3;R.Config.Debug.AdditionalSlots=10;R.Config.Debug.AdditionalRegen=10000
R.Config.Debug.AdditionalRepair=1000;R.Config.Debug.IgnoreResources=true
local stats=R.Stats.Calculate(state,R.Registry,R.Config)
check(stats.ShieldMaxHP==30000 and state.Base.ShieldMaxHP==10000,'HP multiplier changes base without compounding or blueprint edits')
check(stats.ModuleSlots==14 and stats.ModuleRegen==10000 and stats.ShieldRegen==10100,'flat slots and damage-independent regen survive normal caps')
check(stats.RepairBudget==0,'additional repair requires an active repair module')
state.Installed.repair_1={Quote=R.Core.Quote(state,'repair_1',R.Registry,R.Config)}
stats=R.Stats.Calculate(state,R.Registry,R.Config)
check(stats.RepairBudget==1010 and stats.Upkeep==0 and stats.IgnoreResources,'repair addition and ignored shield upkeep')
R.Config.Debug=Schema.Defaults()
stats=R.Stats.Calculate(state,R.Registry,R.Config)
check(stats.ModuleSlots==4 and stats.ShieldMaxHP==10000 and stats.ModuleRegen==0 and stats.Upkeep>0,'disabling restores normal stats')

local previousCalls=0
local hook=setmetatable({Shield={OnEnergyDepleted=function() previousCalls=previousCalls+1 end},
    Class=function(base) return function(def) return setmetatable(def,{__index=base}) end end,
    import=function() return {Export=R} end}, {__index=_G})
assert(loadfile('src/hook/lua/shield.lua','t',hook))()
local dome={Owner={Blueprint={ModularShield={}}}}
R.Config.Debug.IgnoreResources=true
hook.Shield.OnEnergyDepleted(dome)
check(previousCalls==0 and dome.NoEnergyToSustain==false,'modular dome stays online at zero energy')
hook.Shield.OnEnergyDepleted({Owner={Blueprint={}}})
R.Config.Debug.IgnoreResources=false;hook.Shield.OnEnergyDepleted(dome)
check(previousCalls==2,'vanilla shields and disabled flag retain normal energy behavior')
print('PASS: '..count..' shield configuration, bridge, validation and gameplay checks')
