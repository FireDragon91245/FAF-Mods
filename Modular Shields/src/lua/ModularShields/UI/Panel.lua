local UI=import('/mods/FireDragonModLoader/lua/FireDragon/UI.lua').Export
local function Group(parent,name) return UI.Panel(parent,{name=name}) end
local function Bitmap(parent) return UI.Icon(parent,{color='00000000'}) end
local Model=import('/mods/ModularShields/lua/ModularShields/UI/Model.lua').Export
local Exchange=import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export
local Messages=import('/mods/ModularShields/lua/ModularShields/Messages.lua').Export
local C=Model.Colors
local view
local Update
local function Submit(v,action,value,cancelRequestId)
    local ticket=Exchange.Sim.Request(Messages.Action,{EntityId=v.EntityId,Action=action,Value=value,CancelRequestId=cancelRequestId},{replyMode='First'})
    table.insert(v.Actions,ticket);return ticket
end
local function Send(action,value) if view then return Submit(view,action,value) end end
local function QueueRequest(v,action,row,job)
    local now=GetSystemTimeSeconds()
    local jobId=job and job.JobId or nil
    local cancelRequestId=job and not jobId and job.RequestId or nil
    local value=row.Id;if action=='cancel' then value=jobId end
    local ticket=Submit(v,action,value,cancelRequestId)
    table.insert(v.Pending,{Action=action,ModuleId=row.Id,RequestId=ticket.Key,Ticket=ticket,JobId=jobId,CancelRequestId=cancelRequestId,Expires=now+5})
    Update() -- render before the sim has processed installs or cancels
end
local function Text(control,value,color)
    if control.Value~=value then control:SetText(value);control.Value=value end
    if color and control.Tint~=color then control:SetColor(color);control.Tint=color end
end
local function Visible(control,value) if value then control:Show() else control:Hide() end end
local At=UI.At
local function Label(parent,x,y,w,size,color)
    return UI.Label(parent,{x=x,y=y,width=w,height=size+4,size=size,color=color or C.Text})
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
    if v.Window:IsHidden() or not v.Hovered or not v.Hovered.Visible then HideTip(v);return end
    local card=v.Hovered
    local lines=card.Lines and card.Lines() or Model.Tooltip(card.Data,v.State)
    v.Tip.Height:Set(24+table.getn(lines)*20)
    local frame=GetFrame(0)
    local anchor=card.Root.FDHit or card.Root
    v.Tip.Left:Set(function() return math.max(frame.Left()+8,math.min(frame.Right()-v.Tip.Width()-8,anchor.Left())) end)
    v.Tip.Top:Set(function()
        local above=anchor.Top()-v.Tip.Height()-8
        local y=above>=frame.Top()+8 and above or anchor.Top()+anchor.Height()+8
        return math.max(frame.Top()+8,math.min(frame.Bottom()-v.Tip.Height()-8,y))
    end)
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
    local window=UI.Window(frame,{name='Modular Shield Window',title=(state.Faction or 'UEF')..' / Modular Shield',
        prefKey='FireDragon_ModularShields_Window',x=(frame.Width()-780)/2,y=math.max(8,frame.Height()-650),width=780,height=450,minWidth=420,minHeight=260})
    local scroll=UI.Scroll(window.Client,{contentWidth=760,contentHeight=373});UI.Fill(scroll,window.Client,6)
    local p=scroll.Content
    local v={Panel=p,Window=window,Scroll=scroll,EntityId=id,State=state,Cards={},Pending={},Actions={}}
    scroll.OnScroll=function()
        if v.Hovered and v.Hovered.Hover then v.Hovered.Hover:Hide();v.Hovered.Hovered=false end
        v.Hovered=nil;HideTip(v)
    end
    local onHide=window.OnHide
    window.OnHide=function(self,hidden) onHide(self,hidden);if hidden and v.Tip then HideTip(v) end end
    local accents={UEF='ff69b8fa',AEON='ff74e4bb',CYBRAN='fff67b83',SERAPHIM='ffefca78'}
    local accent=accents[state.Faction] or accents.UEF
    v.Title=window.Title
    v.HP=Label(p,16,5,270,17,C.HP)
    v.Regen=Label(p,296,6,210,15,C.Regen)
    v.Damage=Label(p,518,6,224,15,C.Damage)
    v.HPSources={};v.RegenSources={}
    for n=1,3 do
        v.HPSources[n]=Label(p,16,33+(n-1)*20,270,12,C.HP)
        v.RegenSources[n]=Label(p,296,33+(n-1)*20,446,12,C.Regen)
    end
    v.Neighbors=Label(p,16,98,728,11,C.Cost)
    v.Modules=Label(p,16,133,104,12,C.Muted);Text(v.Modules,'MODULES')
    v.Slots=Label(p,16,152,108,12,C.Text)
    v.Upgrades=Label(p,16,128,108,12,C.Muted);Text(v.Upgrades,'UPGRADES')
    v.Hint=Label(p,16,148,108,10,C.Muted);Text(v.Hint,'Click to fit')
    v.Info=Label(p,16,190,728,11,C.Muted)
    local function toggle(offset,symbol,action)
        local b=UI.Button(window.TitleBar,{x=function() return window.Width()-offset end,y=3,width=24,height=24,text=symbol,onClick=function() Send(action) end})
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
        local handle=b.HandleEvent
        b.HandleEvent=function(self,event)
            if event.Type=='MouseEnter' then v.Hovered=hover;UpdateTooltip(v) end
            if event.Type=='MouseExit' and v.Hovered==hover then v.Hovered=nil;HideTip(v) end
            return handle(self,event)
        end
        UI.Interactive(b)
        return b
    end
    v.Pause=toggle(84,'II','pause');v.Repair=toggle(56,'+','repair')
    window.Title.Width:Set(function() return math.max(0,window.Width()-102) end)
    local tip=Group(frame,'Module Tooltip');tip.Depth:Set(function() return window.Depth()+120 end);tip.Width:Set(396);tip.Height:Set(264)
    tip:DisableHitTest();v.Tip=tip
    local tb=UI.FrameSkin(tip)
    local ti=Rect(tip,12,3,372,2,accent,1)
    v.TipParts={tb,ti}
    v.TipLines={}
    for n=1,22 do v.TipLines[n]=Label(tip,12,12+(n-1)*20,372,n==1 and 16 or 12,C.Text) end
    HideTip(v)
    for _,row in ipairs(state.Rows) do
        local card={Controls={}}
        local root=Bitmap(p);root:SetSolidColor('00000000');root.Depth:Set(function() return p.Depth()+4 end);root.ModularId=row.Id
        card.Root=root
        local hover=Rect(root,-2,-2,64,64,accent,0);card.Hover=hover
        local icon=Bitmap(root);icon:DisableHitTest();icon.Depth:Set(function() return root.Depth()+2 end);At(icon,root,0,0,60,60);card.Icon=icon
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
                    if entry.Job then QueueRequest(v,'cancel',entry.Row,entry.Job)
                    elseif entry.Row.Installed then Send('remove',entry.Row.Id) end
                elseif event.Modifiers and event.Modifiers.Left and not entry.Row.Installed and not entry.Job and not entry.Row.Reason then QueueRequest(v,'install',entry.Row) end
                card.Hovered=false;Visible(hover,false)
                if v.Hovered==card then v.Hovered=nil;HideTip(v) end
                return true
            end
            return false
        end
        UI.Interactive(root)
        v.Cards[row.Id]=card;ShowCard(card,false)
    end
    return v
end
Update=function()
    local selection=GetSelectedUnits() or {}
    local unit=table.getn(selection)==1 and selection[1]
    local id=unit and unit:GetEntityId()
    local state=id and Exchange.GetState(Messages.Status,id)
    if not state then
        if view then view.Tip:Destroy();view.Window:Destroy();view=nil end
        return
    end
    if not view or view.EntityId~=id then
        if view then view.Tip:Destroy();view.Window:Destroy() end
        view=Create(state,id)
    end
    local v=view
    local active={}
    for _,ticket in ipairs(v.Actions) do
        local response=ticket:Poll()
        if response then
            v.RequestError=response.error or (response.value and not response.value.Accepted and response.value.Reason) or nil
        end
        if ticket:Status()=='pending' then table.insert(active,ticket)
        elseif ticket.Error then v.RequestError=ticket.Error end
    end
    v.Actions=active
    state,v.Pending=Model.Project(state,v.Pending,GetSystemTimeSeconds())
    v.State=state
    local live=Exchange.GetState(Messages.Live,id) or {HP=state.Stats.ShieldMaxHP,MaxHP=state.Stats.ShieldMaxHP,Regen=0,Damage=0,Status=''}
    if v.RequestError then state.LastReason=v.RequestError end
    Text(v.Title,(state.Faction or 'UEF')..' / Modular Shield',C.Text)
    Text(v.HP,string.format('HP  %.0f / %.0f',live.HP,live.MaxHP),C.HP)
    Text(v.Regen,string.format('+%.0f HP/s  %s',live.Regen,live.Status),C.Regen)
    Text(v.Damage,string.format('-%.0f HP/s  (5s avg)',live.Damage),C.Damage)
    Text(v.Slots,string.format('%d / %d slots',state.Used,state.Slots),state.Used>state.Slots and C.Damage or C.Text)
    local hp={live.BaseHP or state.Stats.BaseHP or state.Stats.ShieldMaxHP,live.ModuleHP or state.Stats.ModuleHP or 0,live.NeighborHP or state.Stats.NeighborHP or 0}
    local regen={live.BaseRegen or 0,live.ModuleRegen or 0,live.NeighborRegen or 0}
    local hpLabels={'initial HP','module HP','neighbor storage HP'}
    local regenLabels={'non-damage vanilla regen','module regen (under fire too)','neighbor power regen'}
    for n=1,3 do
        Text(v.HPSources[n],string.format('%+.0f from %s',hp[n],hpLabels[n]),C.HP)
        Text(v.RegenSources[n],string.format('%+.0f HP/s from %s',regen[n],regenLabels[n]),C.Regen)
    end
    local neighbors=state.Neighbors or {}
    Text(v.Neighbors,string.format('Neighbors: %.0f E/s power | %d energy storage | %d mass storage | Slots: %d base + %d mass | Upkeep %.0f%%',neighbors.Production or 0,neighbors.EnergyStorage or 0,neighbors.MassStorage or 0,state.BaseSlots or state.Slots,state.BonusSlots or 0,100*(state.NativeAdjacency or 1)),C.Cost)
    Text(v.Pause.Label,state.InstallPaused and '>' or 'II')
    v.Pause:SetTextColor(state.InstallPaused and C.Cost or C.Text)
    v.Repair:SetTextColor(state.RepairPaused and C.Muted or C.Regen)
    local barrier=state.Barrier=='Active' and '  |  Barrier active' or (state.Barrier=='WarmingUp' and '  |  Barrier warming up' or '')
    Text(v.Info,state.Used>state.Slots and 'Over capacity: excess modules are dormant. Restore mass storage or remove modules.' or (state.LastReason and Model.Reason(state.LastReason) or string.format('Radius %.0f  |  Assisting %d  |  %.0f work/s  |  %.0f E/s upkeep  |  Power %d',state.Stats.ShieldSize/2,state.Assistants,state.WorkRate,state.ActualEnergy,state.PowerProviders or 0)..barrier),(state.LastReason or state.Used>state.Slots) and C.Damage or C.Muted)
    local faction=string.lower(state.Faction or 'UEF')
    if faction~='uef' and faction~='aeon' and faction~='cybran' and faction~='seraphim' then faction='uef' end
    local members,available=Model.Lists(state)
    local memberRows=math.max(1,math.ceil(table.getn(members)/8))
    local upgradeY=128+memberRows*73
    local upgradeRows=math.max(1,math.ceil(table.getn(available)/8))
    local infoY=upgradeY+upgradeRows*73+8
    v.Panel.Height:Set(infoY+24)
    v.Scroll:ScrollTo()
    At(v.Upgrades,v.Panel,16,upgradeY+7)
    At(v.Hint,v.Panel,16,upgradeY+27)
    At(v.Info,v.Panel,16,infoY)
    local visible={}
    local function place(entries,y)
        for index,entry in ipairs(entries) do
            local card=v.Cards[entry.Row.Id]
            card.Data=entry;visible[entry.Row.Id]=true
            At(card.Root,v.Panel,126+math.mod(index-1,8)*76,y+math.floor((index-1)/8)*73,60,60)
            local dormant=state.Stats.Dormant[entry.Row.Id]
            local locked=entry.Job or dormant or (not entry.Row.Installed and entry.Row.Reason)
            local texture='/mods/ModularShields/textures/modules/'..faction..'_'..entry.Row.Id..(locked and '_dim' or '')..'.dds'
            if card.Texture~=texture then card.Icon:SetTexture(texture);card.Texture=texture end
            local job=entry.Job
            local progress=job and math.min(1,job.PaidWork/job.Quote.Work) or 0
            Text(card.Percentage,job and (job.Pending and '...' or string.format('%.0f%%',100*progress)) or '',C.Text)
            Text(card.Tag,job and job.Kind=='Remove' and 'REMOVE' or (dormant and 'DORMANT' or ''),C.Damage)
            Text(card.Badge,job and entry.Index>1 and tostring(entry.Index) or '',C.Cost)
            card.Progress.Width:Set(job and 50*progress or 0)
            card.Progress:SetSolidColor(job and job.Kind=='Remove' and C.Damage or C.Special)
        end
    end
    place(members,128);place(available,upgradeY)
    for key,card in pairs(v.Cards) do ShowCard(card,visible[key] or false) end
    UpdateTooltip(v)
end
Export={Update=Update}
return Export
