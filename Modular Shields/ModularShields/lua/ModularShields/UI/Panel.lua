local Group = import('/lua/maui/group.lua').Group
local UI = import('/lua/ui/uiutil.lua')
local L = import('/lua/maui/layouthelpers.lua')
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
local panel, signature
local page='modules'
local function Send(action,value)
    SimCallback({ Func = 'ModularShieldAction', Args = { Action = action, Value = value } },true)
end
local function Update()
    local selected = GetSelectedUnits() or {}
    local unit = table.getn(selected) == 1 and selected[1]
    local data = unit and UnitData[unit:GetEntityId()]
    local state = data and data.ModularShield
    if not state then if panel then panel:Destroy(); panel = nil end; signature = nil; return end
    local job = state.Job
    local key = tostring(unit:GetEntityId()) .. ':' .. state.Used .. ':' .. tostring(state.LastReason)
        .. ':' .. page .. ':' .. tostring(state.Barrier) .. ':' .. tostring(state.Assistants)
        .. ':' .. tostring(state.ActualEnergy) .. ':' .. tostring(state.RepairMass)
        .. ':' .. tostring(state.InstallPaused) .. ':' .. tostring(state.RepairPaused)
        .. ':' .. (job and job.Module .. math.floor(job.Progress*100) or 'idle')
    for _, row in ipairs(state.Rows) do key = key .. ':' .. tostring(row.Reason) end
    if signature == key then return end
    signature = key
    if panel then panel:Destroy() end
    local parent = GetFrame(0)
    panel = Group(parent)
    panel.Width:Set(460); panel.Height:Set(680)
    L.AtRightTopIn(panel,parent,12,60)
    local background = Bitmap(panel)
    background:SetSolidColor('ee101820'); L.FillParent(background,panel)
    local function text(value,y,size)
        local control = UI.CreateText(panel,value,size or 12,UI.bodyFont)
        L.AtLeftTopIn(control,panel,8,y)
        return control
    end
    local hint
    local function button(label,y,fn,tooltip)
        local b = text(label,y)
        b:EnableHitTest()
        b.HandleEvent = function(_,event)
            if event.Type == 'ButtonPress' then fn(); return true end
            if event.Type == 'MouseEnter' and hint and tooltip then hint:SetText(tooltip) end
        end
    end
    text('Modular Shield  ' .. state.Used .. '/' .. state.Slots .. ' slots',8,16)
    local stats = state.Stats
    text(string.format('HP %.0f   radius %.1f   regen %.0f/s',stats.ShieldMaxHP,stats.ShieldSize/2,stats.ShieldRegen),32)
    text(string.format('Upkeep %.0f base + %.0f modules; adjacency x%.2f',stats.BaseUpkeep,stats.ModuleUpkeep,state.NativeAdjacency),49)
    text(job and string.format('%s: %.0f%% (%s)',job.Module,job.Progress*100,job.State) or 'Installation idle',66)
    button(state.InstallPaused and '[Resume installation]' or '[Pause installation]',84,function() Send('pause') end)
    button(state.RepairPaused and '[Resume repair aura]' or '[Pause repair aura]',102,function() Send('repair') end)
    if job then button('[Cancel current job]',120,function() Send('cancel',job.Id) end) end
    button('[Modules / Installation queue]',139,function() page=page=='modules' and 'queue' or 'modules';signature=nil end)
    local rows=page=='modules' and state.Rows or {}
    for index, row in ipairs(rows) do
        local entry = row
        local label = entry.Installed and '[Remove] ' .. entry.Name or string.format('[Fit] %s  %.0f M / %.0f E',entry.Name,entry.Quote.Mass,entry.Quote.Energy)
        if entry.Reason and not entry.Installed then label = entry.Name .. ': ' .. entry.Reason .. (entry.Detail and ' ('..entry.Detail..')' or '') end
        if entry.Installed and stats.Dormant[entry.Id] then label=label..' (dormant: '..stats.Dormant[entry.Id]..')' end
        button(label,160+(index-1)*18,function()
            if entry.Installed then Send('remove',entry.Id)
            elseif not entry.Reason then Send('install',entry.Id) end
        end,string.format('%.0f M / %.0f E; %.0fs base; +%.0f E/s; %d slot(s)',entry.Quote.Mass,entry.Quote.Energy,
            entry.Quote.Seconds or 0,entry.Quote.Upkeep,entry.Quote.Slots or 1))
    end
    if page=='queue' then
        for index,jobEntry in ipairs(state.Queue or {}) do
            local entry=jobEntry
            button(string.format('[Cancel] %s  %s  %.0f%%',entry.ModuleId,entry.State,100*entry.PaidWork/entry.Quote.Work),160+(index-1)*36,
                function() Send('cancel',entry.JobId) end)
            text(string.format('Spent %.0f M / %.0f E; total %.0f M / %.0f E',entry.MassSpent,entry.EnergySpent,entry.Quote.Mass,entry.Quote.Energy),178+(index-1)*36)
        end
    end
    hint=text('Hover a module for its work, cost and continuing upkeep.',594)
    text(string.format('Assistants: %d   work: %.1f/s   unit draw: %.0f E/s',state.Assistants,state.WorkRate,state.ActualEnergy),612)
    text(string.format('Barrier: %s   repair: %.2f M/s',state.Barrier or 'NotInstalled',state.RepairMass),630)
    text(state.LastReason or (state.Upgrading and 'Chassis upgrade: module work retained and paused.' or 'Use the native upgrade button for T3 to T4.'),648)
    text(string.format('Custom neighbor energy multiplier: x%.2f',stats.EnergyMultiplier),666)
end
Export = { Update = Update }

return Export
