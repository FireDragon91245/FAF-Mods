local function Contains(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end
local function Requirements(req, installed, caps)
    req = req or {}
    for _, id in ipairs(req.AllModules or {}) do if not installed[id] then return { Code = 'MissingModule', Module = id } end end
    if req.AnyModules and table.getn(req.AnyModules) > 0 then
        local found = false
        for _, id in ipairs(req.AnyModules) do if installed[id] then found = true end end
        if not found then return { Code = 'MissingAnyModule' } end
    end
    for _, id in ipairs(req.Excludes or {}) do if installed[id] then return { Code = 'ExcludedModule', Module = id } end end
    for _, cap in ipairs(req.Capabilities or {}) do if not caps[cap] then return { Code = 'MissingAdjacentPower', Capability = cap } end end
end
local function Used(s, r)
    local n = 0
    for id in pairs(s.Installed) do n = n + r.Modules[id].Slots end
    for _, job in ipairs(s.Queue) do if job.Kind~='Remove' then n = n + r.Modules[job.ModuleId].Slots end end
    return n
end
local function Quote(s, id, r, config)
    local d, b = r.Modules[id], s.Base
    if not d then return nil end
    local fraction = d.CostFraction or config.LevelCost[d.CostLevel]
    return { Mass = b.Mass * fraction, Energy = b.Energy * fraction, Slots=d.Slots,Chassis=s.Chassis,
        Seconds=d.Seconds or config.LevelSeconds[d.SecondsLevel],
        Work = config.InstallRate * (d.Seconds or config.LevelSeconds[d.SecondsLevel]),
        Upkeep = b.Upkeep * d.UpkeepFraction, Version = 1 }
end
local function Eligible(s, id, r, config, includeQueue)
    local d = r.Modules[id]
    if not d then return { Code = 'UnknownModule' } end
    if not Contains(d.Chassis, s.Chassis) then return { Code = 'WrongChassis' } end
    if d.Behavior and config.Enabled[d.Behavior] == false then return { Code = 'DisabledBehavior', Behavior = d.Behavior } end
    if s.Installed[id] then return { Code = 'AlreadyInstalled' } end
    for _,existing in ipairs(r.Order) do
        if s.Installed[existing] and Contains((r.Modules[existing].Requires or {}).Excludes,id) then
            return {Code='ExcludedModule',Module=existing}
        end
    end
    local installed = {}
    for key in pairs(s.Installed) do installed[key] = true end
    for _, job in ipairs(s.Queue) do
        if job.ModuleId == id then return { Code = 'AlreadyQueued' } end
        if includeQueue then installed[job.ModuleId] = job.Kind~='Remove' or nil end
    end
    if Used(s, r) + d.Slots > config.Chassis[s.Chassis].Slots then return { Code = 'NoFreeSlot' } end
    return Requirements(d.Requires, installed, s.Capabilities)
end
local function Request(s, id, r, config)
    local reason = Eligible(s, id, r, config, true)
    if reason then return nil, reason end
    s.NextJob = s.NextJob + 1
    local job = { JobId = s.NextJob, ModuleId = id, Quote = Quote(s,id,r,config),
        State = 'Queued', PaidWork = 0, MassSpent = 0, EnergySpent = 0, SlotReservation = r.Modules[id].Slots }
    -- Lua 5.0's table.remove caches the array length. A direct assignment after
    -- completing/cancelling a job does not update it; table.insert does.
    table.insert(s.Queue,job); s.Revision = s.Revision + 1
    return job
end
local function Invalidate(s, r)
    local available, kept = {}, {}
    for id in pairs(s.Installed) do available[id] = true end
    for _, job in ipairs(s.Queue) do
        if job.Kind=='Remove' then
            if available[job.ModuleId] then table.insert(kept,job);available[job.ModuleId]=nil
            else job.State='Cancelled' end
        elseif Requirements(r.Modules[job.ModuleId].Requires, available, s.Capabilities) then job.State = 'Cancelled'
        else kept[table.getn(kept)+1] = job; available[job.ModuleId] = true end
    end
    s.Queue = kept
end
local function CanRemove(s, id, r)
    if not s.Installed[id] then return { Code = 'NotInstalled' } end
    local remaining = {}
    for key in pairs(s.Installed) do if key ~= id then remaining[key] = true end end
    for _, key in ipairs(r.Order) do
        if remaining[key] then
            local reason = Requirements(r.Modules[key].Requires, remaining, s.Capabilities)
            if reason and reason.Code ~= 'MissingAdjacentPower' then return { Code = 'DependentModule', Module = key } end
        end
    end
end
local function Remove(s,id,r)
    local reason=CanRemove(s,id,r)
    if reason then return reason end
    s.Installed[id] = nil; Invalidate(s,r); s.Revision = s.Revision + 1
end
local function CanUninstall(s,id,r)
    local reason=CanRemove(s,id,r)
    if reason then return reason end
    for _,job in ipairs(s.Queue) do
        if job.ModuleId==id then return {Code='AlreadyQueued'} end
        if job.Kind~='Remove' then
            local remaining={}
            for key in pairs(s.Installed) do if key~=id then remaining[key]=true end end
            for _,queued in ipairs(s.Queue) do
                if queued.Kind~='Remove' then remaining[queued.ModuleId]=true end
            end
            local failure=Requirements(r.Modules[job.ModuleId].Requires,remaining,s.Capabilities)
            if failure and failure.Module==id then return {Code='DependentModule',Module=job.ModuleId} end
        end
    end
end
local function RequestUninstall(s,id,r,config)
    local reason=CanUninstall(s,id,r)
    if reason then return nil,reason end
    s.NextJob=s.NextJob+1
    local job={JobId=s.NextJob,ModuleId=id,Kind='Remove',State='Queued',PaidWork=0,MassSpent=0,EnergySpent=0,
        Quote={Mass=0,Energy=0,Upkeep=0,Slots=0,Seconds=config.RemovalSeconds,Work=config.RemovalSeconds*config.InstallRate}}
    table.insert(s.Queue,job);s.Revision=s.Revision+1
    return job
end
local function Cancel(s, jobId, r)
    for i, job in ipairs(s.Queue) do
        if job.JobId == jobId then
            job.State = 'Cancelled'; table.remove(s.Queue,i); Invalidate(s,r); s.Revision = s.Revision + 1
            return
        end
    end
    return { Code = 'UnknownJob' }
end
local function Complete(s, job, r, config)
    if s.Queue[1] ~= job or job.State == 'Cancelled' then return { Code = 'InvalidJob' } end
    if job.PaidWork < job.Quote.Work then return { Code = 'UnpaidWork' } end
    if job.Kind=='Remove' then
        local reason=CanRemove(s,job.ModuleId,r)
        if reason then return reason end
        s.Installed[job.ModuleId]=nil;job.State='Completed';table.remove(s.Queue,1)
        Invalidate(s,r);s.Revision=s.Revision+1
        return
    end
    local d = r.Modules[job.ModuleId]
    local reason = Requirements(d.Requires, s.Installed, s.Capabilities)
    if reason then return reason end
    if s.Installed[d.Id] or Used(s,r) > config.Chassis[s.Chassis].Slots then return { Code = 'InvalidReservation' } end
    s.Installed[d.Id] = { Id = d.Id, Quote = job.Quote }
    job.State = 'Completed'; table.remove(s.Queue,1); s.Revision = s.Revision + 1
end
Export = { New = function(chassis, base) return { Chassis = chassis, Base = base, Installed = {}, Queue = {},
    Capabilities = {}, NextJob = 0, Revision = 0 } end,
    Requirements = Requirements, Used = Used, Quote = Quote, Eligible = Eligible,
    RequestInstall = Request, RequestRemove = Remove, RequestUninstall=RequestUninstall,
    CanRemove=CanRemove, CanUninstall=CanUninstall, RequestCancel = Cancel, Complete = Complete }

return Export
