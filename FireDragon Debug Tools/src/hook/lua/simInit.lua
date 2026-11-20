local FireDragonPreviousBeginSession=BeginSession
function BeginSession()
    import('/mods/FireDragon Debug Tools/lua/FireDragonDebugTools/Economy.lua').Start()
    import('/mods/FireDragon Debug Tools/lua/FireDragonDebugTools/InstantBuild.lua').Start()
    return FireDragonPreviousBeginSession()
end
