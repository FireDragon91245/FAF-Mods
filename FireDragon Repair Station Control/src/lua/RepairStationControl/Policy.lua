local function Has(unit, category)
    return unit and unit.Blueprint and unit.Blueprint.CategoriesHash and unit.Blueprint.CategoriesHash[category]
end
local function ManagedBlueprint(bp)
    local cats=bp and bp.CategoriesHash or {}
    return not cats.DUMMYUNIT and not cats.INSIGNIFICANTUNIT and
        (cats.ENGINEERSTATION or (cats.POD and cats.ENGINEER)) or false
end
local function Managed(unit)
    return unit and not unit.ModuleHost and ManagedBlueprint(unit.Blueprint) or false
end
local function Silo(unit)
    return Has(unit,'SILO') and (Has(unit,'NUKE') or Has(unit,'ANTIMISSILE'))
end
local function NeedsRepair(unit)
    return unit:GetFractionComplete()<1 or unit:GetHealth()<unit:GetMaxHealth()
end
-- The engine's auto task exposes its resolved repair recipient as its focus.
-- Checking that recipient must not turn repairing an engineer into assisting
-- the engineer's unrelated queued work.
local function DirectAllowed(worker,target,settings)
    if not target or target.Dead then return true end
    if settings.DontHelpNukes and Silo(target) then return false end
    if settings.DontHelpTeam and target.Army~=worker.Army then
        return target:GetFractionComplete()==1 and target:GetHealth()<target:GetMaxHealth()
    end
    return true
end
-- Follow guard/focus chains: guarding an engineer or factory must not bypass
-- the policy on its construction target. Bound the walk for cyclic guards.
local function Allowed(worker,target,settings)
    local seen={}
    local function Visit(unit,depth)
        if not unit or unit.Dead or seen[unit] then return true end
        if depth>16 then return false end
        seen[unit]=true
        if settings.DontHelpNukes and Silo(unit) then return false end
        if settings.DontHelpTeam and unit.Army~=worker.Army then
            -- Healing an existing ally is still useful; contributing to its
            -- construction/factory work is the behavior this option excludes.
            if unit:GetFractionComplete()==1 and unit:GetHealth()<unit:GetMaxHealth() then return true end
            return false
        end
        return Visit(unit:GetFocusUnit(),depth+1) and Visit(unit:GetGuardedUnit(),depth+1)
    end
    return Visit(target,1)
end
Export={Managed=Managed,ManagedBlueprint=ManagedBlueprint,Allowed=Allowed,NeedsRepair=NeedsRepair,Silo=Silo,DirectAllowed=DirectAllowed}
return Export
