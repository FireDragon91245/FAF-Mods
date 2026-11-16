local ModularStructureUnit=StructureUnit
StructureUnit=ClassUnit(ModularStructureUnit) {
    OnStopBeingBuilt=function(self,builder,layer)
        ModularStructureUnit.OnStopBeingBuilt(self,builder,layer)
        local cats=self.Blueprint.CategoriesHash
        if cats.ENERGYSTORAGE or cats.MASSSTORAGE or cats.ENERGYPRODUCTION then
            self:ForkThread(function()
                -- The native completion callback can still report fraction < 1.
                WaitTicks(1)
                local root='/mods/ModularShields/lua/ModularShields/'
                import(root..'Adapters/Adjacency.lua').Export.NotifyCompletion(self,import(root..'Config.lua').Export)
            end)
        end
    end,
}
