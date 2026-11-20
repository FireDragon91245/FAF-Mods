table.getn=table.getn or function(t) return #t end
local root='src/lua/RepairStationControl/'
local P=assert(loadfile(root..'Policy.lua'))()
local id=0
local function unit(army,cats)
    id=id+1
    local u={Army=army,EntityId=id,Blueprint={CategoriesHash=cats or {},AI={GuardScanRadius=25}},health=100,fraction=1,pos={0,0,0}}
    function u:GetFocusUnit() return self.focus end
    function u:GetGuardedUnit() return self.guard end
    function u:GetFractionComplete() return self.fraction end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return 100 end
    function u:GetPosition() return self.pos end
    function u:IsUnitState(s) return self.state==s end
    function u:IsPaused() return self.paused end
    function u:GetCommandQueue() return self.queue or {} end
    function u:ForkThread(fn) self.thread=fn;return fn end
    return u
end
local worker=unit(1,{ENGINEERSTATION=true})
local own,ally=unit(1),unit(2)
local team={DontHelpTeam=true,DontHelpNukes=false}
local nukes={DontHelpTeam=false,DontHelpNukes=true}
local off={DontHelpTeam=false,DontHelpNukes=false}
assert(P.Managed(worker))
assert(P.Managed(unit(1,{POD=true,ENGINEER=true})))
assert(not P.Managed(unit(1,{POD=true,ENGINEER=true,DUMMYUNIT=true})))
assert(not P.Managed(unit(1,{ENGINEER=true})))
assert(P.Allowed(worker,own,team) and not P.Allowed(worker,ally,team))
assert(P.Allowed(worker,ally,off))
ally.health=80;assert(P.Allowed(worker,ally,team),'Still heal allied damage')
ally.fraction=0.5;assert(not P.Allowed(worker,ally,team),'Do not construct damaged allied projects')
ally.health=100;ally.fraction=1
own.focus=ally;assert(not P.Allowed(worker,own,team));own.focus=nil
for _,cat in ipairs({'NUKE','ANTIMISSILE'}) do
    local silo=unit(1,{SILO=true,[cat]=true})
    assert(not P.Allowed(worker,silo,nukes))
    silo.health=70;assert(not P.Allowed(worker,silo,nukes))
    silo.health=100;silo.fraction=0.5;assert(not P.Allowed(worker,silo,nukes))
    silo.fraction=1;own.guard=silo;assert(not P.Allowed(worker,own,nukes));own.guard=nil
end
own.focus=own;assert(P.Allowed(worker,own,team));own.focus=nil

print('PASS: policy, team isolation and guard/focus chains')
