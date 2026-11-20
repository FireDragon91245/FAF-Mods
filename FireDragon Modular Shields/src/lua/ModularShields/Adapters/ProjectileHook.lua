-- Wrap the concrete script as well as its base: faction subclasses can split or
-- spawn extra damage before calling Projectile/NukeProjectile.OnImpact.
local function Wrap(Base)
    return ClassProjectile(Base) {
        OnImpact=function(self,targetType,targetEntity)
            if import('/mods/FireDragon Modular Shields/lua/ModularShields/Services/Combat.lua').Export.Try(self,
                targetType=='Shield' and targetEntity or nil) then return end
            return Base.OnImpact(self,targetType,targetEntity)
        end,
    }
end
Export={Wrap=Wrap}
return Export
