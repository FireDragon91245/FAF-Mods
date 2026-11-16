local ModularUpdateWindow=UpdateWindow
function UpdateWindow(info)
    local data=info.entityId and UnitData[info.entityId]
    if data and data.ModularShield then
        -- The native rollover info can be reused. Copy before attributing aura
        -- spending so successive frames never accumulate the same consumption.
        local copy={};for key,value in pairs(info) do copy[key]=value end
        local mass=data.ModularShieldRepairMass or 0
        copy.massConsumed=(info.massConsumed or 0)+mass
        copy.massRequested=(info.massRequested or 0)+mass
        info=copy
    end
    ModularUpdateWindow(info)
    local live=data and data.ModularShieldLive
    -- Vanilla reads the immutable blueprint here, which omits module and storage
    -- capacity. Preserve its detailed-view visibility and use the live snapshot.
    if live and controls.shieldText and not controls.shieldText:IsHidden() then
        controls.shieldText:SetText(string.format('%.0f / %.0f +%.0f/s',live.HP,live.MaxHP,live.Regen))
    end
end
