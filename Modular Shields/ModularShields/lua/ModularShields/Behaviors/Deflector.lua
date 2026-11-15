local root='/mods/ModularShields/lua/ModularShields/'
local G=import(root..'Core/Geometry.lua').Export
local Impact=import(root..'Adapters/Impact.lua').Export
local function ContainCargo(body,seen)
    seen=seen or {}
    if seen[body] then return end
    seen[body]=true
    -- Standard transports defer the cached cargo's final OnKilled until impact.
    -- Contain only the cargo belonging to this intercepted, already dying body.
    for _,cargo in ipairs(body.cargoCache or {}) do
        if not IsDestroyed(cargo) then
            cargo.ModularCrashContained=true
            cargo.DeathCrashDamage=0
            cargo.DeathWeaponEnabled=false
            ContainCargo(cargo,seen)
        end
    end
end
local function Hit(collider,shield,config,position)
    local plane=collider.Plane
    if not plane or IsDestroyed(plane) or plane.GroundImpacted then return false end
    local tick=GetGameTick()
    if tick<(plane.ModularNextBounceTick or 0) then return true end
    local p=position or collider:GetPosition()
    local center=shield:GetPosition()
    local normal=G.Normal(p,center)
    plane.ModularNextBounceTick=tick+config.Crash.BounceCooldownTicks
    plane.ModularBounceCount=(plane.ModularBounceCount or 0)+1
    plane.ModularInitialCrashDamage=plane.ModularInitialCrashDamage or plane.DeathCrashDamage or 0
    -- Instance fields only. Once intercepted, this body cannot leak its crash damage
    -- even if this impact collapses the dome or the body later hits another shield.
    plane.ModularCrashContained=true
    plane.DeathCrashDamage=0
    ContainCargo(plane)
    local final=plane.ModularBounceCount>=config.Crash.MaxBounces
    local damage=plane.ModularInitialCrashDamage*(final and config.Crash.BreakupDamageFraction or config.Crash.BounceDamageFraction)
    damage=math.min(shield:GetMaxHealth()*(final and config.Crash.BreakupMaxHPFraction or config.Crash.BounceMaxHPFraction),damage)
    local vector={center[1]-p[1],center[2]-p[2],center[3]-p[3]}
    Impact.Apply(shield,plane,math.max(config.Crash.MinimumDamage,damage),vector)
    if final then
        import(root..'Adapters/Visuals.lua').Export.Burst(p,plane.Army,false,3)
        plane.GroundImpacted=true
        -- Destroy bypasses OnKilled/OnImpact and their crash/death weapon paths.
        plane:Destroy()
        if not IsDestroyed(collider) then collider:Destroy() end
        return true
    end
    if not plane.ModularBounceAttached then
        plane:DetachFrom()
        plane:AttachBoneTo(collider.PlaneBone or 0,collider,'anchor')
        plane.ModularBounceAttached=true
        -- Includes Czar and transports; preserve the unit's existing detectors.
        if not plane.Detector then
            plane.Detector=CreateCollisionDetector(plane)
            plane.Trash:Add(plane.Detector)
            plane.Detector:WatchBone(collider.PlaneBone or 0)
            plane.Detector:EnableTerrainCheck(true)
            plane.Detector:Enable()
        end
    end
    local vx,vy,vz=collider:GetVelocity()
    local velocity=G.Reflect({vx*10,vy*10,vz*10},normal,config.Crash.OutwardSpeed)
    velocity[2]=math.max(config.Crash.UpwardSpeed,velocity[2])
    local margin=config.Crash.Clearance
    Warp(collider,{center[1]+normal[1]*(shield.Size/2+margin),center[2]+normal[2]*(shield.Size/2+margin),center[3]+normal[3]*(shield.Size/2+margin)})
    collider:SetVelocity(velocity[1],velocity[2],velocity[3])
    collider:SetLocalAngularVelocity(.15,.1,.15)
    collider:SetLifetime(config.Crash.BodyLifetimeSeconds)
    collider.ShieldImpacted=false
    return true
end
Export={Hit=Hit}
return Export
