local Group=import('/lua/maui/group.lua').Group
local UI=import('/lua/ui/uiutil.lua')
local L=import('/lua/maui/layouthelpers.lua')
local Bitmap=import('/lua/maui/bitmap.lua').Bitmap
local view

local function Send(action,value)
    SimCallback({Func='ModularShieldAction',Args={Action=action,Value=value}},true)
end

local function SetText(control,value)
    if control.ModularText~=value then control:SetText(value);control.ModularText=value end
end

local function Show(control,visible)
    if visible then control:Show() else control:Hide() end
end

local function ShowPage(v)
    local modules=v.Page=='modules'
    for _,row in pairs(v.Rows) do Show(row.Button,modules);Show(row.Detail,modules) end
    for _,row in ipairs(v.QueueRows) do
        local visible=not modules and row.Data~=nil
        Show(row.Button,visible);Show(row.Detail,visible)
    end
end

local function Create(state,entityId)
    local parent=GetFrame(0)
    local panel=Group(parent,'Modular Shield Panel')
    panel.Width:Set(460);panel.Height:Set(680)
    -- Above the world view; do not let its input surface steal module clicks.
    panel.Depth:Set(100)
    L.AtRightTopIn(panel,parent,12,50)
    local background=Bitmap(panel)
    background:SetSolidColor('ee101820')
    background.Depth:Set(function() return panel.Depth() end)
    background:DisableHitTest()
    L.FillParent(background,panel)
    panel.HandleEvent=function(_,event)
        return event.Type=='ButtonPress' or event.Type=='ButtonDClick'
    end
    local v={Panel=panel,EntityId=entityId,Page='modules',Rows={},QueueRows={},State=state}
    local function text(owner,x,y,width,size)
        local t=UI.CreateText(owner,'',size or 12,UI.bodyFont)
        t:DisableHitTest()
        t:SetClipToWidth(true);t.Width:Set(width or 444)
        t.Depth:Set(function() return panel.Depth()+4 end)
        L.AtLeftTopIn(t,owner,x,y)
        return t
    end
    local function button(owner,x,y,width,label,action)
        local b=UI.CreateButtonStd(owner,'/scx_menu/small-btn/small',label,11,0,0)
        b.Width:Set(width);b.Height:Set(24)
        b.Depth:Set(function() return panel.Depth()+3 end)
        L.AtLeftTopIn(b,owner,x,y)
        b.OnClick=action
        b:Enable()
        return b
    end
    v.Title=text(panel,8,8,444,16)
    v.Stats=text(panel,8,32)
    v.Upkeep=text(panel,8,49)
    v.Job=text(panel,8,66)
    v.Pause=button(panel,8,86,216,'Pause installation',function() Send('pause') end)
    v.Repair=button(panel,236,86,216,'Pause repair aura',function() Send('repair') end)
    v.Cancel=button(panel,8,116,216,'Cancel current job',function()
        if v.State.Job then Send('cancel',v.State.Job.Id) end
    end)
    v.Tab=button(panel,236,116,216,'Show installation queue',function()
        v.Page=v.Page=='modules' and 'queue' or 'modules'
        Show(v.Modules,v.Page=='modules');Show(v.Queue,v.Page=='queue')
        ShowPage(v)
    end)
    v.Modules=Group(panel,'Module Buttons');L.FillParent(v.Modules,panel)
    v.Queue=Group(panel,'Installation Queue');L.FillParent(v.Queue,panel);v.Queue:Hide()
    -- Groups have no painted input surface; only buttons accept module clicks.
    v.Modules:DisableHitTest();v.Queue:DisableHitTest()
    local perColumn=math.ceil(table.getn(state.Rows)/2)
    local rowHeight=math.min(36,432/math.max(1,perColumn))
    for index,row in ipairs(state.Rows) do
        local id=row.Id
        local column=math.floor((index-1)/perColumn)
        local x=8+column*228
        local y=154+math.mod(index-1,perColumn)*rowHeight
        local controls={}
        controls.Button=button(v.Modules,x,y,216,'',function()
            local current=v.Rows[id].Data
            if current.Installed then Send('remove',id)
            elseif not current.Reason then Send('install',id) end
        end)
        controls.Detail=text(v.Modules,x+4,y+24,208,10)
        controls.Button.OnRolloverEvent=function(_,event)
            local current=v.Rows[id].Data
            if event=='enter' and current then
                local q=current.Quote
                SetText(v.Hint,string.format('%.0f M / %.0f E | %.0fs | +%.0f E/s | %d slot(s)',
                    q.Mass,q.Energy,q.Seconds or 0,q.Upkeep,q.Slots or 1))
            end
        end
        v.Rows[id]=controls
    end
    for index=1,state.Slots do
        local slot=index
        local controls={}
        controls.Button=button(v.Queue,8,154+(index-1)*48,444,'',function()
            local job=v.QueueRows[slot].Data
            if job then Send('cancel',job.JobId) end
        end)
        controls.Detail=text(v.Queue,12,180+(index-1)*48,436,11)
        v.QueueRows[index]=controls
    end
    v.Hint=text(panel,8,596)
    v.Assist=text(panel,8,614)
    v.Barrier=text(panel,8,632)
    v.Reason=text(panel,8,650)
    SetText(v.Hint,'Hover a button for its cost, work and continuing upkeep.')
    return v
end

local function Update()
    local selected=GetSelectedUnits() or {}
    local unit=table.getn(selected)==1 and selected[1]
    local entityId=unit and unit:GetEntityId()
    local data=entityId and UnitData[entityId]
    local state=data and data.ModularShield
    if not state then
        if view then view.Panel:Destroy();view=nil end
        return
    end
    if not view or view.EntityId~=entityId then
        if view then view.Panel:Destroy() end
        view=Create(state,entityId)
    end
    local v=view
    v.State=state
    local stats,job=state.Stats,state.Job
    SetText(v.Title,'Modular Shield  '..state.Used..'/'..state.Slots..' slots')
    SetText(v.Stats,string.format('HP %.0f | radius %.1f | regen %.0f/s',stats.ShieldMaxHP,stats.ShieldSize/2,stats.ShieldRegen))
    SetText(v.Upkeep,string.format('Upkeep %.0f + %.0f E/s | adjacency x%.2f',stats.BaseUpkeep,stats.ModuleUpkeep,state.NativeAdjacency))
    SetText(v.Job,job and string.format('%s: %.0f%% (%s)',job.Module,100*job.Progress,job.State) or 'Installation idle')
    SetText(v.Pause.label,state.InstallPaused and 'Resume installation' or 'Pause installation')
    SetText(v.Repair.label,state.RepairPaused and 'Resume repair aura' or 'Pause repair aura')
    SetText(v.Tab.label,v.Page=='modules' and 'Show installation queue' or 'Show modules')
    if job then v.Cancel:Enable() else v.Cancel:Disable() end
    for _,row in ipairs(state.Rows) do
        local controls=v.Rows[row.Id]
        controls.Data=row
        SetText(controls.Button.label,(row.Installed and 'Remove ' or 'Fit ')..row.Name)
        if row.Installed or not row.Reason then controls.Button:Enable() else controls.Button:Disable() end
        local detail
        if row.Installed then detail=stats.Dormant[row.Id] or 'Installed'
        elseif row.Reason then detail=row.Reason..(row.Detail and ': '..row.Detail or '')
        else detail=string.format('%.0f M / %.0f E',row.Quote.Mass,row.Quote.Energy) end
        SetText(controls.Detail,detail)
    end
    for index,controls in ipairs(v.QueueRows) do
        local pending=(state.Queue or {})[index]
        controls.Data=pending
        if pending then
            SetText(controls.Button.label,string.format('Cancel %s | %.0f%% (%s)',pending.ModuleId,100*pending.PaidWork/pending.Quote.Work,pending.State))
            SetText(controls.Detail,string.format('Paid %.0f M / %.0f E of %.0f M / %.0f E',pending.MassSpent,pending.EnergySpent,pending.Quote.Mass,pending.Quote.Energy))
        end
    end
    ShowPage(v)
    SetText(v.Assist,string.format('Assistants: %d | work: %.1f/s | draw: %.0f E/s',state.Assistants,state.WorkRate,state.ActualEnergy))
    SetText(v.Barrier,string.format('Barrier: %s | repair: %.2f M/s',state.Barrier or 'NotInstalled',state.RepairMass))
    SetText(v.Reason,state.LastReason or (state.Upgrading and 'Chassis upgrade: module work retained and paused.' or 'Module buttons above; chassis upgrade in the native command bar.'))
end

Export={Update=Update}
return Export
