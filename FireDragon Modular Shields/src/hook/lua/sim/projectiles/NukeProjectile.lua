local PreviousNuke=NukeProjectile
NukeProjectile=ClassProjectile(PreviousNuke) {
    OnImpact=function(self,targetType,targetEntity)
        -- Intercept before NukeProjectile starts its visuals and force threads.
        if import('/mods/FireDragon Modular Shields/lua/ModularShields/Services/Combat.lua').Export.Try(self,
            targetType=='Shield' and targetEntity or nil) then return end
        return PreviousNuke.OnImpact(self,targetType,targetEntity)
    end,
}
