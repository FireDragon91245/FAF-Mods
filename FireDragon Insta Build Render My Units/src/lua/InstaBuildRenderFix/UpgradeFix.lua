-- Restores structures upgraded with ai_InstaBuild.
--
-- Vanilla Unit.OnStartBuild makes an upgrade uncollidable and invulnerable while it is
-- being built (DisallowCollisions, CanTakeDamage, collision shape 'None', IsUpgrade) and
-- the upgrade's OnStopBeingBuilt reverts that. With ai_InstaBuild the upgrade completes
-- before the builder's OnStartBuild runs, so the revert happens first and the upgraded
-- structure stays without collision and invulnerable for the rest of the game. Without
-- a collision box a factory's build platform is gone: finished units drop to the ground
-- in the middle of the factory and drive out through it.

--- Whether OnStartBuild just marked an upgrade that already finished being built.
function NeedsRestore(built, order)
    return order == 'Upgrade' and built ~= nil and not built.Dead
        and built.IsUpgrade == true and built.isFinishedUnit == true
end

--- Mirrors the upgrade branch of Unit.OnStopBeingBuilt and its sphere collision.
function Restore(built)
    built.DisallowCollisions = false
    built.CanTakeDamage = true
    built:RevertCollisionShape()
    built.IsUpgrade = nil
    local bp = built.Blueprint
    if bp and bp.SizeSphere then
        built:SetCollisionShape('Sphere', bp.CollisionSphereOffsetX or 0, bp.CollisionSphereOffsetY or 0,
            bp.CollisionSphereOffsetZ or 0, bp.SizeSphere)
    end
end

--- Unit.OnStartBuild wrapper, runs after vanilla OnStartBuild.
function AfterStartBuild(built, order)
    if NeedsRestore(built, order) then
        Restore(built)
        return true
    end
    return false
end
