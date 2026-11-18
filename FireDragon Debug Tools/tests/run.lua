-- Economy (sim), key binding and hook wiring tests for FireDragon Debug Tools.
table.getn = table.getn or function(t) return #t end

local function loadModule(path, env)
    env = setmetatable(env or {}, { __index = _G })
    assert(loadfile(path, 't', env))()
    return env
end

local count = 0
local function check(value, message) count = count + 1; assert(value, message) end

-- Mirrors the engine: max storage is the base storage plus the storage of every live
-- helper unit of the army. GiveStorage must not be used (the engine keeps only one
-- GiveStorage bonus across both resources).
local HelperStorage = { fdt0001 = { ENERGY = 1000000 }, fdt0002 = { MASS = 1000000 } }
local world

local function newBrain(maxEnergy, maxMass)
    local brain = { stored = { ENERGY = 0, MASS = 0 }, base = { ENERGY = maxEnergy or 1000, MASS = maxMass or 500 } }
    local stat = { Economy_MaxStorage_Energy = 'ENERGY', Economy_MaxStorage_Mass = 'MASS' }
    function brain:Max(resource)
        local max = self.base[resource]
        for _, unit in ipairs(world) do
            if unit.brain == self and not unit.destroyed then max = max + (HelperStorage[unit.id][resource] or 0) end
        end
        return max
    end
    function brain:GetArmyStat(name, default) return { Value = self:Max(stat[name]) or default } end
    function brain:GetEconomyStored(resource) return self.stored[resource] end
    function brain:GiveResource(resource, amount) self.stored[resource] = self.stored[resource] + amount end
    function brain:GiveStorage() error('GiveStorage must not be used') end
    function brain:GetArmyStartPos() return 10, 20 end
    function brain:IsDefeated() return self.defeated == true end
    return brain
end

local Exchange=assert(loadfile('../FireDragon Mod Loader/src/lua/FireDragon/InformationExchange.lua'))()
local Transport=assert(loadfile('../FireDragon Mod Loader/src/lua/FireDragon/ExchangeTransport.lua'))()
local Messages=assert(loadfile('src/lua/FireDragonDebugTools/Messages.lua'))()
local function newEconomy(brains, options)
    options=options or {};world={}
    local bus,clientBus=Exchange.New({clock=function() return 0 end}),Exchange.New({clock=function() return 0 end})
    local packets={}
    local server=Transport.Attach(bus,{realm='Sim',clock=function() return 0 end,send=function(packet) packets[#packets+1]=packet end})
    local client
    local source={player=0,army=options.army,actor=options.army~=nil and brains[options.army]~=nil,cheats=options.cheats~=false}
    client=Transport.Attach(clientBus,{realm='UI',session='economy-test',clock=function() return 0 end,
        send=function(packet)
            server.Receive(packet,source);server.Flush()
            for _,response in ipairs(packets) do client.Receive(response) end;packets={}
        end})
    local env={ArmyBrains=brains,IsDestroyed=function(unit) return unit.destroyed==true end,
        GetSurfaceHeight=function() return 7 end,
        import=function(path)
            if path:find('InformationExchange.lua',1,true) then return {Export=bus} end
            if path:find('Messages.lua',1,true) then return {Export=Messages} end
            error(path)
        end}
    env.CreateUnitHPR=function(id,army,x,y,z)
        local unit={id=id,army=army,brain=brains[army],pos={x,y,z}}
        function unit:Destroy() self.destroyed=true end
        table.insert(world,unit);return unit
    end
    env.forks={};env.ForkThread=function(fn) table.insert(env.forks,fn);return #env.forks end
    env.WaitTicks=function() coroutine.yield() end
    local E=loadModule('src/lua/FireDragonDebugTools/Economy.lua',env)
    E.client=clientBus
    function E.Message(data) E.Start();return clientBus.Sim.Request(Messages.SetResource,data,{replyMode='First'}) end
    return E
end

local function helpers(id)
    local n = 0
    for _, unit in ipairs(world) do
        if unit.id == id and not unit.destroyed then n = n + 1 end
    end
    return n
end

-- The helper blueprints carry the storage the mocks assume, and stay out of unit lists and cap.
for id, storage in pairs(HelperStorage) do
    local upper = string.upper(id)
    local bp = assert(io.open('src/units/' .. upper .. '/' .. upper .. '_unit.bp')):read('a')
    local field = storage.ENERGY and 'StorageEnergy' or 'StorageMass'
    check(string.find(bp, field .. ' = 1000000', 1, true), id .. ' has its storage')
    check(string.find(bp, "'DUMMYUNIT'", 1, true) and string.find(bp, 'CapCost = 0', 1, true), id .. ' is hidden and free')
    local script = assert(io.open('src/units/' .. upper .. '/' .. upper .. '_script.lua')):read('a')
    check(string.find(script, "import('/lua/sim/unit.lua').Unit", 1, true) and string.find(script, 'TypeClass = ' .. upper, 1, true), id .. ' script is a Unit')
end

-- Fill tops storage up exactly to the maximum.
local brain = newBrain()
local E = newEconomy({ brain })
brain.stored.ENERGY = 250
check(E.Fill(brain, 'ENERGY') == 750 and brain.stored.ENERGY == 1000, 'Fill gives only the missing amount')
check(E.Fill(brain, 'ENERGY') == 0 and brain.stored.ENERGY == 1000, 'Full storage receives nothing')

-- Enabling spawns a storage helper at the army start, fills, and starts one loop.
brain = newBrain(); E = newEconomy({ brain })
check(E.Set(1, 'ENERGY', true), 'Energy toggle accepted')
check(helpers('fdt0001') == 1 and world[1].army == 1 and world[1].pos[1] == 10 and world[1].pos[2] == 7 and world[1].pos[3] == 20, 'Enabling spawns the energy helper at the army start')
check(brain.stored.ENERGY == 1001000, 'Enabling fills the boosted storage')
check(E.Set(1, 'MASS', true) and helpers('fdt0002') == 1 and brain.stored.MASS == 1000500, 'Mass toggle spawns the mass helper and fills mass')
check(brain:Max('ENERGY') == 1001000 and brain:Max('MASS') == 1000500, 'Both boosts hold at the same time')
check(#E.forks == 1, 'A single resource loop serves every toggle')
check(E.Set(1, 'MASS', true) and helpers('fdt0002') == 1, 'Re-enabling does not stack helpers')

-- The loop refills every tick and exits once everything is disabled.
local loop = coroutine.create(E.forks[1])
brain.stored.ENERGY = 0; brain.stored.MASS = 3
assert(coroutine.resume(loop))
check(brain.stored.ENERGY == 1001000 and brain.stored.MASS == 1000500, 'Loop tick refills both resources')
check(E.Set(1, 'ENERGY', false) and helpers('fdt0001') == 0 and brain:Max('ENERGY') == 1000, 'Disabling removes the helper and its storage')
check(brain:Max('MASS') == 1000500, 'Disabling energy keeps the mass boost')
brain.stored.ENERGY = 0
assert(coroutine.resume(loop))
check(brain.stored.ENERGY == 0, 'Disabled resources are no longer refilled')
E.Set(1, 'MASS', false)
assert(coroutine.resume(loop))
check(coroutine.status(loop) == 'dead' and helpers('fdt0002') == 0, 'Loop exits when nothing is enabled')
check(E.Set(1, 'ENERGY', true) and #E.forks == 2, 'A new loop starts after the old one ended')
check(E.Set(1, 'MASS', false) and helpers('fdt0002') == 0 and table.getn(world) == 3, 'Disabling an inactive resource changes nothing')

-- Storage changes: helper storage adds to whatever the army's other storage is.
brain = newBrain(); E = newEconomy({ brain })
E.Set(1, 'ENERGY', true); E.Set(1, 'MASS', true)
brain.base.ENERGY = 6000; brain.base.MASS = 900
E.Tick()
check(brain.stored.ENERGY == 1006000 and brain.stored.MASS == 1000900, 'Built or lost storage keeps the boost and is filled')
check(helpers('fdt0001') == 1 and helpers('fdt0002') == 1, 'Storage changes spawn no extra helpers')
world[1].destroyed = true
E.Tick()
check(helpers('fdt0001') == 1 and brain.stored.ENERGY == 1006000, 'A destroyed helper is replaced on the next tick')

-- Defeated armies lose their helpers and stop the loop.
brain = newBrain(); E = newEconomy({ brain })
E.Set(1, 'ENERGY', true)
brain.defeated = true
check(E.Tick() == false and helpers('fdt0001') == 0 and E.Armies[1] == nil, 'Defeat removes helpers and toggles')

-- Invalid requests.
E = newEconomy({ newBrain() })
check(not E.Set(2, 'ENERGY', true), 'Unknown armies are rejected')
check(not E.Set(1, 'FUEL', true) and table.getn(world) == 0, 'Unknown resources are rejected')

-- Callback: command source army, cheat gating and sync snapshot.
local brains = { newBrain(), newBrain() }
E = newEconomy(brains, { army = 2 })
E.Message({ Resource = 'MASS', Enabled = true })
local snap = E.client.GetState(Messages.Economy,'2')
check(snap and snap.Mass == true and snap.Energy == false and snap.Denied == nil, 'Callback toggles and syncs the sender army')
check(table.getn(world) == 1 and world[1].army == 2, 'Only the sender army is affected')
E = newEconomy({ newBrain() }, { army = 1, cheats = false })
E.Message({ Resource = 'ENERGY', Enabled = true })
snap = E.client.GetState(Messages.Economy,'1')
check(snap.Energy == false and #E.forks == 0 and table.getn(world) == 0, 'Without cheats the toggle is refused')
E = newEconomy({ newBrain() }, { army = nil })
E.Message({ Resource = 'ENERGY', Enabled = true })
check(table.getn(world)==0, 'Observer request creates no helpers')
E = newEconomy({ newBrain() }, { army = 1 })
E.Message('bad')
check(table.getn(world)==0, 'Malformed resource message creates no helpers')
-- Key bindings.
local K = loadModule('src/lua/FireDragonDebugTools/Keys.lua')
local b = K.Bindings({ ['Ctrl-A'] = 'select_all' })
check(b and b[K.DefaultKey] == K.KeyAction, 'Default key is bound when free')
check(K.Bindings({ [K.DefaultKey] = 'something_else' }) == nil, 'An occupied default key is left alone')
b = K.Bindings({ ['F7'] = K.ActionName, [K.DefaultKey] = 'something_else' })
check(b and b.F7 == K.KeyAction and b[K.DefaultKey] == nil, 'User bindings for the action are restored instead')
check(K.KeyAction.category == 'mods' and not string.find(K.ActionName, '-', 1, true), 'Action is valid for the keymapper')
check(string.find(K.KeyAction.action, "/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Panel.lua", 1, true), 'Action opens the panel')

-- Startup registers the exchange endpoint; no custom callback/sync hooks remain.
local started=false
local hook=loadModule('src/hook/lua/simInit.lua',{
    BeginSession=function() return 'previous' end,
    import=function() return {Start=function() started=true end} end,
})
check(hook.BeginSession()=='previous' and started,'Sim startup registers the Exchange service')

local actions = loadModule('src/hook/lua/keymap/keyactions.lua', { keyActions = {}, import = function() return K end })
check(actions.keyActions[K.ActionName] == K.KeyAction, 'Key action is registered')
local descriptions = loadModule('src/hook/lua/keymap/keydescriptions.lua', { keyDescriptions = {}, import = function() return K end })
check(descriptions.keyDescriptions[K.ActionName] == K.Description, 'Key description is registered')

local added
hook = loadModule('src/hook/lua/ui/game/gamemain.lua', {
    CreateUI = function() return 'ui' end,
    IN_AddKeyMapTable = function(t) added = t end,
    import = function(path)
        if path == '/lua/keymap/keymapper.lua' then return { GetCurrentKeyMap = function() return {} end } end
        return K
    end,
})
check(hook.CreateUI(true) == 'ui' and added == nil, 'Replays get no key binding')
check(hook.CreateUI(false) == 'ui' and added[K.DefaultKey] == K.KeyAction, 'Games bind the panel key')

print(string.format('PASS: %d debug tools checks', count))
