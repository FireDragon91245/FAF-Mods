-- FireDragon UI: retained layout and software clipping over FAF Maui.
local Group = import('/lua/maui/group.lua').Group
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
local UIUtil = import('/lua/ui/uiutil.lua')
local Dragger = import('/lua/maui/dragger.lua').Dragger
local UI = {}
local function skin(path) return UIUtil.SkinnableFile(path) end
UI.Theme = { Background='f20a141f', Border='ff344958', Surface='ff24394b', Text='ffe1edf7', Muted='ff9fb3c8', Accent='ff69b8fa' }
local function count(t) return table.getn(t) end
local function value(v) if type(v)=='function' then return v() end; return v end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
-- Maui Show() can reveal a child after its ancestor was hidden. Refreshes must
-- respect the owning hierarchy instead of deciding visibility from geometry alone.
local function visible(c)
    while c do
        if c:IsHidden() then return false end
        c=c.FDParent
    end
    return true
end
local function bounds(c) return c.Left(),c.Top(),c.Left()+c.Width(),c.Top()+c.Height() end
local function clip(c)
    local l,t,r,b=bounds(c)
    local p=c.FDParent
    while p do
        if p.FDClip then
            local pl,pt,pr,pb=bounds(p)
            l=math.max(l,pl);t=math.max(t,pt);r=math.min(r,pr);b=math.min(b,pb)
        end
        p=p.FDParent
    end
    return l,t,math.max(l,r),math.max(t,b)
end
function UI.At(c,parent,x,y,w,h)
    c.Left:Set(function() return parent.Left()+value(x or 0) end)
    c.Top:Set(function() return parent.Top()+value(y or 0) end)
    if w then c.Width:Set(w) end
    if h then c.Height:Set(h) end
    return c
end
function UI.Fill(c,parent,inset)
    inset=inset or 0
    return UI.At(c,parent,inset,inset,function() return math.max(0,parent.Width()-2*inset) end,function() return math.max(0,parent.Height()-2*inset) end)
end
local function node(parent,o)
    o=o or {}
    local c=Group(parent,o.name or 'FireDragon UI')
    c:DisableHitTest()
    c.FDParent=parent;c.FDChildren={};c.FDClip=o.clip==true
    if parent.FDChildren then table.insert(parent.FDChildren,c) end
    UI.At(c,parent,o.x,o.y,o.width or 100,o.height or 24)
    c.Depth:Set(function() return parent.Depth()+(o.depth or 2) end)
    c.HandleEvent=function(self,e)
        if e.Type=='ButtonPress' and self.OnClick then self:OnClick(e);return true end
        return false
    end
    return c
end
local function visual(c,kind,o)
    local v
    if kind=='text' then
        v=UIUtil.CreateText(c,o.text or '',o.size or 13,o.font or UIUtil.bodyFont)
        v:SetColor(o.color or UI.Theme.Text);v:SetClipToWidth(true)
        c.SetText=function(self,s)
            self.FDText=s;self.FDRenderedText=s;v:SetText(s)
            if self.FDRefresh then self.FDRefresh() end
        end
        c.SetColor=function(self,s) v:SetColor(s) end
        c.FDText=o.text or ''
        c.FDRenderedText=c.FDText
    else
        v=Bitmap(c)
        if o.texture then v:SetTexture(o.texture) else v:SetSolidColor(o.color or UI.Theme.Surface) end
        c.SetSolidColor=function(self,s) v:SetSolidColor(s) end
        c.SetTexture=function(self,s) v:SetTexture(s) end
    end
    v:DisableHitTest();v.Depth:Set(function() return c.Depth()+1 end)
    -- Only the primitive is cropped; the component's layout dimensions never shrink.
    v.Left:Set(function() local l=clip(c);return l end)
    v.Top:Set(function() local _,t=clip(c);return t end)
    v.Width:Set(function() local l,_,r=clip(c);return r-l end)
    v.Height:Set(function() local _,t,_,b=clip(c);return b-t end)
    local function refresh()
        if not visible(c) then v:Hide();return end
        local l,t,r,b=clip(c)
        if kind=='text' then
            -- Maui cannot crop glyphs vertically: retain whole lines only.
            if t>c.Top() or b<c.Top()+c.Height() or r<=l then v:Hide() else v:Show() end
            if l>c.Left() then
                local s=c.FDText or '';local offset=l-c.Left();local i=1
                while i<=string.len(s) and v:GetStringAdvance(string.sub(s,1,i))<offset do i=i+1 end
                local shown=string.sub(s,i+1)
                if shown~=c.FDRenderedText then v:SetText(shown);c.FDRenderedText=shown end
            elseif c.FDRenderedText~=c.FDText then v:SetText(c.FDText or '');c.FDRenderedText=c.FDText end
        else
            if r<=l or b<=t then v:Hide() else v:Show() end
            local w,h=math.max(1,c.Width()),math.max(1,c.Height())
            v:SetUV((l-c.Left())/w,(t-c.Top())/h,(r-c.Left())/w,(b-c.Top())/h)
        end
    end
    c.FDVisual=v;c.FDRefresh=refresh
    c:SetNeedsFrameUpdate(true)
    c.OnFrame=function() refresh() end
    return c
end
function UI.Panel(parent,o)
    o=o or {};local c=node(parent,o)
    if o.color then visual(c,'bitmap',o) end
    return c
end
function UI.Label(parent,o) o=o or {};return visual(node(parent,o),'text',o) end
function UI.Icon(parent,o) o=o or {};return visual(node(parent,o),'bitmap',o) end
UI.Rect=UI.Icon
function UI.Interactive(c)
    if c.FDHit then return c end
    c:DisableHitTest()
    local hit=Bitmap(c);hit:SetSolidColor('01000000')
    hit:UseAlphaHitTest(false)
    hit.Left:Set(function() local l=clip(c);return l end)
    hit.Top:Set(function() local _,t=clip(c);return t end)
    hit.Width:Set(function() local l,_,r=clip(c);return r-l end)
    hit.Height:Set(function() local _,t,_,b=clip(c);return b-t end)
    hit.Depth:Set(function() return c.Depth()+1 end)
    hit.HandleEvent=function(_,e)
        if e.Type=='ButtonPress' then
            local owner=c
            while owner do if owner.FDWindow then owner:Focus();break end;owner=owner.FDParent end
        end
        if not visible(c) then return false end
        if not c.FDEnabled then return true end
        return c:HandleEvent(e)
    end
    c.FDHit=hit;c.FDEnabled=true
    function c:SetEnabled(enabled)
        self.FDEnabled=enabled==true
        if enabled then self.FDHit:EnableHitTest() else self.FDHit:DisableHitTest() end
        if self.UpdateState then self:UpdateState() end
    end
    return c
end
-- Controls share vanilla art while retaining clipped library geometry.
function UI.Button(parent,o)
    o=o or {}
    local textures=o.textures or {
        up=skin('/scx_menu/small-btn/small_btn_up.dds'),
        over=skin('/scx_menu/small-btn/small_btn_over.dds'),
        down=skin('/scx_menu/small-btn/small_btn_down.dds'),
        disabled=skin('/scx_menu/small-btn/small_btn_dis.dds'),
    }
    local c=UI.Icon(parent,{x=o.x,y=o.y,width=o.width,height=o.height,texture=textures.up})
    c.Label=UI.Label(c,{x=6,y=function() return math.max(0,(c.Height()-18)/2) end,width=function() return math.max(0,c.Width()-12) end,height=18,text=o.text})
    c.OnClick=o.onClick
    function c:UpdateState()
        local state=not self.FDEnabled and 'disabled' or (self.Pressed and 'down' or (self.Hovered and 'over' or 'up'))
        self:SetTexture(textures[state] or textures.up)
        self.Label:SetColor(self.FDEnabled and UI.Theme.Text or UI.Theme.Muted)
    end
    c.HandleEvent=function(self,e)
        if e.Type=='MouseEnter' then self.Hovered=true;self:UpdateState();return true end
        if e.Type=='MouseExit' then self.Hovered=false;self:UpdateState();return true end
        if e.Type=='ButtonPress' or e.Type=='ButtonDClick' then
            if e.Modifiers and e.Modifiers.Right then return true end
            if o.onPress then o.onPress(self,e);return true end
            self.Pressed=true;self:UpdateState()
            local drag=Dragger();self.FDButtonDrag=drag
            local function finish() self.Pressed=false;self.FDButtonDrag=nil;drag:Destroy();self:UpdateState() end
            drag.OnRelease=function(_,x,y)
                local l,t,r,b=clip(self)
                local inside=x and y and x>=l and x<r and y>=t and y<b
                finish()
                if inside and self.FDEnabled and not self:IsHidden() and self.OnClick then self:OnClick(e) end
            end
            drag.OnCancel=finish
            PostDragger(self:GetRootFrame(),e.KeyCode,drag);return true
        end
        return false
    end
    local oldDestroy=c.OnDestroy
    c.OnDestroy=function(self) if self.FDButtonDrag then self.FDButtonDrag:Destroy();self.FDButtonDrag=nil end;if oldDestroy then oldDestroy(self) end end
    c.OnHide=function(self,hidden)
        if hidden then
            self.Hovered=false
            if self.FDButtonDrag then self.FDButtonDrag:OnCancel() end
            self:UpdateState()
        end
    end
    UI.Interactive(c);c:UpdateState();return c
end
function UI.Checkbox(parent,o)
    o=o or {}
    local c=UI.Panel(parent,o);c.Checked=false
    c.Check=UI.Icon(c,{y=function() return (c.Height()-20)/2 end,width=20,height=20,texture=skin('/CHECKBOX/d_up.dds')})
    c.Label=UI.Label(c,{x=26,y=function() return (c.Height()-18)/2 end,width=function() return math.max(0,c.Width()-26) end,height=18,text=o.text})
    function c:UpdateState()
        local state=not self.FDEnabled and 'dis' or (self.Hovered and 'over' or 'up')
        self.Check:SetTexture(skin('/CHECKBOX/'..(self.Checked and 's_' or 'd_')..state..'.dds'))
        self.Label:SetColor(self.FDEnabled and UI.Theme.Text or UI.Theme.Muted)
    end
    function c:SetCheck(v,silent)
        self.Checked=v==true;self:UpdateState()
        if not silent and o.onCheck then o.onCheck(self,self.Checked) end
    end
    function c:IsChecked() return self.Checked end
    c.OnHide=function(self,hidden) if hidden then self.Hovered=false;self:UpdateState() end end
    c.HandleEvent=function(self,e)
        if e.Type=='MouseEnter' then self.Hovered=true;self:UpdateState();return true end
        if e.Type=='MouseExit' then self.Hovered=false;self:UpdateState();return true end
        if e.Type=='ButtonPress' or e.Type=='ButtonDClick' then
            if not (e.Modifiers and e.Modifiers.Right) then self:SetCheck(not self.Checked) end
            return true
        end
        return false
    end
    UI.Interactive(c);c:SetCheck(o.checked,true);return c
end
function UI.FrameSkin(c)
    local root=UI.Panel(c,{depth=0});UI.Fill(root,c)
    local size=12
    local parts={
        {'ul',0,0,size,size}, {'ur',function() return c.Width()-size end,0,size,size},
        {'ll',0,function() return c.Height()-size end,size,size},
        {'lr',function() return c.Width()-size end,function() return c.Height()-size end,size,size},
        {'horz_um',size,0,function() return math.max(0,c.Width()-2*size) end,size},
        {'lm',size,function() return c.Height()-size end,function() return math.max(0,c.Width()-2*size) end,size},
        {'vert_l',0,size,size,function() return math.max(0,c.Height()-2*size) end},
        {'vert_r',function() return c.Width()-size end,size,size,function() return math.max(0,c.Height()-2*size) end},
        {'m',size,size,function() return math.max(0,c.Width()-2*size) end,function() return math.max(0,c.Height()-2*size) end},
    }
    for _,part in ipairs(parts) do UI.Icon(root,{x=part[2],y=part[3],width=part[4],height=part[5],texture=skin('/game/options_brd/options_brd_'..part[1]..'.dds'),depth=0}) end
    return root
end
function UI.Bar(parent,o)
    o=o or {};local c=UI.Panel(parent,{x=o.x,y=o.y,width=o.width,height=o.height or 8,color=o.track or UI.Theme.Border,clip=true})
    c.Fill=UI.Rect(c,{width=0,height=function() return c.Height() end,color=o.color or UI.Theme.Accent})
    c.Fraction=0
    c.Fill.Width:Set(function() return c.Width()*c.Fraction end)
    function c:SetValue(v,max)
        self.Fraction=clamp(v/math.max(max or 1,0.00001),0,1)
        self.Fill.Width:Set(function() return self.Width()*self.Fraction end)
    end
    c:SetValue(o.value or 0);return c
end
-- Fixed cell sizes are deliberate: overflow is clipped or scrolled, never squeezed.
function UI.Layout(parent,mode,o)
    o=o or {};local c=UI.Panel(parent,o);c.Items={}
    function c:Add(child)
        local i=count(self.Items);table.insert(self.Items,child)
        local columns=o.columns or 1;local gap=o.gap or 6;local pad=o.padding or 0
        local w=o.cellWidth or child.Width();local h=o.cellHeight or child.Height()
        local x,y=0,0
        if mode=='row' then x=i*(w+gap)
        elseif mode=='grid' then x=math.mod(i,columns)*(w+gap);y=math.floor(i/columns)*(h+gap)
        else y=i*(h+gap) end
        UI.At(child,self,pad+x,pad+y,w,h)
        return child
    end
    return c
end
function UI.Row(p,o) return UI.Layout(p,'row',o) end
function UI.Column(p,o) return UI.Layout(p,'column',o) end
function UI.Grid(p,o) return UI.Layout(p,'grid',o) end
function UI.Scroll(parent,o)
    o=o or {};o.clip=true
    local c=UI.Panel(parent,o);c.OffsetX=0;c.OffsetY=0
    local thickness=12
    c.Viewport=UI.Panel(c,{clip=true});c.Viewport.FDScrollOwner=c
    c.Content=UI.Panel(c.Viewport,{width=o.contentWidth or o.width or function() return c.Width() end,height=o.contentHeight or o.height or function() return c.Height() end})
    function c:ViewportSize()
        local w,h=self.Width(),self.Height();local horizontal,vertical=false,false
        for n=1,3 do
            horizontal=self.Content.Width()>math.max(0,w-(vertical and thickness or 0))
            vertical=self.Content.Height()>math.max(0,h-(horizontal and thickness or 0))
        end
        return math.max(0,w-(vertical and thickness or 0)),math.max(0,h-(horizontal and thickness or 0)),horizontal,vertical
    end
    UI.At(c.Viewport,c,0,0,function() local w=c:ViewportSize();return w end,function() local _,h=c:ViewportSize();return h end)
    local function offsetContent()
        c.Content.Left:Set(function() return c.Viewport.Left()-c.OffsetX end)
        c.Content.Top:Set(function() return c.Viewport.Top()-c.OffsetY end)
    end
    offsetContent()
    function c:ScrollTo(x,y)
        local oldX,oldY=self.OffsetX,self.OffsetY
        self.OffsetX=clamp(x or self.OffsetX,0,math.max(0,self.Content.Width()-self.Viewport.Width()))
        self.OffsetY=clamp(y or self.OffsetY,0,math.max(0,self.Content.Height()-self.Viewport.Height()))
        if oldX~=self.OffsetX or oldY~=self.OffsetY then
            offsetContent()
            if self.UpdateThumbs then self:UpdateThumbs() end
            if self.OnScroll then self:OnScroll() end
        end
    end
    c.ScrollSetTop=function(self,axis,top) if axis=='Horz' then self:ScrollTo(top,nil) else self:ScrollTo(nil,top) end end
    c.ScrollLines=function(self,axis,n) self:ScrollSetTop(axis,(axis=='Horz' and self.OffsetX or self.OffsetY)+n*(o.step or 24)) end
    c.ScrollPages=function(self,axis,n) self:ScrollSetTop(axis,(axis=='Horz' and self.OffsetX or self.OffsetY)+n*(axis=='Horz' and self.Viewport.Width() or self.Viewport.Height())) end
    c.GetScrollValues=function(self,axis) local h=axis=='Horz';local start=h and self.OffsetX or self.OffsetY;return 0,h and self.Content.Width() or self.Content.Height(),start,start+(h and self.Viewport.Width() or self.Viewport.Height()) end
    c.IsScrollable=function(self,axis) return axis=='Horz' and self.Content.Width()>self.Viewport.Width() or axis~='Horz' and self.Content.Height()>self.Viewport.Height() end
    c.HandleEvent=function(self,e)
        if e.Type=='WheelRotation' then
            local horizontal=e.Modifiers and e.Modifiers.Shift or (not self:IsScrollable('Vert') and self:IsScrollable('Horz'))
            self:ScrollLines(horizontal and 'Horz' or 'Vert',-e.WheelRotation/120*3);return true
        end
        return e.Type=='ButtonPress' or e.Type=='ButtonDClick'
    end
    local function scrollbar(horizontal)
        local track=UI.Rect(c,{depth=30,color=UI.Theme.Border})
        if horizontal then UI.At(track,c,0,function() return c.Viewport.Height() end,function() return c.Viewport.Width() end,thickness)
        else UI.At(track,c,function() return c.Viewport.Width() end,0,thickness,function() return c.Viewport.Height() end);track:SetTexture(skin('/SCROLLBAR_VERT/back_scr_mid.dds')) end
        local thumb=UI.Rect(track,{color=UI.Theme.Muted})
        if not horizontal then thumb:SetTexture(skin('/SCROLLBAR_VERT/bar-mid_scr_up.dds')) end
        local function length() return horizontal and track.Width() or track.Height() end
        local function viewport() return horizontal and c.Viewport.Width() or c.Viewport.Height() end
        local function content() return horizontal and c.Content.Width() or c.Content.Height() end
        local function thumbLength() return math.min(length(),math.max(20,length()*viewport()/math.max(1,content()))) end
        local function position() return (horizontal and c.OffsetX or c.OffsetY)/math.max(1,content()-viewport())*math.max(0,length()-thumbLength()) end
        if horizontal then UI.At(thumb,track,position,0,thumbLength,thickness)
        else UI.At(thumb,track,0,position,thickness,thumbLength) end
        local function set(top) if horizontal then c:ScrollTo(top,nil) else c:ScrollTo(nil,top) end end
        UI.Interactive(track);UI.Interactive(thumb)
        track.OnClick=function(_,e)
            local coordinate=horizontal and e.MouseX-track.Left() or e.MouseY-track.Top()
            set((coordinate-thumbLength()/2)/math.max(1,length()-thumbLength())*math.max(0,content()-viewport()))
        end
        thumb.HandleEvent=function(_,e)
            if e.Type~='ButtonPress' then return false end
            if c.FDScrollDrag then c.FDScrollDrag:OnCancel() end
            local drag=Dragger();c.FDScrollDrag=drag
            local start=horizontal and e.MouseX or e.MouseY;local offset=horizontal and c.OffsetX or c.OffsetY
            drag.OnMove=function(_,x,y) set(offset+((horizontal and x or y)-start)*math.max(0,content()-viewport())/math.max(1,length()-thumbLength())) end
            drag.OnRelease=function() c.FDScrollDrag=nil;drag:Destroy() end;drag.OnCancel=drag.OnRelease
            PostDragger(c:GetRootFrame(),e.KeyCode,drag);return true
        end
        return track,thumb,function() if horizontal then thumb.Left:Set(function() return track.Left()+position() end) else thumb.Top:Set(function() return track.Top()+position() end) end end
    end
    local updateVertical,updateHorizontal
    c.Scrollbar,c.Thumb,updateVertical=scrollbar(false)
    c.HorizontalScrollbar,c.HorizontalThumb,updateHorizontal=scrollbar(true)
    function c:UpdateThumbs() updateVertical();updateHorizontal() end
    c.OnHide=function(self,hidden) if hidden and self.FDScrollDrag then self.FDScrollDrag:OnCancel() end end
    c.OnDestroy=function(self) if self.FDScrollDrag then self.FDScrollDrag:Destroy();self.FDScrollDrag=nil end end
    UI.Interactive(c)
    function c:RefreshScrollbars()
        self:ScrollTo()
        local _,_,horizontal,vertical=self:ViewportSize()
        if visible(self) and vertical then self.Scrollbar:Show() else self.Scrollbar:Hide() end
        if visible(self) and horizontal then self.HorizontalScrollbar:Show() else self.HorizontalScrollbar:Hide() end
    end
    c:SetNeedsFrameUpdate(true);c.OnFrame=function() c:RefreshScrollbars() end
    c:RefreshScrollbars()
    return c
end
function UI.Tabs(parent,o)
    o=o or {};local c=UI.Panel(parent,o);c.Pages={};c.Buttons={}
    c.Body=UI.Panel(c,{y=30,width=function() return c.Width() end,height=function() return math.max(0,c.Height()-30) end,clip=true})
    function c:Select(id)
        assert(self.Pages[id],'Unknown tab: '..tostring(id));self.Selected=id
        for key,page in pairs(self.Pages) do
            if key==id then page:Show() else page:Hide() end
            self.Buttons[key]:SetSolidColor(key==id and UI.Theme.Border or UI.Theme.Surface)
        end
        if o.onSelect then o.onSelect(id) end
    end
    function c:Add(id,title)
        assert(not self.Pages[id],'Duplicate tab')
        local index=count(self.Order or {});self.Order=self.Order or {};table.insert(self.Order,id)
        local page=UI.Panel(self.Body,{clip=true});UI.Fill(page,self.Body)
        self.Pages[id]=page
        self.Buttons[id]=UI.Button(self,{x=index*(o.tabWidth or 136),width=(o.tabWidth or 136)-4,height=26,text=title,onClick=function() self:Select(id) end})
        if not self.Selected then self:Select(id) else page:Hide() end
        return page
    end
    return c
end
local topDepth=1000
function UI.Window(parent,o)
    o=o or {};o.clip=true;o.color=o.color or UI.Theme.Background
    local c=UI.Panel(parent,o);c.FDWindow=true;c.MinWidth=o.minWidth or 180;c.MinHeight=o.minHeight or 100
    c.Background=UI.FrameSkin(c)
    c.Draggable=o.draggable~=false;c.Resizable=o.resizable~=false
    function c:Focus() topDepth=topDepth+512;self.Depth:Set(topDepth) end
    function c:SetSize(w,h) self.Width:Set(math.max(self.MinWidth,w));self.Height:Set(math.max(self.MinHeight,h));if o.onResize then o.onResize(self) end end
    function c:SetMinimumSize(w,h) self.MinWidth=w;self.MinHeight=h;self:SetSize(self.Width(),self.Height()) end
    function c:SetDraggable(v) self.Draggable=v end
    function c:SetResizable(v) self.Resizable=v;if v then self.ResizeGrip:Show() else self.ResizeGrip:Hide() end end
    local storage,layout
    local prefKey=o.prefKey
    if prefKey then
        storage=import('/mods/FireDragonModLoader/lua/FireDragon/Storage.lua').Export.Open('FireDragon.UI')
        layout=import('/lua/maui/layouthelpers.lua')
    end
    function c:SaveGeometry()
        if not storage then return end
        storage:Set(prefKey,{left=layout.InvScaleNumber(self.Left()-parent.Left()),top=layout.InvScaleNumber(self.Top()-parent.Top()),width=layout.InvScaleNumber(self.Width()),height=layout.InvScaleNumber(self.Height())})
    end
    function c:Close() self:SaveGeometry();if o.onClose then o.onClose(self) else self:Hide() end end
    c.TitleBar=UI.Panel(c,{width=function() return c.Width() end,height=30,depth=40})
    c.Title=UI.Label(c.TitleBar,{x=10,y=5,width=function() return math.max(0,c.Width()-50) end,height=20,text=o.title or o.name});c.Title:DisableHitTest()
    c.CloseButton=UI.Button(c.TitleBar,{x=function() return c.Width()-28 end,y=3,width=24,height=24,
        textures={up=skin('/dialogs/close_btn/close_btn_up.dds'),over=skin('/dialogs/close_btn/close_btn_over.dds'),down=skin('/dialogs/close_btn/close_btn_down.dds'),disabled=skin('/dialogs/close_btn/close_btn_dis.dds')},
        onClick=function() c:Close() end})
    c.Client=UI.Panel(c,{y=32,x=2,width=function() return math.max(0,c.Width()-4) end,height=function() return math.max(0,c.Height()-34) end,clip=true})
    c.ResizeGrip=UI.Button(c,{x=function() return c.Width()-18 end,y=function() return c.Height()-18 end,width=18,height=18,text='/',onClick=function() end});c.ResizeGrip.Depth:Set(function() return c.Depth()+90 end)
    local function start(e,resize)
        c:Focus();if resize and not c.Resizable or not resize and not c.Draggable then return true end
        local drag=Dragger();local x,y=e.MouseX,e.MouseY;local l,t=c.Left(),c.Top();local w,h=c.Width(),c.Height()
        c.FDDrag=drag
        drag.OnMove=function(_,mx,my)
            if resize then c:SetSize(w+mx-x,h+my-y)
            else c.Left:Set(clamp(l+mx-x,parent.Left(),math.max(parent.Left(),parent.Left()+parent.Width()-40)));c.Top:Set(clamp(t+my-y,parent.Top(),math.max(parent.Top(),parent.Top()+parent.Height()-30))) end
        end
        drag.OnRelease=function() c.FDDrag=nil;drag:Destroy();c:SaveGeometry() end;drag.OnCancel=drag.OnRelease
        PostDragger(c:GetRootFrame(),e.KeyCode,drag);return true
    end
    UI.Interactive(c.TitleBar)
    c.TitleBar.OnClick=function(_,e) return start(e,false) end
    c.ResizeGrip.HandleEvent=function(_,e) if e.Type=='ButtonPress' then return start(e,true) end;return false end
    local oldDestroy=c.OnDestroy
    c.OnDestroy=function(self) self:SaveGeometry();if self.FDDrag then self.FDDrag:Destroy();self.FDDrag=nil end;if oldDestroy then oldDestroy(self) end end
    c.OnHide=function(self,hidden) if hidden then self:SaveGeometry();if self.FDDrag then self.FDDrag:Destroy();self.FDDrag=nil end end end
    c.HandleEvent=function(self,e) if e.Type=='ButtonPress' then self:Focus();return true end;return e.Type=='ButtonDClick' end
    UI.Interactive(c)
    c:SetSize(value(o.width or 400),value(o.height or 300));c:SetResizable(c.Resizable)
    local saved=storage and storage:Get(prefKey)
    if type(saved)=='table' and type(saved.left)=='number' and type(saved.top)=='number' and type(saved.width)=='number' and type(saved.height)=='number' then
        c:SetSize(math.min(parent.Width(),layout.ScaleNumber(saved.width)),math.min(parent.Height(),layout.ScaleNumber(saved.height)))
        c.Left:Set(clamp(parent.Left()+layout.ScaleNumber(saved.left),parent.Left(),math.max(parent.Left(),parent.Right()-c.Width())))
        c.Top:Set(clamp(parent.Top()+layout.ScaleNumber(saved.top),parent.Top(),math.max(parent.Top(),parent.Bottom()-c.Height())))
    end
    c:Focus()
    return c
end
-- Live bindings use one owner frame callback; destroying the owner destroys subscriptions.
function UI.Bind(owner,read,apply,interval)
    local previous=owner.OnFrame;local elapsed=0;local last;local active=true
    local function update()
        local v=read();if v~=last then last=v;apply(v,owner) end
    end
    owner.OnFrame=function(self,dt) if previous then previous(self,dt) end;if not active then return end;elapsed=elapsed+(dt or 0);if elapsed>=(interval or 0.1) then elapsed=0;update() end end
    owner:SetNeedsFrameUpdate(true);update()
    return function() active=false end
end
function UI.Dim(parent,o) o=o or {};o.color=o.color or '99000000';local c=UI.Rect(parent,o);UI.Fill(c,parent);return c end
-- Texture-space multi-tap blur. This does not sample the game framebuffer.
function UI.Blur(parent,o)
    o=o or {};assert(o.texture,'Blur requires an image texture')
    local c=UI.Panel(parent,o);local radius=o.radius or 2
    for y=-1,1 do for x=-1,1 do
        local tap=UI.Icon(c,{x=x*radius,y=y*radius,width=function() return c.Width() end,height=function() return c.Height() end,texture=o.texture})
        tap.FDVisual:SetAlpha(1/9);tap:DisableHitTest()
    end end
    return c
end
-- Procedural shapes; arbitrary alpha silhouettes can also use texture assets.
function UI.Shape(parent,o)
    o=o or {}
    if o.kind=='circle' or o.kind=='triangle' then
        local c=UI.Panel(parent,o);local rows=o.segments or 48
        for row=0,rows-1 do
            local index=row
            local function halfWidth()
                local y=(index+0.5)/rows
                if o.kind=='circle' then return math.sqrt(math.max(0,1-(2*y-1)^2))*c.Width()/2 end
                return y*c.Width()/2
            end
            UI.Rect(c,{x=function() return c.Width()/2-halfWidth() end,y=function() return index*c.Height()/rows end,
                width=function() return 2*halfWidth() end,height=function() return c.Height()/rows+0.25 end,color=o.color})
        end
        return c
    end
    if o.kind=='border' then
        local c=UI.Panel(parent,o);local s=o.thickness or 1
        UI.Rect(c,{width=function() return c.Width() end,height=s,color=o.color})
        UI.Rect(c,{y=function() return c.Height()-s end,width=function() return c.Width() end,height=s,color=o.color})
        UI.Rect(c,{width=s,height=function() return c.Height() end,color=o.color})
        UI.Rect(c,{x=function() return c.Width()-s end,width=s,height=function() return c.Height() end,color=o.color})
        return c
    end
    return UI.Icon(parent,o)
end
Export = UI
return UI
