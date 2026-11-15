local G=import('/mods/ModularShields/lua/ModularShields/Core/Geometry.lua').Export
local function Radius(u) return math.max(u.Blueprint.SizeX or 1,u.Blueprint.SizeZ or 1)/2 end
local function Safe(u,p)
    if not u:CanPathTo(p) then return false end
    if not import('/mods/ModularShields/lua/ModularShields/Services/Combat.lua').Export.GroundExterior(u,p) then return false end
    local r=Radius(u)
    local size=ScenarioInfo.size
    if p[1]<r or p[3]<r or p[1]>size[1]-r or p[3]>size[2]-r then return false end
    if GetUnitsInRect then
        for _,other in ipairs(GetUnitsInRect(p[1]-r,p[3]-r,p[1]+r,p[3]+r) or {}) do
            if other~=u and not other.Dead and not IsDestroyed(other) and other:GetCurrentLayer()==u:GetCurrentLayer() then
                local q=other:GetPosition();local rr=r+Radius(other)
                if (q[1]-p[1])*(q[1]-p[1])+(q[3]-p[3])*(q[3]-p[3])<rr*rr then return false end
            end
        end
    end
    return true
end
local function Push(u,record,center,radius,config)
    local p=u:GetPosition()
    if record.Outside and Safe(u,record.Outside) then Warp(u,record.Outside);return true end
    local dx,dz=p[1]-center[1],p[3]-center[3]
    local d=math.sqrt(dx*dx+dz*dz)
    if d<.01 then dx,dz,d=1,0,1 end
    local angle=math.atan2(dz,dx)
    local offsets={0,.2,-.2,.5,-.5,1,-1,1.5,-1.5,3.14}
    for _,extra in ipairs({0,3,7,12}) do
        for _,offset in ipairs(offsets) do
            local a=angle+offset
            local rr=radius+Radius(u)+config.Clearance+extra
            local x,z=center[1]+math.cos(a)*rr,center[3]+math.sin(a)*rr
            local q={x,math.max(GetTerrainHeight(x,z),GetSurfaceHeight(x,z)),z}
            if Safe(u,q) then Warp(u,q);record.Outside=G.Copy(q);return true end
        end
    end
    return false
end
local function Tick(host,config)
    if not host.BarrierActive then host.BarrierRecords=nil;return end
    if host.BarrierRadius~=host.MyShield.Size/2 then host.BarrierRecords=nil;host.BarrierRadius=host.MyShield.Size/2 end
    local initial=not host.BarrierRecords
    host.BarrierRecords=host.BarrierRecords or {}
    local center=host.MyShield:GetPosition()
    local radius=host.MyShield.Size/2
    local units=host:GetAIBrain():GetUnitsAroundPoint(categories.LAND*categories.MOBILE,center,radius+config.ScanMargin,'Enemy') or {}
    table.sort(units,function(a,b) return a.EntityId<b.EntityId end)
    local seen={}
    for _,u in ipairs(units) do
        if not u.Dead and not IsDestroyed(u) and IsEnemy(host.Army,u.Army)
            and (u:GetCurrentLayer()=='Land' or u:GetCurrentLayer()=='Seabed') and not u:IsUnitState('Attached') then
            local id,p=u.EntityId,u:GetPosition()
            seen[id]=true
            local record=host.BarrierRecords[id]
            local inside=(p[1]-center[1])*(p[1]-center[1])+(p[3]-center[3])*(p[3]-center[3])<(radius+Radius(u))*(radius+Radius(u))
            if not record then
                record={InsideAllowed=initial and inside,Position=G.Copy(p)}
                host.BarrierRecords[id]=record
            end
            if not inside then record.InsideAllowed=false
            elseif not record.InsideAllowed then Push(u,record,center,radius,config) end
            if not record.InsideAllowed and G.Entry(record.Position,p,center,radius+Radius(u),true) then
                Push(u,record,center,radius,config)
            elseif not inside then record.Outside=G.Copy(p) end
            record.Position=G.Copy(u:GetPosition())
        end
    end
    for id in pairs(host.BarrierRecords) do if not seen[id] then host.BarrierRecords[id]=nil end end
end
Export={Entry=function(a,b,c,r) return G.Entry(a,b,c,r,true) end,Tick=Tick,Safe=Safe}
return Export
