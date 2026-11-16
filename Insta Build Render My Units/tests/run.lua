-- RenderGuard rules and Unit hook wiring, driven by a simulated tick clock.
table.getn = table.getn or function(t) return #t end

local function loadModule(path, env)
    env = setmetatable(env or {}, { __index = _G })
    assert(loadfile(path, 't', env))()
    return env
end

local Guard = loadModule('src/lua/InstaBuildRenderFix/RenderGuard.lua')
local count = 0
local function check(value, message) count = count + 1; assert(value, message) end

-- Simulated sim: a tick counter plus events scheduled at absolute ticks.
local function newSim()
    local sim = { tick = 0, events = {} }
    function sim.at(tick, fn) sim.events[tick] = sim.events[tick] or {}; table.insert(sim.events[tick], fn) end
    function sim.wait(ticks)
        for _ = 1, ticks do
            sim.tick = sim.tick + 1
            for _, fn in ipairs(sim.events[sim.tick] or {}) do fn() end
        end
    end
    function sim.now() return sim.tick end
    return sim
end

local function newUnit(sim, categories)
    local unit = { Blueprint = { CategoriesHash = categories or {} }, calls = {}, hidden = false }
    function unit:HideBone(bone) if bone == 0 then self.hidden = true; Guard.OnRootHidden(self, sim.now()) end end
    function unit:ShowBone(bone)
        table.insert(self.calls, 'show')
        if bone == 0 then self.hidden = false; Guard.OnRootShown(self) end
    end
    function unit:HideLandBones() table.insert(self.calls, 'land') end
    function unit:ShowEnhancementBones() table.insert(self.calls, 'enh') end
    return unit
end

local function never() return false end

-- Factory insta build: the factory thread hides the unit, then ChangeState kills it before ShowBone.
local sim = newSim()
local unit = newUnit(sim)
sim.at(1, function() unit:HideBone(0, true) end)
check(Guard.Watch(unit, sim.wait, sim.now, never), 'Stuck factory hide is repaired')
check(not unit.hidden and sim.tick == 1 + Guard.HoldTicks, 'Repair happens once the hide outlasts HoldTicks')
check(table.concat(unit.calls, ',') == 'show,land,enh', 'Repair re-applies land and enhancement bones')

-- Upgrade: the new structure is shown on completion, then the late upgrade thread hides it again.
sim = newSim(); unit = newUnit(sim)
unit:ShowBone(0, true)
sim.at(1, function() unit:HideBone(0, true) end)
check(Guard.Watch(unit, sim.wait, sim.now, never) and not unit.hidden, 'Late upgrade hide is repaired')

-- Hidden before completion and never shown again.
sim = newSim(); unit = newUnit(sim)
unit:HideBone(0, true)
check(Guard.Watch(unit, sim.wait, sim.now, never) and sim.tick == Guard.HoldTicks, 'Hide carried over from construction is repaired')

-- Re-hiding keeps the original hide time.
sim = newSim(); unit = newUnit(sim)
unit:HideBone(0, true)
sim.at(5, function() unit:HideBone(0, true) end)
Guard.Watch(unit, sim.wait, sim.now, never)
check(sim.tick == Guard.HoldTicks, 'Repeated HideBone does not restart the hold timer')

-- Legitimate short hides (factory 3 ticks, Seraphim air factory 4 ticks) are left alone.
for _, length in ipairs({ 3, 4 }) do
    sim = newSim(); unit = newUnit(sim)
    sim.at(1, function() unit:HideBone(0, true) end)
    sim.at(1 + length, function() unit:ShowBone(0, true) end)
    unit.calls = {}
    check(not Guard.Watch(unit, sim.wait, sim.now, never), length .. '-tick hide is not repaired')
    check(sim.tick == Guard.WatchTicks and table.getn(unit.calls) == 1, 'Watch ends after the window without extra ShowBone')
end

-- Intentional hides: teleport and internal storage.
for _, flag in ipairs({ 'TeleportFx_IsInvisible', 'RenderGuardInStorage' }) do
    sim = newSim(); unit = newUnit(sim)
    unit[flag] = true
    unit:HideBone(0, true)
    check(not Guard.Watch(unit, sim.wait, sim.now, never) and unit.hidden, flag .. ' keeps the unit hidden')
end

-- Hide after the watch window is outside the guard's responsibility.
sim = newSim(); unit = newUnit(sim)
sim.at(Guard.WatchTicks + 1, function() unit:HideBone(0, true) end)
check(not Guard.Watch(unit, sim.wait, sim.now, never), 'Hides after the window are ignored')

-- Dead or destroyed units stop the watch.
sim = newSim(); unit = newUnit(sim)
unit:HideBone(0, true)
sim.at(2, function() unit.Dead = true end)
check(not Guard.Watch(unit, sim.wait, sim.now, never) and sim.tick == 2, 'Dead units stop the watch')
sim = newSim(); unit = newUnit(sim)
unit:HideBone(0, true)
check(not Guard.Watch(unit, sim.wait, sim.now, function() return sim.tick >= 3 end) and sim.tick == 3, 'Destroyed units stop the watch')

-- Watch eligibility.
check(Guard.ShouldWatch(newUnit(sim), {}), 'Built units are watched')
check(not Guard.ShouldWatch(newUnit(sim), nil), 'Units created without a builder are not watched')
check(not Guard.ShouldWatch(newUnit(sim, { COMMAND = true }), {}), 'Commanders (warp-in hide) are not watched')
check(not Guard.ShouldWatch(newUnit(sim, { EXTERNALFACTORYUNIT = true }), {}), 'External factories (always hidden) are not watched')

-- Hook wiring: the class wrapper forwards to the engine methods and feeds the guard.
local engine = { hides = {}, shows = {}, storage = {} }
local BaseUnit = {
    HideBone = function(self, bone, children) table.insert(engine.hides, bone) end,
    ShowBone = function(self, bone, children) table.insert(engine.shows, bone) end,
    OnStorageChange = function(self, loading) table.insert(engine.storage, loading) end,
    OnStopBeingBuilt = function(self) return 'base' end,
    ForkThread = function(self, fn, ...) engine.fork = { fn = fn, args = { ... } } end,
}
local tick = 7
local hookEnv = loadModule('src/hook/lua/sim/Unit.lua', {
    Unit = BaseUnit,
    ClassUnit = function(base) return function(spec) return setmetatable(spec, { __index = base }) end end,
    import = function(path) assert(path == '/mods/InstaBuildRenderFix/lua/InstaBuildRenderFix/RenderGuard.lua', path); return Guard end,
    GetGameTick = function() return tick end,
    WaitTicks = 'WaitTicks', IsDestroyed = 'IsDestroyed',
})
local Hooked = hookEnv.Unit
check(Hooked ~= BaseUnit, 'Hook replaces Unit with a subclass')
local u = setmetatable({ Blueprint = { CategoriesHash = {} } }, { __index = Hooked })
u:HideBone('Turret', true)
check(u.RenderGuardHiddenSince == nil and engine.hides[1] == 'Turret', 'Non-root bones are forwarded but not tracked')
u:HideBone(0, true)
check(u.RenderGuardHiddenSince == 7 and engine.hides[2] == 0, 'Root hides are tracked with the game tick')
u:ShowBone(0, true)
check(u.RenderGuardHiddenSince == nil and engine.shows[1] == 0, 'Root shows clear the tracking')
u:OnStorageChange(true)
check(u.RenderGuardInStorage == true and engine.storage[1] == true, 'Storage loading is flagged and forwarded')
u:OnStorageChange(false)
check(u.RenderGuardInStorage == nil, 'Storage unloading clears the flag')
check(u:OnStopBeingBuilt(nil, 'Land') == 'base' and engine.fork == nil, 'No watch without a builder')
check(u:OnStopBeingBuilt({}, 'Land') == 'base' and engine.fork.fn == Guard.Watch, 'Completed builds fork the watch')
check(engine.fork.args[1] == 'WaitTicks' and engine.fork.args[2] == hookEnv.GetGameTick and engine.fork.args[3] == 'IsDestroyed', 'Watch receives the sim primitives')

print(string.format('PASS: %d render guard checks', count))
