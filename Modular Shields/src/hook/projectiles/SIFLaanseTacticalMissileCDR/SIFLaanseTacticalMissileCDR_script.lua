-- Intercept before this concrete projectile's custom split/damage logic.
local Previous=TypeClass
TypeClass=import('/mods/ModularShields/lua/ModularShields/Adapters/ProjectileHook.lua').Export.Wrap(Previous)
SIFLaanseTacticalMissileCDR=TypeClass
