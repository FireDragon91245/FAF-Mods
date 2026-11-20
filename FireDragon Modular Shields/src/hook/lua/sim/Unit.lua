-- Track active reclaimers, including paused ones: dismantling takes precedence
-- over the repair aura until the reclaim order ends.
local PreviousUnit = Unit
local Assist = import('/mods/FireDragon Modular Shields/lua/ModularShields/Adapters/Assistance.lua').Export
Unit = ClassUnit(PreviousUnit) {
    OnCreate = function(self)
        PreviousUnit.OnCreate(self)
        local cats=self.Blueprint.CategoriesHash
        -- All Hive tiers and Kennel pods need the scripted-job scan. Starting
        -- here also covers pods created/rebuilt directly by their parent tower.
        if cats.ENGINEER and (cats.ENGINEERSTATION or cats.STATIONASSISTPOD)
            and not cats.DUMMYUNIT and not cats.INSIGNIFICANTUNIT then
            self.ModuleAutoAssistThread=self:ForkThread(function()
                while not self.Dead do
                    WaitTicks(10)
                    if not self.Dead and self:GetFractionComplete()==1 then Assist.AutoDrone(self) end
                end
            end)
        end
    end,
    OnStartReclaim = function(self, target)
        if target.IsUnit then
            target.ModularReclaimers = target.ModularReclaimers or {}
            target.ModularReclaimers[self.EntityId] = self
        end
        PreviousUnit.OnStartReclaim(self, target)
    end,
    OnStopReclaim = function(self, target)
        local old = self.EntityBeingReclaimed
        if old and old.ModularReclaimers then old.ModularReclaimers[self.EntityId] = nil end
        PreviousUnit.OnStopReclaim(self, target)
    end,
}
