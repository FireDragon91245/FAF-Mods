-- The host pays for module work. Outside module jobs, native chassis repair is
-- untouched; the generator removes only its dome's native repair focus.
local function Alive(u) return u and not u.Dead and not IsDestroyed(u) end
local function Assigned(u,host)
    -- The active order remains authoritative, including when focus is the dome.
    local queue=u:GetCommandQueue() or {}
    local command=queue[1]
    if not command then return false end
    if type(command)=='table' and command.commandType then
        local kind=command.commandType
        if kind~=9 and kind~=15 and kind~=20 then return false end
        local target=command.target
        local id=command.targetId
        local shield=host.MyShield
        return target==host or (shield and target==shield)
            or (id and (id==host.EntityId or (shield and id==shield:GetEntityId())))
    end
    return table.getn(queue)<=2 and (u:GetGuardedUnit()==host or u:GetFocusUnit()==host)
end
local function InRange(u,host)
    local a,b=u:GetPosition(),host:GetPosition()
    local r=u.Blueprint.Economy.MaxBuildDistance or (u.Blueprint.CategoriesHash.STATIONASSISTPOD and 10 or 0)
    if host.GetSkirtRect then
        local x0,z0,x1,z1=host:GetSkirtRect()
        local dx=math.max(x0-a[1],0,a[1]-x1)
        local dz=math.max(z0-a[3],0,a[3]-z1)
        return dx*dx+dz*dz<=r*r
    end
    r=r+(host.Blueprint.SizeX or 1)/2
    return (a[1]-b[1])*(a[1]-b[1])+(a[3]-b[3])*(a[3]-b[3])<=r*r
end
local function StartEffects(u,host)
    if u.OnPrepareArmToBuild then u:OnPrepareArmToBuild() end
    if u.BuildingOpenAnimManip then u.BuildingOpenAnimManip:SetRate(u.Blueprint.Display.AnimationBuildRate or 1) end
    if u.BuildManipulatorSetEnabled then u:BuildManipulatorSetEnabled(true) end
    if not AttachBeamEntityToEntity then return end
    u.ModularAssistBeams={}
    local bones=u.BuildEffectBones or {0}
    for _,bone in ipairs(bones) do
        local beam=AttachBeamEntityToEntity(u,bone,host,0,u.Army,'/effects/emitters/build_beam_01_emit.bp')
        table.insert(u.ModularAssistBeams,beam)
        u.Trash:Add(beam)
    end
end
local function StopEffects(u)
    for _,beam in ipairs(u.ModularAssistBeams or {}) do beam:Destroy() end
    u.ModularAssistBeams=nil
    if Alive(u) then
        u:SetWorkProgress(0)
        if u.BuildingOpenAnimManip then u.BuildingOpenAnimManip:SetRate(-(u.Blueprint.Display.AnimationBuildRate or 1)) end
        if u.BuildManipulatorSetEnabled then u:BuildManipulatorSetEnabled(false) end
    end
    u.ModularAssistActive=false
    u.ModularAssistProgress=nil
end
local function UpdateProgress(host,progress)
    for _,u in pairs(host.ModuleAssistants or {}) do
        if Alive(u) and u.ModularAssistActive then
            u:SetWorkProgress(progress)
            u.ModularAssistProgress=true
        end
    end
end
local function Claim(u,host)
    local native={Rate=u:GetBuildRate(),Set=u.SetBuildRate,Update=u.UpdateConsumptionValues,
        OwnSet=rawget(u,'SetBuildRate'),OwnUpdate=rawget(u,'UpdateConsumptionValues'),
        Prepare=u.OnPrepareArmToBuild,Tracking=u.OnStopBuilderTracking,
        OwnPrepare=rawget(u,'OnPrepareArmToBuild'),OwnTracking=rawget(u,'OnStopBuilderTracking'),
        OwnEffects=rawget(u,'StartBuildingEffects')}
    u.ModularNativeWork=native;u.ModularAssistOwner=host
    host.ModuleAssistants[u.EntityId]=u
    -- Keep buffs effective while holding the native engine at zero build rate.
    u.SetBuildRate=function(unit,rate) native.Rate=rate;native.Set(unit,0) end
    -- Native guard/repair callbacks must not create extra repair beams or retract
    -- the arm while the scripted module job is using it.
    if u.StopBuildingEffects then u:StopBuildingEffects(u:GetFocusUnit()) end
    u.StartBuildingEffects=function() end
    u.OnPrepareArmToBuild=function(unit)
        if unit.ModularAssistActive and native.Prepare then native.Prepare(unit) end
    end
    u.OnStopBuilderTracking=function(unit)
        if not unit.ModularAssistActive and native.Tracking then native.Tracking(unit) end
    end
    u.UpdateConsumptionValues=function(unit)
        local active=unit.ActiveConsumption
        unit.ActiveConsumption=false
        native.Update(unit)
        unit.ActiveConsumption=active
    end
    native.Set(u,0)
    u:UpdateConsumptionValues()
end
local function Release(host,id)
    local u=host.ModuleAssistants[id]
    if u and u.ModularAssistOwner==host then
        StopEffects(u)
        local native=u.ModularNativeWork
        u.SetBuildRate=native.OwnSet;u.UpdateConsumptionValues=native.OwnUpdate
        u.OnPrepareArmToBuild=native.OwnPrepare;u.OnStopBuilderTracking=native.OwnTracking
        u.StartBuildingEffects=native.OwnEffects
        u.ModularNativeWork=nil;u.ModularAssistOwner=nil
        if Alive(u) then
            native.Set(u,native.Rate);u:UpdateConsumptionValues()
            -- A module can finish while a guard still has chassis damage to
            -- repair. Restore its native animation/effects along with its rate.
            if host.GetHealth and host:GetHealth()<host:GetMaxHealth() and u:GetFocusUnit()==host and not u:IsPaused() then
                if u.OnPrepareArmToBuild then u:OnPrepareArmToBuild() end
                if u.StartBuildingEffects then u:StartBuildingEffects(host,'Repair') end
            end
        end
    end
    host.ModuleAssistants[id]=nil
end
local function ReleaseAll(host)
    host.ModuleAssistants=host.ModuleAssistants or {}
    local ids={};for id in pairs(host.ModuleAssistants) do table.insert(ids,id) end;table.sort(ids)
    for _,id in ipairs(ids) do Release(host,id) end
    host.ModuleAssistantCount=0;host.ModuleWorkRate=nil
end
local function Rate(host,config)
    host.ModuleAssistants=host.ModuleAssistants or {}
    if host.ModuleUpgrading then ReleaseAll(host);return config.InstallRate end
    local job=host.Loadout and host.Loadout.Queue[1]
    local working=job and job.State~='WaitingForSlots' and not host.InstallPaused
    if not working then ReleaseAll(host);return config.InstallRate end
    local candidates={}
    for _,u in ipairs(host:GetGuards() or {}) do candidates[u.EntityId]=u end
    for id,u in pairs(host.Repairers or {}) do candidates[id]=u end
    for id,u in pairs(host.ModuleAssistants) do candidates[id]=u end
    local ids={};for id in pairs(candidates) do table.insert(ids,id) end;table.sort(ids)
    local rate,count=config.InstallRate,0
    local assistants={}
    for _,id in ipairs(ids) do
        local u=candidates[id]
        local owned=u.ModularAssistOwner==host
        local valid=Alive(u) and u.Army==host.Army and u:GetFractionComplete()==1
            and u.Blueprint.CategoriesHash.ENGINEER
            and Assigned(u,host) and InRange(u,host)
            and (not u.ModularAssistOwner or owned)
        if valid then
            if not owned then Claim(u,host) end
            if working and not u:IsPaused() then
                if not u.ModularAssistActive then
                    u.ModularAssistActive=true;StartEffects(u,host)
                end
                rate=rate+u.ModularNativeWork.Rate;count=count+1
                table.insert(assistants,id)
            else Release(host,id) end
        elseif owned then Release(host,id) end
    end
    host.ModuleAssistantCount=count
    host.ModuleWorkRate=math.min(config.InstallMaxRate,rate)
    if job then job.AssistantIds=assistants end
    -- Also initialize engineers joining an installation already in progress.
    if working then UpdateProgress(host,math.min(1,job.PaidWork/job.Quote.Work)) end
    return host.ModuleWorkRate
end
local function AutoEnabled(u)
    if not Alive(u) or not u.AutoModeEnabled or u:IsPaused() then return false end
    local station=u.Parent or u
    if not Alive(station) or not station.AutoModeEnabled or station:IsPaused() then return false end
    return not station:GetScriptBit(4)
end
local function Approaching(u,host)
    local p=u.ModuleAutoAssistMove
    local queue=u:GetCommandQueue() or {}
    local move,guard=queue[1],queue[2]
    return p and table.getn(queue)==2 and move.commandType==2 and guard.commandType==15
        and (guard.target==host or guard.targetId==host.EntityId)
        and move.x==p[1] and move.z==p[3]
end
-- Native auto-assist only sees construction/damage, not scripted module jobs.
-- The pod's one AssistCommander (29) command is its idle docking/return task.
-- Clear that task before guarding; appending work leaves it behind forever.
local function AutoDrone(u)
    if not Alive(u) then return end
    local owner = u.ModuleAutoAssistHost
    if owner then
        if Assigned(u,owner) then u.ModuleAutoAssistMove=nil
        elseif not Approaching(u,owner) then
            u.ModuleAutoAssistHost=nil;u.ModuleAutoAssistMove=nil;return
        end
        local job=owner.Loadout and owner.Loadout.Queue[1]
        if Alive(owner) and AutoEnabled(u)
            and job and job.State~='WaitingForSlots' and not owner.InstallPaused and not owner.ModuleUpgrading then return end
        IssueClearCommands({u})
        u.ModuleAutoAssistHost=nil;u.ModuleAutoAssistMove=nil
    end
    if not AutoEnabled(u) then return end
    local queue=u:GetCommandQueue() or {}
    local cats=u.Blueprint.CategoriesHash
    local idle=(cats.ENGINEERSTATION or (u.Parent and cats.POD))
        and table.getn(queue)==1 and queue[1].commandType==29
    if (next(queue) and not idle) or (u:GetFocusUnit() and not idle)
        or (u:IsUnitState('Moving') and not idle) or u:IsUnitState('Reclaiming')
        or u:IsUnitState('Patrolling') or (u:IsUnitState('Attached') and not idle) then return end
    local anchor=u.Parent or u
    local ai=anchor.Blueprint.AI or {}
    local radius=ai.StagingPlatformScanRadius or ai.GuardScanRadius or u.Blueprint.Economy.MaxBuildDistance or 0
    local center=anchor:GetPosition()
    local hosts=u:GetAIBrain():GetUnitsAroundPoint(categories.MODULARSHIELD,center,radius,'Ally') or {}
    table.sort(hosts,function(a,b) return a.EntityId<b.EntityId end)
    for _,host in ipairs(hosts) do
        local job=host.Loadout and host.Loadout.Queue[1]
        if Alive(host) and host.Army==u.Army and job and job.State~='WaitingForSlots'
            and not host.InstallPaused and not host.ModuleUpgrading then
            local p=host:GetPosition()
            local dx,dz=p[1]-center[1],p[3]-center[3]
            -- The engine broad-phase can include shields outside the scan.
            if dx*dx+dz*dz<=radius*radius then
                if idle then IssueClearCommands({u}) end
                u.ModuleAutoAssistHost=host
                -- Healthy generators expose no native construction focus, so
                -- guard alone leaves a pod docked outside its short build range.
                if cats.POD and (u:IsUnitState('Attached') or not InRange(u,host)) then
                    u.ModuleAutoAssistMove={p[1],p[2],p[3]}
                    IssueMove({u},u.ModuleAutoAssistMove)
                end
                IssueGuard({u},host)
                return
            end
        end
    end
end
Export={Rate=Rate,Stop=ReleaseAll,ReleaseAll=ReleaseAll,UpdateProgress=UpdateProgress,AutoDrone=AutoDrone}
return Export
