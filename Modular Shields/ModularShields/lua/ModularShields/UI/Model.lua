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
    regen={'Works continuously, including under fire.','Vanilla and power bonuses wait for no damage.'},
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
local function Tooltip(entry,state)
    local row,job=entry.Row,entry.Job
    local lines={}
    local function add(text,color) table.insert(lines,{Text=text,Color=color or Colors.Text}) end
    add(Title(row),row.Family=='power' and Colors.HP or (row.Family=='range' and Colors.Range or
        ((row.Family=='regen' or row.Family=='repair') and Colors.Regen or Colors.Special)))
    if job then add((job.Kind=='Remove' and 'Removing: ' or 'Installing: ')..string.format('%.0f%%',100*job.PaidWork/job.Quote.Work)..
        (job.State=='WaitingForSlots' and ' (waiting for module capacity)' or
        ((job.State=='Queued' or job.State=='Paused') and ' ('..job.State..')' or '')),Colors.Cost)
    else add(row.Installed and 'Installed module' or 'Available upgrade',Colors.Muted) end
    local d=row.Deltas or {}
    local sign=row.Installed and -1 or 1
    local suffix=row.Installed and ' on removal' or ''
    if d.ShieldMaxHP and d.ShieldMaxHP~=0 then add(string.format('%+.0f maximum shield HP',sign*d.ShieldMaxHP)..suffix,Colors.HP) end
    if d.ShieldRegen and d.ShieldRegen~=0 then add(string.format('%+.0f shield HP / second',sign*d.ShieldRegen)..suffix,Colors.Regen) end
    if d.ShieldSize and d.ShieldSize~=0 then add(string.format('%+.1f shield radius',sign*d.ShieldSize/2)..suffix,Colors.Range) end
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
    if job then add(job.Kind=='Remove' and 'Right-click: cancel removal; keep module.' or 'Right-click: cancel; spent resources are lost.',Colors.Text)
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
Export={Colors=Colors,Families=Families,Title=Title,Lists=Lists,Tooltip=Tooltip,Reason=Reason}
return Export
