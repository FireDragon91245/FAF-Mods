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
local function lazy(value)
    return setmetatable({Value=value,Set=function(self,v) self.Value=v end},
        {__call=function(self) if type(self.Value)=='function' then return self.Value() end;return self.Value end})
end
local function control(kind,parent,name)
    local c={Kind=kind,Parent=parent,Name=name,Children={},Width=lazy(0),Height=lazy(0),Left=lazy(0),Top=lazy(0)}
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
    function c:Destroy() self.Destroyed=true;for _,child in ipairs(self.Children) do child:Destroy() end end
    controls[#controls+1]=c;return c
end
local frame=control('frame');frame.Width:Set(1920);frame.Height:Set(1080)
function GetFrame() return frame end
local layout={}
function layout.AtLeftTopIn(c,parent,x,y) c.Left:Set(function() return parent.Left()+x end);c.Top:Set(function() return parent.Top()+y end) end
function layout.AtRightTopIn(c,parent,x,y) c.Left:Set(function() return parent.Left()+parent.Width()-c.Width()-x end);c.Top:Set(function() return parent.Top()+y end) end
function layout.FillParent(c,parent) c.Left:Set(function() return parent.Left() end);c.Top:Set(function() return parent.Top() end);c.Width:Set(function() return parent.Width() end);c.Height:Set(function() return parent.Height() end) end
local UI={bodyFont='body'}
function UI.CreateText(parent,label) local t=control('text',parent);t:SetText(label);return t end
function UI.CreateButtonStd(parent,texture,label)
    assert(texture=='/scx_menu/small-btn/small','Use known native button textures')
    local b=control('button',parent);b.label=UI.CreateText(b,label);b.label:DisableHitTest();return b
end
function import(path)
    if path=='/lua/maui/group.lua' then return {Group=function(parent,name) return control('group',parent,name) end} end
    if path=='/lua/maui/bitmap.lua' then return {Bitmap=function(parent) return control('bitmap',parent) end} end
    if path=='/lua/maui/layouthelpers.lua' then return layout end
    if path=='/lua/ui/uiutil.lua' then return UI end
    if path=='/lua/ui/controls.lua' then return {Get=function() return {constructionGroup={Top=function() return 900 end,IsHidden=function() return false end}} end} end
    if path:find('UI/Model.lua',1,true) then return {Export=loadCore('UI/Model.lua')} end
    error('Unexpected UI import '..path)
end
local state=R.Core.New('t3',{Mass=1000,Energy=10000,Upkeep=100,ShieldMaxHP=10000,ShieldSize=40,ShieldRegen=100})
state.Rules=R.Core
local selected={{GetEntityId=function() return 1001 end}}
function GetSelectedUnits() return selected end
UnitData={[1001]={OtherMod={Keep=true}}}
function OnSync() UnitData=table.merged(UnitData,Sync.UnitData) end
assert(loadfile('src/hook/lua/UserSync.lua'))()
local paused,repairPaused=false,false
local function sync()
    local rows={}
    for _,id in ipairs(R.Registry.Order) do
        local d=R.Registry.Modules[id]
        local reason=R.Core.Eligible(state,id,R.Registry,R.Config,true)
        rows[#rows+1]={Id=id,Family=d.Family,Level=d.Level,Behavior=d.Behavior,Name=d.UI.Name,
            Installed=state.Installed[id]~=nil,Reason=reason and reason.Code or false,
            Detail=reason and (reason.Module or reason.Behavior) or false,
            Deltas={ShieldMaxHP=d.Family=='power' and 2500 or 0,ShieldRegen=d.Family=='regen' and 30 or 0,Upkeep=10},
            Quote=R.Core.Quote(state,id,R.Registry,R.Config)}
    end
    local job=state.Queue[1]
    Sync={UnitData={[1001]={ModularShield={Rows=rows,Used=R.Core.Used(state,R.Registry),Slots=R.Core.Capacity(state,R.Config),Faction='CYBRAN',RemovalSeconds=5,
        BaseSlots=R.Config.Chassis[state.Chassis].Slots,BonusSlots=state.BonusSlots or 0,
        Queue=table.deepcopy(state.Queue),QueueCount=#state.Queue,Stats=R.Stats.Calculate(state,R.Registry,R.Config),
        InstallPaused=paused,RepairPaused=repairPaused,ActualEnergy=100,Assistants=0,WorkRate=40,Barrier='NotInstalled',
        Job=job and {Id=job.JobId,Module=job.ModuleId,Progress=job.PaidWork/job.Quote.Work,State=job.State} or false},
        ModularShieldLive={HP=8000,MaxHP=10000,Regen=100,Damage=240,Status='Regenerating'}}}}
    OnSync()
end
local sent={}
local owned={ModuleAction=function(_,action,value)
    if action=='install' then assert(R.Core.RequestInstall(state,value,R.Registry,R.Config))
    elseif action=='remove' then assert(R.Core.RequestUninstall(state,value,R.Registry,R.Config))
    elseif action=='cancel' then assert(not R.Core.RequestCancel(state,value,R.Registry))
    elseif action=='pause' then paused=not paused
    elseif action=='repair' then repairPaused=not repairPaused end
    sync()
end}
local secureCalled=false
function SecureUnits(units) secureCalled=true;assert(units[1]==owned);return units end
function DoCallback() error('Unexpected fallback') end
assert(loadfile('src/hook/lua/SimCallbacks.lua'))()
function SimCallback(request,withSelection)
    assert(withSelection==true)
    sent[#sent+1]=request;DoCallback(request.Func,request.Args,{owned})
end
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
local dock=find(function(c) return c.Name=='Modular Shield Dock' end)
local tip=find(function(c) return c.Name=='Module Tooltip' end)
check(dock.Left()==(1920-760)/2 and dock.Top()+dock.Height()<900,'Dock is bottom center immediately above the native construction group')
check(label('HP  8000 / 10000').Color==Model.Colors.HP,'Live current/max HP is blue')
check(label('+100 HP/s  Regenerating').Color==Model.Colors.Regen,'Live regeneration is green')
check(label('-240 HP/s  (5s avg)').Color==Model.Colors.Damage,'Rolling incoming damage is red')
local power1=card('power_1')
check(not power1.Hidden and card('power_2').Hidden,'Upgrade row shows the next module level of each family')
local image=find(function(c) return c.Parent==power1 and c.Texture end)
check(image.Texture:find('cybran_power_1.dds',1,true),'Module icon uses its faction-specific texture')
hover(power1)
check(not tip.Hidden and label('+2500 maximum shield HP').Color==Model.Colors.HP,'Native hover popup shows capacity change in blue')
click(power1)
check(secureCalled and sent[1].Args.Action=='install' and #state.Queue==1,'Image click reaches the secured install callback')
check(power1.Top()==dock.Top()+158 and image.Texture:find('_dim.dds',1,true),'Queued icon moves to modules row and is grayed out')
check(label('0%') and not label('0%').Hidden,'Pending icon overlays installation percentage')
check(not card('power_2').Hidden,'Queuing a prerequisite exposes the next upgrade')
local job=state.Queue[1];job.PaidWork=job.Quote.Work*.5;job.State='Building'
sync();Panel.Update()
check(label('50%') and not label('50%').Hidden,'Paid progress refreshes the image overlay in place')
click(card('power_2'))
click(power1,true)
check(#state.Queue==0 and power1.Top()==dock.Top()+231 and card('power_2').Hidden,'Right-click cancels pending module and dependent queue')
check(not UnitData[1001].ModularShield.Job and #UnitData[1001].ModularShield.Queue==0,'Snapshot merge clears cancelled job and queue tails')
check(UnitData[1001].OtherMod.Keep,'Module snapshot leaves unrelated unit data intact')
click(power1);job=state.Queue[1];job.PaidWork=job.Quote.Work
assert(not R.Core.Complete(state,job,R.Registry,R.Config));sync();Panel.Update()
check(power1.Top()==dock.Top()+158 and not image.Texture:find('_dim',1,true),'Completed module remains equipped with full-color icon')
hover(power1)
check(label('-2500 maximum shield HP on removal').Color==Model.Colors.HP,'Installed-module tooltip previews the actual loss on removal in blue')
click(power1,true)
check(state.Installed.power_1 and state.Queue[1].Kind=='Remove','Right-click queues timed removal instead of instantly deinstalling')
check(label('REMOVE') and image.Texture:find('_dim.dds',1,true),'Removal has a gray icon and explicit removal overlay')
click(power1,true)
check(state.Installed.power_1 and #state.Queue==0,'Right-clicking removal cancels it and keeps installed module')
click(power1,true);job=state.Queue[1];job.PaidWork=job.Quote.Work
assert(not R.Core.Complete(state,job,R.Registry,R.Config));sync();Panel.Update()
check(not state.Installed.power_1 and power1.Top()==dock.Top()+231,'Finished removal returns icon to available upgrades')
hover(card('deflector'))
check(label('Deflects crashing aircraft and selected').Color==Model.Colors.Special,'Special effect hover descriptions are orange')
card('deflector'):HandleEvent({Type='MouseExit'})
check(tip.Hidden,'Moving away closes the tooltip')
check(label('Deflects crashing aircraft and selected').Hidden,'Tooltip child text also hides without leaving ghosts')
hover(card('impenetrable'))
check(label('[missing] Deflector') and label('[missing] Atomized (nuclear containment)') and label('[missing] Ballistic (missile defense)'),'Impenetrable lists all three special-module requirements separately')
check(label('T1 generators and all storage are excluded.'),'Impenetrable explains the T2+ generator requirement and excludes storage')
UnitData[1001].ModularShieldLive={HP=8000,MaxHP=13500,Regen=30,Damage=240,Status='Module regen only',
    BaseHP=10000,ModuleHP=2500,NeighborHP=1000,BaseRegen=0,ModuleRegen=30,NeighborRegen=0}
Panel.Update()
check(label('+10000 from initial HP') and label('+2500 from module HP') and label('+1000 from neighbor storage HP'),'HP source rows use additive amounts without current/max formatting')
check(label('+0 HP/s from non-damage vanilla regen') and label('+30 HP/s from module regen (under fire too)') and label('+0 HP/s from neighbor power regen'),'Live regeneration source rows show only module regen during damage')
state.Chassis='t4';state.BonusSlots=1
for _,id in ipairs({'power_1','power_2','range_1','regen_1','repair_1','deflector','atomized','ballistic','impenetrable'}) do
    state.Installed[id]={Id=id,Quote=R.Core.Quote(state,id,R.Registry,R.Config)}
end
sync();Panel.Update()
check(dock.Height()==403 and card('impenetrable').Top()==dock.Top()+231,'Storage-supported modules beyond eight wrap into another equipped row')
local before=#controls
for n=1,20 do Panel.Update() end
check(#controls==before,'Status updates preserve image/control identity')
selected={};Panel.Update()
check(dock.Destroyed and tip.Destroyed,'Deselecting cleans up dock and floating tooltip')
print('PASS: '..count..' image UI/callback checks')
