-- The engine sync beat also runs while game ticks are paused.
local FireDragonPreviousResetSyncTable=ResetSyncTable
function ResetSyncTable()
    FireDragonPreviousResetSyncTable()
    import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua').Export._FlushTransport()
end
