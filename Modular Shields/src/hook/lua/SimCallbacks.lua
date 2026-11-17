local PreviousDoCallback = DoCallback
function DoCallback(name,data,units)
    if name == 'ModularShieldAction' then
        if type(data) ~= 'table' then return end
        for _, unit in ipairs(SecureUnits(units) or {}) do
            if unit.ModuleAction and not unit.Dead then
                -- Bounded request receipts let the UI retire optimistic entries even
                -- when the rules reject an install. SecureUnits remains authoritative.
                if type(data.RequestId)=='string' and string.len(data.RequestId)<=96 then
                    unit.ModuleUIResponses=unit.ModuleUIResponses or {}
                    unit.ModuleUIJobs=unit.ModuleUIJobs or {}
                    unit.ModuleUIResponseOrder=unit.ModuleUIResponseOrder or {}
                    if not unit.ModuleUIResponses[data.RequestId] then table.insert(unit.ModuleUIResponseOrder,data.RequestId) end
                    unit.ModuleUIResponses[data.RequestId]=true
                    if table.getn(unit.ModuleUIResponseOrder)>64 then
                        local expired=table.remove(unit.ModuleUIResponseOrder,1)
                        unit.ModuleUIResponses[expired]=nil;unit.ModuleUIJobs[expired]=nil
                    end
                end
                local value=data.Value
                if data.Action=='cancel' and type(data.CancelRequestId)=='string' then
                    value=(unit.ModuleUIJobs or {})[data.CancelRequestId]
                end
                local job=unit:ModuleAction(data.Action,value)
                if data.Action=='install' and type(job)=='table' and job.JobId and type(data.RequestId)=='string' and string.len(data.RequestId)<=96 then
                    job.UIRequestId=data.RequestId
                    unit.ModuleUIJobs[data.RequestId]=job.JobId
                end
                if data.RequestId and unit.PublishModules then unit:PublishModules() end
            end
        end
        return
    end
    return PreviousDoCallback(name,data,units)
end
