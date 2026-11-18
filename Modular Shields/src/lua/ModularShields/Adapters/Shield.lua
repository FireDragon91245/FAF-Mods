local library = import('/lua/shield.lua')
local function Apply(host, stats)
    local s = host.MyShield
    -- Stock CreateShield makes the dome the generator's native build focus.
    -- That exposes shield HP as repair work (and its progress bar) to guards.
    -- Module work has its own economy/progress; only a chassis upgrade needs a
    -- native focus. Removing the dome focus also closes automatic repair paths.
    if not host.ModuleUpgrading and host.ClearFocusEntity then host:ClearFocusEntity() end
    if s and not IsDestroyed(s) then
        local health = s:GetHealth()
        s:SetMaxHealth(stats.ShieldMaxHP)
        s:SetHealth(host, math.min(health, stats.ShieldMaxHP))
        s.Size = stats.ShieldSize
        -- The native thread supplies only regeneration that requires no recent
        -- damage. Module regeneration is applied independently every sim tick.
        s.RegenRate = (stats.BaseRegen or stats.ShieldRegen)+(stats.NeighborRegen or 0)
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
    local ignore=stats.IgnoreResources==true
    if (host.ModuleIgnoreResources==true)~=ignore and s and not IsDestroyed(s) then
        host.ModuleIgnoreResources=ignore
        if ignore then
            s.NoEnergyToSustain=false;s.DepletedByEnergy=false
            if s.Enabled and not s.DepletedByDamage and s:GetHealth()>0 then
                s.Recharged=true;s:OnEnergyViable()
            end
        elseif host:GetAIBrain().EnergyDepleted or host:GetAIBrain():GetEconomyStored('ENERGY')<=0 then
            s:OnEnergyDepleted()
        end
    end
end
local function TickRegen(host)
    local s=host.MyShield
    local rate=host.ModuleStats and host.ModuleStats.ModuleRegen or 0
    if rate<=0 or not s or IsDestroyed(s) or not s:IsUp() then return end
    local hp=s:GetHealth()
    if hp<=0 or hp>=s:GetMaxHealth() then return end
    s:SetHealth(host,math.min(s:GetMaxHealth(),hp+rate/10))
    s:UpdateShieldRatio(-1)
end
Export = { Apply = Apply,TickRegen=TickRegen }

return Export
