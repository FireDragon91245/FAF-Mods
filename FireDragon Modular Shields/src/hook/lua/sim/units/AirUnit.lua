local PreviousAirUnit=AirUnit
AirUnit=ClassUnit(PreviousAirUnit) {
    OnKilled=function(self,instigator,damageType,overkill)
        PreviousAirUnit.OnKilled(self,instigator,damageType,overkill)
        if self.ModularCrashContained then self.DeathCrashDamage=0 end
    end,
    OnImpact=function(self,with)
        if self.ModularCrashContained then self.DeathCrashDamage=0 end
        return PreviousAirUnit.OnImpact(self,with)
    end,
}
