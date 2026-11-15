-- Scripted work backend. Claimed engineers pause native work to avoid double use.
local function Alive(u) return u and not u.Dead and not IsDestroyed(u) end
local function Assigned(u,host) return u:GetGuardedUnit()==host or u:GetFocusUnit()==host end
local function InRange(u,host)
    local a,b=u:GetPosition(),host:GetPosition()
    local r=(u.Blueprint.Economy.MaxBuildDistance or 0)+(host.Blueprint.SizeX or 1)/2
    return (a[1]-b[1])*(a[1]-b[1])+(a[3]-b[3])*(a[3]-b[3])<=r*r
end
local function Release(host,id)
    local u=host.ModuleAssistants[id]
    if u and u.ModularAssistOwner==host then
        u.ModularAssistOwner=nil
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
        local owned=u.ModularAssistOwner==host
        if owned and not u:IsPaused() then
            Release(host,id);host.ModuleAssistExcluded[id]=true;owned=false
        end
        local valid=Alive(u) and u.Army==host.Army and u:GetFractionComplete()==1
            and u.Blueprint.CategoriesHash.ENGINEER and Assigned(u,host) and InRange(u,host)
            and table.getn(u:GetCommandQueue())<=2 and (not u.ModularAssistOwner or owned) and not host.ModuleAssistExcluded[id]
        if valid and (owned or not u:IsPaused()) then
            if not owned then u.ModularAssistOwner=host;host.ModuleAssistants[id]=u;u:SetPaused(true) end
            rate=rate+u:GetBuildRate();count=count+1
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
