local checks=0
local function check(v,msg) checks=checks+1;assert(v,msg) end
local Base={OnCreate=function() end,GetBuildCosts=function() return 5,100,20 end,
    UpdateConsumptionValues=function(u) u:SetConsumptionActive(false) end,
    StartBuildingEffects=function() error('native effects leaked') end,
    StopBeingBuiltEffects=function() error('native mesh reset leaked') end}
function import() return {Unit=Base} end
function ClassUnit(base) return function(t) return setmetatable(t,{__index=base}) end end
local env=setmetatable({}, {__index=_G});assert(loadfile('src/units/mds0001/mds0001_script.lua','t',env))()
local h=setmetatable({}, {__index=env.TypeClass})
function h:SetCollisionShape(shape) self.Collision=shape end
for _,name in ipairs({'SetUnSelectable','SetDoNotTarget','SetCanTakeDamage','SetCanBeKilled','SetReclaimable','SetCapturable'}) do
    h[name]=function(u,value) u[name..'Value']=value end
end
function h:HideBone(bone,children) self.Hidden=bone==0 and children end
function h:SetConsumptionActive(value) self.Consumer=value end
h:OnCreate()
check(h.Hidden and h.Collision=='None','model hidden and collisions disabled at creation')
check(h.SetUnSelectableValue and h.SetDoNotTargetValue,'native selection and targeting disabled')
check(not h.SetCanTakeDamageValue and not h.SetCanBeKilledValue and not h.SetReclaimableValue and not h.SetCapturableValue,'worker cannot be damaged, killed, reclaimed or captured')
h:StartBuildingEffects();h:StopBuildingEffects();h:CreateBuildEffects();h:StopBeingBuiltEffects();h:CreateIdleEffects();h:CreateMovementEffects();h:CreateLayerChangeEffects()
check(true,'construction completion cannot restore the model or start effects')
local t,e,m=h:GetBuildCosts({});check(t==5 and e==100 and m==20,'normal native construction price preserved')
h.ModuleFree=true;t,e,m=h:GetBuildCosts({});check(t==5 and e==0 and m==0,'Ignore Resources retains timing and removes both costs')
h.ActiveConsumption=true;h:UpdateConsumptionValues();check(h.Consumer,'zero-demand free construction keeps native work consumer active')
h.ActiveConsumption=false;h:UpdateConsumptionValues();check(not h.Consumer,'idle helpers do not keep a free consumer active')
h.ModuleFree=false;h.ActiveConsumption=true;h:UpdateConsumptionValues();check(not h.Consumer,'normal mode preserves base consumer decisions')
h.ModuleWorkKind='build';h.GetConsumptionPerSecondMass=function() return 0 end;h.GetConsumptionPerSecondEnergy=function() return 0 end
h:UpdateConsumptionValues();check(h.Consumer,'native zero-price construction can work without a resource request')
print('PASS: '..checks..' invisible helper and resource-cheat contracts')
