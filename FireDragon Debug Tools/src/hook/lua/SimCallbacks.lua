local FireDragonPreviousDoCallback = DoCallback
function DoCallback(name, data, units)
    if name == 'FireDragonDebugSetResource' then
        import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Economy.lua').HandleCallback(data)
        return
    end
    return FireDragonPreviousDoCallback(name, data, units)
end
