local Exchange=assert(loadfile('src/lua/FireDragon/InformationExchange.lua'))()
local Transport=assert(loadfile('src/lua/FireDragon/ExchangeTransport.lua'))()
local checks=0
local function check(v,message) checks=checks+1;assert(v,message) end
local function size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local packets,commands={},{}
local focus=1
local sim=Exchange.New({clock=function() return 0 end})
local ui=Exchange.New({clock=function() return 0 end})
local server=Transport.Attach(sim,{realm='Sim',clock=function() return 0 end,focus=function() return focus end,
    send=function(packet) table.insert(packets,packet) end})
local client=Transport.Attach(ui,{realm='UI',session='routes',clock=function() return 0 end,
    send=function(packet) table.insert(commands,packet) end})
local function flush(full)
    server.Flush(full)
    for _,packet in ipairs(packets) do client.Receive(packet) end;packets={}
end
local edits=0
ui.UI.PublishConfig('style',{scale=1},'ReadWrite',function() edits=edits+1 end)
ui.UI.View('style').scale=2
check(edits==1 and ui.Get('style').scale==2 and not sim.HasConfig('style'),'UI-to-UI configuration stays local')
local received=0
ui.UI.Subscribe('ui.event',function(payload) received=received+payload end)
ui.UI.Publish('ui.event',3)
ui.UI.Respond('ui.ask',function(payload) return payload*2 end)
check(received==3 and ui.UI.Request('ui.ask',4):Poll().value==8 and size(commands)==0,'UI-to-UI notifications and dialogs use the same bus without transport')
sim.Sim.PublishConfig('sim.setting',false)
sim.Sim.Subscribe('sim.event',function(payload) received=received+payload end)
sim.Sim.Publish('sim.event',5)
sim.Sim.Respond('sim.ask',function(payload) return payload+1 end)
check(received==8 and sim.Sim.Request('sim.ask',4):Poll().value==5 and not ui.HasConfig('sim.setting'),'Sim-to-Sim events, requests and local config stay in Sim')
ui.PublishState('ui.style','menu',{color='blue'})
local cached=ui.GetState('ui.style','menu');cached.color='red'
check(ui.GetState('ui.style','menu').color=='blue' and sim.GetState('ui.style','menu')==nil,'local retained snapshots are copied and isolated')
sim.Expose('sim.remote',{requests=true,notifications=true,authorize='Army'})
sim.Respond('sim.remote',function(payload) return payload.amount end)
local ticket=ui.Sim.Request('sim.remote',{amount=12},{replyMode='First'})
for _,command in ipairs(commands) do server.Receive(command,{player=0,army=1,actor=true,cheats=false}) end;commands={}
flush()
check(ticket:Status()=='complete' and ticket:Poll().value==12,'UI-to-Sim uses the same request handlers')
local events=ui.Listen('units.status',16)
sim.UI.PublishState('units.status',1,{Queue={1,2,3}},{army=1})
sim.UI.PublishState('units.status',2,{Queue={4}},{army=2})
sim.UI.PublishState('units.status',1,{Queue={1,2}},{army=1})
flush()
check(ui.GetState('units.status',1).Queue[2]==2 and ui.GetState('units.status',2)==nil,'retained Sim snapshots coalesce and filter by army')
check(events:Count()==1,'coalesced state emits one UI notification')
events:Poll()
flush(true)
check(events:Count()==0,'full resnapshot does not repeat unchanged retained events')
sim.UI.PublishState('units.status',1,{Queue={}},{army=1});flush()
check(next(ui.GetState('units.status',1).Queue)==nil,'whole snapshot clears removed queue tails')
focus=2;flush()
check(ui.GetState('units.status',1)==nil and ui.GetState('units.status',2).Queue[1]==4,'focus change clears stale owner data and restores the new army')
sim.UI.PublishState('units.status',2,{Queue={5}},{army=1});flush()
check(ui.GetState('units.status',2)==nil,'changing a retained record owner immediately revokes the old UI copy')
focus=-1;flush()
check(ui.GetState('units.status',1) and ui.GetState('units.status',2).Queue[1]==5,'observer focus receives all retained records')
sim.UI.PublishState('units.status',1,nil,{army=1});flush()
check(ui.GetState('units.status',1)==nil,'destroyed entity snapshot is removed through the event stream')
flush(true);check(ui.GetState('units.status',1)==nil,'late snapshots cannot revive destroyed entities')
print('PASS: '..checks..' UI/UI, UI/Sim, Sim/Sim and retained event checks')
