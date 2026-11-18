local Window=50 -- five seconds at ten simulation ticks per second
local function Damage(host,amount)
    if amount<=0 then return end
    host.ModuleDamage=host.ModuleDamage or {}
    local tick=GetGameTick()
    host.ModuleDamage[tick]=(host.ModuleDamage[tick] or 0)+amount
end
local function Snapshot(host)
    local tick=GetGameTick()
    local total=0
    for at,amount in pairs(host.ModuleDamage or {}) do
        if at<=tick-Window then host.ModuleDamage[at]=nil else total=total+amount end
    end
    local s=host.MyShield
    local stats=host.ModuleStats
    local hp,max,regen,status=0,stats.ShieldMaxHP,0,'Offline'
    local base,module,neighbor=0,0,0
    if s and not IsDestroyed(s) then
        hp=math.max(0,s:GetHealth());max=s:GetMaxHealth()
        if s:IsUp() then
            if hp>=max then status='Full'
            else
                module=stats.ModuleRegen or 0
                if tick>(s.RegenThreadStartTick or 0) then
                    base=stats.BaseRegen or s.RegenRate or 0;neighbor=stats.NeighborRegen or 0
                end
                regen=base+module+neighbor
                status=tick<=(s.RegenThreadStartTick or 0) and (module>0 and 'Module regen only' or 'Regen delayed') or 'Regenerating'
            end
        end
    end
    return {HP=hp,MaxHP=max,Regen=regen,BaseRegen=base,ModuleRegen=module,NeighborRegen=neighbor,
        BaseHP=stats.BaseHP or stats.ShieldMaxHP,ModuleHP=stats.ModuleHP or 0,NeighborHP=stats.NeighborHP or 0,
        Damage=total/(Window/10),DamageWindow=Window/10,Status=status,RepairMass=host.ModuleRepairMass or 0}
end
Export={Damage=Damage,Snapshot=Snapshot}
return Export
