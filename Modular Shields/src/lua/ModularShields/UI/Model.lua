local Colors={HP='ff55adff',Regen='ff6de595',Damage='ffff737e',Special='ffffa44f',
    Range='ff6cd8f0',Text='ffe4edf5',Muted='ff91a5b8',Cost='ffedce86'}
local Families={'power','range','regen','repair','deflector','atomized','ballistic','impenetrable'}
local Names={power='Shield capacity',range='Shield radius',regen='Regeneration',repair='Structure repair',
    deflector='Deflector',atomized='Nuclear containment',ballistic='Missile defense',impenetrable='Impenetrable'}
local Descriptions={
    deflector={'Deflects crashing aircraft and selected','slow projectiles away from the shield.'},
    atomized={'Contains intercepted nuclear explosions.','The shield absorbs the blast damage.'},
    ballistic={'Intercepts hostile missiles and rockets,','including supported shield-bypassing weapons.'},
    impenetrable={'Blocks hostile ground/air units and projectiles.','Unit impacts cost shield HP by unit weight.'},
    regen={'Adds this HP/s under fire and at peace.','At peace: base + modules + neighbor regen.'},
}
local Reasons={NoFreeSlot='All module slots are reserved.',WrongChassis='Requires a T4 generator.',
    MissingModule='Requires module',MissingAdjacentPower='Requires an edge-adjacent T2+ generator.',
    AlreadyQueued='Already in the installation queue.',DependentModule='Required by module',
    ChassisUpgrading='Module work pauses during chassis upgrading.',NotInstalled='Module is not installed.'}
Reasons.OverCapacity='Not enough slots; restore adjacent mass storage.'
Reasons.DependencyInactive='A required module is dormant.'
local function Reason(code,detail)
    local _,_,parsed,tail=string.find(code or '','^([^:]+):%s*(.*)$')
    if parsed then code=parsed;detail=detail or tail end
    return (Reasons[code] or code or '')..(detail and ': '..string.gsub(detail,'_',' ') or '')
end
local function Title(row)
    local family=row.Family
    local title=Names[family] or row.Name
    if family=='power' or family=='range' or family=='regen' or family=='repair' then
        title=title..' '..({'I','II','III','IV','V'})[row.Level or 1]
    end
    return title
end
local function Lists(state)
    local rows,queued,members,available={},{},{},{}
    for _,row in ipairs(state.Rows) do rows[row.Id]=row end
    for index,job in ipairs(state.Queue or {}) do queued[job.ModuleId]={Job=job,Index=index} end
    for _,family in ipairs(Families) do
        local candidate
        for _,row in ipairs(state.Rows) do
            if row.Family==family then
                if row.Installed then
                    local pending=queued[row.Id]
                    table.insert(members,{Row=row,Job=pending and pending.Job,Index=pending and pending.Index})
                elseif not queued[row.Id] and (not candidate or row.Level<candidate.Level) then candidate=row end
            end
        end
        if candidate then table.insert(available,{Row=candidate}) end
    end
    for index,job in ipairs(state.Queue or {}) do
        local row=rows[job.ModuleId]
        if row and not row.Installed then table.insert(members,{Row=row,Job=job,Index=index}) end
    end
    return members,available
end
local function Requirements(req,available,caps)
    req=req or {}
    for _,id in ipairs(req.AllModules or {}) do if not available[id] then return 'MissingModule',id end end
    if req.AnyModules and table.getn(req.AnyModules)>0 then
        local found=false;for _,id in ipairs(req.AnyModules) do if available[id] then found=true end end
        if not found then return 'MissingAnyModule' end
    end
    for _,id in ipairs(req.Excludes or {}) do if available[id] then return 'ExcludedModule',id end end
    for _,cap in ipairs(req.Capabilities or {}) do if not caps[cap] then return 'MissingAdjacentPower',cap end end
    return false,false
end
-- Replay unacknowledged UI actions in send order over the authoritative snapshot.
-- Cancels remove their job and invalidate dependents just like Core.Loadout.Cancel.
local function Project(state,pending,now)
    local result={};for key,value in pairs(state) do result[key]=value end
    result.Rows={};result.Queue={};result.Used=state.Used
    local rows,available,queued={},{},{}
    for _,row in ipairs(state.Rows) do
        local copy={};for key,value in pairs(row) do copy[key]=value end
        table.insert(result.Rows,copy);rows[row.Id]=copy
    end
    for _,job in ipairs(state.Queue or {}) do table.insert(result.Queue,job) end
    local function indexQueue()
        available={};queued={}
        for _,row in ipairs(result.Rows) do if row.Installed then available[row.Id]=true end end
        for _,job in ipairs(result.Queue) do queued[job.ModuleId]=true;available[job.ModuleId]=job.Kind~='Remove' or nil end
    end
    local function release(job)
        if job.Kind~='Remove' then result.Used=result.Used-((rows[job.ModuleId].Quote or {}).Slots or 1) end
    end
    local function cancel(request)
        local queue,found={},false
        for _,job in ipairs(result.Queue) do
            local target=(request.JobId and job.JobId==request.JobId) or
                (request.CancelRequestId and (job.RequestId or job.UIRequestId)==request.CancelRequestId)
            if target then release(job);found=true else table.insert(queue,job) end
        end
        if not found then return end
        local installed={}
        for _,row in ipairs(result.Rows) do if row.Installed then installed[row.Id]=true end end
        result.Queue={}
        for _,job in ipairs(queue) do
            local valid
            if job.Kind=='Remove' then valid=installed[job.ModuleId]
            else valid=not Requirements(rows[job.ModuleId].Requires,installed,state.Capabilities or {}) end
            if valid then table.insert(result.Queue,job);installed[job.ModuleId]=job.Kind~='Remove' or nil
            else release(job) end
        end
    end
    indexQueue()
    local kept={}
    for _,request in ipairs(pending) do
        local row=rows[request.ModuleId]
        local acknowledged=request.Ticket and request.Ticket:Status()~='pending'
        if not acknowledged and now<request.Expires and row then
            table.insert(kept,request)
            if request.Action=='cancel' then cancel(request)
            elseif not row.Installed and not queued[row.Id] then
                table.insert(result.Queue,{ModuleId=row.Id,JobId=false,RequestId=request.RequestId,Pending=true,State='Sending',PaidWork=0,Quote=row.Quote})
                result.Used=result.Used+(row.Quote.Slots or 1)
            end
            indexQueue()
        end
    end
    if table.getn(kept)>0 then
        for _,row in ipairs(result.Rows) do
            if not row.Installed then
                local reason,detail=row.Reason,row.Detail
                if queued[row.Id] then reason='AlreadyQueued'
                elseif not reason or reason=='AlreadyQueued' or reason=='MissingModule' or reason=='MissingAnyModule' or reason=='ExcludedModule' or reason=='NoFreeSlot' then
                    if result.Used+(row.Quote.Slots or 1)>result.Slots then reason='NoFreeSlot';detail=false
                    else reason,detail=Requirements(row.Requires,available,state.Capabilities or {}) end
                end
                row.Reason=reason;row.Detail=detail
            end
        end
    end
    return result,kept
end
local function Tooltip(entry,state)
    local row,job=entry.Row,entry.Job
    local lines={}
    local function add(text,color) table.insert(lines,{Text=text,Color=color or Colors.Text}) end
    add(Title(row),row.Family=='power' and Colors.HP or (row.Family=='range' and Colors.Range or
        ((row.Family=='regen' or row.Family=='repair') and Colors.Regen or Colors.Special)))
    if job and job.Pending then add('Sending installation request...',Colors.Cost)
    elseif job then add((job.Kind=='Remove' and 'Removing: ' or 'Installing: ')..string.format('%.0f%%',100*job.PaidWork/job.Quote.Work)..
        (job.State=='WaitingForSlots' and ' (waiting for module capacity)' or
        ((job.State=='Queued' or job.State=='Paused') and ' ('..job.State..')' or '')),Colors.Cost)
    else add(row.Installed and 'Installed module' or 'Available upgrade',Colors.Muted) end
    local d=row.Deltas or {}
    local sign=row.Installed and -1 or 1
    local suffix=row.Installed and ' on removal' or ''
    if d.ShieldMaxHP and d.ShieldMaxHP~=0 then add(string.format('%+.0f maximum shield HP',sign*d.ShieldMaxHP)..suffix,Colors.HP) end
    if d.ShieldRegen and d.ShieldRegen~=0 then add(string.format('%+.0f shield HP / second',sign*d.ShieldRegen)..suffix,Colors.Regen) end
    if d.ShieldSize and d.ShieldSize~=0 then add(string.format('%+.0f shield radius',sign*d.ShieldSize/2)..suffix,Colors.Range) end
    if d.RepairBudget and d.RepairBudget~=0 then add(string.format('%+.0f structure HP / second',sign*d.RepairBudget)..suffix,Colors.Regen) end
    for _,text in ipairs(Descriptions[row.Family] or {}) do add(text,row.Family=='regen' and Colors.Regen or Colors.Special) end
    if row.Id=='impenetrable' then
        add('Requires ALL installed special modules:',Colors.Special)
        for _,required in ipairs({'deflector','atomized','ballistic'}) do
            local installed=false
            for _,other in ipairs(state.Rows) do if other.Id==required then installed=other.Installed end end
            add((installed and '[ready] ' or '[missing] ')..({deflector='Deflector',atomized='Atomized (nuclear containment)',ballistic='Ballistic (missile defense)'})[required],Colors.Special)
        end
        add('T4 + completed own T2+ power generator.',Colors.Special)
        add('Share a footprint edge; corners do not count.',Colors.Muted)
        add('T1 generators and all storage are excluded.',Colors.Muted)
        add('Powered dome; 3s warmup after support returns.',Colors.Muted)
    end
    if d.Upkeep then add(string.format('%+.0f energy / second upkeep',sign*d.Upkeep)..suffix,Colors.Cost) end
    if row.Installed then
        local dormant=state.Stats.Dormant[row.Id]
        if dormant then add('Dormant: '..Reason(dormant),Colors.Damage) end
    else
        add(string.format('%.0f mass  |  %.0f energy',row.Quote.Mass,row.Quote.Energy),Colors.Cost)
        add(string.format('%.0fs base installation  |  %d slot(s)',row.Quote.Seconds,row.Quote.Slots or 1),Colors.Muted)
    end
    if job and job.Pending then add('Right-click: cancel pending installation.',Colors.Text)
    elseif job then add(job.Kind=='Remove' and 'Right-click: cancel removal; keep module.' or 'Right-click: cancel; spent resources are lost.',Colors.Text)
    elseif row.Installed then
        add(string.format('Right-click: remove (%.0fs base, no refund).',state.RemovalSeconds or 5),Colors.Text)
        if row.RemoveReason then add(Reason(row.RemoveReason.Code,row.RemoveReason.Module),Colors.Damage) end
    else
        add('Left-click: install this upgrade.',Colors.Text)
        if row.Reason then add(Reason(row.Reason,row.Detail),Colors.Damage) end
    end
    if state.Upgrading then add(Reason('ChassisUpgrading'),Colors.Damage) end
    return lines
end
Export={Colors=Colors,Families=Families,Title=Title,Lists=Lists,Tooltip=Tooltip,Reason=Reason,Project=Project}
return Export
