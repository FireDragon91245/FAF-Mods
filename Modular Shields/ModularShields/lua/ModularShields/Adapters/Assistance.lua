-- Scripted work backend. Claimed engineers pause native work to avoid double use.
local function Alive(u) return u and not u.Dead and not IsDestroyed(u) end
local function Assigned(u,host)
    -- Pausing native construction can clear its focus/guard pointer. The active
    -- order remains authoritative, including when the focus was the dome.
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
    -- Own these separately: SetPaused stops the engineer's native build effects.
    -- Native construction stays paused so there is only one economy backend.
    if not AttachBeamEntityToEntity then return end
    u.ModularAssistBeams={}
    local bones=u.BuildEffectBones or {0}
    for _,bone in ipairs(bones) do
        local beam=AttachBeamEntityToEntity(u,bone,host,0,u.Army,'/effects/emitters/build_beam_01_emit.bp')
        table.insert(u.ModularAssistBeams,beam)
        u.Trash:Add(beam)
    end
end
local function Release(host,id)
    local u=host.ModuleAssistants[id]
    if u and u.ModularAssistOwner==host then
        u.ModularAssistOwner=nil
        u.ModularAssistRate=nil
        for _,beam in ipairs(u.ModularAssistBeams or {}) do beam:Destroy() end
        u.ModularAssistBeams=nil
        if Alive(u) then u:SetPaused(false) end
    end
    host.ModuleAssistants[id]=nil
end
local function ReleaseAll(host)
    host.ModuleAssistants=host.ModuleAssistants or {}
    local ids={};for id in pairs(host.ModuleAssistants) do ids[table.getn(ids)+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do Release(host,id) end
    host.ModuleAssistantCount=0;host.ModuleWorkRate=nil
    host.ModuleAssistExcluded={}
end
local function Rate(host,config)
    host.ModuleAssistants=host.ModuleAssistants or {}
    host.ModuleAssistExcluded=host.ModuleAssistExcluded or {}
    local candidates={}
    for _,u in ipairs(host:GetGuards() or {}) do candidates[u.EntityId]=u end
    for id,u in pairs(host.Repairers or {}) do candidates[id]=u end
    for id,u in pairs(host.ModuleAssistants) do candidates[id]=u end
    local ids={};for id in pairs(candidates) do ids[table.getn(ids)+1]=id end;table.sort(ids)
    local rate,count=config.InstallRate,0
    local assistants={}
    for _,id in ipairs(ids) do
        local u=candidates[id]
        local alive=Alive(u)
        local owned=u.ModularAssistOwner==host
        if owned and alive and not u:IsPaused() then
            Release(host,id);host.ModuleAssistExcluded[id]=true;owned=false
        end
        local valid=alive and u.Army==host.Army and u:GetFractionComplete()==1
            and u.Blueprint.CategoriesHash.ENGINEER and Assigned(u,host) and InRange(u,host)
            and (not u.ModularAssistOwner or owned) and not host.ModuleAssistExcluded[id]
        if valid and (owned or not u:IsPaused()) then
            if not owned then
                u.ModularAssistRate=u:GetBuildRate()
                u.ModularAssistOwner=host;host.ModuleAssistants[id]=u
                u:SetPaused(true)
                StartEffects(u,host)
            else
                local current=u:GetBuildRate()
                if current>0 then u.ModularAssistRate=current end
            end
            rate=rate+u.ModularAssistRate;count=count+1
            assistants[table.getn(assistants)+1]=id
        elseif owned then Release(host,id) end
    end
    host.ModuleAssistantCount=count
    host.ModuleWorkRate=math.min(config.InstallMaxRate,rate)
    local job=host.Loadout and host.Loadout.Queue[1]
    if job then job.AssistantIds=assistants end
    return host.ModuleWorkRate
end
Export={Rate=Rate,ReleaseAll=ReleaseAll}
return Export
