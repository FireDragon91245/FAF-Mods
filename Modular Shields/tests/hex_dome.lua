local count=0
local function check(v,msg) count=count+1;assert(v,msg) end
local entities={}
function LOG() end
function IsDestroyed(e) return e.Destroyed end
function WaitTicks(n) coroutine.yield(n) end
function Warp(e,p) e.Position=p end
function OrientFromDir(v) return v end
function import(path)
    assert(path=='/lua/sim/entity.lua')
    return {Entity=function(spec)
        local e={Owner=spec.Owner}
        function e:SetMesh(p) self.Mesh=p end
        function e:SetDrawScale(n) self.Scale=n end
        function e:SetOrientation(v) self.Direction=v end
        function e:SetVizToFocusPlayer(v) self.Focus=v end
        function e:SetVizToAllies(v) self.Allies=v end
        function e:SetVizToEnemies(v) self.Enemies=v end
        function e:SetVizToNeutrals(v) self.Neutrals=v end
        function e:Destroy() self.Destroyed=true end
        entities[#entities+1]=e
        return e
    end}
end
assert(loadfile('src/lua/ModularShields/Adapters/HexDome.lua'))()
local V=Export
local shield={HP=800,MaxHP=1000,Size=50,Up=true,MeshBp='stock',CreateImpactEffect=function() end}
function shield:IsUp() return self.Up end
function shield:GetHealth() return self.HP end
function shield:GetMaxHealth() return self.MaxHP end
function shield:GetPosition() return {1,2,3} end
function shield:SetMesh(p) self.VisibleMesh=p end
local owner={Blueprint={BlueprintId='mdeb4401'},MyShield=shield,Trash={Add=function() end}}
shield.Owner=owner
for _,id in ipairs({'mdeb4301','mdab4401','mdrb4401','mdsb4401','ueb4301'}) do
    local h={Blueprint={BlueprintId=id},MyShield=shield}
    V.Attach(h)
    check(not shield.HexVisualsAttached,'Other faction/tier/stock shields retain native visuals')
end
V.Attach(owner)
check(shield.HexVisualsAttached and shield.MeshBp:find('Dome_mesh') and shield.VisibleMesh==shield.MeshBp,'UEF T4 switches current and future dome meshes')
check(shield.HP==800 and shield.MaxHP==1000 and shield.Size==50,'Visual attachment preserves gameplay state')
check(shield.CreateImpactEffect==V.Impact,'Actual native surface hits drive lighting')
check(V.HitColour(1)=='Blue' and V.HitColour(.65)=='Yellow' and V.HitColour(.30)=='Red','Impact health thresholds')
local function hit(vector)
    local co=coroutine.create(V.Impact)
    local ok,wait=coroutine.resume(co,shield,vector);assert(ok,wait)
    return co,wait
end
local co,wait=hit({10,0,0})
local e=entities[#entities]
check(wait==9 and shield.HexLiveImpacts==1 and shield.ModularImpactSerial==1,'Impact lifetime is bounded and interception deduplication remains active')
check(e.Mesh:find('HitBlue_mesh') and e.Direction[1]==1 and e.Position[2]==2,'Hit is positioned at dome center and points at impact')
check(e.Scale>shield.Size and e.Scale<shield.Size*1.01,'Offset overlay avoids depth fighting without changing collision')
check(e.Enemies=='Intel' and e.Neutrals=='Intel','Lighting obeys intel visibility')
assert(coroutine.resume(co))
check(e.Destroyed and shield.HexLiveImpacts==0,'Impact releases its entity and slot')
shield.HP=500;co=hit({0,10,0});check(entities[#entities].Mesh:find('HitYellow_mesh'),'Medium HP hit is yellow');assert(coroutine.resume(co))
shield.HP=100;co=hit({0,0,10});check(entities[#entities].Mesh:find('HitRed_mesh'),'Low HP hit is red');assert(coroutine.resume(co))
local before=#entities
local serial=shield.ModularImpactSerial
shield.HexLiveImpacts=8;hit({10,0,0})
check(#entities==before and shield.ModularImpactSerial==serial+1,'Rapid fire caps visuals while recording the processed impact')
shield.HexLiveImpacts=0;shield.Up=false;hit({10,0,0})
check(#entities==before,'Collapsed dome emits no flashes')
shield.Up=true;hit({0,0,0})
check(#entities==before,'Invalid vectors cannot create corrupt orientation')
shield.Up=false;shield.HexVisualsAttached=nil;shield.VisibleMesh=nil;V.Attach(owner)
check(not shield.VisibleMesh and shield.MeshBp:find('Dome_mesh'),'Attaching while down keeps the dome hidden until recharge')
print('PASS: '..count..' UEF T4 visual lifecycle checks')
