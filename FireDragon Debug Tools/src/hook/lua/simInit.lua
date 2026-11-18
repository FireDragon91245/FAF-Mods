local FireDragonPreviousBeginSession=BeginSession
function BeginSession()
    import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Economy.lua').Start()
    import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/InstantBuild.lua').Start()
    return FireDragonPreviousBeginSession()
end
