local Unit = import('/lua/sim/unit.lua').Unit

-- Hidden energy storage helper of Infinite Energy. A Unit (not a DummyUnit): only
-- Unit gets its blueprint storage applied by the engine.
---@class FDT0001 : Unit
FDT0001 = ClassUnit(Unit) {
    -- There is no mesh to swap in when construction finishes.
    StopBeingBuiltEffects = function(self, builder, layer)
        if self.OnBeingBuiltEffectsBag then self.OnBeingBuiltEffectsBag:Destroy() end
    end,
}
TypeClass = FDT0001
