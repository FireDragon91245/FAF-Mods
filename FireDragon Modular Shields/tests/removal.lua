table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
local root='src/lua/ModularShields/'
local function load(path)
    local env=setmetatable({}, {__index=_G});return assert(loadfile(root..path,'t',env))()
end
local R=load('Bootstrap.lua').Build(load)
local C,r,c=R.Core,R.Registry,R.Config
local count=0
local function check(value,message) count=count+1;assert(value,message) end
local function new()
    local s=C.New('t3',{Mass=1000,Energy=10000,Upkeep=100,ShieldMaxHP=10000,ShieldSize=40,ShieldRegen=100});s.Rules=C;return s
end
local function fit(s,id)
    local job=assert(C.RequestInstall(s,id,r,c));job.PaidWork=job.Quote.Work;assert(not C.Complete(s,job,r,c))
end
local s=new();fit(s,'power_1');fit(s,'regen_1');fit(s,'range_1');fit(s,'repair_1')
local job=assert(C.RequestUninstall(s,'power_1',r,c))
check(job.Kind=='Remove' and job.Quote.Seconds==5 and job.Quote.Mass==0 and job.Quote.Energy==0,'Removal is a timed five-second job without a resource price')
check(C.Used(s,r)==4 and R.Stats.Calculate(s,r,c).ShieldMaxHP==11000,'Queued removal retains its slot and benefit')
check(C.Eligible(s,'ballistic',r,c,true).Code=='NoFreeSlot','Removal does not free slots early')
check(select(2,C.RequestUninstall(s,'power_1',r,c)).Code=='AlreadyQueued','Duplicate removals are rejected')
job.PaidWork=job.Quote.Work/2
check(C.Complete(s,job,r,c).Code=='UnpaidWork','Half-finished removal cannot commit')
assert(not C.RequestCancel(s,job.JobId,r))
check(s.Installed.power_1 and C.Used(s,r)==4,'Cancelling removal keeps the installed module and slot')
job=assert(C.RequestUninstall(s,'power_1',r,c));job.PaidWork=job.Quote.Work
assert(not C.Complete(s,job,r,c))
check(not s.Installed.power_1 and C.Used(s,r)==3 and R.Stats.Calculate(s,r,c).ShieldMaxHP==10000,'Completed removal commits stat and slot changes together')
s=new();fit(s,'power_1');fit(s,'power_2')
check(select(2,C.RequestUninstall(s,'power_1',r,c)).Code=='DependentModule','Installed dependents block removing their prerequisite')
s=new();fit(s,'power_1');assert(C.RequestInstall(s,'power_2',r,c))
check(select(2,C.RequestUninstall(s,'power_1',r,c)).Code=='DependentModule','Queued dependents also block prerequisite removal')
s=new();fit(s,'power_1');assert(C.RequestUninstall(s,'power_1',r,c))
check(C.Eligible(s,'power_2',r,c,true).Code=='MissingModule','A module scheduled for removal cannot unlock a new dependent')
-- Exercise the actual job service, including pause/resume, without economy events.
local Assist={Rate=function() return c.InstallRate end,Stop=function() end,UpdateProgress=function() end}
function import() return {Export=Assist} end
local Jobs=load('Services/InstallJobs.lua')
function GetGameTick() return 100 end
function WaitTicks() coroutine.yield() end
function KillThread(co) assert(coroutine.close(co)) end
function CreateEconomyEvent() error('Removal must not create a resource event') end
s=new();fit(s,'power_1');job=assert(C.RequestUninstall(s,'power_1',r,c))
local h={Loadout=s}
function h:ForkThread(fn) local co=coroutine.create(fn);assert(coroutine.resume(co));return co end
function h:SetWorkProgress(progress) self.Progress=progress end
function h:PublishModules() end
function h:ReconcileModules() end
Jobs.Start(h,R);local co=h.ModuleThread
for n=1,20 do assert(coroutine.resume(co)) end
check(job.PaidWork>0 and job.PaidWork<job.Quote.Work and s.Installed.power_1,'Removal advances over simulation ticks and leaves effects until completion')
local paid=job.PaidWork;Jobs.Stop(h)
check(job.PaidWork==paid and s.Installed.power_1,'Stopping removal preserves partial work and equipment')
Jobs.Start(h,R);co=h.ModuleThread
while coroutine.status(co)~='dead' do assert(coroutine.resume(co)) end
check(not s.Installed.power_1 and h.Progress==0,'Resumed removal completes and clears native progress')
print('PASS: '..count..' timed-removal checks')
