local RSCPreviousBeginSession=BeginSession
function BeginSession()
    local result=RSCPreviousBeginSession()
    import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Settings.lua').Export.Start()
    import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Controller.lua').Export.Start()
    return result
end
