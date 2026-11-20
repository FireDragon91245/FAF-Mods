local ModularPreviousBeginSession=BeginSession
function BeginSession()
    import('/mods/FireDragon Modular Shields/lua/ModularShields/Services/Communication.lua').Export.Start()
    import('/mods/FireDragon Modular Shields/lua/ModularShields/Services/DebugConfig.lua').Export.InitSim()
    return ModularPreviousBeginSession()
end
