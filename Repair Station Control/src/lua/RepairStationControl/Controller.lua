local Policy=import('/mods/RepairStationControl/lua/RepairStationControl/Policy.lua').Export
local Settings=import('/mods/RepairStationControl/lua/RepairStationControl/Settings.lua').Export
local Exchange=import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export
local units={}
local function Active(settings) return settings.DontHelpTeam or settings.DontHelpNukes end
local function Publish(unit)
    Exchange.UI.PublishState('RepairStationControl.Auto',unit.EntityId,
        {Enabled=unit.AutoModeEnabled==true},{army=unit.Army})
end
local function Native(unit,enabled)
    if unit.RSCNativeMode==enabled then return end
    unit.RSCNativeWrite=true
    moho.unit_methods.SetAutoMode(unit,enabled)
    unit.RSCNativeWrite=nil
    unit.RSCNativeMode=enabled
end
local function Configure(unit,settings)
    local desired=unit.AutoModeEnabled==true
    -- The native search has no per-worker candidate predicate. It must never
    -- compete with the filtered selector, even for one simulation tick.
    Native(unit,desired and not Active(settings))
    unit.AutoModeEnabled=desired
    unit.RSCArmy=unit.Army
    Publish(unit)
end
local function Cancel(unit)
    IssueClearCommands({unit})
    unit.RSCAutoTarget=nil
end
local function Busy(target)
    return target:IsUnitState('Building') or target:IsUnitState('SiloBuildingAmmo')
end
local function Candidate(worker,settings)
    local bp=worker.Blueprint
    local anchor=worker.Parent
    if not anchor or anchor.Dead then anchor=worker end
    local ai=anchor.Blueprint.AI or {}
    local radius=ai.StagingPlatformScanRadius or ai.GuardScanRadius or
        (bp.Economy or {}).MaxBuildDistance or (bp.AI or {}).GuardScanRadius or 25
    local pos=anchor:GetPosition()
    local nearby=worker:GetAIBrain():GetUnitsAroundPoint(categories.ALLUNITS,pos,radius,'Ally') or {}
    local best,distance
    for _,target in ipairs(nearby) do
        if target~=worker and not target.Dead and not target.ModuleHost and
            not (target.Blueprint.CategoriesHash or {}).INSIGNIFICANTUNIT and
            IsAlly(worker.Army,target.Army) and Policy.Allowed(worker,target,settings) and
            (Policy.NeedsRepair(target) or Busy(target)) then
            local p=target:GetPosition()
            local d=(p[1]-pos[1])*(p[1]-pos[1])+(p[3]-pos[3])*(p[3]-pos[3])
            if d<=radius*radius and (not distance or d<distance or
                (d==distance and target.EntityId<best.EntityId)) then best=target;distance=d end
        end
    end
    return best
end
local function OwnOrder(unit)
    local target=unit.RSCAutoTarget
    local first=(unit:GetCommandQueue() or {})[1]
    return target and first and (first.commandType==9 or first.commandType==15 or first.commandType==20)
        and (first.target==target or first.targetId==target.EntityId)
end
local function NativeIdle(unit)
    -- Pods and Hives retain the engine's AssistCommander idle command even
    -- with auto acquisition disabled. It is not a player order.
    local queue=unit:GetCommandQueue() or {}
    local cats=unit.Blueprint.CategoriesHash
    return (cats.ENGINEERSTATION or (unit.Parent and cats.POD)) and table.getn(queue)==1
        and queue[1].commandType==29
end
local function Reconcile(unit,settings)
    local focus,guarded=unit:GetFocusUnit(),unit:GetGuardedUnit()
    if (focus and not Policy.Allowed(unit,focus,settings)) or
        (guarded and not NativeIdle(unit) and not Policy.Allowed(unit,guarded,settings)) then
        Cancel(unit)
    end
end
local function StationEnabled(unit)
    local parent=unit.Parent
    if parent and not parent.Dead and (parent.Blueprint.CategoriesHash or {}).ENGINEERSTATION then
        if not parent.AutoModeEnabled or parent:IsPaused() or parent:GetScriptBit(4) then return false end
    end
    return not (unit.Blueprint.CategoriesHash.ENGINEERSTATION and unit:GetScriptBit(4))
end
local function Update(unit)
    if unit.Dead then return end
    local settings=Settings.Get(unit.Army)
    if unit.RSCArmy~=unit.Army or unit.RSCFiltering~=Active(settings) then
        Configure(unit,settings);unit.RSCFiltering=Active(settings)
    end
    if not Active(settings) then unit.RSCAutoTarget=nil;return end
    -- Validation releases a task when its circumstances change; acquisition is
    -- filtered BEFORE orders are issued. Native acquisition remains disabled.
    Reconcile(unit,settings)
    if unit.RSCAutoTarget then
        if not OwnOrder(unit) then unit.RSCAutoTarget=nil
        elseif not unit.AutoModeEnabled or not StationEnabled(unit) or unit.RSCAutoTarget.Dead or
            (not Policy.NeedsRepair(unit.RSCAutoTarget) and not Busy(unit.RSCAutoTarget)) then Cancel(unit) end
    end
    local idle=NativeIdle(unit)
    if not unit.AutoModeEnabled or not StationEnabled(unit) or unit:IsPaused() or
        unit.ModularAssistOwner or unit.ModuleAutoAssistHost or unit:GetFocusUnit() or
        (next(unit:GetCommandQueue() or {}) and not idle) or (unit:IsUnitState('Moving') and not idle) or
        unit:IsUnitState('Reclaiming') or unit:IsUnitState('Patrolling') or (unit:IsUnitState('Attached') and not idle) then return end
    local target=Candidate(unit,settings)
    if target then
        if idle then Cancel(unit) end
        unit.RSCAutoTarget=target
        if Policy.NeedsRepair(target) then IssueRepair({unit},target) else IssueGuard({unit},target) end
    end
end
local function SetAuto(unit,enabled)
    unit.AutoModeEnabled=enabled==true
    Configure(unit,Settings.Get(unit.Army))
    if not enabled and OwnOrder(unit) then Cancel(unit) end
end
local function AutoEvent(unit,enabled)
    if unit.RSCNativeWrite or not Policy.Managed(unit) then return end
    unit.RSCNativeMode=enabled
    SetAuto(unit,enabled)
end
local function Track(unit)
    if not Policy.Managed(unit) or units[unit.EntityId] then return end
    units[unit.EntityId]=unit
    if unit.AutoModeEnabled==nil then unit.AutoModeEnabled=(unit.Blueprint.AI or {}).InitialAutoMode==true end
    Configure(unit,Settings.Get(unit.Army))
    unit.RepairStationControlThread=unit:ForkThread(function()
        while not unit.Dead do
            WaitTicks(10)
            if unit:GetFractionComplete()==1 then Update(unit) end
        end
    end)
end
local function ApplyArmy(army,settings)
    local ids={};for id in pairs(units) do table.insert(ids,id) end;table.sort(ids)
    for _,id in ipairs(ids) do
        local unit=units[id]
        if not unit.Dead and unit.Army==army then
            -- Disable native acquisition before stopping an already excluded
            -- target. This callback runs in the accepted settings transaction.
            Configure(unit,settings);unit.RSCFiltering=Active(settings)
            Reconcile(unit,settings)
        end
    end
end
local function Start()
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
Export={Track=Track,Update=Update,Candidate=Candidate,ApplyArmy=ApplyArmy,SetAuto=SetAuto,AutoEvent=AutoEvent,Start=Start,
    Remove=function(unit)
        if not units[unit.EntityId] then return end
        units[unit.EntityId]=nil
        Exchange.UI.PublishState('RepairStationControl.Auto',unit.EntityId,nil,{army=unit.Army})
    end}
return Export
