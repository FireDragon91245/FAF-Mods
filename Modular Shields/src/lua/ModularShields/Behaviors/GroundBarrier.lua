local G=import('/mods/ModularShields/lua/ModularShields/Core/Geometry.lua').Export
local Impact=import('/mods/ModularShields/lua/ModularShields/Adapters/Impact.lua').Export
local function Radius(u) return math.max(u.Blueprint.SizeX or 1,u.Blueprint.SizeZ or 1)/2 end
local function Air(u) return u:GetCurrentLayer()=='Air' end
local function DistanceSquared(a,b,air)
    local dx,dz=a[1]-b[1],a[3]-b[3]
    local dy=air and a[2]-b[2] or 0
    return dx*dx+dy*dy+dz*dz
end
local function Safe(u,p)
    if not Air(u) and not u:CanPathTo(p) then return false end
    if not import('/mods/ModularShields/lua/ModularShields/Services/Combat.lua').Export.GroundExterior(u,p) then return false end
    local r=Radius(u)
    local size=ScenarioInfo.size
    if p[1]<r or p[3]<r or p[1]>size[1]-r or p[3]>size[2]-r then return false end
    if GetUnitsInRect then
        for _,other in ipairs(GetUnitsInRect(p[1]-r,p[3]-r,p[1]+r,p[3]+r) or {}) do
            if other~=u and not other.Dead and not IsDestroyed(other) and other:GetCurrentLayer()==u:GetCurrentLayer() then
                local q=other:GetPosition();local rr=r+Radius(other)
                if DistanceSquared(q,p,Air(u))<rr*rr then return false end
            end
        end
    end
    return true
end
local function Push(u,record,center,radius,config)
    local p=u:GetPosition()
    local air=Air(u)
    local speed=air and (u.Blueprint.Air or {}).MaxAirspeed or (u.Blueprint.Physics or {}).MaxSpeed
    speed=speed or 2
    local distance=math.max(config.MinimumPush,speed*config.ReturnSeconds)
    local edge=radius+Radius(u)
    -- Fly out along the dome's cross-section at the current altitude. Warping
    -- aircraft to terrain height would turn a force-field hit into a crash.
    if air then local dy=p[2]-center[2];edge=math.sqrt(math.max(0,edge*edge-dy*dy)) end
    local minimum=edge+config.Clearance+distance
    if record.Outside then
        local q=record.Outside
        if (not air or math.abs(q[2]-p[2])<.1)
            and (q[1]-center[1])*(q[1]-center[1])+(q[3]-center[3])*(q[3]-center[3])>=minimum*minimum and Safe(u,q) then
            Warp(u,q);return true
        end
    end
    local dx,dz=p[1]-center[1],p[3]-center[3]
    local d=math.sqrt(dx*dx+dz*dz)
    if d<.01 then dx,dz,d=1,0,1 end
    local angle=math.atan2(dz,dx)
    local offsets={0,.2,-.2,.5,-.5,1,-1,1.5,-1.5,3.14}
    for _,extra in ipairs({0,3,7,12}) do
        for _,offset in ipairs(offsets) do
            local a=angle+offset
            local rr=minimum+extra
            local x,z=center[1]+math.cos(a)*rr,center[3]+math.sin(a)*rr
            local q={x,air and p[2] or math.max(GetTerrainHeight(x,z),GetSurfaceHeight(x,z)),z}
            if Safe(u,q) then Warp(u,q);record.Outside=G.Copy(q);return true end
        end
    end
    return false
end
local function Charge(host,u,position,center,config)
    local tick=GetGameTick()
    u.ModularBarrierHits=u.ModularBarrierHits or {}
    for id,untilTick in pairs(u.ModularBarrierHits) do if untilTick<=tick then u.ModularBarrierHits[id]=nil end end
    if u.ModularBarrierHits[host.EntityId] then return end
    u.ModularBarrierHits[host.EntityId]=tick+config.HitCooldownTicks
    local weight=(u.Blueprint.Physics or {}).Mass or (u.Blueprint.Economy or {}).BuildCostMass or 1
    local damage=math.max(config.MinimumDamage,weight*config.DamagePerMass)
    Impact.Apply(host.MyShield,u,damage,{center[1]-position[1],center[2]-position[2],center[3]-position[3]})
end
local function Tick(host,config)
    if not host.BarrierActive then host.BarrierRecords=nil;return end
    if host.BarrierRadius~=host.MyShield.Size/2 then host.BarrierRecords=nil;host.BarrierRadius=host.MyShield.Size/2 end
    host.BarrierRecords=host.BarrierRecords or {}
    local center=host.MyShield:GetPosition()
    local radius=host.MyShield.Size/2
    local units=host:GetAIBrain():GetUnitsAroundPoint((categories.LAND+categories.AIR)*categories.MOBILE,center,radius+config.ScanMargin,'Enemy') or {}
    table.sort(units,function(a,b) return a.EntityId<b.EntityId end)
    local seen={}
    for _,u in ipairs(units) do
        if not u.Dead and not IsDestroyed(u) and IsEnemy(host.Army,u.Army)
            and (u:GetCurrentLayer()=='Land' or u:GetCurrentLayer()=='Seabed' or Air(u)) and not u:IsUnitState('Attached') then
            local id,p=u.EntityId,u:GetPosition()
            seen[id]=true
            local record=host.BarrierRecords[id]
            local inside=DistanceSquared(p,center,Air(u))<(radius+Radius(u))*(radius+Radius(u))
            if not record then
                record={Position=G.Copy(p)}
                host.BarrierRecords[id]=record
            end
            local crossed=G.Entry(record.Position,p,center,radius+Radius(u),not Air(u))
            if inside or crossed then
                if Push(u,record,center,radius,config) then
                    Charge(host,u,p,center,config)
                    if host.MyShield:GetHealth()<=0 or host.MyShield.DisallowCollisions or not host.MyShield:IsUp() then
                        host.BarrierActive=false;host.BarrierRecords=nil;return
                    end
                end
            elseif not inside then record.Outside=G.Copy(p) end
            record.Position=G.Copy(u:GetPosition())
        end
    end
    for id in pairs(host.BarrierRecords) do if not seen[id] then host.BarrierRecords[id]=nil end end
end
Export={Entry=function(a,b,c,r) return G.Entry(a,b,c,r,true) end,Tick=Tick,Safe=Safe}
return Export
