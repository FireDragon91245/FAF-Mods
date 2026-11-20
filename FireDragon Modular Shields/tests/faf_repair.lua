-- Run with the float-number Lua 5.0 host as well as modern Lua.
-- FAF defines ^ through __pow as bitwise XOR.
function __pow(a,b)
    local result,bit=0,1
    while a>0 or b>0 do
        if math.mod(a,2)~=math.mod(b,2) then result=result+bit end
        a=math.floor(a/2);b=math.floor(b/2);bit=bit*2
    end
    return result
end
math.mod=math.mod or math.fmod
if setfenv then assert(28^2==30,'test must reproduce FAF XOR semantics') end
function IsDestroyed(u) return not u or u.Destroyed end
function WaitTicks(n) coroutine.yield(n) end
categories={ALLUNITS=1}
local env=setmetatable({}, {__index=_G})
local chunk
if setfenv then chunk=assert(loadfile('src/lua/ModularShields/Behaviors/Repair.lua'));setfenv(chunk,env)
else chunk=assert(loadfile('src/lua/ModularShields/Behaviors/Repair.lua','t',env)) end
chunk()
local Repair=env.Export
local target={EntityId=2,Army=1,Position={10,4.75,0},Blueprint={Economy={BuildTime=500,BuildCostMass=100}}}
function target:GetFractionComplete() return .2 end
function target:GetMaxHealth() return 100 end
function target:GetHealth() return 20 end
function target:GetPosition() return self.Position end
local host={Army=1,ModuleStats={RepairBudget=30,ShieldSize=56},
    MyShield={IsUp=function() return true end,GetPosition=function() return {0,0,0} end}}
function host:GetAIBrain() return {GetUnitsAroundPoint=function() return {target} end} end
local worker
function CreateUnitHPR()
    worker={}
    local noop=function() end
    worker.HideBone=noop;worker.SetCollisionShape=noop;worker.SetCanTakeDamage=noop
    worker.SetCanBeKilled=noop;worker.SetReclaimable=noop;worker.SetCapturable=noop
    function worker:Destroy() self.Destroyed=true end
    function worker:SetBuildRate(rate) self.Rate=rate end
    function worker:UpdateConsumptionValues() end
    function worker:GetCommandQueue() return self.Queue or {} end
    function worker:ForkThread(fn,host,target,R)
        self.Thread=coroutine.create(function() fn(self,host,target,R) end)
        assert(coroutine.resume(self.Thread))
    end
    return worker
end
function IssueRepair(units,u) assert(not units[1].Destroyed);units[1].Target=u;units[1].Queue={1} end
function IssueClearCommands(units) units[1].Queue={} end
Repair.Tick(host,{Config={RepairTargetLimit=24,Debug={IgnoreResources=true}}})
assert(worker and not worker.Destroyed and worker.Rate==150 and worker.Target==target,
    'native helper must survive 11-unit distance within a 28-unit radius')
assert(coroutine.resume(worker.Thread));assert(not worker.Destroyed,'helper must continue across ticks')
target.Position={30,4.75,0}
assert(coroutine.resume(worker.Thread));assert(worker.Destroyed,'helper must stop when target leaves the radius')
print('PASS: FAF float Lua/XOR construction range and worker lifetime regression')
