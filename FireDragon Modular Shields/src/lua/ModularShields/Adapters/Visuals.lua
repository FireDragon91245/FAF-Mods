local Entity = import('/lua/sim/Entity.lua').Entity
local function Burst(position,army,nuclear,scale)
    -- Independent effect entity: no projectile impact, damage, force or death weapon.
    local entity=Entity({Army=army})
    entity:SetCollisionShape('None')
    entity:SetVizToFocusPlayer('Always')
    entity:SetVizToAllies('Always')
    entity:SetVizToEnemies('Intel')
    Warp(entity,position)
    local effects=nuclear and {
        '/effects/emitters/nuke_base03_emit.bp',
        '/effects/emitters/nuke_plume_01_emit.bp',
        '/effects/emitters/nuke_head_fire_01_emit.bp',
    } or {'/effects/emitters/destruction_explosion_concussion_ring_01_emit.bp',
        '/effects/emitters/destruction_explosion_fire_plume_01_emit.bp'}
    for _,path in ipairs(effects) do
        CreateAttachedEmitter(entity,-1,army,path):ScaleEmitter(scale or 1)
    end
    ForkThread(function() WaitTicks(nuclear and 150 or 40); if not IsDestroyed(entity) then entity:Destroy() end end)
end
Export={Burst=Burst}
return Export
