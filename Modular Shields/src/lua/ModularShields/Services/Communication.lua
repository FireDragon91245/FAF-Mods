local Messages=import('/mods/ModularShields/lua/ModularShields/Messages.lua').Export
local started
local function exchange() return import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export end
local function Start()
    if started then return end
    started=true
    local bus=exchange()
    bus.Expose(Messages.Action,{requests=true,authorize=function(_,_,data)
        if not Messages.ValidateAction(data) then return false end
        local units=import('/lua/SimCallbacks.lua').SecureUnits({data.EntityId})
        local unit=units and units[1]
        return unit~=nil and not unit.Dead and unit.Loadout~=nil and type(unit.ModuleAction)=='function'
    end})
    bus.Respond(Messages.Action,function(data,_,context)
        if not Messages.ValidateAction(data) then return {Accepted=false,Reason='InvalidMessage'} end
        local unit=GetEntityById(data.EntityId)
        if not unit or unit.Dead or not unit.ModuleAction then return {Accepted=false,Reason='MissingUnit'} end
        local value=data.Value
        if data.Action=='cancel' and not value then
            for _,job in ipairs(unit.Loadout.Queue) do
                if job.UIRequestId==data.CancelRequestId then value=job.JobId;break end
            end
            if not value then return {Accepted=false,Reason='UnknownJob'} end
        end
        local result,reason=unit:ModuleAction(data.Action,value)
        if data.Action=='install' then
            if result and result.JobId then
                result.UIRequestId=context.source and context.source.requestKey or ('Sim:'..tostring(context.requestID))
            end
        else reason=result end
        if unit.PublishModules then unit:PublishModules() end
        return {Accepted=data.Action=='install' and result~=nil or (data.Action~='install' and not reason),
            JobId=data.Action=='install' and result and result.JobId or nil,Reason=reason and reason.Code or nil}
    end)
end
local function Publish(host,topic,value)
    exchange().UI.PublishState(topic,host.EntityId,value,{army=host.Army})
end
Export={Start=Start,
    Status=function(host,value) Publish(host,Messages.Status,value) end,
    Live=function(host,value) Publish(host,Messages.Live,value) end,
    Remove=function(host) Publish(host,Messages.Status,nil);Publish(host,Messages.Live,nil) end}
return Export
