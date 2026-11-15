local PreviousCollider=ShieldCollider
local function Combat() return import('/mods/ModularShields/lua/ModularShields/Services/Combat.lua').Export end
ShieldCollider=ClassProjectile(PreviousCollider) {
    Start=function(self,parent,bone)
        PreviousCollider.Start(self,parent,bone)
        Combat().Track(self)
    end,
    OnImpact=function(self,targetType,targetEntity)
        if targetType=='Shield' and targetEntity and Combat().Try(self,targetEntity) then return end
        if self.Plane and self.Plane.ModularCrashContained then self.Plane.DeathCrashDamage=0 end
        PreviousCollider.OnImpact(self,targetType,targetEntity)
    end,
    OnDestroy=function(self)
        Combat().Forget(self)
        PreviousCollider.OnDestroy(self)
    end,
}
TypeClass=ShieldCollider
