local library = import('/lua/shield.lua')
local function Apply(host, stats)
    local s = host.MyShield
    if s and not IsDestroyed(s) then
        local health = s:GetHealth()
        s:SetMaxHealth(stats.ShieldMaxHP)
        s:SetHealth(host, math.min(health, stats.ShieldMaxHP))
        s.Size = stats.ShieldSize
        s.RegenRate = stats.ShieldRegen
        if s:IsUp() then
            s:SetCollisionShape('Sphere', 0, 0, 0, s.Size / 2)
            s:SetDrawScale(s.Size)
            if s.MeshZ then s.MeshZ:SetDrawScale(s.Size) end
            s:UpdateShieldRatio(-1)
            if health > 0 and health < stats.ShieldMaxHP and s.RegenThread and s.RegenThreadSuspended then
                s.RegenThreadStartTick = s.RegenThreadStartTick or (GetGameTick() + 10 * (s.RegenStartTime or 3))
                ResumeThread(s.RegenThread)
            end
        end
        library.LargestShieldDiameter = math.max(library.LargestShieldDiameter or 0, s.Size)
    end
    -- FAF retains its normal adjacency multiplier on this override.
    host:SetEnergyMaintenanceConsumptionOverride(stats.Upkeep)
    host:UpdateConsumptionValues()
end
Export = { Apply = Apply }

return Export
