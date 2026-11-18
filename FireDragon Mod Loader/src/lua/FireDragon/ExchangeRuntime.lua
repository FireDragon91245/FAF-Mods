-- The only engine-specific UI/Sim transport and lifecycle wiring.
local Runtime={}
local Transport=import('/mods/FireDragonModLoader/lua/FireDragon/ExchangeTransport.lua').Export
local function clock() return GetGameTimeSeconds() end
local lastFullTick
function Runtime.StartSim(bus)
    if bus._transport then return bus._transport end
    local transport=Transport.Attach(bus,{realm='Sim',clock=clock,focus=function() return GetFocusArmy() end,
        send=function(packet) Sync.FireDragonExchange=packet end})
    return transport
end
function Runtime.Flush(bus)
    local tick=GetGameTick()
    local full=not lastFullTick or tick-lastFullTick>=50
    if full then lastFullTick=tick end
    Runtime.StartSim(bus).Flush(full)
end
function Runtime.StartUI(bus)
    if bus._transport then return bus._transport end
    -- A UI-only correlation nonce. It grants no authority in Sim.
    local session=tostring(GetSystemTimeSeconds())..':'..tostring(math.random(1,1000000))..':'..tostring(math.random(1,1000000))
    local transport=Transport.Attach(bus,{realm='UI',clock=clock,session=session,
        send=function(packet) SimCallback({Func='FireDragonExchange',Args=packet}) end})
    import('/lua/ui/game/gamemain.lua').AddBeatFunction(function() transport.Tick();import('/mods/FireDragonModLoader/lua/FireDragon/Bindings.lua').Export.Step() end)
    transport.Hello()
    return transport
end
function Runtime.ReceiveCommand(bus,packet)
    local army=import('/lua/simutils.lua').GetCurrentCommandSourceArmy()
    local source={realm='UI',army=army,player=GetCurrentCommandSource(),cheats=CheatsEnabled(),
        actor=army~=nil and army>=1 and ArmyBrains[army]~=nil}
    return Runtime.StartSim(bus).Receive(packet,source)
end
function Runtime.ReceiveSync(bus,packet) return Runtime.StartUI(bus).Receive(packet) end
Export=Runtime
return Export
