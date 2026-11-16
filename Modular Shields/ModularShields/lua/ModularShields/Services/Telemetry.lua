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
    local hp,max,regen,status=0,host.ModuleStats.ShieldMaxHP,0,'Offline'
    if s and not IsDestroyed(s) then
        hp=math.max(0,s:GetHealth());max=s:GetMaxHealth()
        if s:IsUp() then
            if hp>=max then status='Full'
            elseif tick<=(s.RegenThreadStartTick or 0) then status='Regen delayed'
            else regen=s.RegenRate or 0;status='Regenerating' end
        end
    end
    return {HP=hp,MaxHP=max,Regen=regen,Damage=total/(Window/10),DamageWindow=Window/10,Status=status}
end
Export={Damage=Damage,Snapshot=Snapshot}
return Export
