table.getn=table.getn or function(t) local n=0;while t[n+1]~=nil do n=n+1 end;return n end
-- Real bus/transport regressions: intentions never modify authoritative mirrors.
local E=assert(loadfile('src/lua/FireDragon/InformationExchange.lua'))()
local T=assert(loadfile('src/lua/FireDragon/ExchangeTransport.lua'))()
local B=assert(loadfile('src/lua/FireDragon/Bindings.lua'))()
local now,checks=0,0
local function check(v,m) checks=checks+1;assert(v,m) end
local function reason(model,path)
    local status=model:Status(path)
    for i=table.getn(status.outcomes),1,-1 do
        if status.outcomes[i].Reason then return status.outcomes[i].Reason end
    end
end
local sim,ui=E.New{clock=function() return now end},E.New{clock=function() return now end}
local commands,packets={},{}
local actor={army=1,player=0,actor=true,cheats=true}
local server=T.Attach(sim,{realm='Sim',clock=function() return now end,send=function(p) table.insert(packets,p) end})
local client=T.Attach(ui,{realm='UI',session='binding-test',clock=function() return now end,send=function(p) table.insert(commands,p) end})
local owner=sim.PublishConfig('settings',{a=1,b=2,nested={x=1,y=2}},'ReadWrite',function() end,
    function(v) return v.a<=10 end,{scope='Sim',authorize='Cheats'})
local function process()
    local batch=commands;commands={}
    for _,p in ipairs(batch) do server.Receive(p,actor) end
    server.Flush();local result=packets;packets={};return result
end
local function receive(batch,part)
    for _,p in ipairs(batch) do
        client.Receive{protocol=1,configs=part~='reply' and p.configs or {},records=part~='state' and p.records or {},
            states=part~='reply' and p.states or {}}
    end
    B.Step()
end
receive(process())
local j=B.Config(ui,'settings')
local observed={}
local c={SetValue=function(self,v) self.Value=v end}
local d={SetValue=function(self,v) self.Value=v end}
B.Attach(c,{journal=j,path={'a'}});B.Attach(d,{journal=j,path={'a'}})
c.Binding:Submit(3)
check(c.Value==3 and d.Value==3 and ui.Get('settings').a==1,'multiple observers project immediately over untouched mirror')
B.Step();check(c.Value==3,'stale refresh cannot revert intention')
local batch=process();receive(batch,'reply')
check(c.Value==3 and j.Operations[1]~=nil,'reply before snapshot retains projection')
receive(batch,'state');check(c.Value==3 and j.Operations[1]==nil,'revision fence settles accepted edit')
c.Binding:Submit(4);c.Binding:Submit(5)
local rapid=process();receive(rapid,'state')
check(c.Value==5 and j.Operations[1]~=nil,'snapshot before reply retains newer intent')
receive(rapid,'reply');check(c.Value==5 and j.Operations[1]==nil,'snapshot-first operation settles after reply')
j:Submit{Path={'a'},Value=99};j:Submit{Path={'b'},Value=8}
receive(process());check(j:Get().a==5 and j:Get().b==8 and reason(j,{'a'})=='invalid_value','rejected path leaves unrelated newer path intact')
j:Submit{Path={'nested'},Value={x=8,y=9}};j:Submit{Path={'nested','x'},Value=10}
check(j:Get().nested.x==10 and j:Get().nested.y==9 and ui.Get('settings').nested.x==1,'overlapping parent and child use ordered copies')
receive(process());check(j:Get().nested.x==10,'nested authoritative reconciliation')
actor.cheats=false;c.Binding:Submit(6);c.Binding:Submit(7)
receive(process());check(c.Value==5 and reason(j,{'a'})=='denied','denial rolls back to current authority')
actor.cheats=true
c.Binding:Submit(8);local late=process();now=6;B.Step()
check(c.Value==5 and j.History[table.getn(j.History)].Status=='unknown','timeout removes projection and reports unknown outcome')
receive(late);check(c.Value==8,'late authority applies even after ticket timeout')
local observerCount=0;for _ in pairs(j.Observers) do observerCount=observerCount+1 end
c:OnDestroy();d.Binding:Submit(9)
check(c.Value==8 and d.Value==9,'destroyed control detaches while remaining observer works')
local after=0;for _ in pairs(j.Observers) do after=after+1 end
check(after==observerCount-1,'destroy removes observer')
receive(process())
local reopened={SetValue=function(self,v) self.Value=v end};B.Attach(reopened,{journal=j,path={'a'}})
check(reopened.Value==9,'reopened view reads existing projection')
B.Attach(reopened,{journal=j,path={'a'},optimistic=false});reopened.Binding:Submit(10)
check(reopened.Value==9,'optimistic opt-out waits for authoritative snapshot')
receive(process());check(reopened.Value==10,'opt-out accepts authoritative result')
local localJournal=B.Local{flag=false}
localJournal:Submit{Path={'flag'},Value=true};check(localJournal:Get().flag,'local binding needs no transport')
local localBus=E.New{clock=function() return now end};localBus.PublishConfig('local',{v=1},'ReadWrite',function() end)
local localConfig=B.Config(localBus,'local');localConfig:Submit{Path={'v'},Value=2}
check(localConfig:Get().v==2 and localBus.Get('local').v==2,'UI to UI local config works')
-- Request completion is not application success; confirmation is retained revision.
sim.Expose('action',{requests=true,authorize='Army'})
sim.UI.PublishState('state',1,{enabled=false},{army=1});receive(process())
sim.Respond('action',function(data)
    if data.reject then return {Accepted=false,Reason='DomainRejected'} end
    sim.UI.PublishState('state',1,{enabled=data.Value},{army=1});return {Accepted=true}
end)
local action=B.State(ui,'state',1,{topic='action',project=function(state,ops)
    for _,op in ipairs(ops) do state.enabled=op.Value end;return state
end,payload=function(op) return {Value=op.Value,reject=op.reject} end})
action:Submit{Value=true};check(action:Get().enabled and not ui.GetState('state',1).enabled,'request state projection is isolated')
local request=process();receive(request,'reply');check(action.Operations[1]~=nil,'accepted action waits for retained snapshot')
receive(request,'state');check(action.Operations[1]==nil and action:Get().enabled,'request revision confirmation settles')
action:Submit{Value=false,reject=true};receive(process())
check(action:Get().enabled and reason(action)=='DomainRejected','Accepted=false rejects completed request')
action:Submit{Value=false};sim.UI.PublishState('state',1,nil,{army=1});server.Flush();receive(packets,'state');packets={}
check(action:Get()==nil,'target removal clears projection')
-- Older reply loss cannot cover a newer normalized result.
commands={}
local newOwner=sim.PublishConfig('normal',{v=1},'ReadWrite',function() end,nil,{scope='Sim',authorize='Army'})
receive(process())
local norm=B.Config(ui,'normal')
norm:Submit{Path={'v'},Value=4};norm:Submit{Path={'v'},Value=7}
local normalized=process();newOwner:Set{v=6};server.Flush()
for _,p in ipairs(packets) do table.insert(normalized,p) end;packets={}
-- Lose the older receipt but receive the newest fence and normalized snapshot.
for _,p in ipairs(normalized) do
    local records={}
    for _,record in ipairs(p.records or {}) do
        if record.id==norm.Operations[2].Ticket.ID then table.insert(records,record) end
    end
    client.Receive{protocol=1,configs=p.configs,records=records}
end
B.Step();check(norm:Get().v==6,'newer settlement suppresses older projection and accepts normalization')
-- A target incarnation change invalidates local intent even when IDs are reused.
sim.UI.PublishState('state',1,{enabled=true},{army=1});receive(process())
action:Submit{Value=false};commands={}
sim.UI.PublishState('state',1,nil,{army=1});sim.UI.PublishState('state',1,{enabled=true},{army=1})
receive(process());check(action:Get().enabled and action.Operations[1]==nil,'same-flush removal and recreation cannot inherit old intention')
local standalone=E.New{clock=function() return now end}
standalone.PublishState('multi',1,{v=0})
standalone.Respond('many',function() return {Accepted=true} end)
standalone.Respond('many',function() return {Accepted=false,Reason='SecondDenied'} end)
local multi=B.State(standalone,'multi',1,{topic='many',replyMode='All',
    payload=function() return {} end,
    project=function(state,ops) for _,op in ipairs(ops) do state.v=1 end;return state end,
    settle=function(replies)
        check(table.getn(replies)==2,'explicit policy receives every reply')
        for _,r in ipairs(replies) do if r.value.Accepted==false then return false,r.value.Reason end end
        return true
    end,
    confirm=function() return true end})
multi:Submit{};check(reason(multi)=='SecondDenied' and multi:Get().v==0,'multiple replies use declared policy instead of first acceptance')
local alive=B.Local{v=0};local ownerControl={}
B.Own(ownerControl,alive)
for i=1,601 do B.Step() end
check(not alive.Closed,'owned view keeps settled journal alive')
ownerControl:OnDestroy()
for i=1,601 do B.Step() end
check(alive.Closed,'unobserved settled journal retires and releases subscriptions')
-- Managed definitions own journals across target changes, view disposal and retirement.
commands={}
sim.Expose('managed-action',{requests=true,authorize='Army'})
for key=1,2 do sim.UI.PublishState('managed-state',key,{x=false,y=false},{army=1}) end
receive(process())
sim.Respond('managed-action',function(data)
    if data.Reject then return {Accepted=false,Reason='Unavailable'} end
    local state={x=false,y=false}
    state[data.Field]=data.Value
    sim.UI.PublishState('managed-state',data.Target,state,{army=1});return {Accepted=true}
end)
local source=B.DefineState(ui,{
    stateTopic='managed-state',topic='managed-action',ordered=true,initialState={Problems={}},
    payload=function(op,target) return {Target=target,Field=op.Field,Value=op.Value,Reject=op.Reject} end,
    project=function(state,ops)
        for _,op in ipairs(ops) do
            check(op.Ticket==nil and op.Results==nil,'project receives plain operation metadata')
            state[op.Field]=op.Value
        end
        return state
    end,
    reconcile=function(data,outcome,authoritative,projected)
        if not outcome.Intent then return data end
        local field=outcome.Intent.Field
        local previous=data.Problems[field]
        if not previous or previous.ID<=outcome.ID then
            data.Problems[field]=outcome.Reason and outcome.Status~='dismissed' and outcome or nil
        end
        return data
    end,
})
local target=1
local switched={SetCheck=function(self,v) self.Value=v end}
B.Attach(switched,{source=source,target=function() return target end,path={'x'},
    intent=function(value) return {Field='x',Value=value} end})
switched.Binding:Submit(true)
check(switched.Value and source:For(1):Get().x,'managed source projects immediately')
target=2;B.Step()
check(not switched.Value and not source:For(2):Get().x,'framework retargets control without leaking old intentions')
target=nil;B.Step()
check(not switched.Value and switched.BindingStatus.available==false,'empty selection detaches target and clears its display')
target=2;B.Step()
check(not switched.Value and switched.BindingStatus.available,'binding recovers after an empty target')
local otherView={SetCheck=function(self,v) self.Value=v end}
B.Attach(otherView,{source=source,target=1,path={'x'},intent=function(value) return {Field='x',Value=value} end})
check(otherView.Value,'another view acquires existing pending projection without a mod cache')
receive(process());check(otherView.Value and not switched.Value,'late response stays with its original target')
local managed=source:For(1)
check(managed==source:For(1),'definition returns a reusable target handle')
otherView:OnDestroy()
managed:Submit{Field='x',Value=false,Reject=true}
managed:Submit{Field='y',Value=true}
receive(process())
check(managed:Status().state.Problems.x.Reason=='Unavailable' and not managed:Status().state.Problems.y,
    'mod-owned outcome state preserves failure across unrelated success')
local failed=managed:Status().state.Problems.x.ID
managed:Dismiss(failed)
check(not managed:Status().state.Problems.x,'explicit dismissal is reconciled by the domain handler')
managed:Submit{Field='x',Value=true};otherView={}
source:Bind(otherView,1)
now=now+6
for i=1,601 do B.Step() end
check(managed:Status().state.Problems.x.Status=='unknown','timeout is structured mod state and is never retried')
otherView:OnDestroy();switched:OnDestroy()
for i=1,601 do B.Step() end
check(managed:Get()~=nil,'held model handle reacquires a retired journal automatically')
check(managed:Status().pending==0 and not next(managed:Status().state.Problems),'retirement recreates clean outcome state')
local direct={SetValue=function(self,v) self.Value=v end}
B.Attach(direct,{bus=localBus,config='local',path={'v'}})
direct.Binding:Submit(3)
check(direct.Value==3 and localBus.Get('local').v==3 and B.Status{bus=localBus,config='local'}.pending==0,'direct configuration binding and status resolve framework journals')
-- Programming failures propagate. Only explicit refusal outcomes become user state.
managed:Submit{Field='x',Value=false,Reject=true};receive(process())
check(managed:Status().state.Problems.x~=nil,'domain failure is stored before target replacement')
sim.UI.PublishState('managed-state',1,nil,{army=1});receive(process())
sim.UI.PublishState('managed-state',1,{x=true,y=false},{army=1});receive(process())
check(not next(managed:Status().state.Problems),'new target incarnation cannot inherit old user-facing failure state')
local broken=B.Journal{read=function() return {} end,send=function() error('payload bug') end}
local ok,message=pcall(function() broken:Submit{} end)
check(not ok and string.find(message,'payload bug',1,true) and table.getn(broken:Status().outcomes)==0,
    'send-hook bug is visible and is not converted into user rejection')
broken:Close()
local badProjection=B.Journal{read=function() return {} end,send=function() end,project=function() error('projection bug') end}
ok,message=pcall(function() badProjection:Get() end)
check(not ok and string.find(message,'projection bug',1,true),'projection-hook bugs propagate')
badProjection:Close()
local badReconcile=B.Journal{read=function() return {} end,send=function() end,reconcile=function() error('reconciliation bug') end}
ok,message=pcall(function() badReconcile:Submit{} end)
check(not ok and string.find(message,'reconciliation bug',1,true),'reconciliation-hook bugs propagate')
badReconcile:Close()
local brokenValidator=localBus.PublishConfig('validator-bug',{v=0},'ReadWrite',function() end,
    function(value) if value.v==0 then return true end;error('validator bug') end)
local configBug=B.Config(localBus,'validator-bug')
ok,message=pcall(function() configBug:Submit{Path={'v'},Value=1} end)
check(not ok and string.find(message,'validator bug',1,true),'local validator bugs stay visible')
configBug:Close()
print('PASS: '..checks..' binding transaction regressions')
