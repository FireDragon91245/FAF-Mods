-- Economy (sim), key binding and hook wiring tests for FireDragon Debug Tools.
table.getn = table.getn or function(t) return #t end

local function loadModule(path, env)
    env = setmetatable(env or {}, { __index = _G })
    assert(loadfile(path, 't', env))()
    return env
end

local count = 0
local function check(value, message) count = count + 1; assert(value, message) end

local function newBrain(maxEnergy, maxMass)
    local brain = { stored = { ENERGY = 0, MASS = 0 }, max = { ENERGY = maxEnergy or 1000, MASS = maxMass or 500 }, storageCalls = {} }
    local stat = { Economy_MaxStorage_Energy = 'ENERGY', Economy_MaxStorage_Mass = 'MASS' }
    function brain:GetArmyStat(name, default) return { Value = self.max[stat[name]] or default } end
    function brain:GetEconomyStored(resource) return self.stored[resource] end
    function brain:GiveResource(resource, amount) self.stored[resource] = self.stored[resource] + amount end
    function brain:GiveStorage(kind, amount)
        table.insert(self.storageCalls, kind .. ':' .. amount)
        local resource = kind == 'Energy' and 'ENERGY' or 'MASS'
        self.max[resource] = self.max[resource] + amount
    end
    return brain
end

local function newEconomy(brains, options)
    options = options or {}
    local env = {
        ArmyBrains = brains,
        Sync = {},
        CheatsEnabled = function() return options.cheats ~= false end,
        import = function(path)
            assert(path == '/lua/simutils.lua', path)
            return { GetCurrentCommandSourceArmy = function() return options.army end }
        end,
    }
    env.forks = {}
    env.ForkThread = function(fn) table.insert(env.forks, fn); return #env.forks end
    env.WaitTicks = function() coroutine.yield() end
    return loadModule('src/lua/FireDragonDebugTools/Economy.lua', env)
end

-- Fill tops storage up exactly to the maximum.
local brain = newBrain()
local E = newEconomy({ brain })
brain.stored.ENERGY = 250
check(E.Fill(brain, 'ENERGY') == 750 and brain.stored.ENERGY == 1000, 'Fill gives only the missing amount')
check(E.Fill(brain, 'ENERGY') == 0 and brain.stored.ENERGY == 1000, 'Full storage receives nothing')

-- Enabling boosts storage, fills immediately and starts one loop.
brain = newBrain(); E = newEconomy({ brain })
check(E.Set(1, 'ENERGY', true), 'Energy toggle accepted')
check(brain.storageCalls[1] == 'Energy:' .. E.StorageBoost, 'Enabling adds the storage boost')
check(brain.stored.ENERGY == 1000 + E.StorageBoost, 'Enabling fills the boosted storage')
check(E.Set(1, 'MASS', true) and brain.stored.MASS == 500 + E.StorageBoost, 'Mass toggle fills mass')
check(#E.forks == 1, 'A single resource loop serves every toggle')
check(E.Set(1, 'MASS', true) and #brain.storageCalls == 2, 'Re-enabling does not stack the boost')

-- The loop refills every tick and exits once everything is disabled.
local loop = coroutine.create(E.forks[1])
brain.stored.ENERGY = 0; brain.stored.MASS = 3
assert(coroutine.resume(loop))
check(brain.stored.ENERGY == 1000 + E.StorageBoost and brain.stored.MASS == 500 + E.StorageBoost, 'Loop tick refills both resources')
check(E.Set(1, 'ENERGY', false) and brain.storageCalls[3] == 'Energy:' .. -E.StorageBoost, 'Disabling removes the boost')
brain.stored.ENERGY = 0
assert(coroutine.resume(loop))
check(brain.stored.ENERGY == 0, 'Disabled resources are no longer refilled')
E.Set(1, 'MASS', false)
assert(coroutine.resume(loop))
check(coroutine.status(loop) == 'dead', 'Loop exits when nothing is enabled')
check(E.Set(1, 'ENERGY', true) and #E.forks == 2, 'A new loop starts after the old one ended')
check(E.Set(1, 'MASS', false) and #brain.storageCalls == 5, 'Disabling an inactive resource changes nothing')

-- Invalid requests.
E = newEconomy({ newBrain() })
check(not E.Set(2, 'ENERGY', true), 'Unknown armies are rejected')
check(not E.Set(1, 'FUEL', true), 'Unknown resources are rejected')

-- Callback: command source army, cheat gating and sync snapshot.
local brains = { newBrain(), newBrain() }
E = newEconomy(brains, { army = 2 })
E.HandleCallback({ Resource = 'MASS', Enabled = true })
local snap = E.Sync.FireDragonDebug['2']
check(snap and snap.Mass == true and snap.Energy == false and snap.Denied == nil, 'Callback toggles and syncs the sender army')
check(brains[1].storageCalls[1] == nil and brains[2].storageCalls[1] ~= nil, 'Only the sender army is affected')
E = newEconomy({ newBrain() }, { army = 1, cheats = false })
E.HandleCallback({ Resource = 'ENERGY', Enabled = true })
snap = E.Sync.FireDragonDebug['1']
check(snap.Denied == true and snap.Energy == false and #E.forks == 0, 'Without cheats the toggle is refused')
E = newEconomy({ newBrain() }, { army = nil })
E.HandleCallback({ Resource = 'ENERGY', Enabled = true })
check(E.Sync.FireDragonDebug == nil, 'Observers are ignored')
E = newEconomy({ newBrain() }, { army = 1 })
E.HandleCallback('bad')
check(E.Sync.FireDragonDebug == nil, 'Malformed data is ignored')

-- Key bindings.
local K = loadModule('src/lua/FireDragonDebugTools/Keys.lua')
local b = K.Bindings({ ['Ctrl-A'] = 'select_all' })
check(b and b[K.DefaultKey] == K.KeyAction, 'Default key is bound when free')
check(K.Bindings({ [K.DefaultKey] = 'something_else' }) == nil, 'An occupied default key is left alone')
b = K.Bindings({ ['F7'] = K.ActionName, [K.DefaultKey] = 'something_else' })
check(b and b.F7 == K.KeyAction and b[K.DefaultKey] == nil, 'User bindings for the action are restored instead')
check(K.KeyAction.category == 'mods' and not string.find(K.ActionName, '-', 1, true), 'Action is valid for the keymapper')
check(string.find(K.KeyAction.action, "/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Panel.lua", 1, true), 'Action opens the panel')

-- Hooks forward to the previous implementations.
local handled
local hook = loadModule('src/hook/lua/SimCallbacks.lua', {
    DoCallback = function(name) return 'previous:' .. name end,
    import = function() return { HandleCallback = function(data) handled = data end } end,
})
check(hook.DoCallback('Other', {}) == 'previous:Other', 'Other callbacks reach vanilla')
check(hook.DoCallback('FireDragonDebugSetResource', { x = 1 }) == nil and handled.x == 1, 'Debug callback is handled')

local synced
hook = loadModule('src/hook/lua/UserSync.lua', {
    OnSync = function() return 'previous' end,
    Sync = { FireDragonDebug = { ['1'] = {} } },
    import = function() return { OnSync = function(data) synced = data end } end,
})
check(hook.OnSync() == 'previous' and synced['1'], 'Sync data reaches the panel')

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
