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
Guard.Watch(unit, sim.wait, sim.now, never)
check(not unit.hidden, 'Stuck factory hide is repaired')
check(not unit.hidden and sim.tick == 1 + Guard.HoldTicks, 'Repair happens once the hide outlasts HoldTicks')
check(table.concat(unit.calls, ',') == 'show,land,enh', 'Repair re-applies land and enhancement bones')

-- Upgrade: the new structure is shown on completion, then the late upgrade thread hides it again.
sim = newSim(); unit = newUnit(sim)
unit:ShowBone(0, true)
sim.at(1, function() unit:HideBone(0, true) end)
Guard.Watch(unit, sim.wait, sim.now, never)
check(not unit.hidden, 'Late upgrade hide is repaired')

-- Hidden before completion and never shown again.
sim = newSim(); unit = newUnit(sim)
unit:HideBone(0, true)
Guard.Watch(unit, sim.wait, sim.now, never)
check(not unit.hidden and sim.tick == Guard.HoldTicks, 'Hide carried over from construction is repaired')

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
    Guard.Watch(unit, sim.wait, sim.now, never)
    check(not unit.hidden, length .. '-tick hide ends normally')
    check(sim.tick == Guard.WatchTicks and table.getn(unit.calls) == 1, 'Watch ends after the window without extra ShowBone')
end

-- Intentional hides: teleport and internal storage.
for _, flag in ipairs({ 'TeleportFx_IsInvisible', 'RenderGuardInStorage' }) do
    sim = newSim(); unit = newUnit(sim)
    unit[flag] = true
    unit:HideBone(0, true)
    Guard.Watch(unit, sim.wait, sim.now, never)
    check(unit.hidden, flag .. ' keeps the unit hidden')
end

-- Hide after the watch window is outside the guard's responsibility.
sim = newSim(); unit = newUnit(sim)
sim.at(Guard.WatchTicks + 1, function() unit:HideBone(0, true) end)
Guard.Watch(unit, sim.wait, sim.now, never)
check(sim.tick == Guard.WatchTicks and #unit.calls == 0, 'Hides after the window are ignored')

-- Dead or destroyed units stop the watch.
sim = newSim(); unit = newUnit(sim)
unit:HideBone(0, true)
sim.at(2, function() unit.Dead = true end)
Guard.Watch(unit, sim.wait, sim.now, never)
check(sim.tick == 2 and unit.hidden, 'Dead units stop the watch')
sim = newSim(); unit = newUnit(sim)
unit:HideBone(0, true)
Guard.Watch(unit, sim.wait, sim.now, function() return sim.tick >= 3 end)
check(sim.tick == 3 and unit.hidden, 'Destroyed units stop the watch')

-- Model FAF's scheduler: a yielded result is a numeric tick count; completion
-- must have no result. Boolean final returns previously triggered warning spam.
for _, ending in ipairs({ 'timeout', 'repair', 'dead', 'destroyed' }) do
    sim = newSim(); unit = newUnit(sim)
    if ending ~= 'timeout' then unit:HideBone(0, true) end
    if ending == 'dead' then sim.at(2, function() unit.Dead = true end) end
    local watcher = coroutine.create(function()
        return Guard.Watch(unit, coroutine.yield, sim.now,
            function() return ending == 'destroyed' and sim.tick >= 2 end)
    end)
    while true do
        local results = table.pack(coroutine.resume(watcher))
        check(results[1], ending .. ': watch resumes successfully')
        if coroutine.status(watcher) == 'dead' then
            check(results.n == 1, ending .. ': completion returns no scheduler instruction')
            break
        end
        check(results.n == 2 and type(results[2]) == 'number' and results[2] >= 1,
            ending .. ': yields only a valid tick count')
        sim.wait(results[2])
    end
end

-- Watch eligibility.
check(Guard.ShouldWatch(newUnit(sim), {}), 'Built units are watched')
check(not Guard.ShouldWatch(newUnit(sim), nil), 'Units created without a builder are not watched')
check(not Guard.ShouldWatch(newUnit(sim, { COMMAND = true }), {}), 'Commanders (warp-in hide) are not watched')
check(not Guard.ShouldWatch(newUnit(sim, { EXTERNALFACTORYUNIT = true }), {}), 'External factories (always hidden) are not watched')

-- Hook wiring: the class wrapper forwards to the engine methods and feeds the guard.
local engine = { hides = {}, shows = {}, storage = {}, starts = {} }
local BaseUnit = {
    HideBone = function(self, bone, children) table.insert(engine.hides, bone) end,
    ShowBone = function(self, bone, children) table.insert(engine.shows, bone) end,
    OnStorageChange = function(self, loading) table.insert(engine.storage, loading) end,
    OnStopBeingBuilt = function(self) return 'base' end,
    OnStartBuild = function(self, built, order)
        table.insert(engine.starts, order)
        if order == 'Upgrade' then
            built.DisallowCollisions, built.CanTakeDamage, built.IsUpgrade, built.shape = true, false, true, 'None'
        end
        return true
    end,
    ForkThread = function(self, fn, ...) engine.fork = { fn = fn, args = { ... } } end,
}
local Upgrade = loadModule('src/lua/InstaBuildRenderFix/UpgradeFix.lua')
local modules = {
    ['/mods/FireDragon Insta Build Render My Units/lua/InstaBuildRenderFix/RenderGuard.lua'] = Guard,
    ['/mods/FireDragon Insta Build Render My Units/lua/InstaBuildRenderFix/UpgradeFix.lua'] = Upgrade,
}
local tick = 7
local hookEnv = loadModule('src/hook/lua/sim/Unit.lua', {
    Unit = BaseUnit,
    ClassUnit = function(base) return function(spec) return setmetatable(spec, { __index = base }) end end,
    import = function(path) return assert(modules[path], path) end,
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

-- Upgrades: vanilla OnStartBuild makes the upgrade uncollidable and invulnerable; its
-- OnStopBeingBuilt reverts that. With ai_InstaBuild the upgrade already finished.
local function newUpgrade(finished, sphere)
    local built = { isFinishedUnit = finished, Blueprint = { SizeSphere = sphere } }
    function built:RevertCollisionShape() self.shape = 'Blueprint' end
    function built:SetCollisionShape(shape, x, y, z, size) self.shape = shape .. size end
    return built
end
local insta = newUpgrade(true)
check(u:OnStartBuild(insta, 'Upgrade') == true and engine.starts[1] == 'Upgrade', 'OnStartBuild forwards to vanilla')
check(insta.shape == 'Blueprint' and insta.CanTakeDamage == true and insta.DisallowCollisions == false and insta.IsUpgrade == nil,
    'Finished insta upgrade gets collision and damage back')
local sphere = newUpgrade(true, 3)
u:OnStartBuild(sphere, 'Upgrade')
check(sphere.shape == 'Sphere3', 'Sphere collision from the blueprint is re-applied')
local normal = newUpgrade(nil)
u:OnStartBuild(normal, 'Upgrade')
check(normal.shape == 'None' and normal.CanTakeDamage == false and normal.IsUpgrade == true, 'Upgrades still being built are left to vanilla')
check(not Upgrade.NeedsRestore(newUpgrade(true), 'FactoryBuild'), 'Non-upgrade orders are ignored')
local dead = newUpgrade(true); dead.IsUpgrade = true; dead.Dead = true
check(not Upgrade.NeedsRestore(dead, 'Upgrade'), 'Dead upgrades are ignored')

-- Factory roll-off: vanilla FactoryUnit flow driven through the FactoryUnit hook.
local Fix = loadModule('src/lua/InstaBuildRenderFix/FactoryFix.lua')
local function isDestroyed(entity) return entity.destroyed == true end

local log
local VanillaFactory = {
    CalculateRollOffPoint = function(self) return 90, 1, 2, 3 end,
    OnStopBuild = function(self, unit, order)
        table.insert(log, 'stop')
        if not self.FactoryBuildFailed and order ~= 'Upgrade' then
            unit.moveOrders = unit.attached and 1 or 0
            table.insert(log, 'move')
        end
        return 'vanilla'
    end,
    FinishBuildThread = function(self, unit, order)
        unit.attached = false
        table.insert(log, 'detach')
    end,
}
VanillaFactory.BuildingState = {
    Main = function(self)
        local unit = self.UnitBeingBuilt
        unit:HideBone(0, true)
        self.BuildBoneRotator:SetGoal(90)
        unit:AttachBoneTo(-2, self, 0)
        table.insert(log, 'main')
        coroutine.yield()
        unit:ShowBone(0, true)
    end,
}
-- Forks the hooked Main like ChangeState and runs it up to its WaitTicks.
local function startMain(factory)
    local thread = coroutine.create(HookedFactoryMain)
    assert(coroutine.resume(thread, factory))
    return thread
end
local factoryHook = loadModule('src/hook/lua/sim/units/FactoryUnit.lua', {
    FactoryUnit = VanillaFactory,
    ClassUnit = function(base) return function(spec) return setmetatable(spec, { __index = base }) end end,
    State = function(base) return function(spec) return setmetatable(spec, { __index = base }) end end,
    import = function(path) assert(path == '/mods/FireDragon Insta Build Render My Units/lua/InstaBuildRenderFix/FactoryFix.lua', path); return Fix end,
    IsDestroyed = isDestroyed,
    WaitTicks = function(ticks) table.insert(log, 'wait' .. ticks) end,
})
local HookedFactory = factoryHook.FactoryUnit
HookedFactoryMain = HookedFactory.BuildingState.Main
check(HookedFactory ~= VanillaFactory and HookedFactory.BuildingState ~= VanillaFactory.BuildingState, 'Hook replaces FactoryUnit and its BuildingState')

local function newFactory()
    local factory = setmetatable({
        Blueprint = { Display = { BuildAttachBone = 'Attachpoint' } },
        RollOffPoint = { 0, 0, 0 },
        BuildBoneRotator = { SetGoal = function(self, goal) self.goal = goal end },
        SetBusy = function(self, busy) self.busy = busy end,
        SetBlockCommandQueue = function(self, block) self.blocked = block end,
    }, { __index = HookedFactory })
    local unit = { fraction = 1, hidden = false }
    function unit:GetFractionComplete() return self.fraction end
    function unit:HideBone() self.hidden = true; self.RenderGuardHiddenSince = 1; table.insert(log, 'hide') end
    function unit:ShowBone() self.hidden = false; self.RenderGuardHiddenSince = nil; table.insert(log, 'show') end
    function unit:AttachBoneTo(bone, parent, parentBone)
        self.attached = true; self.attachBone = parentBone; table.insert(log, 'attach')
    end
    factory.UnitBeingBuilt = unit
    return factory, unit
end

-- ai_InstaBuild: OnStopBuild runs before the forked BuildingState.Main.
log = {}
local factory, built = newFactory()
check(factory:OnStopBuild(built, 'FactoryBuild') == 'vanilla', 'OnStopBuild forwards to vanilla')
check(table.concat(log, ',') == 'attach,stop,move', 'Instant build is attached before the move-off order')
check(built.moveOrders == 1 and built.attachBone == 'Attachpoint', 'Move-off order is issued to the attached unit')
check(factory.BuildBoneRotator.goal == 90 and factory.RollOffPoint[3] == 3, 'Roll-off point and rotator are set like vanilla Main')
HookedFactory.BuildingState.Main(factory)
check(table.concat(log, ',') == 'attach,stop,move' and not built.hidden, 'Late BuildingState.Main is skipped')
factory:FinishBuildThread(built, 'FactoryBuild')
check(table.concat(log, ',', 4) == 'wait3,detach' and factory.busy and factory.blocked,
    'Unit stays attached for 3 ticks on a busy factory before the vanilla detach')
check(not built.attached and not built.hidden, 'Unit is detached visible without an extra show')

-- Normal build: Main ran ticks earlier, OnStopBuild is left alone.
log = {}
factory, built = newFactory()
assert(coroutine.resume(startMain(factory)))
factory:OnStopBuild(built, 'FactoryBuild')
check(table.concat(log, ',') == 'hide,attach,main,show,stop,move', 'Normal builds keep the vanilla flow')
factory:FinishBuildThread(built, 'FactoryBuild')
check(log[7] == 'detach' and log[8] == nil, 'Normal builds are detached without a hold or an extra show')

-- Fast build: Main hid the unit and was destroyed by ChangeState before its ShowBone.
log = {}
factory, built = newFactory()
startMain(factory)
factory:OnStopBuild(built, 'FactoryBuild')
factory:FinishBuildThread(built, 'FactoryBuild')
check(table.concat(log, ',') == 'hide,attach,main,stop,move,detach,show' and not built.hidden, 'Cut-off Main hide is undone after FinishBuildThread')

-- Cases where OnStopBuild must not attach.
local function attachedBy(setup, order)
    log = {}
    local f, u = newFactory()
    setup(f, u)
    f:OnStopBuild(u, order or 'FactoryBuild')
    return u.attached == true
end
check(not attachedBy(function() end, 'Upgrade'), 'Upgrades are not attached')
check(not attachedBy(function(f) f.FactoryBuildFailed = true end), 'Failed builds are not attached')
check(not attachedBy(function(_, u) u.fraction = 0.5 end), 'Incomplete units are not attached')
check(not attachedBy(function(_, u) u.destroyed = true end), 'Destroyed units are not attached')
check(not attachedBy(function(f) f.Dead = true end), 'Dead factories do not attach')
check(not attachedBy(function(f) f.BuildBoneRotator = nil end), 'Factories without a build rotator are left alone')
log = {}
factory, built = newFactory()
built.destroyed = true
factory.UnitBeingBuilt = built
check(not Fix.AfterFinishBuild(built, isDestroyed), 'Destroyed units are not shown')

print(string.format('PASS: %d render guard checks', count))
