local FireDragonPreviousOnSync=OnSync
function OnSync()
    if Sync.FireDragonExchange then
        import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export._ReceiveSync(Sync.FireDragonExchange)
    end
    return FireDragonPreviousOnSync()
end
