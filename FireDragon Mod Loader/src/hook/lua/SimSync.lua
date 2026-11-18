-- The engine sync beat also runs while game ticks are paused.
local FireDragonPreviousResetSyncTable=ResetSyncTable
function ResetSyncTable()
    FireDragonPreviousResetSyncTable()
    import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export._FlushTransport()
end
