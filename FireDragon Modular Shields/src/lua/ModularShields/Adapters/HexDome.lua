-- UEF T4 visual experiment. No gameplay, HP, collision or economy mutations.
local root = '/mods/FireDragon Modular Shields/effects/entities/UEFT4Hex/'
local function Eligible(host)
    return host.Blueprint and host.Blueprint.BlueprintId == 'mdeb4401'
end
local function HitColour(ratio)
    if ratio <= 0.30 then return 'Red' end
    if ratio <= 0.65 then return 'Yellow' end
    return 'Blue'
end
local function Impact(shield, vector)
    -- Preserve the interception adapter's native-impact deduplication contract.
    shield.ModularImpactSerial=(shield.ModularImpactSerial or 0)+1
    if IsDestroyed(shield) or not shield:IsUp() or not vector then return end
    local x,y,z = vector[1],vector[2],vector[3]
    local distance = math.sqrt(x*x+y*y+z*z)
    if distance < 0.001 then return end
    -- Always show the newest hit. At saturation, retire the oldest flash rather
    -- than dropping incoming impacts for the remainder of its lifetime.
    local impacts = shield.HexImpacts or {}
    shield.HexImpacts = impacts
    if table.getn(impacts) >= 32 then
        local oldest = table.remove(impacts,1)
        if not IsDestroyed(oldest) then oldest:Destroy() end
    end
    local Entity = import('/lua/sim/entity.lua').Entity
    local entity = Entity({Owner=shield.Owner})
    impacts[table.getn(impacts)+1] = entity
    shield.HexLiveImpacts = table.getn(impacts)
    shield.Owner.Trash:Add(entity)
    entity:SetMesh(root..'Hit'..HitColour(shield:GetHealth()/math.max(1,shield:GetMaxHealth()))..'_mesh')
    entity:SetDrawScale(shield.Size*1.002)
    Warp(entity,shield:GetPosition())
    entity:SetOrientation(OrientFromDir({-x/distance,-y/distance,-z/distance}),true)
    entity:SetVizToFocusPlayer('Always')
    entity:SetVizToAllies('Always')
    entity:SetVizToEnemies('Intel')
    entity:SetVizToNeutrals('Intel')
    WaitTicks(9)
    if not IsDestroyed(entity) then entity:Destroy() end
    -- An evicted flash's sleeping thread must not remove a newer flash's slot.
    for i,active in ipairs(impacts) do
        if active == entity then table.remove(impacts,i);break end
    end
    shield.HexLiveImpacts = table.getn(impacts)
end
local function Attach(host)
    if not Eligible(host) then return end
    -- Native shader loader is an installation dependency. Keep this choice
    -- deterministic: no local DLL/graphics checks in synchronized simulation Lua.
    local shield=host.MyShield
    if not shield or IsDestroyed(shield) or shield.HexVisualsAttached then return end
    shield.HexVisualsAttached=true
    shield.MeshBp=root..'Dome_mesh'
    -- ShieldFill writes opaque depth even with zero colour alpha. A transparent
    -- dome must not keep that stock companion (including after recharge).
    shield.MeshZBp=''
    if shield.MeshZ and not IsDestroyed(shield.MeshZ) then shield.MeshZ:SetMesh('') end
    if shield:IsUp() then shield:SetMesh(shield.MeshBp) end
    -- FAF already forks CreateImpactEffect at actual surface hit positions.
    -- Replace only this instance; all other shields keep native impact effects.
    shield.CreateImpactEffect=Impact
    LOG('MODULAR_HEX_ACTIVE: mdeb4401 dome and impact shader attached')
end
Export={Attach=Attach,Eligible=Eligible,HitColour=HitColour,Impact=Impact}
return Export
