local Bindings=assert(loadfile('src/lua/FireDragon/Bindings.lua'))()
table.getn=table.getn or function(t) local n=0;while t[n+1]~=nil do n=n+1 end;return n end
local Exchange=assert(loadfile('src/lua/FireDragon/InformationExchange.lua'))()
local Transport=assert(loadfile('src/lua/FireDragon/ExchangeTransport.lua'))()
local time=0
local sim,ui=Exchange.New({clock=function() return time end}),Exchange.New({clock=function() return time end})
local commands,threads,beats={},{},{}
local function runtime(bus,realm)
    local env=setmetatable({Sync={},ArmyBrains={[1]={}},
        GetGameTimeSeconds=function() return time end,GetGameTick=function() return time*10 end,
        GetSystemTimeSeconds=function() return time end,GetCurrentCommandSource=function() return 0 end,
        GetFocusArmy=function() return 1 end,
        CheatsEnabled=function() return true end,WaitTicks=function() coroutine.yield() end,
        ForkThread=function(fn)
            local thread=coroutine.create(fn);assert(coroutine.resume(thread));table.insert(threads,thread);return thread
        end,
        SimCallback=function(command) table.insert(commands,command) end}, {__index=_G})
    env.import=function(path)
        if string.find(path,'FireDragon/Bindings.lua',1,true) then return {Export=Bindings} end
        if string.find(path,'ExchangeTransport.lua',1,true) then return {Export=Transport} end
        if path=='/lua/simutils.lua' then return {GetCurrentCommandSourceArmy=function() return 1 end} end
        if path=='/lua/ui/game/gamemain.lua' then return {AddBeatFunction=function(fn) table.insert(beats,fn) end} end
        if string.find(path,'InformationExchange.lua',1,true) then return {Export=bus} end
        error(path)
    end
    assert(loadfile('src/lua/FireDragon/ExchangeRuntime.lua','t',env))()
    local R=env.Export
    bus._StartSim=function() return R.StartSim(bus) end
    bus._StartUI=function() return R.StartUI(bus) end
    bus._ReceiveCommand=function(packet) return R.ReceiveCommand(bus,packet) end
    bus._ReceiveSync=function(packet) return R.ReceiveSync(bus,packet) end
    bus._FlushTransport=function() return R.Flush(bus) end
    return env
end
-- This test uses only Lua 5.0 syntax; loadfile environments are set with setfenv there.
local function inEnvironment(path,env)
    local fn
    if setfenv then fn=assert(loadfile(path));setfenv(fn,env)
    else fn=assert(loadfile(path,'t',env)) end
    return fn()
end
-- Construct runtime environments using the same compatibility path.
local nativeLoadfile=loadfile
if setfenv then
    loadfile=function(path,mode,env)
        local fn,err=nativeLoadfile(path)
        if fn and env then setfenv(fn,env) end
        return fn,err
    end
end
math.mod=math.mod or math.fmod
local simEnv=runtime(sim,'Sim')
simEnv.SetupSession=function() return 'previous setup' end
inEnvironment('src/hook/lua/simInit.lua',simEnv)
assert(simEnv.SetupSession()=='previous setup')
simEnv.DoCallback=function(name) return 'previous '..name end
inEnvironment('src/hook/lua/SimCallbacks.lua',simEnv)
assert(simEnv.DoCallback('Other',{})=='previous Other')
local accepted=0
sim.PublishConfig('engine',{amount=1},'ReadWrite',function(_,_,change)
    accepted=accepted+1;assert(change.source.army==1 and change.source.player==0)
end,nil,{scope='Sim',authorize='Cheats'})
local uiEnv=runtime(ui,'UI')
simEnv.ResetSyncTable=function() simEnv.Sync={} end
inEnvironment('src/hook/lua/SimSync.lua',simEnv)
uiEnv.CreateUI=function() return 'previous UI' end
inEnvironment('src/hook/lua/ui/game/gamemain.lua',uiEnv)
assert(uiEnv.CreateUI(false)=='previous UI' and table.getn(beats)==1)
uiEnv.OnSync=function() return 'previous sync' end
inEnvironment('src/hook/lua/UserSync.lua',uiEnv)
local function tick(paused)
    local batch=commands;commands={}
    for _,command in ipairs(batch) do simEnv.DoCallback(command.Func,command.Args) end
    if not paused then time=time+.1 end
    simEnv.ResetSyncTable()
    uiEnv.Sync=simEnv.Sync;simEnv.Sync={}
    assert(uiEnv.OnSync()=='previous sync')
    for _,beat in ipairs(beats) do beat() end
end
tick();assert(ui.Get('engine').amount==1)
local ticket=ui.SetPath('engine',{'amount'},2)
assert(ui.Get('engine').amount==1)
tick();assert(accepted==1 and ui.Get('engine').amount==2 and ticket:Status()=='complete')
sim.Expose('engine.ask',{requests=true,authorize='Army'})
sim.Respond('engine.ask',function(payload) return payload.amount*2 end)
ticket=ui.Sim.Request('engine.ask',{amount=4})
tick();assert(ticket:Status()=='complete' and ticket:Poll().value==8)
ticket=ui.SetPath('engine',{'amount'},3)
local pausedAt=time
tick(true);assert(time==pausedAt and ticket:Status()=='complete' and ui.Get('engine').amount==3,
    'sync beat delivers config and receipts while simulation ticks are paused')
print('PASS: engine hooks route config and request/reply through the shared runtime')
