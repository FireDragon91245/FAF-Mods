local ModularUpdateWindow=UpdateWindow
local Exchange=import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export
local Messages=import('/mods/ModularShields/lua/ModularShields/Messages.lua').Export
function UpdateWindow(info)
    local state=info.entityId and Exchange.GetState(Messages.Status,info.entityId)
    local live=info.entityId and Exchange.GetState(Messages.Live,info.entityId)
    if state then
        -- The native rollover info can be reused. Copy before attributing aura
        -- spending so successive frames never accumulate the same consumption.
        local copy={};for key,value in pairs(info) do copy[key]=value end
        local mass=live and live.RepairMass or 0
        copy.massConsumed=(info.massConsumed or 0)+mass
        copy.massRequested=(info.massRequested or 0)+mass
        info=copy
    end
    ModularUpdateWindow(info)
    -- Vanilla reads the immutable blueprint here, which omits module and storage
    -- capacity. Preserve its detailed-view visibility and use the live snapshot.
    if live and controls.shieldText and not controls.shieldText:IsHidden() then
        controls.shieldText:SetText(string.format('%.0f / %.0f +%.0f/s',live.HP,live.MaxHP,live.Regen))
    end
end
