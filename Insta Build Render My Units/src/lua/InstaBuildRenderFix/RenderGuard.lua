-- Repairs units whose root bone stays hidden after construction.
--
-- Vanilla hides the root bone while a unit is being built and shows it again from a
-- thread a few ticks later (FactoryUnit.BuildingState.Main, StructureUnit upgrade
-- effects). With ai_InstaBuild the build finishes before that thread shows the unit:
-- ChangeState destroys the factory thread between HideBone and ShowBone, and an
-- upgrade's UpgradingState.Main hides the new structure after OnStopBuild already
-- showed it. The unit then stays invisible forever.
--
-- The guard tracks root-bone visibility and, during a short window after a unit
-- finishes construction, shows it again once it has been hidden longer than any
-- legitimate construction hide.

-- Longest legitimate construction hide is 4 ticks (Seraphim air factory roll-out).
HoldTicks = 10
-- How long after completion a stray hide can still appear (upgrade thread runs 1 tick later).
WatchTicks = 50

local Excluded = { COMMAND = true, EXTERNALFACTORYUNIT = true }

--- Records a HideBone(0) call. Re-hiding an already hidden unit keeps the original time.
function OnRootHidden(unit, tick)
    if not unit.RenderGuardHiddenSince then
        unit.RenderGuardHiddenSince = tick
    end
end

--- Records a ShowBone(0) call.
function OnRootShown(unit)
    unit.RenderGuardHiddenSince = nil
end

--- Whether a completed unit should be watched for a stuck construction hide.
function ShouldWatch(unit, builder)
    if not builder or unit.Dead then return false end
    local hash = unit.Blueprint and unit.Blueprint.CategoriesHash
    if hash then
        for category in pairs(Excluded) do
            if hash[category] then return false end
        end
    end
    return true
end

--- Whether the unit is hidden by something other than construction.
local function IntentionallyHidden(unit)
    return unit.TeleportFx_IsInvisible or unit.RenderGuardInStorage
end

function ShouldRepair(unit, tick)
    local since = unit.RenderGuardHiddenSince
    if not since or unit.Dead or IntentionallyHidden(unit) then return false end
    return tick - since >= HoldTicks
end

--- Shows the unit and re-applies the sub-bone visibility vanilla sets after construction.
function Repair(unit)
    unit:ShowBone(0, true)
    if unit.HideLandBones then unit:HideLandBones() end
    if unit.ShowEnhancementBones then unit:ShowEnhancementBones() end
end

--- Thread body: watch a freshly completed unit and repair it at most once.
---@param waitTicks fun(ticks: number)
---@param getTick fun(): number
---@param isDestroyed fun(unit): boolean
---@return boolean repaired
function Watch(unit, waitTicks, getTick, isDestroyed)
    for _ = 1, WatchTicks do
        waitTicks(1)
        if unit.Dead or isDestroyed(unit) then return false end
        if ShouldRepair(unit, getTick()) then
            Repair(unit)
            return true
        end
    end
    return false
end
