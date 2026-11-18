local FireDragonPreviousSetupSession=SetupSession
function SetupSession()
    import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export._StartSim()
    return FireDragonPreviousSetupSession()
end
