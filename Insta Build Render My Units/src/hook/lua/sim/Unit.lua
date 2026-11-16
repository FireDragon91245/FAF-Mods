-- Insta Build Render My Units!: track root-bone visibility and repair units left
-- invisible by an interrupted construction hide. Logic lives in RenderGuard.lua.
local RenderGuard = import('/mods/InstaBuildRenderFix/lua/InstaBuildRenderFix/RenderGuard.lua')
local RenderGuardPreviousUnit = Unit

Unit = ClassUnit(RenderGuardPreviousUnit) {
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
