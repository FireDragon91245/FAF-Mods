local Policy=import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Policy.lua').Export
local Settings=import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Settings.lua').Export
local Exchange=import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua').Export
local units={}
local function Bridge()
    local native=FireDragonLoader and FireDragonLoader.Mods and FireDragonLoader.Mods.RepairStationControl
    assert(native and native.Worker and native.Target,'Repair Station Control requires its native TargetFilter DLL and a supported FAF executable')
    return native
end
local function Publish(unit)
    Exchange.UI.PublishState('RepairStationControl.Auto',unit.EntityId,{Enabled=unit.AutoModeEnabled==true},{army=unit.Army})
end
local function Configure(unit,settings)
    -- Never replace native acquisition. Only the two policy bits enter its
    -- candidate gates; all native ranking, task dispatch and docking survive.
    Bridge().Worker(tonumber(unit.EntityId),(settings.DontHelpTeam and 1 or 0)+(settings.DontHelpNukes and 2 or 0))
    unit.RSCArmy=unit.Army
    Publish(unit)
end
local function NativeIdle(unit)
    local queue=unit:GetCommandQueue() or {}
    local cats=unit.Blueprint.CategoriesHash
    return (cats.ENGINEERSTATION or (unit.Parent and cats.POD)) and table.getn(queue)==1 and queue[1].commandType==29
end
local function Reconcile(unit,settings)
    local focus,guarded=unit:GetFocusUnit(),unit:GetGuardedUnit()
    local idle=NativeIdle(unit)
    local allowed=idle and Policy.DirectAllowed or Policy.Allowed
    if (focus and not allowed(unit,focus,settings)) or
        (guarded and not idle and not Policy.Allowed(unit,guarded,settings)) then
        IssueClearCommands({unit})
    end
end
local function Update(unit)
    if unit.Dead then return end
    local settings=Settings.Get(unit.Army)
    if unit.RSCArmy~=unit.Army then Configure(unit,settings) end
    Reconcile(unit,settings)
end
local function SetAuto(unit,enabled)
    unit.RSCNativeWrite=true
    moho.unit_methods.SetAutoMode(unit,enabled==true)
    unit.RSCNativeWrite=nil
    unit.AutoModeEnabled=enabled==true
    Publish(unit)
end
local function AutoEvent(unit,enabled)
    if unit.RSCNativeWrite or not Policy.Managed(unit) then return end
    unit.AutoModeEnabled=enabled==true
    Publish(unit)
end
local function Track(unit)
    local cats=unit.Blueprint.CategoriesHash or {}
    Bridge().Target(tonumber(unit.EntityId),(Policy.Silo(unit) and 1 or 0)+(cats.INSIGNIFICANTUNIT and 2 or 0))
    if not Policy.Managed(unit) or units[unit.EntityId] then return end
    units[unit.EntityId]=unit
    if unit.AutoModeEnabled==nil then unit.AutoModeEnabled=(unit.Blueprint.AI or {}).InitialAutoMode==true end
    Configure(unit,Settings.Get(unit.Army))
    unit.RepairStationControlThread=unit:ForkThread(function()
        while not unit.Dead do
            WaitTicks(1)
            if unit:GetFractionComplete()==1 then Update(unit) end
        end
    end)
end
local function ApplyArmy(army,settings)
    local ids={};for id in pairs(units) do table.insert(ids,id) end;table.sort(ids)
    for _,id in ipairs(ids) do
        local unit=units[id]
        if not unit.Dead and unit.Army==army then Configure(unit,settings);Reconcile(unit,settings) end
    end
end
local function Reset() units={};Bridge().Reset() end
local function Start()
    Bridge()
    Exchange.Expose('RepairStationControl.SetAuto',{notifications=true,authorize=function(source,_,payload)
        if type(payload)~='table' or type(payload.Enabled)~='boolean' or type(payload.EntityId)~='number' then return false end
        local unit=GetEntityById(payload.EntityId)
        return source.army and unit and not unit.Dead and unit.Army==source.army and Policy.Managed(unit)
    end})
    Exchange.Subscribe('RepairStationControl.SetAuto',function(payload)
        local unit=GetEntityById(payload.EntityId)
        if unit and not unit.Dead then SetAuto(unit,payload.Enabled) end
    end)
end
Export={Track=Track,Update=Update,ApplyArmy=ApplyArmy,SetAuto=SetAuto,AutoEvent=AutoEvent,Start=Start,Reset=Reset,
    Remove=function(unit)
        Bridge().Worker(tonumber(unit.EntityId),0);Bridge().Target(tonumber(unit.EntityId),0)
        if not units[unit.EntityId] then return end
        units[unit.EntityId]=nil
        Exchange.UI.PublishState('RepairStationControl.Auto',unit.EntityId,nil,{army=unit.Army})
    end}
return Export
