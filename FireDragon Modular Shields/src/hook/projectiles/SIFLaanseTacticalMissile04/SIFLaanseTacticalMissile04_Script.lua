-- Intercept before this concrete projectile's custom split/damage logic.
local Previous=TypeClass
TypeClass=import('/mods/FireDragon Modular Shields/lua/ModularShields/Adapters/ProjectileHook.lua').Export.Wrap(Previous)
SIFLaanseTacticalMissile04=TypeClass
