-- Key action for the debug panel. The action appears under "Mods" in the F1 key
-- bindings dialog; Alt-Shift-D is bound by default when it is free.

ActionName = 'firedragon_debug_tools_toggle'
DefaultKey = 'Alt-Shift-D'
Description = 'Toggle FireDragon Debug Tools panel'
KeyAction = {
    action = "UI_Lua import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Panel.lua').Toggle()",
    category = 'mods',
}

--- Key map entries to add at game start. The lobby applies the key map before mod key
--- actions exist, so keys the user bound to this action must be added again here.
---@param keyMap table<string, string> current key -> action name map
---@return table<string, table>|nil
function Bindings(keyMap)
    keyMap = keyMap or {}
    local result
    for key, action in pairs(keyMap) do
        if action == ActionName then
            result = result or {}
            result[key] = KeyAction
        end
    end
    if not result and not keyMap[DefaultKey] then
        result = { [DefaultKey] = KeyAction }
    end
    return result
end
