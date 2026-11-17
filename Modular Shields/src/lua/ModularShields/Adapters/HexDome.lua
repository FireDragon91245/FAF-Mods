-- UEF T4 visual experiment. No gameplay, HP, collision or economy mutations.
local root = '/mods/ModularShields/effects/entities/UEFT4Hex/'
local function Eligible(host)
    return host.Blueprint and host.Blueprint.BlueprintId == 'mdeb4401'
end
local function HitColour(ratio)
    if ratio <= 0.30 then return 'Red' end
    if ratio <= 0.65 then return 'Yellow' end
    return 'Blue'
end
local function Impact(shield, vector)
    -- Preserve the interception adapter's native-impact deduplication contract,
    -- even if this visual is skipped because of its allocation cap.
    shield.ModularImpactSerial=(shield.ModularImpactSerial or 0)+1
    if IsDestroyed(shield) or not shield:IsUp() or not vector then return end
    -- Keep visual allocation bounded under rapid fire. Gameplay hits are untouched.
    if (shield.HexLiveImpacts or 0) >= 8 then return end
    local x,y,z = vector[1],vector[2],vector[3]
    local distance = math.sqrt(x*x+y*y+z*z)
    if distance < 0.001 then return end
    shield.HexLiveImpacts = (shield.HexLiveImpacts or 0)+1
    local Entity = import('/lua/sim/entity.lua').Entity
    local entity = Entity({Owner=shield.Owner})
    shield.Owner.Trash:Add(entity)
    entity:SetMesh(root..'Hit'..HitColour(shield:GetHealth()/math.max(1,shield:GetMaxHealth()))..'_mesh')
    entity:SetDrawScale(shield.Size*1.002)
    Warp(entity,shield:GetPosition())
    entity:SetOrientation(OrientFromDir({x/distance,y/distance,z/distance}),true)
    entity:SetVizToFocusPlayer('Always')
    entity:SetVizToAllies('Always')
    entity:SetVizToEnemies('Intel')
    entity:SetVizToNeutrals('Intel')
    WaitTicks(9)
    if not IsDestroyed(entity) then entity:Destroy() end
    shield.HexLiveImpacts = shield.HexLiveImpacts-1
end
local function Attach(host)
    if not Eligible(host) then return end
    -- Native shader loader is an installation dependency. Keep this choice
    -- deterministic: no local DLL/graphics checks in synchronized simulation Lua.
    local shield=host.MyShield
    if not shield or IsDestroyed(shield) or shield.HexVisualsAttached then return end
    shield.HexVisualsAttached=true
    shield.MeshBp=root..'Dome_mesh'
    -- Retain FAF's standard depth/fog-of-war companion mesh.
    if shield:IsUp() then shield:SetMesh(shield.MeshBp) end
    -- FAF already forks CreateImpactEffect at actual surface hit positions.
    -- Replace only this instance; all other shields keep native impact effects.
    shield.CreateImpactEffect=Impact
    LOG('MODULAR_HEX_ACTIVE: mdeb4401 dome and impact shader attached')
end
Export={Attach=Attach,Eligible=Eligible,HitColour=HitColour,Impact=Impact}
return Export
