-- Compatibility shims for the FAF Lua 5.0 APIs used by production code.
table.getn = table.getn or function(t) return #t end
math.mod = math.mod or math.fmod
local originalHuge=math.huge
math.huge=nil
local root = 'src/lua/ModularShields/'
local function load(path)
    local env = setmetatable({}, { __index = _G })
    local result = assert(loadfile(root .. path,'t',env))()
    assert(result == env.Export, 'Module must export for FAF import/doscript: ' .. path)
    return result
end
function import(path) return {Export=load(assert(path:match('/lua/ModularShields/(.*)')))} end
local R = load('Bootstrap.lua').Build(load)
local C,r,c = R.Core,R.Registry,R.Config
local count = 0
local function check(value,message) count=count+1; assert(value,message) end
local function new(tier)
    local s = C.New(tier or 't3',{ Mass=1000,Energy=10000,Upkeep=100,ShieldMaxHP=10000,ShieldSize=40,ShieldRegen=100 })
    s.Rules = C
    return s
end
local function fit(s,id)
    local job,reason = C.RequestInstall(s,id,r,c)
    assert(job,reason and reason.Code)
    job.PaidWork = job.Quote.Work
    assert(not C.Complete(s,job,r,c))
end
local s = new()
check(C.Eligible(s,'power_2',r,c,true).Code=='MissingModule','No skipping levels')
for level=1,4 do fit(s,'power_'..level) end
check(C.Used(s,r)==4,'Each level occupies a slot')
check(C.Eligible(s,'power_5',r,c,true).Code=='NoFreeSlot','T3 cannot fit V')
check(C.RequestRemove(s,'power_1',r).Code=='DependentModule','Keep prerequisites')
local stats = R.Stats.Calculate(s,r,c)
check(stats.ShieldMaxHP==28500 and stats.Upkeep==140,'Staged benefits and quoted upkeep add once per level')
check(R.Stats.Calculate(s,r,c).ShieldMaxHP==28500,'Recalculation is idempotent')
check(not C.RequestRemove(s,'power_4',r),'Remove highest level')
check(C.Used(s,r)==3,'Removal frees exactly one slot')
s = new()
local j = assert(C.RequestInstall(s,'power_1',r,c))
local j2 = assert(C.RequestInstall(s,'power_2',r,c))
check(C.Eligible(s,'power_1',r,c,true).Code=='AlreadyQueued','No duplicate pending IDs')
check(C.Complete(s,j,r,c).Code=='UnpaidWork','Unpaid jobs never commit')
j.PaidWork=j.Quote.Work*.99
check(C.Complete(s,j,r,c).Code=='UnpaidWork','99 percent is not complete')
check(R.Stats.Calculate(s,r,c).ShieldMaxHP==10000,'No benefits before payment')
check(R.Stats.Calculate(s,r,c).Upkeep==100,'No upkeep before completion')
check(not C.RequestCancel(s,j.JobId,r),'Cancel accepted')
check(#s.Queue==0 and j2.State=='Cancelled','Dependent queue invalidated')
check(C.Complete(s,j,r,c).Code=='InvalidJob','Cancelled callback cannot grant module')
s = new('t4')
for level=1,5 do fit(s,'power_'..level) end
check(C.Used(s,r)==5,'T4 level V leaves three slots')
local caps = R.Neighbors.Evaluate(r,{{Id=1,Completed=true,SameArmy=true,EdgeAdjacent=true,Tier='t2',Tags={power_generator=true}}})
check(caps.legendary_power_support,'True edge neighbor supplies support')
caps = R.Neighbors.Evaluate(r,{{Id=1,Completed=false,SameArmy=true,EdgeAdjacent=true,Tags={energy_storage=true}}})
check(not caps.legendary_power_support,'Foundation does not count')
caps = R.Neighbors.Evaluate(r,{{Id=1,Completed=true,SameArmy=false,EdgeAdjacent=true,Tags={energy_storage=true}}})
check(not caps.legendary_power_support,'Allied different army does not count')
caps = R.Neighbors.Evaluate(r,{{Id=1,Completed=true,SameArmy=true,EdgeAdjacent=false,Tags={power_generator=true}}})
check(not caps.legendary_power_support,'Aura distance is not adjacency')
check(not C.Eligible(new(),'atomized',r,c,true),'Special modules available for playtesting')
c.Enabled.atomized=false
check(C.Eligible(new(),'atomized',r,c,true).Code=='DisabledBehavior','Match-wide feature switch is enforced')
c.Enabled.atomized=true
local resolver=load('Services/ThreatResolver.lua')
local threat,hits={},0
local context={Operational=true,Hostile=true,HostId=1,DamageShield=function(d) hits=hits+d end}
local outcome={Damage=100,Kind='test',Suppress=function(t) t.Suppressed=true end}
check(resolver.Resolve(threat,context,outcome),'First dome resolves')
check(not resolver.Resolve(threat,context,outcome) and hits==100 and threat.Suppressed,'Overlap resolves once')
context.Hostile=false
check(not resolver.Resolve({},context,outcome),'No friendly resolution')
local barrier=load('Behaviors/GroundBarrier.lua')
check(barrier.Entry({-20,0,0},{20,0,0},{0,0,0},10)==.25,'Swept high speed crossing')
check(barrier.Entry({0,0,0},{20,0,0},{0,0,0},10)==nil,'Existing interior unit may exit')
check(barrier.Entry({-20,0,10},{20,0,10},{0,0,0},10)==nil,'Tangent does not enter')
-- Extension contract: adding a stat module and a neighbor rule needs no generator changes.
local function extended(path)
    local value=load(path)
    if path=='Definitions/Modules.lua' then
        value[#value+1]={Id='extension',Family='test',Slots=1,MaxInstances=1,Chassis={'t3'},Requires={},
            Effects={{Stat='ShieldMaxHP',Op='Add',Value=500}},CostFraction=.1,Seconds=10,UpkeepFraction=.1,AI={Priority=1},UI={Name='Test'}}
    elseif path=='Definitions/NeighborRules.lua' then
        value[#value+1]={Id='mass_bonus',Priority=1,Relation='EdgeAdjacent',Ownership='SameArmy',Minimum=1,
            AnyProviderTag={'mass_storage'},Effects={{Stat='ShieldRegen',Op='Add',Value=5}}}
    end
    return value
end
local E=load('Bootstrap.lua').Build(extended)
s=new();local job=assert(C.RequestInstall(s,'extension',E.Registry,c));job.PaidWork=job.Quote.Work
assert(not C.Complete(s,job,E.Registry,c))
local _,effects=E.Neighbors.Evaluate(E.Registry,{{Id=2,Completed=true,SameArmy=true,EdgeAdjacent=true,Tags={mass_storage=true}}})
stats=E.Stats.Calculate(s,E.Registry,c,effects)
check(stats.ShieldMaxHP==10500 and stats.ShieldRegen==105,'Declarative module and neighbor extension')
local function badModules(edit)
    local ok=pcall(function() load('Bootstrap.lua').Build(function(path)
        local v=load(path);if path=='Definitions/Modules.lua' then edit(v) end;return v
    end) end)
    check(not ok,'Invalid registry must fail closed')
end
badModules(function(v) v[2].Id=v[1].Id end)
badModules(function(v) v[1].Requires={AllModules={'power_2'}} end)
badModules(function(v) v[1].CostFraction=0/0 end)
badModules(function(v) v[1].CostFraction=1/0 end)
badModules(function(v) v[1].CostFraction=-1/0 end)
badModules(function(v) v[1].Seconds=0 end)
badModules(function(v) v[1].Behavior='unknown' end)
-- Configurable combinations require genuinely distinct physical neighbors.
local rules={Providers={generator={},storage={}},Rules={{Id='combo',Priority=0,Minimum=1,
    AllProviderTags={'generator','storage'},RequireDistinctProviders=true,
    Effects={{Capability='combo',Value=true}}}}}
local dual={Id=1,Completed=true,SameArmy=true,EdgeAdjacent=true,Tags={generator=true,storage=true}}
caps=R.Neighbors.Evaluate(rules,{dual})
check(not caps.combo,'One dual-tagged provider cannot satisfy distinct-provider combination')
local second={Id=2,Completed=true,SameArmy=true,EdgeAdjacent=true,Tags={storage=true}}
caps=R.Neighbors.Evaluate(rules,{dual,second})
check(caps.combo,'Separate providers satisfy combination')
rules.Rules={{Id='discount',Priority=0,Minimum=1,AnyProviderTag={'storage'},PerProvider=true,
    MaximumCount=2,Diminishing=.5,EffectMinimum=-.2,StackingGroup='discount',Stacking='Sum',
    Effects={{Stat='EnergyMultiplier',Op='Add',Value=-.1}}}}
local _,mods=R.Neighbors.Evaluate(rules,{dual,second,second})
check(math.abs(mods[1].Value+.15)<1e-8,'Distinct count, provider cap and diminishing effects')
s=new();stats=R.Stats.Calculate(s,r,c,mods)
check(stats.Upkeep==85 and stats.PreNeighborUpkeep==100,'Custom discount applied once after module upkeep')
stats=R.Stats.Calculate(s,r,c,{{Stat='RepairMassMultiplier',Op='Add',Value=-10}})
check(stats.RepairMassMultiplier==c.Floors.RepairMassMultiplier,'Repair cost has positive efficiency floor')
print('PASS: '..count..' core contract checks')
math.huge=originalHuge
