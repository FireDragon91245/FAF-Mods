local Unit = import('/lua/sim/unit.lua').Unit

-- Hidden mass storage helper of Infinite Mass. A Unit (not a DummyUnit): only
-- Unit gets its blueprint storage applied by the engine.
---@class FDT0002 : Unit
FDT0002 = ClassUnit(Unit) {
    -- There is no mesh to swap in when construction finishes.
    StopBeingBuiltEffects = function(self, builder, layer)
        if self.OnBeingBuiltEffectsBag then self.OnBeingBuiltEffectsBag:Destroy() end
    end,
}
TypeClass = FDT0002
