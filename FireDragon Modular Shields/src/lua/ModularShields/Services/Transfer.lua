local R=import('/mods/FireDragon Modular Shields/lua/ModularShields/Runtime.lua').Export
local function Snapshot(host,withQueue)
    if not host.Loadout then return nil end
    local s=host.MyShield
    return { Installed=table.deepcopy(host.Loadout.Installed),
        Queue=withQueue and table.deepcopy(host.Loadout.Queue) or {},
        NextJob=host.Loadout.NextJob,InstallPaused=host.InstallPaused,RepairPaused=host.RepairPaused,
        ShieldToggle=host.GetScriptBit and host:GetScriptBit('RULEUTC_ShieldToggle'),
        Shield=s and { HP=s:GetHealth(),Up=s:IsUp(),Enabled=s.Enabled,Recharged=s.Recharged,
            DepletedByDamage=s.DepletedByDamage,DepletedByEnergy=s.DepletedByEnergy,
            NoEnergyToSustain=s.NoEnergyToSustain,RegenStart=s.RegenThreadStartTick,
            ChargeDeadline=s.ModularChargeDeadline } }
end
local function Restore(host,data)
    if not data then return end
    local state=host.Loadout
    state.Installed=table.deepcopy(data.Installed)
    state.Queue=table.deepcopy(data.Queue or {})
    state.NextJob=data.NextJob or 0
    state.Revision=state.Revision+1
    host.InstallPaused=data.InstallPaused
    host.RepairPaused=data.RepairPaused
    if data.ShieldToggle~=nil and host.SetScriptBit then host:SetScriptBit('RULEUTC_ShieldToggle',data.ShieldToggle) end
    -- Paid modules survive losing storage or changing owner. Reconcile computes
    -- capacity at the new location; excess reservations wait instead of vanishing.
    host:ReconcileModules()
    local s,old=host.MyShield,data.Shield
    if s and old then
        s:SetHealth(host,math.min(old.HP,s:GetMaxHealth()))
        s.RegenThreadStartTick=old.RegenStart
        s.DepletedByDamage=old.DepletedByDamage
        s.DepletedByEnergy=old.DepletedByEnergy
        s.NoEnergyToSustain=old.NoEnergyToSustain
        s.Recharged=old.Recharged
        s.Enabled=old.Enabled
        if old.ChargeDeadline then s.ModularResumeCharge=math.max(0,(old.ChargeDeadline-GetGameTick())/10) end
        if old.Up then ChangeState(s,s.OnState)
        elseif old.DepletedByDamage then ChangeState(s,s.DamageDrainedState)
        elseif old.NoEnergyToSustain then ChangeState(s,s.EnergyDrainedState)
        elseif old.Enabled then ChangeState(s,s.RechargeState)
        else ChangeState(s,s.OffState) end
    end
end
Export={Snapshot=Snapshot,Restore=Restore}
return Export
