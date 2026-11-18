local Bindings=assert(loadfile('src/lua/FireDragon/Bindings.lua'))()
-- Headless Maui contract and routed-input regression checks.
table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
local controls={}
-- Cache computations and track dependencies like Maui; plain scalar changes do
-- not invalidate layout. The previous always-recomputing mock hid slider bugs.
local evaluating
local function dirty(var)
    if var.Dirty then return end
    var.Dirty=true
    for user in pairs(var.Users) do dirty(user) end
end
local function lazy(v)
    local var={v=v,Dirty=true,Users={},Uses={}}
    function var:Set(value) self.v=value;dirty(self) end
    return setmetatable(var,{__call=function(self)
        if self.Dirty then
            for dependency in pairs(self.Uses) do dependency.Users[self]=nil end
            self.Uses={}
            local previous=evaluating;evaluating=self
            self.Cached=type(self.v)=='function' and self.v() or self.v
            evaluating=previous;self.Dirty=false
        end
        if evaluating then self.Users[evaluating]=true;evaluating.Uses[self]=true end
        return self.Cached
    end})
end
local function control(parent,name)
    local c={Parent=parent,Name=name,Children={}}
    for _,k in ipairs({'Left','Top','Width','Height','Depth'}) do c[k]=lazy(0) end
    c.Right=lazy(function() return c.Left()+c.Width() end);c.Bottom=lazy(function() return c.Top()+c.Height() end)
    if parent then table.insert(parent.Children,c) end
    function c:DisableHitTest() self.NoHit=true end
    function c:EnableHitTest() self.NoHit=false end
    c.TextAdvance=lazy(0);c.FontAscent=lazy(11);c.FontDescent=lazy(3)
    function c:SetText(v) self.Text=v;self.TextAdvance:Set(#v*7) end
    function c:SetDropShadow(v) self.DropShadow=v end
    function c:GetText() return self.Text end
    function c:SetFont() end
    function c:SetForegroundColor() end
    function c:SetBackgroundColor() end
    function c:ShowBackground() end
    function c:SetMaxChars() end
    function c:EnableInput() self.InputEnabled=true end
    function c:DisableInput() self.InputEnabled=false end
    function c:AcquireFocus() self.Focused=true end
    function c:SetColor(v) self.Color=v end
    function c:SetSolidColor(v) self.Color=v;self.Texture=nil end
    function c:SetTexture(v) self.Texture=v;self.Color=nil end
    function c:SetClipToWidth(v) self.Clip=v end
    function c:SetCenteredHorizontally(v) self.CenteredHorizontally=v end
    function c:SetCenteredVertically(v) self.CenteredVertically=v end
    function c:SetUV(...) self.UV={...} end
    function c:SetAlpha(v) self.Alpha=v end
    function c:GetStringAdvance(s) return #s*7 end
    function c:UseAlphaHitTest(v) self.AlphaHit=v end
    function c:SetNeedsFrameUpdate(v) self.Updates=v end
    -- Native Maui propagates visibility into descendants, clearing page flags.
    local function propagate(node,hidden)
        node.Hidden=hidden
        if node.OnHide and node:OnHide(hidden) then return end
        for _,child in ipairs(node.Children) do if not child.Destroyed then propagate(child,hidden) end end
    end
    function c:Hide() assert(not self.Destroyed);propagate(self,true) end
    function c:Show() assert(not self.Destroyed);propagate(self,false) end
    function c:IsHidden() return self.Hidden end
    function c:GetRootFrame() return GetFrame(0) end
    function c:Destroy() self.Destroyed=true;if self.OnDestroy then self:OnDestroy() end;for _,child in ipairs(self.Children) do child:Destroy() end end
    controls[#controls+1]=c;return c
end
local frame=control(nil,'frame');frame.Width:Set(1920);frame.Height:Set(1080)
function GetFrame() return frame end
local drag
function PostDragger(_,_,d) drag=d end
local UIUtil={bodyFont='body',buttonFont='button',SkinnableFile=function(p) return '/skin'..p end}
function UIUtil.CreateText(parent,text) local c=control(parent);c:SetText(text);return c end
local ui,storage,exchange
local savedPreferences={}
function SavePreferences() end
function import(path)
        if string.find(path,'FireDragon/Bindings.lua',1,true) then return {Export=Bindings} end
    if path:find('FireDragon/InformationExchange.lua',1,true) then return {Export=exchange} end
    if path:find('FireDragon/Storage.lua',1,true) then return {Export=storage} end
    if path=='/lua/user/prefs.lua' then return {GetCurrentProfile=function() return savedPreferences end,GetFromCurrentProfile=function(k) return savedPreferences[k] end,SetToCurrentProfile=function(k,v) savedPreferences[k]=v end} end
    if path=='/lua/maui/layouthelpers.lua' then return {ScaleNumber=function(v) return v end,InvScaleNumber=function(v) return v end} end
    if path=='/lua/maui/group.lua' then return {Group=control} end
    if path=='/lua/maui/bitmap.lua' then return {Bitmap=control} end
    if path=='/lua/maui/edit.lua' then return {Edit=control} end
    if path=='/lua/maui/dragger.lua' then return {Dragger=function() return control() end} end
    if path=='/lua/ui/uiutil.lua' then return UIUtil end
    if path:find('FireDragon/UI.lua',1,true) then return {Export=ui} end
    if path:find('FireDragonDebugTools/Messages.lua',1,true) then return {Export=assert(loadfile('../FireDragon Debug Tools/src/lua/FireDragonDebugTools/Messages.lua'))()} end
    if path:find('Keys.lua',1,true) then return {DefaultKey='Alt-Shift-D'} end
    error(path)
end
storage=assert(loadfile('src/lua/FireDragon/Storage.lua'))()
exchange=assert(loadfile('src/lua/FireDragon/InformationExchange.lua'))()
ui=assert(loadfile('src/lua/FireDragon/UI.lua'))()
local checks=0
local function check(v,m) checks=checks+1;assert(v,m) end
local w=ui.Window(frame,{x=100,y=100,width=300,height=200,minWidth=240,minHeight=160,title='Test'})
w:SetSize(10,10);check(w.Width()==240 and w.Height()==160,'minimum window size')
w.TitleBar:HandleEvent({Type='ButtonPress',MouseX=110,MouseY=110,KeyCode=1});drag:OnMove(210,220);drag:OnRelease()
check(w.Left()==200 and w.Top()==210,'captured drag moves window')
w.ResizeGrip:HandleEvent({Type='ButtonPress',MouseX=w.ResizeGrip.Left()+1,MouseY=w.ResizeGrip.Top()+1,KeyCode=1});drag:OnMove(w.ResizeGrip.Left()+101,w.ResizeGrip.Top()+101);drag:OnRelease()
check(w.Width()==340 and w.Height()==260,'resize grip uses captured drag')
w:SetDraggable(false);drag=nil;w.TitleBar:HandleEvent({Type='ButtonPress',MouseX=0,MouseY=0});check(drag==nil,'position lock')
w:SetResizable(false);check(w.ResizeGrip.Hidden,'size lock hides grip')
local tabs=ui.Tabs(w.Client);ui.Fill(tabs,w.Client)
local a=tabs:Add('a','First');local b=tabs:Add('b','Second');check(not a.Hidden and b.Hidden,'initial tab')
tabs:Select('b');check(a.Hidden and not b.Hidden,'tab switch')
check(tabs.Buttons.b.FDVisual.Texture:find('small_btn_down.dds',1,true),'selected tab uses native down texture, not a solid overlay')
tabs.Buttons.b:HandleEvent({Type='MouseEnter'})
check(tabs.Buttons.b.FDVisual.Texture:find('small_btn_down.dds',1,true),'selected tab keeps its texture on hover')
check(tabs.Buttons.b.Label.FDVisual.Color=='ff000000','selected tab uses black text against its bright background')
tabs.Buttons.a:HandleEvent({Type='MouseEnter'})
check(tabs.Buttons.a.Label.FDVisual.Color=='ff000000','hovered button retains readable contrast')
tabs.Buttons.a:HandleEvent({Type='MouseExit'})
check(tabs.Buttons.a.Label.FDVisual.Color==ui.Theme.Text,'leaving hover restores the normal caption color')
local symbol=ui.Button(b,{width=28,height=28,text='+'})
check(symbol.Label.Left()==math.floor(symbol.Left()+(symbol.Width()-symbol.Label.Width())/2) and symbol.Label.Top()==math.floor(symbol.Top()+(symbol.Height()-symbol.Label.Height())/2),'button glyphs use measured pixel-aligned centering')
check(symbol.Label.FDVisual.DropShadow==false,'captions render without a washed-out shadow')
symbol:OnFrame()
check(symbol.FDVisual.UV[1]==8/200 and symbol.FDVisual.UV[2]==14/72 and symbol.FDVisual.UV[4]==60/72,'button art excludes its transparent outer margin')
symbol.Width:Set(80);symbol.Height:Set(40);symbol.Label:SetText('II')
check(symbol.Label.Width()==14 and symbol.Label.Left()==math.floor(symbol.Left()+33) and symbol.Label.Top()==math.floor(symbol.Top()+13),'caption measurement and centering follow resizing and text changes')
symbol:SetTextColor('ff74e4bb');symbol:HandleEvent({Type='MouseEnter'});symbol:SetTextColor('ff74e4bb')
check(symbol.Label.FDVisual.Color=='ff000000','status refresh cannot override hover contrast')
symbol:HandleEvent({Type='MouseExit'});symbol:SetEnabled(false)
check(symbol.Label.FDVisual.Color==ui.Theme.Muted,'disabled button uses muted text')
tabs:Add('custom','Narrow',{width=92})
check(tabs.Buttons.custom.Width()==92 and tabs.Buttons.custom.Left()==tabs.Buttons.b.Right()+4,'individual tab widths preserve adjacent layout')
tabs:Add('tail','Last',{width=64})
tabs:Remove('custom')
check(tabs.Buttons.tail.Left()==tabs.Buttons.b.Right()+4,'removing an unequal-width tab closes its gap')
tabs:Remove('tail')
local slider=ui.Slider(b,{width=200,min=0,max=10,step=1})
local initialLeft=slider.Thumb.Left()
slider:SetValue(5,true)
check(slider.Thumb.Left()>initialLeft and slider.Thumb.Left()==slider.Left()+84,'slider invalidates cached thumb geometry')
check(slider.Thumb.FDVisual.Texture:find('/slider02/slider_btn_up.dds',1,true),'slider uses vanilla thumb texture')
local commits,previews=0,0
local scrub=ui.Slider(b,{width=200,min=0,max=100,step=10,
    onPreview=function() previews=previews+1 end,onChange=function() commits=commits+1 end})
scrub:HandleEvent({Type='ButtonPress',MouseX=scrub.Left()+16+168*.2,KeyCode=1})
drag:OnMove(scrub.Left()+16+168*.5,0)
scrub:OnFrame(.2)
check(commits==0 and previews==2,'drag previews update locally without submitting')
drag:OnMove(scrub.Left()+16+168*.8,0);scrub:OnFrame(.29)
check(commits==0 and scrub.Value==80,'motion restarts the idle delay')
scrub:OnFrame(.02)
check(commits==1,'idle sends one latest value')
drag:OnRelease()
check(commits==1,'release after idle does not repeat the same update')
scrub:HandleEvent({Type='ButtonPress',MouseX=scrub.Left()+16+168*.4,KeyCode=1});drag:OnRelease()
check(commits==2 and scrub.Value==40,'release immediately commits the final value')
local status1,status2='pending','pending'
local ticket1={Status=function() return status1 end}
local ticket2={Status=function() return status2 end}
local writes=0
local optimistic=ui.Checkbox(b,{onCheck=function() writes=writes+1;return writes==1 and ticket1 or ticket2 end})
optimistic:SetCheck(true);optimistic:SetCheck(false,true)
check(optimistic.Checked,'pending checkbox ignores stale confirmed value')
optimistic:SetCheck(false);status1='complete';optimistic:SetCheck(true,true)
check(not optimistic.Checked,'older confirmation cannot overwrite a newer toggle')
status2='failed';optimistic:SetCheck(true,true)
check(optimistic.Checked,'rejected latest toggle restores confirmed value')
status2='pending'
local numeric=ui.NumberInput(b,{width=220,min=0,max=100,step=10,onChange=function() return ticket2 end})
numeric:SetValue(30);numeric:SetValue(0,true)
check(numeric.Value==30 and numeric.Input:GetText()=='30','pending numeric control preserves its local value')
status2='complete';numeric:SetValue(30,true)
numeric.Slider:HandleEvent({Type='ButtonPress',MouseX=numeric.Slider.Left()+16+100*.7,KeyCode=1})
numeric:SetValue(30,true)
check(numeric.Value==70 and numeric.Input:GetText()=='70','refresh cannot reset an unsubmitted slider preview')
drag:OnRelease()
check(numeric.Input.FrameParts[1].FDVisual.Texture:find('/game/chat_brd/',1,true),'numeric entry uses the vanilla frame')
local scroll=ui.Scroll(b,{width=100,height=80,contentWidth=500,contentHeight=400})
check(scroll.HorizontalScrollbar.FDVisual.Texture:find('/scrollbar/horizontal-back.dds',1,true) and scroll.HorizontalThumb.FDVisual.Texture:find('/scrollbar/horizontal-thumb.dds',1,true),'horizontal scrollbar uses rotated vanilla art instead of solid blue colors')
local icon=ui.Icon(scroll.Content,{x=80,y=60,width=60,height=60,texture='test'})
icon:OnFrame(0)
check(icon.Width()==60 and icon.FDVisual.Width()==8 and icon.FDVisual.Height()==8,'overflow cropped without shrinking layout')
check(math.abs(icon.FDVisual.UV[3]-8/60)<0.0001,'cropped icon preserves UV scale')
ui.Interactive(icon);check(icon.FDHit.Width()==8 and icon.FDHit.Height()==8,'input region clipped with image')
scroll:ScrollTo(999,999);check(scroll.OffsetX==412 and scroll.OffsetY==332,'scroll clamp both axes')
scroll:ScrollTo(0,0);scroll:HandleEvent({Type='WheelRotation',WheelRotation=-120});check(scroll.OffsetY==72,'wheel scroll')
scroll.Content.Height:Set(10);scroll:OnFrame(0);check(scroll.OffsetY==0,'content shrink clamps offset')
local grid=ui.Grid(a,{columns=2,cellWidth=40,cellHeight=30,gap=5})
local cells={}
for i=1,3 do cells[i]=grid:Add(ui.Panel(grid)) end
check(cells[3].Left()==grid.Left() and cells[3].Top()==grid.Top()+35,'grid wrap')
local bar=ui.Bar(a,{width=100,value=0.5});bar.Width:Set(200);check(bar.Fill.Width()==100,'bar follows resize')
local n=0;local bound=ui.Label(a);local cancel=ui.Bind(bound,function() return n end,function(v,c) c:SetText(tostring(v)) end)
n=2;bound:OnFrame(0.2);check(bound.FDText=='2','live binding updates');cancel();n=3;bound:OnFrame(0.2);check(bound.FDText=='2','cancel binding')
local circle=ui.Shape(a,{kind='circle',width=40,height=40,color='ffffffff'});check(#circle.FDChildren==48,'procedural circle')
local blur=ui.Blur(a,{texture='test'});check(#blur.FDChildren==9,'blur samples')
w:Destroy();check(icon.Destroyed and blur.Destroyed,'window destroys owned tree')
-- Route through native-style hit surfaces, respecting visibility, alpha and depth.
local function hidden(c)
    while c do if c.Hidden or c.Destroyed then return true end;c=c.Parent end
    return false
end
local function at(x,y)
    local best
    for _,c in ipairs(controls) do
        if not hidden(c) and not c.NoHit and c.HandleEvent and c.Width()>0 and c.Height()>0 then
            local inBounds=x>=c.Left() and x<c.Right() and y>=c.Top() and y<c.Bottom()
            local alphaBlocked=c.Color=='00000000' and c.AlphaHit~=false
            if inBounds and not alphaBlocked and (not best or c.Depth()>=best.Depth()) then best=c end
        end
    end
    return best
end
local function pointer(c,kind,x,y)
    x=x or (c.Left()+c.Width()/2);y=y or (c.Top()+c.Height()/2)
    local target=assert(at(x,y),'No pointer target')
    local event={Type=kind or 'ButtonPress',MouseX=x,MouseY=y,KeyCode=1,Modifiers={Left=true}}
    local original=target
    while target do if target.HandleEvent and target:HandleEvent(event) then break end;target=target.Parent end
    return original,x,y
end
local testWindow=ui.Window(frame,{x=100,y=100,width=400,height=220,title='Input regression'})
local clicks=0
local button=ui.Button(testWindow.Client,{x=20,y=20,width=100,height=28,text='Click',onClick=function() clicks=clicks+1 end})
check(button.FDHit.AlphaHit==false,'hit surfaces explicitly ignore alpha')
pointer(button,'MouseEnter');check(button.Hovered and button.FDVisual.Texture:find('_over.dds',1,true),'vanilla hover state')
local target,x,y=pointer(button)
check(target==button.FDHit and button.Pressed and clicks==0,'pointer reaches button and waits for release')
drag:OnRelease(x,y);check(clicks==1 and not button.Pressed,'release activates button')
pointer(button);drag:OnRelease(1,1);check(clicks==1,'release outside cancels click')
button:SetEnabled(false);pointer(button);check(clicks==1,'disabled button blocks activation');button:SetEnabled(true)
local otherWindow=ui.Window(frame,{x=100,y=100,width=400,height=220,title='Overlap'})
testWindow:Focus()
check(testWindow.Depth()>otherWindow.ResizeGrip.FDHit.Depth(),'focus raises the entire window above the other window chrome')
otherWindow:Destroy()
savedPreferences.test_window={left=50,top=60,width=350,height=250}
local remembered=ui.Window(frame,{x=20,y=30,width=300,height=200,prefKey='test.window'})
check(remembered.Left()==20 and remembered.Top()==30 and remembered.Width()==300 and remembered.Height()==200,'window ignores legacy flat profile geometry')
remembered:SetSize(450,320);remembered.Left:Set(180);remembered.Top:Set(210);remembered:Destroy()
check(storage.Get('FireDragon.UI','test.window').width==450,'window saves geometry through shared storage with exact keys')
check(savedPreferences.test_window.width==350,'new writes leave legacy geometry intact')
local restored=ui.Window(frame,{width=200,height=150,prefKey='test.window'})
check(restored.Width()==450 and restored.Height()==320 and restored.Left()==180 and restored.Top()==210,'window restores saved position and size after destruction')
restored.Left:Set(9999);restored.Top:Set(9999);restored:Close();restored:Destroy()
restored=ui.Window(frame,{prefKey='test.window'})
check(restored.Right()<=frame.Right() and restored.Bottom()<=frame.Bottom(),'saved offscreen positions clamp to frame')
restored:Destroy()
local noScroll=ui.Scroll(testWindow.Client,{x=150,width=180,height=150,contentWidth=180,contentHeight=100})
check(noScroll.Scrollbar.Hidden and noScroll.HorizontalScrollbar.Hidden,'unneeded scrollbars initially hidden')
noScroll.Content.Width:Set(400);noScroll:OnFrame(0)
check(not noScroll.HorizontalScrollbar.Hidden and noScroll.Viewport.Height()==138,'horizontal overflow shows track and reserves space')
local track=noScroll.HorizontalScrollbar
pointer(track)
check(noScroll.OffsetX>0,'horizontal track click scrolls content')
local thumb=noScroll.HorizontalThumb
local _,hx,hy=pointer(thumb);drag:OnMove(hx+30,hy);drag:OnRelease()
check(noScroll.OffsetX>0 and noScroll.Content.Left()<noScroll.Left(),'horizontal thumb dragging moves content')
noScroll.Content.Width:Set(180);noScroll:OnFrame(0)
check(noScroll.HorizontalScrollbar.Hidden and noScroll.OffsetX==0,'horizontal track hides and offset clamps when content fits')
noScroll.Content.Height:Set(400);noScroll:OnFrame(0);check(not noScroll.Scrollbar.Hidden,'overflow shows scrollbar')
noScroll.Content.Height:Set(50);noScroll:OnFrame(0);check(noScroll.Scrollbar.Hidden,'content shrink hides scrollbar')
local _,cx,cy=pointer(testWindow.CloseButton);drag:OnRelease(cx,cy)
check(testWindow.Hidden and at(cx,cy)~=testWindow.CloseButton.FDHit,'close button hides window and input tree')
-- Exercise the real debug UI: clicks remain secured sim requests and sync is silent.
local sent={}
local economyRevision=0
exchange.StateRevision=function() return economyRevision end
exchange.Sim={Request=function(topic,data)
    sent[#sent+1]={Topic=topic,Args=data}
    local once=false
    return {Status=function() return 'complete' end,Poll=function()
        if once then return nil end;once=true;return {value={Accepted=true},confirmation={revision=0}}
    end}
end}
local function economy(data)
    economyRevision=economyRevision+1
    exchange.PublishState('FireDragonDebugTools.Economy','1',data);Bindings.Step()
    for _,c in ipairs(controls) do if not c.Destroyed and c.FDWindow and c.OnFrame then c:OnFrame(.2) end end
end
local focusArmy=1
function GetFocusArmy() return focusArmy end
local env=setmetatable({}, {__index=_G})
assert(loadfile('../FireDragon Debug Tools/src/lua/FireDragonDebugTools/Panel.lua','t',env))()
economy({Energy=false,Mass=false})
env.Toggle()
local box
for _,c in ipairs(controls) do if c.Checked~=nil and c.Label.FDText:find('Infinite Energy',1,true) then box=c end end
check(box~=nil,'debug window uses shared checkbox')
check(box.Check.FDVisual.Texture:find('/CHECKBOX/d_up.dds',1,true) and box.Label.FDText=='Infinite Energy','checkbox uses square vanilla art and separate label')
pointer(box,'MouseEnter');check(box.Check.FDVisual.Texture:find('d_over.dds',1,true),'checkbox hover graphic')
local _,bx,by=pointer(box);check(sent[1].Args.Resource=='ENERGY' and sent[1].Args.Enabled,'debug click callback')
economy({Energy=true,Mass=false});check(box.Checked and #sent==1,'sync updates without feedback')
local debugWindow=box
while not debugWindow.FDWindow do debugWindow=debugWindow.FDParent end
check(debugWindow.FDWindow,'debug tabs mount inside shared window')
local _,dx,dy=pointer(debugWindow.CloseButton);drag:OnRelease(dx,dy);check(debugWindow.Hidden,'debug close routes correctly')
for _,c in ipairs(controls) do if not c.Destroyed and c.Updates and c.OnFrame then c:OnFrame(0.2) end end
check(debugWindow.FDVisual.Hidden and box.Check.FDVisual.Hidden and box.Label.FDVisual.Hidden,'closed debug window stays visually hidden across frame refreshes')
local function allVisualsHidden(node)
    if node.FDVisual and not node.FDVisual.Hidden then return false end
    for _,child in ipairs(node.FDChildren or {}) do if not allVisualsHidden(child) then return false end end
    return true
end
check(allVisualsHidden(debugWindow),'all window frame, label and icon renderers remain hidden after close')
economy({Energy=false,Mass=true})
check(box.Label.FDVisual.Hidden,'sync cannot reveal a closed window')
env.Toggle()
for _,c in ipairs(controls) do if not c.Destroyed and c.Updates and c.OnFrame then c:OnFrame(0.2) end end
check(not debugWindow.FDVisual.Hidden and not box.Check.FDVisual.Hidden and not box.Label.FDVisual.Hidden,'reopening restores rendering')
check(not debugWindow.Hidden and at(box.Left()+30,box.Top()+10)==box.FDHit,'debug reopen restores mouse input')
local debugTabs
for _,child in ipairs(debugWindow.Client.FDChildren) do if child.Pages then debugTabs=child end end
check(debugTabs.Pages.vanilla and not debugTabs.Pages.shields,'Vanilla always visible; shields tab absent without parameter')
local schema=assert(loadfile('../Modular Shields/src/lua/ModularShields/DebugParameters.lua'))()
local Transport=assert(loadfile('src/lua/FireDragon/ExchangeTransport.lua'))()
local simBus=exchange.New()
local commands,packets={},{}
local actor={army=1,player=0,actor=true,cheats=true}
local server=Transport.Attach(simBus,{realm='Sim',clock=function() return 0 end,send=function(packet) packets[#packets+1]=packet end})
local client=Transport.Attach(exchange,{realm='UI',session='debug-ui',clock=function() return 0 end,
    send=function(packet) commands[#commands+1]=packet end})
local function flush()
    local batch=commands;commands={}
    for _,packet in ipairs(batch) do server.Receive(packet,actor) end
    server.Flush()
    for _,packet in ipairs(packets) do client.Receive(packet) end
    packets={};Bindings.Step()
end
local schemaOwner=simBus.PublishConfig(schema.SchemaKey,schema.Fields,'ReadOnly',nil,nil,{scope='Sim'})
local published=simBus.PublishConfig(schema.Key,schema.Defaults(),'ReadWrite',function(values)
    sent[#sent+1]={Config=values}
end,schema.Validate,{scope='Sim',authorize='Cheats'})
flush()
debugWindow:OnFrame(.2)
check(debugTabs.Pages.shields~=nil,'published parameter makes shield tab appear live')
for _,button in pairs(debugTabs.Buttons) do
    check(button.Height()>=32 and button.Width()>=button.Label.FDVisual:GetStringAdvance(button.Label.FDText)+32,'debug tabs have room around their captions')
    check(button.Right()<=debugTabs.Right(),'debug tabs fit the window')
end
debugWindow:SetSize(debugWindow.MinWidth,debugWindow.MinHeight)
check(debugTabs.Buttons.shields.Right()<=debugTabs.Right(),'both debug tabs fit at minimum window width')
debugTabs:Select('shields')
check(debugTabs.Buttons.vanilla.Width()<debugTabs.Buttons.shields.Width(),'tabs size individually to their captions')
for cycle=1,3 do
    debugWindow:Close();env.Toggle()
    for _,c in ipairs(controls) do if not c.Destroyed and c.Updates and c.OnFrame then c:OnFrame(.2) end end
    check(debugTabs.Pages.vanilla.Hidden and not debugTabs.Pages.shields.Hidden and allVisualsHidden(debugTabs.Pages.vanilla),'reopening preserves the selected page and hides all inactive renderers')
    check(at(box.Left()+30,box.Top()+10)~=box.FDHit,'inactive vanilla checkbox cannot intercept input')
end
local numbers={}
local ignore
local function visit(node)
    if node.Input and node.Slider then numbers[#numbers+1]=node end
    if node.Checked~=nil and node.Label.FDText=='Ignore Resources' then ignore=node end
    for _,child in ipairs(node.FDChildren or {}) do visit(child) end
end
visit(debugTabs.Pages.shields)
check(#numbers==4 and ignore~=nil,'shield tab uses two boolean and four numeric controls')
local hp,regen,slots,repair=numbers[1],numbers[2],numbers[3],numbers[4]
hp.Input.Edit:SetText('4');hp.Input.Edit:OnEnterPressed('4')
check(exchange.Get(schema.Key).HPMultiplier==1,'UI edit waits for Sim authority')
debugWindow:OnFrame(.2)
check(hp.Value==4 and hp.Slider.Value==4,'stale configuration refresh preserves pending numeric input')
flush()
check(hp.Value==4 and hp.Slider.Value==4 and exchange.Get(schema.Key).HPMultiplier==4,'text entry updates slider and publisher')
hp.Input.Edit:SetText('99');hp.Input.Edit:OnEnterPressed('99')
flush()
check(hp.Value==10 and hp.Input:GetText()=='10','text value clamps to HP maximum')
local sentBefore=#sent
hp.Input.Edit:SetText('bad');hp.Input.Edit:OnEnterPressed('bad')
check(hp.Input:GetText()=='10' and #sent==sentBefore,'invalid numeric text resets without publishing')
regen.Slider:HandleEvent({Type='ButtonPress',MouseX=regen.Slider.Left()+5+(regen.Slider.Width()-10)*.345,KeyCode=1})
drag:OnRelease()
flush()
check(math.mod(regen.Value,100)==0 and exchange.Get(schema.Key).AdditionalRegen==regen.Value,'regen slider publishes in steps of 100')
slots.Input.Edit:SetText('17');slots.Input.Edit:OnEnterPressed('17')
repair.Input.Edit:SetText('400');repair.Input.Edit:OnEnterPressed('400')
flush()
check(exchange.Get(schema.Key).AdditionalSlots==17 and exchange.Get(schema.Key).AdditionalRepair==400,'slots and repair text controls publish independently')
ignore:SetCheck(true)
debugWindow:OnFrame(.2)
check(ignore.Checked and not exchange.Get(schema.Key).IgnoreResources,'pending shield checkbox stays checked before acknowledgement')
flush()
check(exchange.Get(schema.Key).IgnoreResources,'boolean shield control edits shared ReadWrite config')
actor.cheats=false;ignore:SetCheck(false);debugWindow:OnFrame(.2)
check(not ignore.Checked,'pending disabled checkbox does not flash back on')
flush();debugWindow:OnFrame(.2)
check(ignore.Checked and exchange.Get(schema.Key).IgnoreResources,'denied edit is restored from authoritative values')
check(exchange.ConfigStatus(schema.Key).denied,'UI reads denial from generic exchange status')
debugTabs:Select('vanilla');hp.Input:OnFrame()
check(hp.Input.Edit.Hidden,'native text input hides when its tab is hidden')
debugWindow:Close();env.Toggle();hp.Input:OnFrame()
check(debugTabs.Pages.shields.Hidden and allVisualsHidden(debugTabs.Pages.shields) and hp.Input.Edit.Hidden,'reopening Vanilla does not expose shield controls or native inputs')
published:Close();schemaOwner:Close();flush();debugWindow:OnFrame(.2)
check(not debugTabs.Pages.shields and debugTabs.Pages.vanilla,'removing parameter removes only shield tab')
debugWindow:Close();env.Toggle()
check(not debugWindow.Hidden,'reopening safely skips removed tab controls')
-- Bound slider drafts are shared immediately, but only commits send messages.
local boundWrites=0
local rejectBound=false
exchange.PublishConfig('slider-local',{n=0},'ReadWrite',function() boundWrites=boundWrites+1 end,function() return not rejectBound end)
local shared=Bindings.Config(exchange,'slider-local')
local n1=ui.NumberInput(frame,{width=300,min=0,max=100,step=10,binding={journal=shared,path={'n'}}})
local n2=ui.NumberInput(frame,{width=300,min=0,max=100,step=10,binding={journal=shared,path={'n'}}})
n1.Slider:HandleEvent{Type='ButtonPress',MouseX=n1.Slider.Left()+16+(n1.Slider.Width()-32)*.7,KeyCode=1}
check(n1.Value==70 and n2.Value==70 and boundWrites==0,'bound slider previews update all observers without sending')
n1.Slider:OnFrame(.4)
check(boundWrites==1 and n2.Value==70,'bound idle commit sends once')
drag:OnRelease();check(boundWrites==1,'bound release after idle does not resubmit')
n2.Input.Edit:SetText('86');n2.Input.Edit:OnEnterPressed()
check(n1.Value==90 and n2.Value==90 and boundWrites==2,'bound typed Enter shares stepped numeric value')
n1:Destroy();n2:SetValue(40)
check(shared:Get().n==40,'destroyed numeric binding leaves other control usable')
rejectBound=true
n2.Slider:HandleEvent{Type='ButtonPress',MouseX=n2.Slider.Left()+16+(n2.Slider.Width()-32)*.7,KeyCode=1}
n2.Slider:OnFrame(.4);drag:OnRelease()
check(n2.Value==40 and n2.Slider.Value==40,'rejection during an idle drag reconciles when the drag ends')
exchange.PublishState('FireDragonDebugTools.Economy','2',{Energy=true,Mass=false})
focusArmy=2;Bindings.Step()
check(box.Checked and box.FDEnabled,'focus-army binding switches targets without a mod refresh')
focusArmy=3;Bindings.Step()
check(not box.Checked and not box.FDEnabled,'missing target cannot display the previous army state')
focusArmy=1;Bindings.Step()
check(not box.Checked and box.FDEnabled,'returning to an available army restores its own state and input')
print('PASS: '..checks..' shared UI and debug window checks')
