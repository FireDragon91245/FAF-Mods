-- Sim side of the debug tools: per-army infinite resources.
--
-- Enabling a resource adds a large storage boost and tops storage up every tick, so
-- even instant builds of experimentals never stall. Disabling removes the boost again.

local SimUtils = import('/lua/simutils.lua')

StorageBoost = 1000000
Callback = 'FireDragonDebugSetResource'

local MaxStorageStat = { ENERGY = 'Economy_MaxStorage_Energy', MASS = 'Economy_MaxStorage_Mass' }
local StorageType = { ENERGY = 'Energy', MASS = 'Mass' }

---@type table<number, table<string, boolean>>
Armies = {}
local loop

--- Tops the brain's storage of one resource up to its maximum.
function Fill(brain, resource)
    local missing = brain:GetArmyStat(MaxStorageStat[resource], 0).Value - brain:GetEconomyStored(resource)
    if missing > 0 then brain:GiveResource(resource, missing) end
    return missing
end

--- Fills every enabled resource once; returns whether anything is still enabled.
function Tick()
    local active = false
    for army, state in pairs(Armies) do
        local brain = ArmyBrains[army]
        for resource in pairs(MaxStorageStat) do
            if state[resource] then
                active = true
                if brain then Fill(brain, resource) end
            end
        end
    end
    return active
end

local function Loop()
    while Tick() do WaitTicks(1) end
    loop = nil
end

--- Enables or disables an infinite resource for an army.
---@return boolean accepted
function Set(army, resource, enabled)
    local brain = ArmyBrains[army]
    if not brain or not MaxStorageStat[resource] then return false end
    local state = Armies[army] or {}
    Armies[army] = state
    enabled = enabled == true
    if (state[resource] == true) == enabled then return true end

    state[resource] = enabled or nil
    brain:GiveStorage(StorageType[resource], enabled and StorageBoost or -StorageBoost)
    if enabled then
        Fill(brain, resource)
        if not loop then loop = ForkThread(Loop) end
    end
    return true
end

function Snapshot(army, denied)
    local state = Armies[army] or {}
    return { Energy = state.ENERGY == true, Mass = state.MASS == true, Denied = denied or nil }
end

--- Handles the UI toggle for the army that sent it. Only allowed with cheats enabled
--- (the engine also reports single-player games as cheats enabled).
function HandleCallback(data)
    local army = SimUtils.GetCurrentCommandSourceArmy()
    if not army or type(data) ~= 'table' then return end
    local allowed = CheatsEnabled()
    if allowed then Set(army, data.Resource, data.Enabled) end
    Sync.FireDragonDebug = Sync.FireDragonDebug or {}
    Sync.FireDragonDebug[tostring(army)] = Snapshot(army, not allowed)
end
