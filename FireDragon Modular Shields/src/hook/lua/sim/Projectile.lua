local PreviousProjectile=Projectile
local Combat
local function Service()
    Combat=Combat or import('/mods/FireDragon Modular Shields/lua/ModularShields/Services/Combat.lua').Export
    return Combat
end
Projectile=ClassProjectile(PreviousProjectile) {
    OnCreate=function(self,inWater)
        PreviousProjectile.OnCreate(self,inWater)
        Service().Track(self)
    end,
    OnImpact=function(self,targetType,targetEntity)
        if Service().Try(self,targetType=='Shield' and targetEntity or nil) then return end
        return PreviousProjectile.OnImpact(self,targetType,targetEntity)
    end,
    OnDestroy=function(self)
        if Combat then Combat.Forget(self) end
        PreviousProjectile.OnDestroy(self)
    end,
}
