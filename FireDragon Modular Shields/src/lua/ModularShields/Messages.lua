-- Static message names and plain payloads shared by UI and Sim.
local actions={install=true,remove=true,cancel=true,pause=true,repair=true}
local function ValidateAction(data)
    if type(data)~='table' or not actions[data.Action] then return false end
    -- FAF's UI unit handles return decimal string IDs. Preserve the original ID
    -- for native lookups; only normalize a local copy for shape validation.
    local id=data.EntityId
    if type(id)=='string' then
        if not string.find(id,'^%d+$') then return false end
        id=tonumber(id)
    end
    if type(id)~='number' or id-id~=0 or id<1 or id~=math.floor(id) then return false end
    if data.Action=='install' or data.Action=='remove' then return type(data.Value)=='string' and string.len(data.Value)<=96 end
    if data.Action=='cancel' then return (type(data.Value)=='number' and data.Value>=1 and data.Value==math.floor(data.Value))
        or (type(data.CancelRequestId)=='string' and string.len(data.CancelRequestId)<=256) end
    return true
end
Export={Action='ModularShields.Action',Status='ModularShields.Status',Live='ModularShields.Live',ValidateAction=ValidateAction}
return Export
