-- Headless Maui contract and routed-input regression checks.
table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
local controls={}
local function lazy(v) return setmetatable({Set=function(self,x) self.v=x end,v=v},{__call=function(self) if type(self.v)=='function' then return self.v() end;return self.v end}) end
local function control(parent,name)
    local c={Parent=parent,Name=name,Children={}}
    for _,k in ipairs({'Left','Top','Width','Height','Depth'}) do c[k]=lazy(0) end
    c.Right=lazy(function() return c.Left()+c.Width() end);c.Bottom=lazy(function() return c.Top()+c.Height() end)
    if parent then table.insert(parent.Children,c) end
    function c:DisableHitTest() self.NoHit=true end
    function c:EnableHitTest() self.NoHit=false end
    function c:SetText(v) self.Text=v end
    function c:SetColor(v) self.Color=v end
    function c:SetSolidColor(v) self.Color=v end
    function c:SetTexture(v) self.Texture=v end
    function c:SetClipToWidth(v) self.Clip=v end
    function c:SetUV(...) self.UV={...} end
    function c:SetAlpha(v) self.Alpha=v end
    function c:GetStringAdvance(s) return #s*7 end
    function c:UseAlphaHitTest(v) self.AlphaHit=v end
    function c:SetNeedsFrameUpdate(v) self.Updates=v end
    function c:Hide() self.Hidden=true;if self.OnHide then self:OnHide(true) end end
    function c:Show() self.Hidden=false;if self.OnHide then self:OnHide(false) end end
    function c:IsHidden() return self.Hidden end
    function c:GetRootFrame() return GetFrame(0) end
    function c:Destroy() self.Destroyed=true;if self.OnDestroy then self:OnDestroy() end;for _,child in ipairs(self.Children) do child:Destroy() end end
    controls[#controls+1]=c;return c
end
local frame=control(nil,'frame');frame.Width:Set(1920);frame.Height:Set(1080)
function GetFrame() return frame end
local drag
function PostDragger(_,_,d) drag=d end
local UIUtil={bodyFont='body',SkinnableFile=function(p) return '/skin'..p end}
function UIUtil.CreateText(parent,text) local c=control(parent);c.Text=text;return c end
local ui
local savedPreferences={}
function import(path)
    if path=='/lua/user/prefs.lua' then return {GetFromCurrentProfile=function(k) return savedPreferences[k] end,SetToCurrentProfile=function(k,v) savedPreferences[k]=v end} end
    if path=='/lua/maui/layouthelpers.lua' then return {ScaleNumber=function(v) return v end,InvScaleNumber=function(v) return v end} end
    if path=='/lua/maui/group.lua' then return {Group=control} end
    if path=='/lua/maui/bitmap.lua' then return {Bitmap=control} end
    if path=='/lua/maui/dragger.lua' then return {Dragger=function() return control() end} end
    if path=='/lua/ui/uiutil.lua' then return UIUtil end
    if path:find('FireDragon/UI.lua',1,true) then return {Export=ui} end
    if path:find('Keys.lua',1,true) then return {DefaultKey='Alt-Shift-D'} end
    error(path)
end
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
local scroll=ui.Scroll(b,{width=100,height=80,contentWidth=500,contentHeight=400})
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
local remembered=ui.Window(frame,{x=20,y=30,width=300,height=200,prefKey='test.window'})
remembered:SetSize(450,320);remembered.Left:Set(180);remembered.Top:Set(210);remembered:Destroy()
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
function SimCallback(r) sent[#sent+1]=r end
function GetFocusArmy() return 1 end
local env=setmetatable({}, {__index=_G})
assert(loadfile('../FireDragon Debug Tools/src/lua/FireDragonDebugTools/Panel.lua','t',env))()
env.Toggle()
local box
for _,c in ipairs(controls) do if c.Checked~=nil and c.Label.FDText:find('Infinite Energy',1,true) then box=c end end
check(box~=nil,'debug window uses shared checkbox')
check(box.Check.FDVisual.Texture:find('/CHECKBOX/d_up.dds',1,true) and box.Label.FDText=='Infinite Energy','checkbox uses square vanilla art and separate label')
pointer(box,'MouseEnter');check(box.Check.FDVisual.Texture:find('d_over.dds',1,true),'checkbox hover graphic')
local _,bx,by=pointer(box);check(sent[1].Args.Resource=='ENERGY' and sent[1].Args.Enabled,'debug click callback')
env.OnSync({['1']={Energy=true,Mass=false}});check(box.Checked and #sent==1,'sync updates without feedback')
local debugWindow=box
while not debugWindow.FDWindow do debugWindow=debugWindow.FDParent end
check(debugWindow.FDWindow,'single page mounts directly under window without tabs')
local _,dx,dy=pointer(debugWindow.CloseButton);drag:OnRelease(dx,dy);check(debugWindow.Hidden,'debug close routes correctly')
for _,c in ipairs(controls) do if not c.Destroyed and c.Updates and c.OnFrame then c:OnFrame(0.2) end end
check(debugWindow.FDVisual.Hidden and box.Check.FDVisual.Hidden and box.Label.FDVisual.Hidden,'closed debug window stays visually hidden across frame refreshes')
local function allVisualsHidden(node)
    if node.FDVisual and not node.FDVisual.Hidden then return false end
    for _,child in ipairs(node.FDChildren or {}) do if not allVisualsHidden(child) then return false end end
    return true
end
check(allVisualsHidden(debugWindow),'all window frame, label and icon renderers remain hidden after close')
env.OnSync({['1']={Energy=false,Mass=true}})
check(box.Label.FDVisual.Hidden,'sync cannot reveal a closed window')
env.Toggle()
for _,c in ipairs(controls) do if not c.Destroyed and c.Updates and c.OnFrame then c:OnFrame(0.2) end end
check(not debugWindow.FDVisual.Hidden and not box.Check.FDVisual.Hidden and not box.Label.FDVisual.Hidden,'reopening restores rendering')
check(not debugWindow.Hidden and at(box.Left()+30,box.Top()+10)==box.FDHit,'debug reopen restores mouse input')
print('PASS: '..checks..' shared UI and debug window checks')
