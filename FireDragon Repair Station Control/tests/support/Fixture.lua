return function()
    table.getn=table.getn or function(t) return #t end
    local root='src/lua/RepairStationControl/'
    local P=assert(loadfile(root..'Policy.lua'))()
    local X=assert(loadfile('../FireDragon Core & Loader/src/lua/FireDragon/InformationExchange.lua'))()
    local E=X.New({onError=error})
    local T=assert(loadfile('../FireDragon Core & Loader/src/lua/FireDragon/ExchangeTransport.lua'))()
    local packets={}
    local server=T.Attach(E,{realm='Sim',clock=function() return 0 end,send=function(p) packets[#packets+1]=p end})
    local w={P=P,E=E,units={},nearby={},orders={},clears=0,nativeCalls=0}
    local S,C
    local env=setmetatable({categories={ALLUNITS=1,MODULARSHIELD=2},WaitTicks=function() end,
        IsAlly=function(a,b) return a==b or b==2 end,IsDestroyed=function(u) return not u or u.Dead end,
        GetEntityById=function(id) return w.units[id] end}, {__index=_G})
    w.workerSettings={}
    env.FireDragonLoader={Mods={RepairStationControl={
        SetRestrictions=function(id,team,nukes) w.workerSettings[id]={DontHelpTeam=team,DontHelpNukes=nukes} end,
        ForgetWorker=function(id) w.workerSettings[id]=nil end,
        Reset=function() w.workerSettings={} end,
    }}}
    function env.import(path)
        if path:find('/FireDragon/Engine.lua',1,true) then return {Export=assert(loadfile('../FireDragon Core & Loader/src/lua/FireDragon/Engine.lua','t',env))()} end
        if path:find('InformationExchange.lua',1,true) then return {Export=E} end
        if path:find('Policy.lua',1,true) then return {Export=P} end
        if path:find('Settings.lua',1,true) then return {Export=S} end
        if path:find('Controller.lua',1,true) then return {Export=C} end
        if path:find('/ModularShields/Adapters/Assistance.lua',1,true) then
            w.Assist=w.Assist or assert(loadfile('../FireDragon Modular Shields/src/lua/ModularShields/Adapters/Assistance.lua','t',env))()
            return {Export=w.Assist}
        end
        error(path)
    end
    env.moho={unit_methods={SetAutoMode=function(u,enabled)
        w.nativeCalls=w.nativeCalls+1
        u.NativeAuto=enabled;u.AutoModeEnabled=enabled
        if C then C.AutoEvent(u,enabled) end
    end}}
    function env.IssueClearCommands(list)
        w.clears=w.clears+1;list[1].Queue={};list[1].Focus=nil;list[1].Guard=nil
    end
    local function order(list,target,kind)
        local u=list[1];u.Queue[#u.Queue+1]={commandType=kind,target=target};u.Focus=target;u.Guard=kind==15 and target or nil
        w.orders[#w.orders+1]={unit=u,target=target,kind=kind}
    end
    function env.IssueRepair(list,target) order(list,target,9) end
    function env.IssueGuard(list,target) order(list,target,15) end
    function env.IssueMove(list,p)
        local u=list[1];u.Queue[#u.Queue+1]={commandType=2,x=p[1],y=p[2],z=p[3]}
    end
    S=assert(loadfile(root..'Settings.lua','t',env))()
    C=assert(loadfile(root..'Controller.lua','t',env))();C.Start()
    w.C,w.S,w.env=C,S,env
    function w:Unit(id,army,cats)
        local u={EntityId=id,Army=army or 1,Blueprint={CategoriesHash=cats or {},AI={GuardScanRadius=25},Economy={MaxBuildDistance=25}},
            Queue={},AutoModeEnabled=true,NativeAuto=true,Health=100,Fraction=1,Position={0,0,0}}
        function u:GetFocusUnit() return self.Focus end
        function u:GetGuardedUnit() return self.Guard or (self.Queue[1] and self.Queue[1].target) end
        function u:GetCommandQueue() return self.Queue end
        function u:GetFractionComplete() return self.Fraction end
        function u:GetHealth() return self.Health end
        function u:GetMaxHealth() return 100 end
        function u:GetPosition() return self.Position end
        function u:IsUnitState(s) return self.State==s end
        function u:IsPaused() return self.Paused end
        function u:GetScriptBit(bit) return self.ProductionOff and bit==4 end
        function u:ForkThread(fn) return fn end
        function u:GetBuildRate() return self.NativeRate or 25 end
        function u:SetBuildRate(rate) self.NativeRate=rate end
        function u:UpdateConsumptionValues() end
        function u:SetWorkProgress(p) self.Progress=p end
        function u:BuildManipulatorSetEnabled() end
        function u:GetAIBrain() return {GetUnitsAroundPoint=function(_,cat) return cat==2 and (w.shields or {}) or w.nearby end} end
        w.units[id]=u
        return u
    end
    function w:Settings(army,team,nukes)
        S.Ensure(army)
        E.Set(S.Key(army),{DontHelpTeam=team,DontHelpNukes=nukes})
    end
    function w:Client(army)
        local commands={}
        local bus=X.New()
        local client=T.Attach(bus,{realm='UI',clock=function() return 0 end,session='test'..tostring(army),send=function(p) commands[#commands+1]=p end})
        function w:Deliver()
            local pending=commands;commands={}
            for _,packet in ipairs(pending) do server.Receive(packet,{realm='UI',army=army,player=army,actor=true}) end
        end
        function w:Sync()
            server.Flush(true)
            local pending=packets;packets={}
            for _,packet in ipairs(pending) do client.Receive(packet) end
        end
        self:Sync()
        return bus
    end
    return w
end
