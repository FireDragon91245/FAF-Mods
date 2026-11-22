local RSCPreviousBeginSession=BeginSession
function BeginSession()
    import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Controller.lua').Export.Reset()
    local result=RSCPreviousBeginSession()
    import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Settings.lua').Export.Start()
    import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Controller.lua').Export.Start()
    return result
end
