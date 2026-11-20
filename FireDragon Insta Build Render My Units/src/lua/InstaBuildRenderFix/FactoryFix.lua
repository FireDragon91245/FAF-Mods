-- Keeps factory roll-off intact when a unit completes in the tick it was started.
--
-- Vanilla factories attach the unit to their build bone in BuildingState.Main, a thread
-- forked by OnStartBuild. OnStopBuild later issues the move-off-factory order and
-- FinishBuildThread detaches the unit. With ai_InstaBuild, OnStopBuild runs before the
-- forked Main: the move-off order is issued first, then Main attaches (and hides) the
-- finished unit, which drops the order. The unit is detached in place and stays in the
-- middle of the factory, clipping into it.
--
-- The fix performs Main's attach synchronously in OnStopBuild when Main has not started
-- yet, so the vanilla order attach -> move-off -> detach is restored, and the late Main
-- is skipped. When Main did start but was cut off before showing the unit again, the
-- unit is shown as soon as FinishBuildThread is done.

--- BuildingState.Main wrapper: true when the unit was already attached by OnStopBuild.
function SkipBuildingMain(unit)
    if not unit then return false end
    if unit.InstaFixAttached then return true end
    unit.InstaFixMainStarted = true
    return false
end

--- BuildingState.Main wrapper: Main reached its own ShowBone.
function BuildingMainFinished(unit)
    if unit then unit.InstaFixMainFinished = true end
end

local function Alive(entity, isDestroyed)
    return entity and not entity.Dead and not isDestroyed(entity)
end

--- Whether OnStopBuild completes a unit whose BuildingState.Main has not run yet.
function NeedsAttach(factory, unit, order, isDestroyed)
    if order == 'Upgrade' or factory.FactoryBuildFailed then return false end
    if not (Alive(factory, isDestroyed) and Alive(unit, isDestroyed)) then return false end
    if unit.InstaFixMainStarted or unit.InstaFixAttached then return false end
    if not (factory.BuildBoneRotator and factory.RollOffPoint) then return false end
    return unit:GetFractionComplete() >= 1
end

--- Mirrors BuildingState.Main without the anti-rotation hide and the build effects.
function Attach(factory, unit)
    local spin, x, y, z = factory:CalculateRollOffPoint()
    local rollOffPoint = factory.RollOffPoint
    rollOffPoint[1], rollOffPoint[2], rollOffPoint[3] = x, y, z
    factory.BuildBoneRotator:SetGoal(spin)
    unit:AttachBoneTo(-2, factory, factory.Blueprint.Display.BuildAttachBone or 0)
    unit.InstaFixAttached = true
end

--- OnStopBuild wrapper, runs before the vanilla OnStopBuild.
function BeforeStopBuild(factory, unit, order, isDestroyed)
    if NeedsAttach(factory, unit, order, isDestroyed) then
        Attach(factory, unit)
        return true
    end
    return false
end

--- Ticks FinishBuildThread waits before detaching a unit attached by OnStopBuild.
--- The engine moves an attached unit onto the build bone one tick after AttachBoneTo;
--- vanilla detaches in the same tick, which leaves the unit on the ground inside the
--- factory. Holding it like vanilla's BuildingState.Main lifts it onto the platform
--- and lets the build rotator face it towards the roll-off point first.
HoldTicks = 3

function HoldBeforeFinish(unit, isDestroyed)
    if Alive(unit, isDestroyed) and unit.InstaFixAttached then return HoldTicks end
    return 0
end

--- FinishBuildThread wrapper, runs after the vanilla thread changed the factory state.
--- ChangeState destroyed a Main that hid the unit and never reached its ShowBone.
function AfterFinishBuild(unit, isDestroyed)
    if not Alive(unit, isDestroyed) then return false end
    if unit.InstaFixMainStarted and not unit.InstaFixMainFinished and unit.RenderGuardHiddenSince then
        unit:ShowBone(0, true)
        return true
    end
    return false
end
