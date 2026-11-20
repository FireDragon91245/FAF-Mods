local Base=import('/lua/sim/Unit.lua').Unit
MDS0001=ClassUnit(Base) {
    OnCreate=function(self)
        Base.OnCreate(self)
        self:SetCollisionShape('None')
        self:SetUnSelectable(true)
        self:SetDoNotTarget(true)
        self:SetCanTakeDamage(false)
        self:SetCanBeKilled(false)
        self:SetReclaimable(false)
        self:SetCapturable(false)
        self:HideBone(0,true)
    end,
    UpdateConsumptionValues=function(self)
        Base.UpdateConsumptionValues(self)
        -- The base method disables the economy consumer at zero demand, which
        -- makes native ResourceConsumed zero and stalls free construction.
        if self.ActiveConsumption and (self.ModuleFree or (self.ModuleWorkKind=='build'
            and self:GetConsumptionPerSecondMass()==0 and self:GetConsumptionPerSecondEnergy()==0)) then
            self:SetConsumptionActive(true)
        end
    end,
    GetBuildCosts=function(self,blueprint)
        local time,energy,mass=Base.GetBuildCosts(self,blueprint)
        if self.ModuleFree then return time,0,0 end
        return time,energy,mass
    end,
    StartBuildingEffects=function() end,
    StopBuildingEffects=function() end,
    CreateBuildEffects=function() end,
    OnPrepareArmToBuild=function() end,
    StopBeingBuiltEffects=function() end,
    CreateIdleEffects=function() end,
    CreateMovementEffects=function() end,
    CreateLayerChangeEffects=function() end,
    CreateWreckage=function() end,
}
TypeClass=MDS0001
