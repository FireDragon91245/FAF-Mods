table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
function table.deepcopy(t)
    if type(t)~='table' then return t end
    local copy={};for k,v in pairs(t) do copy[k]=table.deepcopy(v) end;return copy
end
-- Match FAF's recursive merge, which retains missing fields and array tails.
function table.merged(base,patch)
    for k,v in pairs(patch) do
        if type(v)=='table' and type(base[k])=='table' then table.merged(base[k],v)
        else base[k]=table.deepcopy(v) end
    end
    return base
end
local function loadCore(path)
    local env=setmetatable({}, {__index=_G})
    return assert(loadfile('src/lua/ModularShields/'..path,'t',env))()
end
local R=loadCore('Bootstrap.lua').Build(loadCore)
local controls={}
local preferences={}
function SavePreferences() end
local clock=0
function GetSystemTimeSeconds() return clock end
function GetFocusArmy() return 1 end
local function lazy(value)
    return setmetatable({Value=value,Set=function(self,v) self.Value=v end},
        {__call=function(self) if type(self.Value)=='function' then return self.Value() end;return self.Value end})
end
local function control(kind,parent,name)
    local c={Kind=kind,Parent=parent,Name=name,Children={},Width=lazy(0),Height=lazy(0),Left=lazy(0),Top=lazy(0)}
    c.Right=lazy(function() return c.Left()+c.Width() end);c.Bottom=lazy(function() return c.Top()+c.Height() end)
    function c:UseAlphaHitTest(v) self.AlphaHit=v end
    function c:SetNeedsFrameUpdate(v) self.NeedsFrameUpdate=v end
    function c:GetRootFrame() return GetFrame(0) end
    function c:SetUV(...) self.UV={...} end
    function c:SetAlpha(v) self.Alpha=v end
    function c:GetStringAdvance(s) return #s*7 end
    c.Depth=lazy(function() return parent and parent.Depth()+1 or 0 end)
    if parent then parent.Children[#parent.Children+1]=c end
    function c:DisableHitTest() self.NoHit=true end
    function c:EnableHitTest() self.NoHit=false end
    function c:SetClipToWidth(v) self.Clip=v end
    function c:SetText(v) self.Text=v end
    function c:SetSolidColor(v) self.Color=v end
    function c:SetTexture(v) self.Texture=v end
    function c:SetColor(v) self.Color=v end
    function c:SetDropShadow() end
    function c:IsHidden() return self.Hidden end
    function c:Show() self.Hidden=false end
    function c:Hide() self.Hidden=true end
    function c:Enable() self.Disabled=false;self.NoHit=false end
    function c:Disable() self.Disabled=true;self.NoHit=true end
    function c:Destroy() self.Destroyed=true;if self.OnDestroy then self:OnDestroy() end;for _,child in ipairs(self.Children) do child:Destroy() end end
    controls[#controls+1]=c;return c
end
local frame=control('frame');frame.Width:Set(1920);frame.Height:Set(1080)
function GetFrame() return frame end
local layout={ScaleNumber=function(v) return v end,InvScaleNumber=function(v) return v end}
function layout.AtLeftTopIn(c,parent,x,y) c.Left:Set(function() return parent.Left()+x end);c.Top:Set(function() return parent.Top()+y end) end
function layout.AtRightTopIn(c,parent,x,y) c.Left:Set(function() return parent.Left()+parent.Width()-c.Width()-x end);c.Top:Set(function() return parent.Top()+y end) end
function layout.FillParent(c,parent) c.Left:Set(function() return parent.Left() end);c.Top:Set(function() return parent.Top() end);c.Width:Set(function() return parent.Width() end);c.Height:Set(function() return parent.Height() end) end
local UI={bodyFont='body',SkinnableFile=function(p) return '/skin'..p end}
function UI.CreateText(parent,label) local t=control('text',parent);t:SetText(label);return t end
function UI.CreateButtonStd(parent,texture,label)
    assert(texture=='/scx_menu/small-btn/small','Use known native button textures')
    local b=control('button',parent);b.label=UI.CreateText(b,label);b.label:DisableHitTest();return b
end
local sharedUI,sharedStorage,exchangeUI,exchangeSim
function import(path)
    if path:find("FireDragon/InformationExchange.lua",1,true) then return {Export=exchangeUI} end
    if path:find("ModularShields/Messages.lua",1,true) then return {Export=loadCore("Messages.lua")} end
    if path=='/mods/FireDragonModLoader/lua/FireDragon/Storage.lua' then
        if not sharedStorage then sharedStorage=assert(loadfile('../FireDragon Mod Loader/src/lua/FireDragon/Storage.lua'))() end
        return {Export=sharedStorage}
    end
    if path=='/lua/user/prefs.lua' then return {GetCurrentProfile=function() return preferences end,GetFromCurrentProfile=function(k) return preferences[k] end,SetToCurrentProfile=function(k,v) preferences[k]=v end} end
    if path=='/mods/FireDragonModLoader/lua/FireDragon/UI.lua' then
        if not sharedUI then sharedUI=assert(loadfile('../FireDragon Mod Loader/src/lua/FireDragon/UI.lua'))() end
        return {Export=sharedUI}
    end
    if path=='/lua/maui/dragger.lua' then return {Dragger=function() return {Destroy=function() end} end} end
    if path=='/lua/maui/group.lua' then return {Group=function(parent,name) return control('group',parent,name) end} end
    if path=='/lua/maui/bitmap.lua' then return {Bitmap=function(parent) return control('bitmap',parent) end} end
    if path=='/lua/maui/layouthelpers.lua' then return layout end
    if path=='/lua/ui/uiutil.lua' then return UI end
    if path=='/lua/ui/controls.lua' then return {Get=function() return {constructionGroup={Top=function() return 900 end,IsHidden=function() return false end}} end} end
    if path:find('UI/Model.lua',1,true) then return {Export=loadCore('UI/Model.lua')} end
    error('Unexpected UI import '..path)
end
local owned
local state=R.Core.New('t3',{Mass=1000,Energy=10000,Upkeep=100,ShieldMaxHP=10000,ShieldSize=40,ShieldRegen=100})
state.Rules=R.Core
local selected={{GetEntityId=function() return 1001 end}}
function GetSelectedUnits() return selected end
UnitData={[1001]={OtherMod={Keep=true}}}
local Exchange=assert(loadfile('../FireDragon Mod Loader/src/lua/FireDragon/InformationExchange.lua'))()
local Transport=assert(loadfile('../FireDragon Mod Loader/src/lua/FireDragon/ExchangeTransport.lua'))()
local Messages=loadCore('Messages.lua')
exchangeUI=Exchange.New({clock=function() return clock end});exchangeSim=Exchange.New({clock=function() return clock end})
local packets={}
local server=Transport.Attach(exchangeSim,{realm='Sim',clock=function() return clock end,send=function(packet) packets[#packets+1]=packet end})
local client
local function flush()
    server.Flush()
    for _,packet in ipairs(packets) do client.Receive(packet) end
    packets={}
end
local paused,repairPaused=false,false
local function sync()
    local rows={}
    for _,id in ipairs(R.Registry.Order) do
        local d=R.Registry.Modules[id]
        local reason=R.Core.Eligible(state,id,R.Registry,R.Config,true)
        rows[#rows+1]={Id=id,Family=d.Family,Level=d.Level,Behavior=d.Behavior,Name=d.UI.Name,Requires=d.Requires,
            Installed=state.Installed[id]~=nil,Reason=reason and reason.Code or false,
            Detail=reason and (reason.Module or reason.Behavior) or false,
            Deltas={ShieldMaxHP=d.Family=='power' and 2500 or 0,ShieldRegen=d.Family=='regen' and 30 or 0,Upkeep=10},
            Quote=R.Core.Quote(state,id,R.Registry,R.Config)}
    end
    local job=state.Queue[1]
    local status={Rows=rows,Used=R.Core.Used(state,R.Registry),Slots=R.Core.Capacity(state,R.Config),Faction='CYBRAN',RemovalSeconds=5,
        BaseSlots=R.Config.Chassis[state.Chassis].Slots,BonusSlots=state.BonusSlots or 0,
        Capabilities=state.Capabilities,Queue=table.deepcopy(state.Queue),QueueCount=#state.Queue,Stats=R.Stats.Calculate(state,R.Registry,R.Config),
        InstallPaused=paused,RepairPaused=repairPaused,ActualEnergy=100,Assistants=0,WorkRate=40,Barrier='NotInstalled',
        Job=job and {Id=job.JobId,Module=job.ModuleId,Progress=job.PaidWork/job.Quote.Work,State=job.State} or false}
    exchangeSim.UI.PublishState(Messages.Status,1001,status,{army=1})
    exchangeSim.UI.PublishState(Messages.Live,1001,{HP=8000,MaxHP=10000,Regen=100,Damage=240,Status='Regenerating'},{army=1})
    flush()
end
local sent={}
local delayed={}
local delayCallbacks=false
owned={ModuleAction=function(_,action,value)
    local created
    if owned.Reject then return nil,{Code='Rejected'} end
    if owned.RejectCancel and action=='cancel' then return {Code='Rejected'} end
    if action=='install' then created=assert(R.Core.RequestInstall(state,value,R.Registry,R.Config))
    elseif action=='remove' then assert(R.Core.RequestUninstall(state,value,R.Registry,R.Config))
    elseif action=='cancel' then assert(not R.Core.RequestCancel(state,value,R.Registry))
    elseif action=='pause' then paused=not paused
    elseif action=='repair' then repairPaused=not repairPaused end
    sync()
    return created
end}
owned.PublishModules=sync
owned.Loadout=state;owned.EntityId=1001;owned.Army=1
local secureCalled=false
local commEnv=setmetatable({GetEntityById=function(id) return id==1001 and owned or nil end,
    import=function(path)
        if path:find('FireDragon/InformationExchange.lua',1,true) then return {Export=exchangeSim} end
        if path=='/lua/SimCallbacks.lua' then return {SecureUnits=function(units)
            secureCalled=true;assert(units[1]==1001);return {owned}
        end} end
        return import(path)
    end}, {__index=_G})
assert(loadfile('src/lua/ModularShields/Services/Communication.lua','t',commEnv))()
commEnv.Export.Start()
local function deliver(request)
    server.Receive(request,{army=1,player=0,actor=true,cheats=false});flush()
end
local function requestKey(packet) return packet.session..'/'..tostring(packet.id) end
client=Transport.Attach(exchangeUI,{realm='UI',session='shield-ui-test',clock=function() return clock end,
    send=function(request)
        sent[#sent+1]=request
        if delayCallbacks then delayed[#delayed+1]=request else deliver(request) end
    end})
local Panel=loadCore('UI/Panel.lua')
local Model=loadCore('UI/Model.lua')
local count=0
local function check(value,message) count=count+1;assert(value,message) end
local function find(predicate)
    for _,c in ipairs(controls) do if not c.Destroyed and predicate(c) then return c end end
end
local function card(id) return assert(find(function(c) return c.ModularId==id end)) end
local function label(text) return find(function(c) return c.Kind=='text' and c.Text==text end) end
local function click(c,right)
    assert(not c.Hidden and not c.Destroyed)
    assert(c:HandleEvent({Type='ButtonPress',Modifiers=right and {Right=true} or {Left=true}}))
    Panel.Update()
end
local function hover(c) c:HandleEvent({Type='MouseEnter'}) end
sync();Panel.Update()
local window=find(function(c) return c.Name=='Modular Shield Window' end)
local dock=card('power_1').Parent
local tip=find(function(c) return c.Name=='Module Tooltip' end)
check(window.Width()==780 and window.MinWidth==420 and window.Resizable,'Shield menu uses a resizable shared window with minimum size')
check(label('HP  8000 / 10000').Color==Model.Colors.HP,'Live current/max HP is blue')
check(label('+100 HP/s  Regenerating').Color==Model.Colors.Regen,'Live regeneration is green')
check(label('-240 HP/s  (5s avg)').Color==Model.Colors.Damage,'Rolling incoming damage is red')
-- Deliberately hold the simulation replies: the UI must remain responsive.
delayCallbacks=true
local first=card('power_1')
first:HandleEvent({Type='ButtonPress',Modifiers={Left=true}})
check(#state.Queue==0 and first.Top()==dock.Top()+158 and not card('power_2').Hidden,'click moves pending upgrade immediately without a simulation reply')
check(label('...') and not label('...').Parent.Hidden,'pending installation has immediate feedback')
card('power_2'):HandleEvent({Type='ButtonPress',Modifiers={Left=true}})
card('range_1'):HandleEvent({Type='ButtonPress',Modifiers={Left=true}})
check(#delayed==3 and not card('power_3').Hidden,'rapid clicks queue prerequisites and another family without waiting')
Panel.Update();Panel.Update()
check(first.Top()==dock.Top()+158 and #state.Queue==0,'stale snapshots preserve pending entries')
for _,request in ipairs(delayed) do deliver(request) end
delayed={};delayCallbacks=false;Panel.Update()
check(#state.Queue==3 and label('0%'),'acknowledgements replace pending indicators with real jobs')
delayCallbacks=true
first:HandleEvent({Type='ButtonPress',Modifiers={Right=true}})
check(#state.Queue==3 and first.Top()>dock.Top()+158 and card('power_2').Hidden,'cancel immediately removes the target and dependent queue without a sim reply')
check(card('range_1').Top()==dock.Top()+158,'cancel keeps unrelated queued upgrades')
Panel.Update();Panel.Update()
check(first.Top()>dock.Top()+158,'stale snapshots do not restore a cancelled job')
for _,request in ipairs(delayed) do deliver(request) end
delayed={};delayCallbacks=false;Panel.Update()
check(#state.Queue==1 and state.Queue[1].ModuleId=='range_1','cancel acknowledgement matches the projected queue')
state.Queue={};state.Revision=state.Revision+1;sync();Panel.Update()
-- A rejected request is rolled back from an explicit receipt, not an arbitrary beat delay.
delayCallbacks=true
card('power_1'):HandleEvent({Type='ButtonPress',Modifiers={Left=true}})
local rejected=delayed[1]
owned.Reject=true;deliver(rejected);owned.Reject=false
state.Queue={};sync();Panel.Update()
check(card('power_1').Top()>dock.Top()+158 and card('power_2').Hidden,'rejected request returns to upgrades and hides its dependent level')
delayed={}
card('power_1'):HandleEvent({Type='ButtonPress',Modifiers={Left=true}})
clock=6;Panel.Update()
check(card('power_1').Top()>dock.Top()+158,'unanswered request times out without a stuck module')
delayed={};clock=7
card('power_1'):HandleEvent({Type='ButtonPress',Modifiers={Left=true}})
card('power_2'):HandleEvent({Type='ButtonPress',Modifiers={Left=true}})
card('power_1'):HandleEvent({Type='ButtonPress',Modifiers={Right=true}})
check(#delayed==3 and delayed[3].value.CancelRequestId==requestKey(delayed[1]),'pending install can be cancelled using its request token before it has a job id')
check(card('power_1').Top()>dock.Top()+158 and card('power_2').Hidden,'pre-ack cancellation removes pending dependents immediately')
card('power_1'):HandleEvent({Type='ButtonPress',Modifiers={Left=true}})
local replacementToken=requestKey(delayed[4])
local originalInstall=table.remove(delayed,1)
deliver(originalInstall);Panel.Update()
check(#state.Queue==1 and card('power_1').Top()==dock.Top()+158,'old install acknowledgement does not consume a replacement install request')
for _,request in ipairs(delayed) do deliver(request) end
delayed={};Panel.Update()
check(#state.Queue==1 and state.Queue[1].ModuleId=='power_1' and state.Queue[1].UIRequestId==replacementToken,
    'install-cancel-reinstall processes correctly in send order: '..tostring(#state.Queue)..' / '..tostring(state.Queue[1] and state.Queue[1].UIRequestId)..' / '..replacementToken)
-- A rejected cancel must restore the original job after its explicit response.
card('power_1'):HandleEvent({Type='ButtonPress',Modifiers={Right=true}})
check(card('power_1').Top()>dock.Top()+158,'confirmed job cancellation projects immediately')
local rejectedCancel=delayed[1]
owned.RejectCancel=true;deliver(rejectedCancel);owned.RejectCancel=false;sync();Panel.Update()
check(card('power_1').Top()==dock.Top()+158 and #state.Queue==1,'rejected cancellation restores authoritative job')
delayed={}
card('power_1'):HandleEvent({Type='ButtonPress',Modifiers={Right=true}})
clock=13;Panel.Update()
check(card('power_1').Top()==dock.Top()+158,'unanswered cancellation times out without a hidden job')
state.Queue={};state.Revision=state.Revision+1;sync();Panel.Update()
delayed={};delayCallbacks=false;sent={};clock=14
local power1=card('power_1')
check(not power1.Hidden and card('power_2').Hidden,'Upgrade row shows the next module level of each family')
local image=find(function(c) return c.Parent and c.Parent.Parent==power1 and c.Texture end)
check(image.Texture:find('cybran_power_1.dds',1,true),'Module icon uses its faction-specific texture')
hover(power1)
check(not tip.Hidden and label('+2500 maximum shield HP').Color==Model.Colors.HP,'Native hover popup shows capacity change in blue')
click(power1)
check(secureCalled and sent[1].value.Action=='install' and #state.Queue==1,'Image click reaches the secured install callback')
check(power1.Top()==dock.Top()+158 and image.Texture:find('_dim.dds',1,true),'Queued icon moves to modules row and is grayed out')
check(label('0%') and not label('0%').Hidden,'Pending icon overlays installation percentage')
check(not card('power_2').Hidden,'Queuing a prerequisite exposes the next upgrade')
local job=state.Queue[1];job.PaidWork=job.Quote.Work*.5;job.State='Building'
sync();Panel.Update()
check(label('50%') and not label('50%').Hidden,'Paid progress refreshes the image overlay in place')
click(card('power_2'))
click(power1,true)
check(#state.Queue==0 and power1.Top()==dock.Top()+231 and card('power_2').Hidden,'Right-click cancels pending module and dependent queue')
check(not exchangeUI.GetState(Messages.Status,1001).Job and #exchangeUI.GetState(Messages.Status,1001).Queue==0,'Snapshot merge clears cancelled job and queue tails')
check(UnitData[1001].OtherMod.Keep,'Module snapshot leaves unrelated unit data intact')
click(power1);job=state.Queue[1];job.PaidWork=job.Quote.Work
assert(not R.Core.Complete(state,job,R.Registry,R.Config));sync();Panel.Update()
check(power1.Top()==dock.Top()+158 and not image.Texture:find('_dim',1,true),'Completed module remains equipped with full-color icon')
hover(power1)
check(label('-2500 maximum shield HP on removal').Color==Model.Colors.HP,'Installed-module tooltip previews the actual loss on removal in blue')
click(power1,true)
check(state.Installed.power_1 and state.Queue[1].Kind=='Remove','Right-click queues timed removal instead of instantly deinstalling')
check(label('REMOVE') and image.Texture:find('_dim.dds',1,true),'Removal has a gray icon and explicit removal overlay')
delayCallbacks=true
power1:HandleEvent({Type='ButtonPress',Modifiers={Right=true}})
check(state.Queue[1].Kind=='Remove' and state.Installed.power_1 and not label('REMOVE'),'cancelling removal immediately clears its overlay while keeping the module installed')
Panel.Update()
check(not label('REMOVE'),'stale snapshots do not revive removal overlay')
for _,request in ipairs(delayed) do deliver(request) end
delayed={};delayCallbacks=false;Panel.Update()
check(state.Installed.power_1 and #state.Queue==0,'Right-clicking removal cancels it and keeps installed module')
click(power1,true);job=state.Queue[1];job.PaidWork=job.Quote.Work
assert(not R.Core.Complete(state,job,R.Registry,R.Config));sync();Panel.Update()
check(not state.Installed.power_1 and power1.Top()==dock.Top()+231,'Finished removal returns icon to available upgrades')
hover(card('deflector'))
check(label('Deflects crashing aircraft and selected').Color==Model.Colors.Special,'Special effect hover descriptions are orange')
card('deflector'):HandleEvent({Type='MouseExit'})
check(tip.Hidden,'Moving away closes the tooltip')
check(label('Deflects crashing aircraft and selected').Parent.Hidden,'Tooltip child text also hides without leaving ghosts')
hover(card('impenetrable'))
check(label('[missing] Deflector') and label('[missing] Atomized (nuclear containment)') and label('[missing] Ballistic (missile defense)'),'Impenetrable lists all three special-module requirements separately')
check(label('T1 generators and all storage are excluded.'),'Impenetrable explains the T2+ generator requirement and excludes storage')
exchangeSim.UI.PublishState(Messages.Live,1001,{HP=8000,MaxHP=13500,Regen=30,Damage=240,Status='Module regen only',
    BaseHP=10000,ModuleHP=2500,NeighborHP=1000,BaseRegen=0,ModuleRegen=30,NeighborRegen=0},{army=1});flush()
Panel.Update()
check(label('+10000 from initial HP') and label('+2500 from module HP') and label('+1000 from neighbor storage HP'),'HP source rows use additive amounts without current/max formatting')
check(label('+0 HP/s from non-damage vanilla regen') and label('+30 HP/s from module regen (under fire too)') and label('+0 HP/s from neighbor power regen'),'Live regeneration source rows show only module regen during damage')
state.Chassis='t4';state.BonusSlots=1
for _,id in ipairs({'power_1','power_2','range_1','regen_1','repair_1','deflector','atomized','ballistic','impenetrable'}) do
    state.Installed[id]={Id=id,Quote=R.Core.Quote(state,id,R.Registry,R.Config)}
end
sync();Panel.Update()
check(dock.Height()>=403 and card('impenetrable').Top()==dock.Top()+231,'Storage-supported modules beyond eight wrap into another equipped row')
local before=#controls
for n=1,20 do Panel.Update() end
check(#controls==before,'Status updates preserve image/control identity')
-- Hover surfaces must follow both window movement and scroll offsets.
window.Left:Set(window.Left()+123);window.Top:Set(window.Top()+47);window.Height:Set(260)
local viewport=dock.Parent.FDScrollOwner or dock.Parent
viewport:ScrollTo(80,40)
local root=card('power_1')
root.FDVisual:Hide() -- root surface is decorative; its separate native hit area remains active
check(root.FDHit.AlphaHit==false,'Module hit regions ignore bitmap alpha')
check(root.FDHit.Left()==math.max(root.Left(),viewport.Left()) and root.FDHit.Top()==math.max(root.Top(),viewport.Top()),'Module hover hitbox follows translated/scrolled visual bounds')
root.FDHit:HandleEvent({Type='MouseEnter',MouseX=root.FDHit.Left()+2,MouseY=root.FDHit.Top()+2})
check(not tip.Hidden and tip.Left()>=frame.Left()+8 and tip.Top()>=frame.Top()+8,'Tooltip anchors to the actual hit surface and stays onscreen')
viewport:ScrollTo(80,60)
check(tip.Hidden,'Scrolling clears a stale tooltip')
local captured
function PostDragger(_,_,drag) captured=drag end
local close=window.CloseButton
close.FDHit:HandleEvent({Type='MouseEnter'})
close.FDHit:HandleEvent({Type='ButtonPress',KeyCode=1,Modifiers={Left=true}})
captured:OnRelease(close.Left()+12,close.Top()+12)
check(window.Hidden and tip.Hidden,'Shield close button hides its window and tooltip')
selected={};Panel.Update()
check(window.Destroyed and dock.Destroyed and tip.Destroyed,'Deselecting cleans up dock and floating tooltip')
local saved=preferences.FireDragonStorage['FireDragon.UI']['FireDragon_ModularShields_Window']
selected={{GetEntityId=function() return 1001 end}};Panel.Update()
local reopened=find(function(c) return c.Name=='Modular Shield Window' end)
check(reopened.Left()==saved.left and reopened.Top()==saved.top and reopened.Width()==saved.width and reopened.Height()==saved.height,'shield reselection restores window position and size')
local resizedViewport=card('power_1').Parent.Parent.FDScrollOwner
check(resizedViewport~=nil,'scroll hierarchy exposes its owner')
resizedViewport:RefreshScrollbars()
check(not resizedViewport.HorizontalScrollbar.Hidden,'narrow shield window exposes horizontal scrollbar')
selected={};Panel.Update()
print('PASS: '..count..' image UI/callback checks')
