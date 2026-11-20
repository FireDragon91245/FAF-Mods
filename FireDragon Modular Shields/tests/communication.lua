table.getn=table.getn or function(t) return #t end
local Exchange=assert(loadfile('../FireDragon Core & Loader/src/lua/FireDragon/InformationExchange.lua'))()
local Transport=assert(loadfile('../FireDragon Core & Loader/src/lua/FireDragon/ExchangeTransport.lua'))()
local Messages=assert(loadfile('src/lua/ModularShields/Messages.lua'))()
local sim,ui=Exchange.New({clock=function() return 0 end}),Exchange.New({clock=function() return 0 end})
local packets,commands,current={},{},nil
local server=Transport.Attach(sim,{realm='Sim',clock=function() return 0 end,send=function(packet) packets[#packets+1]=packet end})
local client=Transport.Attach(ui,{realm='UI',session='owned-unit',clock=function() return 0 end,send=function(packet) commands[#commands+1]=packet end})
local hosts={[1]={EntityId=1,Army=1,Loadout={Queue={}}},[2]={EntityId=2,Army=2,Loadout={Queue={}}}}
local service,called
for _,host in pairs(hosts) do
    host.NextJob=0
    function host:PublishModules() service.Status(self,{Queue=self.Loadout.Queue}) end
    function host:ModuleAction(action,value)
        called=(called or 0)+1
        if action=='install' then
            self.NextJob=self.NextJob+1
            local job={JobId=self.NextJob,ModuleId=value}
            table.insert(self.Loadout.Queue,job);return job
        elseif action=='cancel' then
            for index,job in ipairs(self.Loadout.Queue) do
                if job.JobId==value then table.remove(self.Loadout.Queue,index);return end
            end
            return {Code='UnknownJob'}
        end
    end
end
local env=setmetatable({GetEntityById=function(id) return hosts[tonumber(id)] end,import=function(path)
    if path:find('InformationExchange.lua',1,true) then return {Export=sim} end
    if path:find('Messages.lua',1,true) then return {Export=Messages} end
    if path=='/lua/SimCallbacks.lua' then return {SecureUnits=function(ids)
        local host=hosts[tonumber(ids[1])]
        return host and host.Army==current.army and {host} or {}
    end} end
    error(path)
end},{__index=_G})
assert(loadfile('src/lua/ModularShields/Services/Communication.lua','t',env))()
service=env.Export;service.Start()
local function deliver()
    local batch=commands;commands={}
    current={army=1,player=0,actor=true,cheats=false}
    for _,command in ipairs(batch) do server.Receive(command,current) end
    server.Flush()
    for _,packet in ipairs(packets) do client.Receive(packet) end;packets={}
end
local install=ui.Sim.Request(Messages.Action,{EntityId=1,Action='install',Value='power_1'},{replyMode='First'})
local cancel=ui.Sim.Request(Messages.Action,{EntityId=1,Action='cancel',CancelRequestId=install.Key},{replyMode='First'})
deliver()
assert(install:Poll().value.Accepted and cancel:Poll().value.Accepted and #hosts[1].Loadout.Queue==0,
    'install/cancel before acknowledgement follows engine command order')
assert(next(ui.GetState(Messages.Status,1).Queue)==nil,'retained queue snapshot contains no removed tail')
local before=called
local nativeId=ui.Sim.Request(Messages.Action,{EntityId='1',Action='install',Value='power_1'},{replyMode='First'})
deliver();assert(nativeId:Poll().value.Accepted,'FAF UI string entity ID reaches the authorized handler')
before=called
local enemy=ui.Sim.Request(Messages.Action,{EntityId=2,Action='install',Value='power_1'},{replyMode='First'})
deliver();assert(enemy:Status()=='failed' and enemy.Error=='denied' and called==before,'native unit control validation rejects another army')
local invalid=ui.Sim.Request(Messages.Action,{EntityId=1,Action='unknown'},{replyMode='First'})
deliver();assert(invalid:Status()=='failed' and called==before,'invalid static action shape is rejected')
local missing=ui.Sim.Request(Messages.Action,{EntityId=999,Action='pause'},{replyMode='First'})
deliver();assert(missing.Error=='denied','missing target cannot receive an action')
local response=sim.Request(Messages.Action,{EntityId=1,Action='install',Value='regen_1'}):Poll()
assert(response.value.Accepted and #hosts[1].Loadout.Queue==2,'Sim-to-Sim callers use the same message handler')
service.Live(hosts[1],{HP=100,RepairMass=2.5});deliver()
assert(ui.GetState(Messages.Live,1).RepairMass==2.5,'live telemetry travels through retained events')
service.Remove(hosts[1]);deliver()
assert(ui.GetState(Messages.Status,1)==nil and ui.GetState(Messages.Live,1)==nil,'entity removal clears both retained streams')
print('PASS: shield action ordering, unit authorization, static contracts and retained telemetry')
