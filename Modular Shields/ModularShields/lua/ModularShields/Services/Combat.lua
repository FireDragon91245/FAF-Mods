local root='/mods/ModularShields/lua/ModularShields/'
local R=import(root..'Runtime.lua').Export
local G=import(root..'Core/Geometry.lua').Export
local Deflector=import(root..'Behaviors/Deflector.lua').Export
local Impact=import(root..'Adapters/Impact.lua').Export
local hosts,projectiles={},{}
local thread
local candidateTick,candidates
local function Operational(host)
    local s=host and host.MyShield
    return host and not host.Dead and not IsDestroyed(host) and host.ModuleStats
        and s and not IsDestroyed(s) and not s.DisallowCollisions and s:IsUp()
end
local function Classify(p)
    if p.CrashingAirplaneShieldCollisionLogic or p.Plane then return 'crash' end
    local bp=p.Blueprint or {}
    local c=bp.CategoriesHash or {}
    local id=string.lower(bp.BlueprintId or '')
    id=string.gsub(id,'.*/','');id=string.gsub(id,'_proj%.bp$','')
    if c.HELPER or c.ANTIMISSILE then return nil end
    if (c.STRATEGIC and c.MISSILE) or c.TACTICALNUKE or (p.InnerRing and p.OuterRing) then return 'nuclear' end
    if c.MISSILE or c.ROCKET or R.Config.Projectiles.BallisticIds[id] then return 'ballistic' end
    if R.Config.Projectiles.ReflectIds[id] then return 'reflect' end
    return 'ordinary'
end
local function Supports(host,kind)
    if not Operational(host) then return false end
    local caps=host.ModuleStats.Capabilities
    if kind=='crash' then return caps.deflector end
    if kind=='nuclear' then return caps.atomized end
    if kind=='ballistic' then return caps.ballistic end
    if kind=='reflect' then return caps.deflector end
    return host.BarrierActive
end
local function Candidates(kind)
    local tick=GetGameTick()
    if candidateTick~=tick then
        candidates={crash={},nuclear={},ballistic={},reflect={},ordinary={}}
        for id,host in pairs(hosts) do
            for name,list in pairs(candidates) do if Supports(host,name) then list[table.getn(list)+1]=host end end
        end
        for _,list in pairs(candidates) do table.sort(list,function(a,b) return a.EntityId<b.EntityId end) end
        candidateTick=tick
    end
    return candidates[kind]
end
local function Damage(p,nuclear)
    local d=p.DamageData or {}
    local n=d.DamageAmount or 0
    if nuclear then
        n=math.max(n,(p.InnerRing and p.InnerRing.Damage or 0)+(p.OuterRing and p.OuterRing.Damage or 0),
            d.NukeInnerRingDamage or 0)
    end
    return math.max(0,n)
end
local function Resolve(p,host,kind,position)
    if p.ModularResolution or IsDestroyed(p) or not Supports(host,kind) or not IsEnemy(host.Army,p.Army) then return false end
    local shield=host.MyShield
    if kind=='crash' then return Deflector.Hit(p,shield,R.Config,position) end
    local tick=GetGameTick()
    if p.ModularReflectUntil and tick<p.ModularReflectUntil then return false end
    local point=position or p:GetPosition()
    local center=shield:GetPosition()
    local vector={center[1]-point[1],center[2]-point[2],center[3]-point[3]}
    local amount=Damage(p,kind=='nuclear')
    if kind=='reflect' then
        local normal=G.Normal(point,center)
        local x,y,z=p:GetVelocity()
        local v=G.Reflect({10*x,10*y,10*z},normal,R.Config.Projectiles.ReflectionOutwardSpeed)
        p:TrackTarget(false);p:SetTurnRate(0);p:SetAcceleration(0)
        p:SetNewTargetGround({point[1]+normal[1]*100,point[2]+normal[2]*100,point[3]+normal[3]*100})
        Warp(p,{point[1]+normal[1]*2,point[2]+normal[2]*2,point[3]+normal[3]*2})
        p:SetVelocity(v[1],v[2],v[3])
        p.ModularPrevious=G.Copy(p:GetPosition())
        p.ModularReflectUntil=tick+R.Config.Projectiles.ReflectionCooldownTicks
        p.ModularLastShield=host.EntityId
        Impact.Apply(shield,p.Launcher or p,amount,vector)
        return true
    end
    -- Claim before destroying: overlapping domes and nested callbacks resolve once.
    p.ModularResolution={HostId=host.EntityId,Kind=kind}
    local launcher=p.Launcher
    local army=p.Army
    p:SetCollision(false);p:TrackTarget(false)
    p.DamageData={DamageAmount=0,DamageRadius=0,DoTTime=0,DoTPulses=0,Buffs={}}
    p.InnerRing=nil;p.OuterRing=nil
    p:Destroy() -- never OnKilled/OnImpact; those can split or start blast/force threads
    local instigator=launcher and not IsDestroyed(launcher) and launcher or nil
    Impact.Apply(shield,instigator,amount,vector)
    import(root..'Adapters/Visuals.lua').Export.Burst(point,army,kind=='nuclear',kind=='nuclear' and 1 or .5)
    return true
end
local function Try(p,directShield)
    if p.ModularResolution then return true end
    if IsDestroyed(p) then return false end
    local kind=Classify(p)
    if not kind then return false end
    if kind=='ordinary' and Damage(p,false)<=0 then return false end
    if directShield and directShield.Owner and p.ModularLastShield==directShield.Owner.EntityId
        and GetGameTick()<(p.ModularReflectUntil or 0) then return true end
    if directShield and directShield.Owner and Resolve(p,directShield.Owner,kind) then return true end
    local a,b=p.ModularPrevious,p:GetPosition()
    if not a then p.ModularPrevious=G.Copy(b);return false end
    local best,bestT
    -- Earliest crossed dome wins; entity ID breaks exact geometric ties.
    for _,host in ipairs(Candidates(kind)) do
        if Supports(host,kind) and IsEnemy(host.Army,p.Army) then
            local shield=host.MyShield
            local t=G.Entry(a,b,shield:GetPosition(),shield.Size/2,false)
            if t and (not bestT or t<bestT or (t==bestT and host.EntityId<best.EntityId)) then best,bestT=host,t end
        end
    end
    if best then return Resolve(p,best,kind,G.Point(a,b,bestT)) end
    return false
end
local function Start()
    if thread then return end
    thread=ForkThread(function()
        WaitTicks(1)
        while next(hosts) do
            local hostIds={}
            for id in pairs(hosts) do hostIds[table.getn(hostIds)+1]=id end
            table.sort(hostIds)
            for _,id in ipairs(hostIds) do
                local host=hosts[id]
                if host.Dead or IsDestroyed(host) then hosts[id]=nil
                elseif host.TickBarrier then host:TickBarrier() end
            end
            local ids={}
            for id in pairs(projectiles) do ids[table.getn(ids)+1]=id end
            table.sort(ids)
            for _,id in ipairs(ids) do
                local p=projectiles[id]
                if IsDestroyed(p) or p.ModularResolution then projectiles[id]=nil
                else
                    Try(p)
                    if not IsDestroyed(p) then p.ModularPrevious=G.Copy(p:GetPosition()) end
                end
            end
            WaitTicks(1)
        end
        thread=nil
    end)
end
Export={Operational=Operational,Classify=Classify,Damage=Damage,Resolve=Resolve,Try=Try,
    Invalidate=function() candidateTick=nil end,
    Register=function(host) hosts[host.EntityId]=host;candidateTick=nil;Start() end,
    Unregister=function(host) hosts[host.EntityId]=nil;candidateTick=nil end,
    Track=function(p)
        if Classify(p) then projectiles[p.EntityId]=p;p.ModularPrevious=G.Copy(p:GetPosition()) end
    end,
    Forget=function(p) projectiles[p.EntityId]=nil end,
    GroundExterior=function(u,p)
        for _,host in pairs(hosts) do
            if host.BarrierActive and Operational(host) and IsEnemy(host.Army,u.Army) then
                local c=host.MyShield:GetPosition()
                local r=host.MyShield.Size/2+math.max(u.Blueprint.SizeX or 1,u.Blueprint.SizeZ or 1)/2
                if (p[1]-c[1])*(p[1]-c[1])+(p[3]-c[3])*(p[3]-c[3])<r*r then return false end
            end
        end
        return true
    end,
}
return Export
