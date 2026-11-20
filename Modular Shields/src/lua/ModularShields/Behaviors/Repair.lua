local function Alive(u) return u and not u.Dead and not IsDestroyed(u) end
local function Reclaiming(target)
    for id,u in pairs(target.ModularReclaimers or {}) do
        if Alive(u) and u.EntityBeingReclaimed==target then return true end
        target.ModularReclaimers[id]=nil
    end
    return false
end
local function Eligible(host,target)
    if not Alive(host) or not Alive(target) or target==host or target.ModuleHost
        or target.Army~=host.Army or Reclaiming(target) or host.RepairPaused
        or not host.MyShield or not host.MyShield:IsUp() or host.ModuleStats.RepairBudget<=0 then return false end
    if target:GetFractionComplete()==1 and target:GetHealth()>=target:GetMaxHealth() then return false end
    local a,b=host.MyShield:GetPosition(),target:GetPosition()
    local dx,dy,dz=a[1]-b[1],a[2]-b[2],a[3]-b[3]
    local radius=host.ModuleStats.ShieldSize/2
    return dx*dx+dy*dy+dz*dz<=radius*radius
end
local function RemoveEvent(helper)
    helper.ModuleEventEpoch=(helper.ModuleEventEpoch or 0)+1
    if helper.ModuleRepairEvent then RemoveEconomyEvent(helper,helper.ModuleRepairEvent);helper.ModuleRepairEvent=nil end
    helper.ModuleEventRequestedMass=0
end
local function StopHelper(helper)
    if not Alive(helper) then return end
    RemoveEvent(helper)
    helper:SetBuildRate(0)
    IssueClearCommands({helper})
    helper:Destroy()
end
local function Consumption(host)
    local mass,energy,requestedMass,requestedEnergy=0,0,0,0
    local now=GetGameTick()
    for _,helper in pairs(host.ModuleRepairHelpers or {}) do
        if Alive(helper) then
            if helper.ModuleWorkKind=='build' then
                local m,e=helper:GetConsumptionPerSecondMass(),helper:GetConsumptionPerSecondEnergy()
                local fraction=math.max(0,math.min(1,helper:GetResourceConsumed()))
                requestedMass=requestedMass+m;requestedEnergy=requestedEnergy+e
                mass=mass+m*fraction;energy=energy+e*fraction
            else
                requestedMass=requestedMass+(helper.ModuleEventRequestedMass or 0)
                if now-(helper.ModulePaidTick or -100)<=1 then mass=mass+(helper.ModulePaidRate or 0) end
            end
        end
    end
    return mass,energy,requestedMass,requestedEnergy
end
local function Stop(host)
    for _,helper in pairs(host.ModuleRepairHelpers or {}) do StopHelper(helper) end
    host.ModuleRepairHelpers={}
end
local function Work(helper,host,target,R)
    while Eligible(host,target) do
        local free=(R.Config.Debug or {}).IgnoreResources==true
        local building=target:GetFractionComplete()<1
        if building then
            helper.ModuleWorkKind='build'
            if helper.ModuleFree~=free then helper.ModuleFree=free;helper:UpdateConsumptionValues() end
            local rate=helper.ModuleHPPerSecond*target.Blueprint.Economy.BuildTime/target:GetMaxHealth()
            if helper.ModuleBuildRate~=rate then
                helper.ModuleBuildRate=rate;helper:SetBuildRate(rate);helper:UpdateConsumptionValues()
            end
            -- Native repair can drop a stale order during builder handoff. Retry
            -- idle work rather than retaining a one-time "ordered" flag forever.
            if table.getn(helper:GetCommandQueue() or {})==0 then IssueRepair({helper},target) end
            WaitTicks(1)
        else
            if helper.ModuleWorkKind=='build' then
                helper:SetBuildRate(0);IssueClearCommands({helper})
            end
            helper.ModuleWorkKind='repair'
            local hp=math.min(target:GetMaxHealth()-target:GetHealth(),helper.ModuleHPPerSecond/10)
            if free or (target.Blueprint.Economy.BuildCostMass or 0)<=0 then
                RemoveEvent(helper)
                target:SetHealth(host,target:GetHealth()+hp)
                WaitTicks(1)
            else
                -- Every target owns a native economy event, including moving and
                -- airborne units which native IssueRepair refuses. The fulfilled
                -- fraction buys smooth chassis HP, never shield-dome regeneration.
                local perHP=R.Config.RepairFactor*(host.ModuleStats.RepairMassMultiplier or 1)
                    *target.Blueprint.Economy.BuildCostMass/target:GetMaxHealth()
                local cost=hp*perHP
                local epoch=(helper.ModuleEventEpoch or 0)+1
                helper.ModuleEventEpoch=epoch
                local progress=0
                helper.ModuleEventRequestedMass=cost*10
                local event=CreateEconomyEvent(helper,0,cost,.1,function(_,fraction)
                    if not Alive(helper) or helper.ModuleEventEpoch~=epoch or not Eligible(host,target)
                        or (R.Config.Debug or {}).IgnoreResources then return end
                    fraction=math.max(progress,math.min(1,fraction))
                    local delta=fraction-progress;progress=fraction
                    if delta<=0 then return end
                    local tick=GetGameTick()
                    if helper.ModulePaidTick~=tick then helper.ModulePaidTick=tick;helper.ModulePaidRate=0 end
                    helper.ModulePaidRate=helper.ModulePaidRate+cost*delta*10
                    target:SetHealth(host,math.min(target:GetMaxHealth(),target:GetHealth()+hp*delta))
                end)
                helper.ModuleRepairEvent=event
                repeat WaitTicks(1) until progress>=1 or not Eligible(host,target)
                    or (R.Config.Debug or {}).IgnoreResources
                RemoveEvent(helper)
            end
        end
    end
    StopHelper(helper)
end
local function StartHelper(host,target,rate,R)
    host.ModuleRepairHelpers=host.ModuleRepairHelpers or {}
    local helper=host.ModuleRepairHelpers[target.EntityId]
    if not Alive(helper) then
        local p=target:GetPosition()
        helper=CreateUnitHPR('mds0001',host.Army,p[1],p[2],p[3],0,0,0)
        helper.ModuleHost=host;helper.ModuleTarget=target;helper.ModuleHPPerSecond=rate
        helper.ModuleFree=(R.Config.Debug or {}).IgnoreResources==true
        host.ModuleRepairHelpers[target.EntityId]=helper
        helper:ForkThread(Work,host,target,R)
    else helper.ModuleHPPerSecond=rate end
end
local function Tick(host,R)
    host.ModuleRepairHelpers=host.ModuleRepairHelpers or {}
    if not Alive(host) or host.RepairPaused or not host.MyShield or not host.MyShield:IsUp()
        or host.ModuleStats.RepairBudget<=0 then Stop(host);return end
    local targets={}
    for _,u in ipairs(host:GetAIBrain():GetUnitsAroundPoint(categories.ALLUNITS,host.MyShield:GetPosition(),host.ModuleStats.ShieldSize/2,'Ally') or {}) do
        if Eligible(host,u) then table.insert(targets,u) end
    end
    table.sort(targets,function(a,b) return a.EntityId<b.EntityId end)
    local wanted={}
    local count=table.getn(targets)
    if count>0 then
        local rate=host.ModuleStats.RepairBudget/count
        for _,u in ipairs(targets) do wanted[u.EntityId]=true;StartHelper(host,u,rate,R) end
    end
    for id,helper in pairs(host.ModuleRepairHelpers) do
        if not wanted[id] then StopHelper(helper);host.ModuleRepairHelpers[id]=nil end
    end
end
Export={Tick=Tick,Stop=Stop,Consumption=Consumption,Reclaiming=Reclaiming}
return Export
