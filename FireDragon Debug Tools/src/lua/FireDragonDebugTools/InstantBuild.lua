-- ai_InstaBuild is a match-wide engine variable. Track menu requests in Sim;
-- the engine exposes no documented getter for changes entered in the console.
local Exchange=import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export
local Messages=import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Messages.lua').Export
local started
local enabled=false

local function Snapshot() return {Enabled=enabled} end
local function Publish()
    Exchange.UI.PublishState(Messages.InstantBuild,'match',Snapshot())
end

function Start()
    if started then return end
    started=true
    Exchange.Expose(Messages.SetInstantBuild,{requests=true,authorize='Cheats'})
    Exchange.Respond(Messages.SetInstantBuild,function(data)
        if not Messages.ValidateInstantBuild(data) then
            return {Accepted=false,Reason='InvalidMessage'}
        end
        -- Always set explicitly, even for repeated requests: the console may have
        -- changed the engine value since the last menu request.
        SimConExecute('ai_InstaBuild '..(data.Enabled and 'true' or 'false'))
        enabled=data.Enabled
        Publish()
        return {Accepted=true,State=Snapshot()}
    end)
    Publish()
end
