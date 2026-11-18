local ModularPreviousBeginSession=BeginSession
function BeginSession()
    import('/mods/ModularShields/lua/ModularShields/Services/Communication.lua').Export.Start()
    import('/mods/ModularShields/lua/ModularShields/Services/DebugConfig.lua').Export.InitSim()
    return ModularPreviousBeginSession()
end
