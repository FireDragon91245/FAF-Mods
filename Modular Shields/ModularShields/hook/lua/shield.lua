local PreviousShield=Shield
local Combat
local function Service()
    Combat=Combat or import('/mods/ModularShields/lua/ModularShields/Services/Combat.lua').Export
    return Combat
end
Shield=Class(PreviousShield) {
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
