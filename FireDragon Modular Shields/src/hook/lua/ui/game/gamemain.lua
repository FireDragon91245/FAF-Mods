local previousCreateUI = CreateUI
function CreateUI(isReplay)
    local result = previousCreateUI(isReplay)
    local panel = import('/mods/FireDragon Modular Shields/lua/ModularShields/UI/Panel.lua').Export
    AddBeatFunction(panel.Update)
    return result
end
