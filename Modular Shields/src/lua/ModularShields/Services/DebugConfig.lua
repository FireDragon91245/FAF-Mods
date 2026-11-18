local root='/mods/ModularShields/lua/ModularShields/'
local Schema=import(root..'DebugParameters.lua').Export
local owner, runtime
local hosts={}
local function exchange() return import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export end
local function InitSim()
    if owner then return end
    runtime=import(root..'Runtime.lua').Export
    local bus=exchange()
    bus.PublishConfig(Schema.SchemaKey,Schema.Fields,'ReadOnly',nil,nil,{scope='Sim'})
    owner=bus.PublishConfig(Schema.Key,runtime.Config.Debug,'ReadWrite',function(values,old)
        runtime.Config.Debug=values
        local ids={};for id in pairs(hosts) do table.insert(ids,id) end;table.sort(ids)
        local jobs=import(root..'Services/InstallJobs.lua').Export
        for _,id in ipairs(ids) do
            local host=hosts[id]
            if host.Dead or IsDestroyed(host) then hosts[id]=nil
            else
                if values.InstantUpgrade~=old.InstantUpgrade or values.IgnoreResources~=old.IgnoreResources then jobs.Stop(host) end
                host:ReconcileModules();jobs.Start(host,runtime)
            end
        end
    end,Schema.Validate,{scope='Sim',authorize='Cheats'})
end
Export={InitSim=InitSim,
    Track=function(host) InitSim();hosts[host.EntityId]=host end,
    Untrack=function(host) hosts[host.EntityId]=nil end}
return Export
