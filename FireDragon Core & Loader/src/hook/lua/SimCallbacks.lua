local FireDragonPreviousDoCallback=DoCallback
function DoCallback(name,data,units)
    if name=='FireDragonExchange' then
        return import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua').Export._ReceiveCommand(data)
    end
    return FireDragonPreviousDoCallback(name,data,units)
end
