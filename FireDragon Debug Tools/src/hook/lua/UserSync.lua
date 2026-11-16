local FireDragonPreviousOnSync = OnSync
function OnSync()
    local result = FireDragonPreviousOnSync()
    if Sync.FireDragonDebug then
        import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Panel.lua').OnSync(Sync.FireDragonDebug)
    end
    return result
end
