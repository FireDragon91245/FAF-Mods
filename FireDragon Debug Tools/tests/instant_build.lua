-- Exercise the real Exchange transport: all players share one match setting.
table.getn = table.getn or function(t) return #t end
local Exchange=assert(loadfile('../FireDragon Core & Loader/src/lua/FireDragon/InformationExchange.lua'))()
local Transport=assert(loadfile('../FireDragon Core & Loader/src/lua/FireDragon/ExchangeTransport.lua'))()
local Messages=assert(loadfile('src/lua/FireDragonDebugTools/Messages.lua'))()
local Bindings=assert(loadfile('../FireDragon Core & Loader/src/lua/FireDragon/Bindings.lua'))()
local count=0
local function check(value,message) count=count+1;assert(value,message) end
local bus=Exchange.New({clock=function() return 0 end})
local clients,packets,commands={},{},{}
local server=Transport.Attach(bus,{realm='Sim',clock=function() return 0 end,
    send=function(packet) packets[#packets+1]=packet end})
local function flush()
    server.Flush()
    for _,packet in ipairs(packets) do
        for _,client in ipairs(clients) do client.transport.Receive(packet) end
    end
    packets={}
end
local function client(army,cheats)
    local b=Exchange.New({clock=function() return 0 end})
    local c={bus=b}
    c.transport=Transport.Attach(b,{realm='UI',session='instant-build-'..army,clock=function() return 0 end,
        send=function(packet)
            server.Receive(packet,{player=army-1,army=army,actor=true,cheats=cheats})
            flush()
        end})
    clients[#clients+1]=c
    return c
end
local a,b,denied=client(1,true),client(2,true),client(3,false)
local env=setmetatable({
    SimConExecute=function(command) commands[#commands+1]=command end,
    import=function(path)
        if path:find('InformationExchange.lua',1,true) then return {Export=bus} end
        if path:find('Messages.lua',1,true) then return {Export=Messages} end
        error(path)
    end,
},{__index=_G})
assert(loadfile('src/lua/FireDragonDebugTools/InstantBuild.lua','t',env))()
env.Start();flush()
check(#commands==0,'Opening a match does not overwrite the engine setting')
check(a.bus.GetState(Messages.InstantBuild,'match').Enabled==false,'Initial menu state is off')
local function request(c,data)
    return c.bus.Sim.Request(Messages.SetInstantBuild,data,{replyMode='First'})
end
request(a,{Enabled=true})
check(commands[1]=='ai_InstaBuild true','Enabling explicitly sets the engine boolean')
check(a.bus.GetState(Messages.InstantBuild,'match').Enabled and b.bus.GetState(Messages.InstantBuild,'match').Enabled,
    'All players receive the shared enabled state')
request(b,{Enabled=false})
check(commands[2]=='ai_InstaBuild false' and not a.bus.GetState(Messages.InstantBuild,'match').Enabled,
    'Another army can disable the same match-wide setting')
request(b,{Enabled=false})
check(#commands==3 and commands[3]=='ai_InstaBuild false','Repeated requests reapply an explicit value')
local ticket=request(denied,{Enabled=true})
local reply=ticket:Poll()
check(#commands==3 and reply and reply.error=='denied','Cheats-disabled requests cannot execute console commands')
for _,data in ipairs({'bad',{}, {Enabled=1},{Enabled='false'}}) do
    ticket=request(a,data);reply=ticket:Poll()
    check(#commands==3 and reply and reply.value.Accepted==false and reply.value.Reason=='InvalidMessage',
        'Malformed values are rejected without executing a command')
end
env.Start();flush()
check(#commands==3 and not a.bus.GetState(Messages.InstantBuild,'match').Enabled,'Service startup is idempotent')

-- Load the real panel to exercise its checkbox binding and UI-side session controls.
local checkboxes,labels,sessionCommands={},{},{}
local session={speed=0,paused=false,mode='adjustable',army=1,canPause=true,resume='Accepted',time=0}
local slider,refresh
local function control() return {} end
local vanilla={}
local tabs={Add=function(_,id) if id=='vanilla' then return vanilla end end}
local UI={
    Window=function() return {Client={Width=function() return 440 end,Height=function() return 400 end}} end,
    Tabs=function() return tabs end,At=function() end,
    Checkbox=function(parent,options)
        check(parent==vanilla,'Vanilla checkboxes use the Vanilla tab')
        checkboxes[options.text]=options
        return control()
    end,
    Label=function(_,options)
        local label={text=options.text}
        function label:SetText(text) self.text=text end
        function label:SetColor(color) self.color=color end
        labels[options.y]=label
        return label
    end,
    Slider=function(_,options)
        slider={options=options,Value=options.value}
        function slider:SetValue(value) self.Value=value end
        function slider:SetEnabled(enabled) self.enabled=enabled end
        return slider
    end,
    Bind=function(_,_,apply) refresh=apply end,
}
local panel=setmetatable({
    GetFrame=function() return {Width=function() return 1920 end} end,
    GetFocusArmy=function() return session.army end,
    GetGameSpeed=function() return session.speed end,
    SessionIsPaused=function() return session.paused end,
    SessionIsReplay=function() return session.replay==true end,
    SessionGetScenarioInfo=function() return {Options={GameSpeed=session.mode}} end,
    GetSystemTimeSeconds=function() return session.time end,
    SessionRequestPause=function() sessionCommands[#sessionCommands+1]='pause' end,
    SessionResume=function() sessionCommands[#sessionCommands+1]='resume';return session.resume end,
    ConExecute=function(command) sessionCommands[#sessionCommands+1]=command end,
    import=function(path)
        if path:find('/UI.lua',1,true) then return {Export=UI} end
        if path:find('/Bindings.lua',1,true) then return {Export=Bindings} end
        if path:find('/InformationExchange.lua',1,true) then return {Export=a.bus} end
        if path:find('/Messages.lua',1,true) then return {Export=Messages} end
        if path:find('/Keys.lua',1,true) then return {DefaultKey='Alt-Shift-D'} end
        if path=='/lua/ui/game/tabs.lua' then return {CanUserPause=function() return session.canPause end} end
        error(path)
    end,
},{__index=_G})
assert(loadfile('src/lua/FireDragonDebugTools/Panel.lua','t',panel))()
panel.Toggle()
local box=assert(checkboxes['Instant Build (all armies)'])
check(box.y==72 and box.binding.target=='match','Instant Build is the third row and binds the match target')
local model=box.binding.source:For(box.binding.target)
model:Submit(box.binding.intent(true))
check(model:Get().Enabled==true and commands[4]=='ai_InstaBuild true','Checkbox binding reaches the Sim engine setter')
model:Submit(box.binding.intent(false))
check(model:Get().Enabled==false and commands[5]=='ai_InstaBuild false','Checkbox binding can disable instant build')

check(slider.Value==1 and labels[112].text=='Game speed: 1 (normal)' and #sessionCommands==0,
    'Opening the panel reflects normal speed without changing the session')
slider.options.onChange(slider,10)
check(sessionCommands[1]=='WLD_GameSpeed 9' and slider.Value==10 and not slider.enabled,
    'Preset 10 requests native +9 and waits for confirmation')
session.speed=9;refresh()
check(slider.Value==10 and slider.enabled,'Confirmed speed changes re-enable the slider')
session.speed=3;refresh()
check(slider.Value==4 and labels[112].text=='Game speed: 4 (FAF +3)' and #sessionCommands==1,
    'Keyboard or console speed changes update the control without sending requests')
session.speed=50;refresh()
check(slider.Value==10 and labels[112].text:find('FAF +50',1,true) and #sessionCommands==1,
    'External fast speeds are displayed honestly without overwriting them')
session.speed=-2;refresh()
check(slider.Value==1 and labels[112].text:find('FAF -2',1,true) and #sessionCommands==1,
    'External slow speeds are displayed without overwriting them')
slider.options.onChange(slider,0)
check(sessionCommands[2]=='pause' and not slider.enabled,'Preset 0 requests a native simulation pause')
session.paused=true;refresh()
check(slider.Value==0 and slider.enabled and labels[112].text=='Game speed: 0 (paused)',
    'A confirmed pause leaves UI controls active')
session.time=20;refresh()
check(slider.Value==0 and slider.enabled and #sessionCommands==2,
    'UI refresh continues while simulation time is stopped')
slider.options.onChange(slider,5)
check(sessionCommands[3]=='resume' and sessionCommands[4]=='WLD_GameSpeed 4' and not slider.enabled,
    'Leaving 0 resumes the session at the selected native speed')
session.paused=false;session.speed=4;refresh()
check(slider.Value==5 and slider.enabled,'Resume waits for both pause and speed confirmation')

session.paused=true;session.resume='Declined';refresh()
local previous=#sessionCommands
slider.options.onChange(slider,1)
check(#sessionCommands==previous+1 and sessionCommands[#sessionCommands]=='resume' and slider.Value==0
    and labels[184].text=='Refused: the session cannot resume yet',
    'A refused multiplayer resume keeps the paused state and cannot change speed')
session.resume='Accepted';session.canPause=false
slider.options.onChange(slider,1)
check(sessionCommands[#sessionCommands-1]=='resume' and sessionCommands[#sessionCommands]=='WLD_GameSpeed 0',
    'Exhausted pause quota does not prevent resuming')
session.paused=false;session.speed=0;refresh()
previous=#sessionCommands
slider.options.onChange(slider,0)
check(#sessionCommands==previous and slider.Value==1 and labels[184].text=='Refused: no pauses remaining',
    'Pause limits are enforced and refusals restore the confirmed slider value')

session.mode='normal';session.canPause=true
slider.options.onChange(slider,2)
check(#sessionCommands==previous and slider.Value==1 and labels[184].text=='Refused: game speed is fixed by the lobby',
    'Fixed-speed lobbies cannot send speed-changing commands')
slider.options.onChange(slider,0)
session.paused=true;refresh()
check(sessionCommands[#sessionCommands]=='pause' and slider.enabled,'Fixed-speed games can still pause')
slider.options.onChange(slider,1)
check(sessionCommands[#sessionCommands]=='resume','The matching fixed-speed preset can resume without changing speed')
session.paused=false;refresh()
session.army=-1;refresh()
check(not slider.enabled,'Live observers cannot operate the speed slider')
previous=#sessionCommands
slider.options.onChange(slider,2)
check(#sessionCommands==previous and labels[184].text=='Observers cannot change the live session',
    'Observer requests cannot alter the session even with a stale UI event')

session.replay=true;session.canPause=false;refresh()
check(slider.enabled,'Replay session controls are not restricted like live observers')
slider.options.onChange(slider,0)
check(sessionCommands[#sessionCommands]=='pause','Replay pause does not consume player timeouts')
session.paused=true;refresh()
session.army=1;session.replay=false;session.mode='adjustable'
slider.options.onChange(slider,3)
session.time=session.time+6;refresh()
check(slider.enabled and slider.Value==0 and labels[184].text=='Session confirmation timed out (5 seconds)',
    'Unconfirmed session changes time out using UI time, including while paused')
session.paused=false;session.speed=2;refresh()
check(slider.Value==3,'Late session confirmation still updates the authoritative display')
slider.FDSliderDrag={};slider.Value=8;slider.options.onPreview(slider,8);refresh()
check(slider.Value==8 and labels[112].text=='Game speed: 8 (FAF +7)',
    'Engine refresh does not overwrite a slider drag preview')
slider.FDSliderDrag=nil;refresh()
check(slider.Value==3,'Ending an uncommitted preview restores the confirmed engine speed')
print(string.format('PASS: %d instant build and Vanilla panel checks',count))
