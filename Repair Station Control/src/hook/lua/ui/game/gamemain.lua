local RSCPreviousCreateUI=CreateUI
function CreateUI(isReplay)
    local result=RSCPreviousCreateUI(isReplay)
    if not isReplay then
        AddBeatFunction(import('/mods/RepairStationControl/lua/RepairStationControl/Panel.lua').Update)
    end
    return result
end
