-- FAF merges unit sync tables recursively. Module status is a complete snapshot:
-- replacing just this field prevents removed jobs and queue tails surviving.
local PreviousOnSync=OnSync
function OnSync()
    for id,data in pairs(Sync.UnitData or {}) do
        if data.ModularShield~=nil and UnitData[id] then UnitData[id].ModularShield=nil end
    end
    return PreviousOnSync()
end
