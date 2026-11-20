local RSCPreviousCreateUI=CreateUI
function CreateUI(isReplay)
    local result=RSCPreviousCreateUI(isReplay)
    if not isReplay then
        AddBeatFunction(import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Panel.lua').Update)
    end
    return result
end
