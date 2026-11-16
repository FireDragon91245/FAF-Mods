local Group=import('/lua/maui/group.lua').Group
local Bitmap=import('/lua/maui/bitmap.lua').Bitmap
local UI=import('/lua/ui/uiutil.lua')
local Controls=import('/lua/ui/controls.lua')
local Model=import('/mods/ModularShields/lua/ModularShields/UI/Model.lua').Export
local C=Model.Colors
local view
local function Send(action,value) SimCallback({Func='ModularShieldAction',Args={Action=action,Value=value}},true) end
local function Text(control,value,color)
    if control.Value~=value then control:SetText(value);control.Value=value end
    if color and control.Tint~=color then control:SetColor(color);control.Tint=color end
end
local function Visible(control,value) if value then control:Show() else control:Hide() end end
local function At(control,parent,x,y,w,h)
    control.Left:Set(function() return parent.Left()+x end);control.Top:Set(function() return parent.Top()+y end)
    if w then control.Width:Set(w) end;if h then control.Height:Set(h) end
end
local function Label(parent,x,y,w,size,color)
    local t=UI.CreateText(parent,'',size,UI.bodyFont)
    t:DisableHitTest();t:SetClipToWidth(true);t:SetDropShadow(true)
    t.Depth:Set(function() return parent.Depth()+5 end);At(t,parent,x,y,w)
    t:SetColor(color or C.Text)
    return t
end
local function Rect(parent,x,y,w,h,color,depth)
    local b=Bitmap(parent);b:SetSolidColor(color);b:DisableHitTest()
    b.Depth:Set(function() return parent.Depth()+(depth or 1) end);At(b,parent,x,y,w,h);return b
end
local function ShowCard(card,show)
    card.Visible=show
    for _,control in ipairs(card.Controls) do Visible(control,show) end
    Visible(card.Hover,show and card.Hovered or false)
end
local function HideTip(v)
    v.Tip:Hide()
    for _,control in ipairs(v.TipParts) do control:Hide() end
    for _,control in ipairs(v.TipLines) do control:Hide() end
end
local function UpdateTooltip(v)
    if not v.Hovered or not v.Hovered.Visible then HideTip(v);return end
    local card=v.Hovered
    local lines=card.Lines and card.Lines() or Model.Tooltip(card.Data,v.State)
    v.Tip.Height:Set(24+table.getn(lines)*20)
    v.Tip.Left:Set(function() return math.max(8,math.min(GetFrame(0).Width()-v.Tip.Width()-8,card.Root.Left()-12)) end)
    v.Tip.Top:Set(function() return math.max(8,v.Panel.Top()-v.Tip.Height()-8) end)
    for index,t in ipairs(v.TipLines) do
        local line=lines[index]
        Text(t,line and line.Text or '',line and line.Color)
        Visible(t,line~=nil)
    end
    v.Tip:Show()
    for _,control in ipairs(v.TipParts) do control:Show() end
end
local function Create(state,id)
    local frame=GetFrame(0)
    local p=Group(frame,'Modular Shield Dock')
    p.Depth:Set(100);p.Width:Set(function() return math.min(760,frame.Width()-32) end);p.Height:Set(250)
    p.Left:Set(function() return (frame.Width()-p.Width())/2 end)
    p.Top:Set(function()
        local native=Controls.Get().constructionGroup
        local top=frame.Height()-190
        if native and not native:IsHidden() and native.Top()>frame.Height()/2 then top=native.Top() end
        return math.max(8,top-p.Height()-8)
    end)
    p.HandleEvent=function(_,event) return event.Type=='ButtonPress' or event.Type=='ButtonDClick' end
    local v={Panel=p,EntityId=id,State=state,Cards={}}
    local accents={UEF='ff69b8fa',AEON='ff74e4bb',CYBRAN='fff67b83',SERAPHIM='ffefca78'}
    local accent=accents[state.Faction] or accents.UEF
    local border=Rect(p,0,0,760,250,'ff344958',0)
    border.Width:Set(p.Width)
    local bg=Rect(p,1,1,758,248,'f20a141f',1);bg.Width:Set(function() return p.Width()-2 end)
    local stripe=Rect(p,1,1,758,3,accent,2);stripe.Width:Set(function() return p.Width()-2 end)
    local divider=Rect(p,14,66,732,1,'ff263c4c',2);divider.Width:Set(function() return p.Width()-28 end)
    v.Title=Label(p,16,10,490,14,C.Text)
    v.HP=Label(p,16,35,270,17,C.HP)
    v.Regen=Label(p,296,36,210,15,C.Regen)
    v.Damage=Label(p,518,36,224,15,C.Damage)
    v.Modules=Label(p,16,83,104,12,C.Muted);Text(v.Modules,'MODULES')
    v.Slots=Label(p,16,102,108,12,C.Text)
    v.Upgrades=Label(p,16,158,108,12,C.Muted);Text(v.Upgrades,'UPGRADES')
    v.Hint=Label(p,16,178,108,10,C.Muted);Text(v.Hint,'Click to fit')
    v.Info=Label(p,16,220,728,11,C.Muted)
    local function toggle(x,symbol,action)
        local b=Bitmap(p);At(b,p,x,9,24,23);b:SetSolidColor('ff24394b');b.Depth:Set(107)
        local t=Label(b,5,2,20,14,C.Text);Text(t,symbol)
        local hover={Root=b,Visible=true,Lines=function()
            if action=='pause' then return {
                {Text=v.State.InstallPaused and 'Resume module work' or 'Pause module work',Color=C.Cost},
                {Text='Pauses both fitting and module removal.',Color=C.Text},
                {Text='The shield continues to operate normally.',Color=C.Muted}}
            end
            return {{Text=v.State.RepairPaused and 'Resume repair aura' or 'Pause repair aura',Color=C.Regen},
                {Text='Controls repairs to nearby structures.',Color=C.Text},
                {Text='Shield regeneration continues normally.',Color=C.Muted}}
        end}
        b.HandleEvent=function(_,event)
            if event.Type=='MouseEnter' then v.Hovered=hover;UpdateTooltip(v);return true end
            if event.Type=='MouseExit' then if v.Hovered==hover then v.Hovered=nil;HideTip(v) end;return true end
            if event.Type=='ButtonPress' then Send(action);return true end
            return false
        end
        return t
    end
    v.Pause=toggle(690,'II','pause');v.Repair=toggle(722,'+','repair')
    local tip=Group(frame,'Module Tooltip');tip.Depth:Set(200);tip.Width:Set(396);tip.Height:Set(264)
    tip:DisableHitTest();v.Tip=tip
    local tb=Rect(tip,0,0,396,264,accent,0);tb.Height:Set(tip.Height)
    local ti=Rect(tip,1,1,394,262,'fc101b29',1);ti.Height:Set(function() return tip.Height()-2 end)
    v.TipParts={tb,ti}
    v.TipLines={}
    for n=1,16 do v.TipLines[n]=Label(tip,12,12+(n-1)*20,372,n==1 and 16 or 12,C.Text) end
    HideTip(v)
    for _,row in ipairs(state.Rows) do
        local card={Controls={}}
        local root=Bitmap(p);root:SetSolidColor('00000000');root.Depth:Set(104);root.ModularId=row.Id
        card.Root=root
        local hover=Rect(root,-2,-2,64,64,accent,0);card.Hover=hover
        local icon=Bitmap(root);icon:DisableHitTest();icon.Depth:Set(105);At(icon,root,0,0,60,60);card.Icon=icon
        local tag=Label(root,4,2,54,9,C.Damage);card.Tag=tag
        local percentage=Label(root,7,22,52,16,C.Text);card.Percentage=percentage
        local badge=Label(root,43,3,20,10,C.Cost);card.Badge=badge
        local track=Rect(root,5,56,50,3,'ff263c4c',3);card.Track=track
        local progress=Rect(root,5,56,0,3,C.Special,4);card.Progress=progress
        card.Controls={root,icon,tag,percentage,badge,track,progress}
        root.HandleEvent=function(_,event)
            if event.Type=='MouseEnter' then
                card.Hovered=true;v.Hovered=card;Visible(hover,true);UpdateTooltip(v);return true
            elseif event.Type=='MouseExit' then
                card.Hovered=false;Visible(hover,false)
                if v.Hovered==card then v.Hovered=nil;HideTip(v) end
                return true
            elseif event.Type=='ButtonPress' then
                local entry=card.Data
                if not entry or v.State.Upgrading then return true end
                local right=event.Modifiers and event.Modifiers.Right
                if right then
                    if entry.Job then Send('cancel',entry.Job.JobId)
                    elseif entry.Row.Installed then Send('remove',entry.Row.Id) end
                elseif event.Modifiers and event.Modifiers.Left and not entry.Row.Installed and not entry.Job and not entry.Row.Reason then Send('install',entry.Row.Id) end
                card.Hovered=false;Visible(hover,false)
                if v.Hovered==card then v.Hovered=nil;HideTip(v) end
                return true
            end
            return false
        end
        v.Cards[row.Id]=card;ShowCard(card,false)
    end
    return v
end
local function Update()
    local selection=GetSelectedUnits() or {}
    local unit=table.getn(selection)==1 and selection[1]
    local id=unit and unit:GetEntityId()
    local data=id and UnitData[id]
    local state=data and data.ModularShield
    if not state then
        if view then view.Tip:Destroy();view.Panel:Destroy();view=nil end
        return
    end
    if not view or view.EntityId~=id then
        if view then view.Tip:Destroy();view.Panel:Destroy() end
        view=Create(state,id)
    end
    local v=view;v.State=state
    local live=data.ModularShieldLive or {HP=state.Stats.ShieldMaxHP,MaxHP=state.Stats.ShieldMaxHP,Regen=0,Damage=0,Status=''}
    Text(v.Title,(state.Faction or 'UEF')..'  /  MODULAR SHIELD',C.Text)
    Text(v.HP,string.format('HP  %.0f / %.0f',live.HP,live.MaxHP),C.HP)
    Text(v.Regen,string.format('+%.0f HP/s  %s',live.Regen,live.Status),C.Regen)
    Text(v.Damage,string.format('-%.0f HP/s  (5s avg)',live.Damage),C.Damage)
    Text(v.Slots,string.format('%d / %d slots',state.Used,state.Slots),C.Text)
    Text(v.Pause,state.InstallPaused and '>' or 'II',state.InstallPaused and C.Cost or C.Text)
    Text(v.Repair,'+',state.RepairPaused and C.Muted or C.Regen)
    local barrier=state.Barrier=='Active' and '  |  Barrier active' or (state.Barrier=='WarmingUp' and '  |  Barrier warming up' or '')
    Text(v.Info,state.LastReason and Model.Reason(state.LastReason) or string.format('Radius %.1f  |  Assisting %d  |  %.1f work/s  |  %.0f E/s upkeep  |  Power %d',state.Stats.ShieldSize/2,state.Assistants,state.WorkRate,state.ActualEnergy,state.PowerProviders or 0)..barrier,state.LastReason and C.Damage or C.Muted)
    local faction=string.lower(state.Faction or 'UEF')
    if faction~='uef' and faction~='aeon' and faction~='cybran' and faction~='seraphim' then faction='uef' end
    local members,available=Model.Lists(state)
    local visible={}
    local function place(entries,y)
        for index,entry in ipairs(entries) do
            local card=v.Cards[entry.Row.Id]
            card.Data=entry;visible[entry.Row.Id]=true
            At(card.Root,v.Panel,126+(index-1)*76,y,60,60)
            local locked=entry.Job or (not entry.Row.Installed and entry.Row.Reason)
            local texture='/mods/ModularShields/textures/modules/'..faction..'_'..entry.Row.Id..(locked and '_dim' or '')..'.dds'
            if card.Texture~=texture then card.Icon:SetTexture(texture);card.Texture=texture end
            local job=entry.Job
            local progress=job and math.min(1,job.PaidWork/job.Quote.Work) or 0
            Text(card.Percentage,job and string.format('%.0f%%',100*progress) or '',C.Text)
            Text(card.Tag,job and job.Kind=='Remove' and 'REMOVE' or '',C.Damage)
            Text(card.Badge,job and entry.Index>1 and tostring(entry.Index) or '',C.Cost)
            card.Progress.Width:Set(job and 50*progress or 0)
            card.Progress:SetSolidColor(job and job.Kind=='Remove' and C.Damage or C.Special)
        end
    end
    place(members,78);place(available,151)
    for key,card in pairs(v.Cards) do ShowCard(card,visible[key] or false) end
    UpdateTooltip(v)
end
Export={Update=Update}
return Export
