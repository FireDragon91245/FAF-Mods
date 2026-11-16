-- Lua 5.0 tracks array lengths changed by table.remove/insert. Modern Lua's
-- length operator alone misses queue reuse failures in the game runtime.
local lengths=setmetatable({}, {__mode='k'})
local insert,remove=table.insert,table.remove
table.getn=function(t) return lengths[t] or #t end
table.insert=function(t,v)
    local n=table.getn(t);insert(t,n+1,v);lengths[t]=n+1
end
table.remove=function(t,index)
    local n=table.getn(t);local value=remove(t,index);lengths[t]=n-1;return value
end
math.mod=math.mod or math.fmod
local function load(path)
    local env=setmetatable({}, {__index=_G})
    return assert(loadfile('src/lua/ModularShields/'..path,'t',env))()
end
local R=load('Bootstrap.lua').Build(load)
local s=R.Core.New('t3',{Mass=1000,Energy=10000,Upkeep=100})
local count=0
local function check(v,msg) count=count+1;assert(v,msg) end
local first=assert(R.Core.RequestInstall(s,'power_1',R.Registry,R.Config))
first.PaidWork=first.Quote.Work
assert(not R.Core.Complete(s,first,R.Registry,R.Config))
check(table.getn(s.Queue)==0,'Completed queue reports empty')
local a=assert(R.Core.RequestInstall(s,'range_1',R.Registry,R.Config))
local b=assert(R.Core.RequestInstall(s,'range_2',R.Registry,R.Config))
check(table.getn(s.Queue)==2 and s.Queue[1]==a and s.Queue[2]==b,'Reusing a completed queue preserves length and both jobs')
assert(not R.Core.RequestCancel(s,a.JobId,R.Registry))
check(table.getn(s.Queue)==0,'Cancel also removes queued dependents')
local c=assert(R.Core.RequestInstall(s,'regen_1',R.Registry,R.Config))
local d=assert(R.Core.RequestInstall(s,'regen_2',R.Registry,R.Config))
check(table.getn(s.Queue)==2 and s.Queue[1]==c and s.Queue[2]==d,'Reusing a cancelled queue preserves both jobs')
c.PaidWork=c.Quote.Work;assert(not R.Core.Complete(s,c,R.Registry,R.Config))
local e=assert(R.Core.RequestInstall(s,'range_1',R.Registry,R.Config))
check(table.getn(s.Queue)==2 and s.Queue[1]==d and s.Queue[2]==e,'Appending after head completion preserves the remaining job')
print('PASS: '..count..' Lua 5.0 queue reuse checks')
