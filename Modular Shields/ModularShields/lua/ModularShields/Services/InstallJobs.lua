local Assist=import('/mods/ModularShields/lua/ModularShields/Adapters/Assistance.lua').Export
local function Stop(host)
    host.ModuleEpoch=(host.ModuleEpoch or 0)+1
    if host.ModuleEvent then RemoveEconomyEvent(host,host.ModuleEvent);host.ModuleEvent=nil end
    if host.ModuleThread then KillThread(host.ModuleThread);host.ModuleThread=nil end
    Assist.ReleaseAll(host)
end
local function Start(host,R)
    if host.ModuleThread or host.InstallPaused or host.ModuleUpgrading or table.getn(host.Loadout.Queue)==0 then return end
    local epoch=host.ModuleEpoch or 0
    host.ModuleThread=host:ForkThread(function()
        WaitTicks(1)
        while not host.Dead and table.getn(host.Loadout.Queue)>0 and not host.InstallPaused and not host.ModuleUpgrading do
            local s,core=host.Loadout,R.Core
            local job=s.Queue[1]
            local reason=core.Requirements(R.Registry.Modules[job.ModuleId].Requires,s.Installed,s.Capabilities)
            if reason then core.RequestCancel(s,job.JobId,R.Registry)
            else
                job.State='Building'
                while job.PaidWork<job.Quote.Work and not host.Dead do
                    local rate=Assist.Rate(host,R.Config)
                    local before=job.PaidWork
                    local work=math.min(rate*R.Config.InstallSliceSeconds,job.Quote.Work-before)
                    local fraction=work/job.Quote.Work
                    local fulfilled=0
                    host.ModuleEvent=CreateEconomyEvent(host,job.Quote.Energy*fraction,job.Quote.Mass*fraction,
                        math.max(.1,work/rate),function(_,progress)
                            if (host.ModuleEpoch or 0)~=epoch then return end
                            fulfilled=math.max(fulfilled,math.min(1,math.max(0,progress)))
                            job.PaidWork=math.min(job.Quote.Work,before+work*fulfilled)
                            job.MassSpent=job.Quote.Mass*job.PaidWork/job.Quote.Work
                            job.EnergySpent=job.Quote.Energy*job.PaidWork/job.Quote.Work
                        end)
                    repeat
                        WaitTicks(1)
                        -- Reconcile during resource stalls as well as paid work.
                        local nextRate=Assist.Rate(host,R.Config)
                        if nextRate~=rate then break end
                    until fulfilled>=1
                    RemoveEconomyEvent(host,host.ModuleEvent);host.ModuleEvent=nil
                    if job.Quote.Work-job.PaidWork<.000001 then job.PaidWork=job.Quote.Work end
                    host:PublishModules()
                end
                local failure=core.Complete(s,job,R.Registry,R.Config)
                if failure then core.RequestCancel(s,job.JobId,R.Registry);host.ModuleReason=failure.Code end
                Assist.ReleaseAll(host)
                host:ReconcileModules()
            end
        end
        Assist.ReleaseAll(host)
        host.ModuleThread=nil;host:PublishModules()
    end)
end
Export={Start=Start,Stop=Stop}
return Export
