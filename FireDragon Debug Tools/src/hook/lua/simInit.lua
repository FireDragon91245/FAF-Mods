local FireDragonPreviousBeginSession=BeginSession
function BeginSession()
    import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Economy.lua').Start()
    return FireDragonPreviousBeginSession()
end
