-- Reflect/intercept before concrete artillery impact and split handlers.
local Previous=TypeClass
TypeClass=import('/mods/ModularShields/lua/ModularShields/Adapters/ProjectileHook.lua').Export.Wrap(Previous)
SBOOtheTacticalBomb01=TypeClass
