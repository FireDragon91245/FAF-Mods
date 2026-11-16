local FireDragonPreviousCreateUI = CreateUI
function CreateUI(isReplay)
    local result = FireDragonPreviousCreateUI(isReplay)
    if not isReplay then
        local keyMap = import('/lua/keymap/keymapper.lua').GetCurrentKeyMap()
        local bindings = import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Keys.lua').Bindings(keyMap)
        if bindings then IN_AddKeyMapTable(bindings) end
    end
    return result
end
