local PreviousShield=Shield
local Combat
local function Service()
    Combat=Combat or import('/mods/FireDragon Modular Shields/lua/ModularShields/Services/Combat.lua').Export
    return Combat
end
Shield=Class(PreviousShield) {
    OnEnergyDepleted=function(self)
        if self.Owner and self.Owner.Blueprint.ModularShield
            and import('/mods/FireDragon Modular Shields/lua/ModularShields/Runtime.lua').Export.Config.Debug.IgnoreResources then
            self.NoEnergyToSustain=false
            return
        end
        return PreviousShield.OnEnergyDepleted(self)
    end,
    ApplyDamage=function(self,instigator,amount,vector,damageType,overspill)
        local host=self.Owner
        if not (host and host.Loadout) then return PreviousShield.ApplyDamage(self,instigator,amount,vector,damageType,overspill) end
        local before=math.max(0,self:GetHealth())
        local result=PreviousShield.ApplyDamage(self,instigator,amount,vector,damageType,overspill)
        local after=not IsDestroyed(self) and math.max(0,self:GetHealth()) or 0
        import('/mods/FireDragon Modular Shields/lua/ModularShields/Services/Telemetry.lua').Export.Damage(host,
            math.max(0,before-after))
        return result
    end,
    CreateImpactEffect=function(self,vector)
        if self.Owner and self.Owner.Blueprint.ModularShield then self.ModularImpactSerial=(self.ModularImpactSerial or 0)+1 end
        return PreviousShield.CreateImpactEffect(self,vector)
    end,
    OnCollisionCheck=function(self,other)
        if self.Owner and self.Owner.Loadout and Service().Try(other,self) then return false end
        return PreviousShield.OnCollisionCheck(self,other)
    end,
    ChargingUp=function(self,progress,time)
        if self.Owner and self.Owner.Blueprint.ModularShield then
            if self.ModularResumeCharge then progress=time-self.ModularResumeCharge;self.ModularResumeCharge=nil end
            self.ModularChargeDeadline=GetGameTick()+math.max(0,time-progress)*10
        end
        PreviousShield.ChargingUp(self,progress,time)
        self.ModularChargeDeadline=nil
    end,
}
