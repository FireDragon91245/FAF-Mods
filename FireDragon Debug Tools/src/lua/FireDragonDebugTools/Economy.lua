-- Sim side of the debug tools: per-army infinite resources.
--
-- Enabling a resource spawns a hidden helper unit whose blueprint carries a huge
-- storage (units/FDT0001 energy, units/FDT0002 mass) and tops storage up every tick,
-- so even instant builds of experimentals never stall. Disabling destroys the helper.
--
-- The engine sums helper storage with every other storage unit, so the boost survives
-- building, upgrading or losing storage. brain:GiveStorage cannot be used: the engine
-- keeps a single GiveStorage bonus for one resource, so a mass boost wipes the energy
-- boost (and vanilla's +100 energy) and vice versa.

local function exchange() return import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export end
local Messages=import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Messages.lua').Export
local started
Helpers = { ENERGY = 'fdt0001', MASS = 'fdt0002' }

local MaxStorageStat = { ENERGY = 'Economy_MaxStorage_Energy', MASS = 'Economy_MaxStorage_Mass' }

---@type table<number, table<string, boolean>>
Armies = {}
---@type table<number, table<string, Unit>>
Spawned = {}
local loop

local function MaxStorage(brain, resource)
    return brain:GetArmyStat(MaxStorageStat[resource], 0).Value
end

local function Helper(army, resource)
    local unit = Spawned[army] and Spawned[army][resource]
    if unit and not IsDestroyed(unit) then return unit end
end

--- Spawns the storage helper of a resource unless the army already has one.
function EnsureHelper(brain, army, resource)
    if Helper(army, resource) then return false end
    local x, z = brain:GetArmyStartPos()
    x, z = x or 0, z or 0
    Spawned[army] = Spawned[army] or {}
    Spawned[army][resource] = CreateUnitHPR(Helpers[resource], army, x, GetSurfaceHeight(x, z), z, 0, 0, 0)
    return true
end

function RemoveHelper(army, resource)
    local unit = Helper(army, resource)
    if unit then unit:Destroy() end
    if Spawned[army] then Spawned[army][resource] = nil end
end

--- Tops the brain's storage of one resource up to its maximum.
function Fill(brain, resource)
    local missing = MaxStorage(brain, resource) - brain:GetEconomyStored(resource)
    if missing > 0 then brain:GiveResource(resource, missing) end
    return missing
end

--- Keeps helpers alive and storage full for every enabled resource; returns whether
--- anything is still enabled. Defeated armies lose their toggles and helpers.
function Tick()
    local active = false
    for army, state in pairs(Armies) do
        local brain = ArmyBrains[army]
        if not brain or brain:IsDefeated() then
            for resource in pairs(state) do RemoveHelper(army, resource) end
            Armies[army] = nil
            Publish(army)
        else
            for resource in pairs(state) do
                active = true
                EnsureHelper(brain, army, resource)
                Fill(brain, resource)
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
    if enabled then
        EnsureHelper(brain, army, resource)
        Fill(brain, resource)
        if not loop then loop = ForkThread(Loop) end
    else
        RemoveHelper(army, resource)
    end
    Publish(army)
    return true
end

function Snapshot(army)
    local state = Armies[army] or {}
    return { Energy = state.ENERGY == true, Mass = state.MASS == true }
end

--- Retained economy events and a cheat-gated request handler share Exchange.
function Publish(army)
    exchange().UI.PublishState(Messages.Economy,tostring(army),Snapshot(army),{army=army})
end
function Start()
    if started then return end
    started=true
    local bus=exchange()
    bus.Expose(Messages.SetResource,{requests=true,authorize='Cheats'})
    bus.Respond(Messages.SetResource,function(data,_,context)
        if not Messages.ValidateResource(data) then
            return {Accepted=false,Reason='InvalidMessage'}
        end
        local army=context.source and context.source.army
        local brain=army and ArmyBrains[army]
        if not brain or brain:IsDefeated() then return {Accepted=false,Reason='MissingArmy'} end
        local accepted=Set(army,data.Resource,data.Enabled)
        return {Accepted=accepted,State=Snapshot(army)}
    end)
    for army in pairs(ArmyBrains) do Publish(army) end
end
