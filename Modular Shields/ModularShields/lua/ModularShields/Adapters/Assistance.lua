-- The host pays for module work. Guarding engineers never run native repair in parallel.
local function Alive(u) return u and not u.Dead and not IsDestroyed(u) end
local function Assigned(u,host)
    -- The active order remains authoritative, including when focus is the dome.
    local queue=u:GetCommandQueue() or {}
    local command=queue[1]
    if not command then return false end
    if type(command)=='table' and command.commandType then
        local kind=command.commandType
        if kind~=9 and kind~=15 and kind~=20 then return false end -- assist, guard, repair
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
    if host.GetSkirtRect then
        local x0,z0,x1,z1=host:GetSkirtRect()
        local dx=math.max(x0-a[1],0,a[1]-x1)
        local dz=math.max(z0-a[3],0,a[3]-z1)
        local r=u.Blueprint.Economy.MaxBuildDistance or 0
        return dx*dx+dz*dz<=r*r
    end
    local r=(u.Blueprint.Economy.MaxBuildDistance or 0)+(host.Blueprint.SizeX or 1)/2
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
        if u.ModularAssistProgress then u:SetWorkProgress(0) end
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
    -- Native guard/repair callbacks must not create idle repair beams or retract
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
        if Alive(u) then native.Set(u,native.Rate);u:UpdateConsumptionValues() end
    end
    host.ModuleAssistants[id]=nil
end
local function Stop(host)
    for _,u in pairs(host.ModuleAssistants or {}) do StopEffects(u) end
    host.ModuleAssistantCount=0;host.ModuleWorkRate=nil
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
    local working=job and not host.InstallPaused
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
            and u.Blueprint.CategoriesHash.ENGINEER and Assigned(u,host) and InRange(u,host)
            and (not u.ModularAssistOwner or owned)
        if valid then
            if not owned then Claim(u,host) end
            if working and not u:IsPaused() then
                if not u.ModularAssistActive then
                    u.ModularAssistActive=true;StartEffects(u,host)
                end
                rate=rate+u.ModularNativeWork.Rate;count=count+1
                table.insert(assistants,id)
            else StopEffects(u) end
        elseif owned then Release(host,id) end
    end
    host.ModuleAssistantCount=count
    host.ModuleWorkRate=math.min(config.InstallMaxRate,rate)
    if job then job.AssistantIds=assistants end
    -- Also initialize engineers joining an installation already in progress.
    if working then UpdateProgress(host,math.min(1,job.PaidWork/job.Quote.Work)) end
    return host.ModuleWorkRate
end
Export={Rate=Rate,Stop=Stop,ReleaseAll=ReleaseAll,UpdateProgress=UpdateProgress}
return Export
