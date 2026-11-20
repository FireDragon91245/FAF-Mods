local Exchange=import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export
local Policy=import('/mods/RepairStationControl/lua/RepairStationControl/Policy.lua').Export
local function Managed(pods)
    for _,pod in ipairs(pods) do if Policy.ManagedBlueprint(pod:GetBlueprint()) then return true end end
    return false
end
local function Mode(pods)
    if not Managed(pods) then return nil end
    local mode,mixed
    for _,pod in ipairs(pods) do
        local state=Exchange.GetState('RepairStationControl.Auto',pod:GetEntityId())
        local enabled
        if state then enabled=state.Enabled else enabled=pod:IsAutoMode() end
        if mode==nil then mode=enabled elseif mode~=enabled then mixed=true end
    end
    return mode,mixed
end
local function Set(pod,enabled)
    if Policy.ManagedBlueprint(pod:GetBlueprint()) then
        return Exchange.Sim.Publish('RepairStationControl.SetAuto',{EntityId=pod:GetEntityId(),Enabled=enabled})
    end
    pod:ProcessInfo('SetAutoMode',enabled and 'true' or 'false')
end
Export={Mode=Mode,Managed=Managed,Set=Set}
return Export
