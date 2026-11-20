-- FireDragon: Insta Build Render My Units!: keep factory roll-off working for units completed in the
-- tick they were started. Logic lives in FactoryFix.lua.
local InstaFixFactoryFix = import('/mods/FireDragon Insta Build Render My Units/lua/InstaBuildRenderFix/FactoryFix.lua')
local InstaFixPreviousFactoryUnit = FactoryUnit
local InstaFixPreviousBuildingMain = FactoryUnit.BuildingState.Main

FactoryUnit = ClassUnit(InstaFixPreviousFactoryUnit) {
    OnStopBuild = function(self, unitBeingBuilt, order)
        InstaFixFactoryFix.BeforeStopBuild(self, unitBeingBuilt, order, IsDestroyed)
        return InstaFixPreviousFactoryUnit.OnStopBuild(self, unitBeingBuilt, order)
    end,

    FinishBuildThread = function(self, unitBeingBuilt, order, rollOffPointSpin)
        local hold = InstaFixFactoryFix.HoldBeforeFinish(unitBeingBuilt, IsDestroyed)
        if hold > 0 then
            self:SetBusy(true)
            self:SetBlockCommandQueue(true)
            WaitTicks(hold)
        end
        InstaFixPreviousFactoryUnit.FinishBuildThread(self, unitBeingBuilt, order, rollOffPointSpin)
        InstaFixFactoryFix.AfterFinishBuild(unitBeingBuilt, IsDestroyed)
    end,

    BuildingState = State(InstaFixPreviousFactoryUnit.BuildingState) {
        Main = function(self)
            local unit = self.UnitBeingBuilt
            if InstaFixFactoryFix.SkipBuildingMain(unit) then return end
            InstaFixPreviousBuildingMain(self)
            InstaFixFactoryFix.BuildingMainFinished(unit)
        end,
    },
}
