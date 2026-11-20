-- FireDragon: Insta Build Render My Units!: track root-bone visibility and repair units left
-- invisible by an interrupted construction hide (RenderGuard.lua), and restore
-- structures upgraded in the tick they were started (UpgradeFix.lua).
local RenderGuard = import('/mods/FireDragon Insta Build Render My Units/lua/InstaBuildRenderFix/RenderGuard.lua')
local InstaFixUpgradeFix = import('/mods/FireDragon Insta Build Render My Units/lua/InstaBuildRenderFix/UpgradeFix.lua')
local RenderGuardPreviousUnit = Unit

Unit = ClassUnit(RenderGuardPreviousUnit) {
    OnStartBuild = function(self, built, order)
        local result = RenderGuardPreviousUnit.OnStartBuild(self, built, order)
        InstaFixUpgradeFix.AfterStartBuild(built, order)
        return result
    end,

    HideBone = function(self, bone, affectChildren)
        if bone == 0 then RenderGuard.OnRootHidden(self, GetGameTick()) end
        return RenderGuardPreviousUnit.HideBone(self, bone, affectChildren)
    end,

    ShowBone = function(self, bone, affectChildren)
        if bone == 0 then RenderGuard.OnRootShown(self) end
        return RenderGuardPreviousUnit.ShowBone(self, bone, affectChildren)
    end,

    OnStorageChange = function(self, loading)
        self.RenderGuardInStorage = loading or nil
        return RenderGuardPreviousUnit.OnStorageChange(self, loading)
    end,

    OnStopBeingBuilt = function(self, builder, layer)
        local result = RenderGuardPreviousUnit.OnStopBeingBuilt(self, builder, layer)
        if RenderGuard.ShouldWatch(self, builder) then
            self:ForkThread(RenderGuard.Watch, WaitTicks, GetGameTick, IsDestroyed)
        end
        return result
    end,
}
