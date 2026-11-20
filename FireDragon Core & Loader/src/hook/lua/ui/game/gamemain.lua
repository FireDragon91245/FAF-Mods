local FireDragonPreviousCreateUI=CreateUI
function CreateUI(isReplay)
    local result=FireDragonPreviousCreateUI(isReplay)
    import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua').Export._StartUI()
    return result
end
