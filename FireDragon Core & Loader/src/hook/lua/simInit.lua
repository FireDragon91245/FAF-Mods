local FireDragonPreviousSetupSession=SetupSession
function SetupSession()
    import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua').Export._StartSim()
    return FireDragonPreviousSetupSession()
end
