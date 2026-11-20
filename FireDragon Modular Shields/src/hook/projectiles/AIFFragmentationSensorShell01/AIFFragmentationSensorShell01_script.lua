-- Reflect/intercept before concrete artillery impact and split handlers.
local Previous=TypeClass
TypeClass=import('/mods/FireDragon Modular Shields/lua/ModularShields/Adapters/ProjectileHook.lua').Export.Wrap(Previous)
AIFFragmentationSensorShell01=TypeClass
