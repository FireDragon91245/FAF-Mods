local FireDragonPreviousOnSync=OnSync
function OnSync()
    if Sync.FireDragonExchange then
        import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua').Export._ReceiveSync(Sync.FireDragonExchange)
    end
    return FireDragonPreviousOnSync()
end
