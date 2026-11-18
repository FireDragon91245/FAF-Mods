-- Runs unchanged on stock Lua and the vendored float-number FAF VM.
local Exchange=assert(loadfile('src/lua/FireDragon/InformationExchange.lua'))()
local Transport=assert(loadfile('src/lua/FireDragon/ExchangeTransport.lua'))()
local time,checks=0,0
local function check(v,message) checks=checks+1;assert(v,message) end
local function rejects(fn) check(not pcall(fn),'expected rejection') end
local commands,packets={},{}
local callbackErrors={}
local sim=Exchange.New({clock=function() return time end,onError=function(err) table.insert(callbackErrors,err) end})
local server=Transport.Attach(sim,{realm='Sim',clock=function() return time end,send=function(packet) table.insert(packets,packet) end})
local function client(session,source)
    local bus=Exchange.New({clock=function() return time end})
    local transport=Transport.Attach(bus,{realm='UI',session=session,clock=function() return time end,
        send=function(packet) table.insert(commands,{packet=packet,source=source}) end})
    return bus,transport
end
local actor={player=0,army=1,actor=true,cheats=true}
local ui,receiver=client('client1',actor)
local other,otherReceiver=client('client2',{player=1,army=2,actor=true,cheats=true})
local function deliver()
    local batch=commands;commands={}
    for _,command in ipairs(batch) do server.Receive(command.packet,command.source) end
end
local function sync(full)
    server.Flush(full)
    local batch=packets;packets={}
    for _,packet in ipairs(batch) do receiver.Receive(packet);otherReceiver.Receive(packet) end
    return batch
end
local changes=0
local config=sim.PublishConfig('settings',{nested={enabled=false},count=1},'ReadWrite',function(_,_,change)
    changes=changes+1
    if change.source then check(change.source.realm=='UI' and change.source.army==1,'config source is engine-owned') end
end,function(v) return type(v.count)=='number' and v.count>=1 and v.count<=10 end,{scope='Sim',authorize='Cheats'})
sim.PublishConfig('schema',{label='settings'},'ReadOnly',nil,nil,{scope='Sim'})
sim.PublishConfig('private',123)
sync()
check(ui.HasConfig('settings') and other.HasConfig('schema') and not ui.HasConfig('private'),'Sim declarations auto-discover in both UIs')
local ticket=ui.SetPath('settings',{'nested','enabled'},true)
check(ticket:Status()=='pending' and not ui.Get('settings').nested.enabled,'UI write waits for authoritative confirmation')
deliver()
check(sim.Get('settings').nested.enabled and changes==1,'accepted update invokes publisher once in Sim')
sync()
check(ticket:Status()=='complete' and ui.Get('settings').nested.enabled and other.Get('settings').nested.enabled,'config acknowledgement and broadcast mirror')
check(changes==1 and ui.ConfigStatus('settings').status=='complete','mirroring never echoes a write')
ui.View('settings').count=4
deliver();sync();check(sim.Get('settings').count==4,'nested proxy assignments use remote transport')
ticket=ui.SetPath('settings',{'count'},99);deliver();sync()
check(ticket:Status()=='failed' and ui.ConfigStatus('settings').error=='invalid_value' and ui.Get('settings').count==4,'validator rejection preserves both copies')
rejects(function() ui.Set('schema',{}) end)
actor.cheats=false
ticket=ui.SetPath('settings',{'count'},5);deliver();sync()
check(ticket:Status()=='failed' and ui.ConfigStatus('settings').denied and sim.Get('settings').count==4,'generic cheat policy rejects remote writes')
actor.cheats=true
local late,lateReceiver=client('late',{player=2,army=3,actor=true,cheats=true})
server.Flush(true)
for _,packet in ipairs(packets) do lateReceiver.Receive(packet) end;packets={}
check(late.Get('settings').count==4,'late UI discovers the current full snapshot')
-- Out-of-order config packets cannot restore an older value.
config:Set({nested={enabled=false},count=6});local old=sync()
config:Set({nested={enabled=false},count=7});sync()
for _,packet in ipairs(old) do receiver.Receive(packet) end
check(ui.Get('settings').count==7,'stale snapshot ignored')
config:Close();sync();check(not ui.HasConfig('settings'),'unpublish propagates a tombstone')
config=sim.PublishConfig('settings',{count=1},'ReadOnly',nil,nil,{scope='Sim'})
sync();check(ui.Get('settings').count==1,'republishing a key propagates a new generation')

sim.Expose('broadcast',{notifications=true,authorize='Army'})
local readers={}
for i=1,4 do readers[i]=sim.Listen('broadcast',4) end
ticket=ui.Sim.Publish('broadcast',{amount=3,source={army=99}})
local originalCommand=commands[1]
deliver();sync()
check(ticket:Status()=='complete' and ticket:Poll().value.delivered==4,'UI notification reaches four Sim readers')
for _,reader in ipairs(readers) do
    local message=reader:Poll()
    check(message.payload.amount==3 and message.source.army==1,'notification payload/source preserved separately')
end
check(not server.Receive(originalCommand.packet,originalCommand.source),'duplicate command rejected across ticks')
check(not server.Receive(originalCommand.packet,{player=1,army=2,actor=true,cheats=true}),
    'a different player cannot impersonate a UI session or inject its replies')
sim.ConfigureTopic('work',{delivery='Consume',capacity=2})
sim.Expose('work',{notifications=true,authorize='Army'})
local workerA,workerB=sim.Listen('work'),sim.Listen('work')
ui.Sim.Publish('work',{amount=2});deliver();sync()
local peek=workerA:Peek()
check(peek and workerB:Poll(peek.messageID).payload.amount==2 and workerA:Poll()==nil,'remote notifications preserve shared peek/consume semantics')
local uiMessages=ui.Listen('display',2)
sim.UI.Publish('display',{value=42});sync()
check(uiMessages:Poll().payload.value==42,'Sim notifications arrive through ordinary UI listeners')
ticket=ui.Sim.Publish('unknown',{});deliver();sync()
check(ticket:Status()=='failed' and ticket:Poll().error=='denied','unexposed topics denied')
sim.Expose('guarded',{notifications=true,authorize=function(source) return source.army==2 end})
ticket=ui.Sim.Publish('guarded',{});deliver();sync();check(ticket:Status()=='failed','custom authorizer receives trusted identity')

sim.Expose('ask',{requests=true,authorize='Army'})
local replyA=sim.Respond('ask',function(payload,_,context)
    check(context.source.army==1,'request context includes command source')
    return {amount=payload.amount}
end)
local replyB=sim.Respond('ask',function() return false end)
ticket=ui.Sim.Request('ask',{amount=3},{replyMode='All'})
deliver();sync()
check(ticket:Status()=='complete' and ticket:Poll().value.amount==3 and ticket:Poll().value==false and ticket:Poll()==nil,'All collects remote replies')
ticket=ui.Sim.Request('ask',{amount=4},{replyMode='First'})
deliver();sync()
check(ticket:Status()=='complete' and ticket:Poll().value.amount==4 and ticket:Poll()==nil,'First accepts just one remote reply')
replyA:Close();replyB:Close()
local inbox=sim.ListenRequests('ask',2)
ticket=ui.Sim.Request('ask',{amount=5},{replyMode='First'})
deliver();sync();check(ticket:Status()=='pending','polling Sim handler does not block UI')
local message=inbox:Peek()
check(message.source.army==1 and message.TryClaim(),'Sim claims request locally before work')
inbox:Poll(message.messageID).Reply(nil);sync()
check(ticket:Status()=='complete' and ticket:Poll()~=nil,'deferred explicit nil reply survives wire envelope')
ticket=ui.Sim.Request('ask',1);deliver()
message=inbox:Poll();check(ticket:Cancel(),'UI cancels remote ticket');deliver();sync()
check(not message.Reply(2) and ticket:Status()=='cancelled','cancel invalidates the Sim responder')
ticket=ui.Sim.Request('ask',1,{timeout=1});deliver();message=inbox:Poll()
time=2;server.Flush();receiver.Tick()
check(ticket:Status()=='timeout' and not message.TryClaim(),'both runtimes enforce expiration')
packets={};deliver()
local a=ui.Sim.Request('ask',1)
local b=other.Sim.Request('ask',2)
deliver()
local first,second=inbox:Poll(),inbox:Poll()
first.Reply('a');second.Reply('b');sync()
check(a:Poll().value=='a' and b:Poll().value=='b','replies are correlated to the originating UI session')
sim.Expose('progress',{requests=true,authorize='Army'})
local progressA,progressB=sim.ListenRequests('progress',1),sim.ListenRequests('progress',1)
local progress=ui.Sim.Request('progress',nil,{replyMode='All'})
deliver();sync();check(progress:Pending()==2,'UI receives the authoritative outstanding responder count')
progressA:Poll().Reply(1);sync()
check(progress:Pending()==1 and progress:Poll().value==1,'partial reply updates progress without completing the dialog')
server.Flush();check(next(packets)==nil,'unchanged pending dialog does not generate repeated progress traffic')
progressB:Close();sync()
check(progress:Status()=='complete' and progress:Poll().error=='responder_closed','closed deferred responder is forwarded as a final error')
progressA:Close()
local overflowA=ui.Sim.Request('ask',1)
ui.Sim.Request('ask',2);ui.Sim.Request('ask',3)
deliver();sync()
check(overflowA:Status()=='complete' and overflowA:Poll().error=='queue_overflow','bounded Sim inbox reports overflow across transport')
inbox:Close();sync()
local cyclic={};cyclic.self=cyclic
rejects(function() ui.Sim.Publish('broadcast',cyclic) end)
rejects(function() ui.Sim.Publish('broadcast',string.rep('x',65537)) end)
rejects(function() sim.PublishConfig('oversized',string.rep('x',65537),'ReadOnly',nil,nil,{scope='Sim'}) end)
check(not sim.HasConfig('oversized'),'oversized config rejected before publication')
rejects(function() config:Set(string.rep('x',65537)) end)
check(sim.Get('settings').count==1,'oversized owner update is rejected before committing')
local observer,observerReceiver=client('observer',{player=3,army=-1,actor=false,cheats=true})
ticket=observer.Sim.Publish('broadcast',{});deliver();server.Flush()
for _,packet in ipairs(packets) do observerReceiver.Receive(packet) end;packets={}
check(ticket:Status()=='failed','observers cannot mutate Sim')
check(next(callbackErrors)==nil,'no application callback assertion was swallowed')
print('PASS: '..checks..' shared UI/Sim transport checks')
