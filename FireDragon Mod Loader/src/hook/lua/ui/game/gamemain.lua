local FireDragonPreviousCreateUI=CreateUI
function CreateUI(isReplay)
    local result=FireDragonPreviousCreateUI(isReplay)
    import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export._StartUI()
    return result
end
