local PreviousDoCallback = DoCallback
function DoCallback(name,data,units)
    if name == 'ModularShieldAction' then
        if type(data) ~= 'table' then return end
        for _, unit in ipairs(SecureUnits(units) or {}) do
            if unit.ModuleAction and not unit.Dead then unit:ModuleAction(data.Action,data.Value) end
        end
        return
    end
    return PreviousDoCallback(name,data,units)
end
