local function Tick(host, runtime)
    host.ModuleRepairMass=0
    local shield, stats = host.MyShield, host.ModuleStats
    if host.RepairPaused or not shield or not shield:IsUp() or stats.RepairBudget <= 0 then return end
    local center, radius = shield:GetPosition(), stats.ShieldSize / 2
    local targets = host:GetAIBrain():GetUnitsAroundPoint(categories.STRUCTURE, center, radius, 'Ally') or {}
    table.sort(targets, function(a,b) return a.EntityId < b.EntityId end)
    local count = table.getn(targets)
    if count == 0 then return end
    local budget, examined = stats.RepairBudget, math.min(count, runtime.Config.RepairTargetLimit)
    local start = math.mod((host.RepairCursor or 0), count)
    for offset = 1, examined do
        local u = targets[math.mod((start + offset - 1), count) + 1]
        if u ~= host and not u.Dead and not IsDestroyed(u) and u.Army == host.Army and u:GetFractionComplete() == 1 then
            local p = u:GetPosition()
            local dx,dy,dz = p[1]-center[1],p[2]-center[2],p[3]-center[3]
            local missing = u:GetMaxHealth() - u:GetHealth()
            if missing > 0 and dx*dx+dy*dy+dz*dz <= radius*radius then
                local perHP = runtime.Config.RepairFactor * (stats.RepairMassMultiplier or 1) * u.Blueprint.Economy.BuildCostMass / u:GetMaxHealth()
                if perHP > 0 or (runtime.Config.Debug or {}).IgnoreResources then
                    local hp = math.min(missing, budget / (examined-offset+1))
                    -- TakeResource returns actual mass removed (audited in installed SimUtils).
                    -- No yield between withdrawal and healing: other repairers cannot spend it twice.
                    local free=(runtime.Config.Debug or {}).IgnoreResources
                    local paid = not free and host:GetAIBrain():TakeResource('Mass', hp * perHP) or 0
                    host.ModuleRepairMass=host.ModuleRepairMass+math.max(0,paid)
                    local restored = free and hp or math.min(hp, math.max(0,paid) / perHP)
                    u:SetHealth(host, u:GetHealth() + restored)
                    budget = budget - restored
                end
            end
        end
    end
    host.RepairCursor = math.mod((start + examined), count)
    -- Direct, exact withdrawals are not native economy events. Attribute their
    -- actual one-second rate to the selected-unit display without charging twice.
end
Export = { Tick = Tick }

return Export
