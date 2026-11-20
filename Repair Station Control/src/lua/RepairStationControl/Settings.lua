local Exchange=import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export
local owners={}
local function Key(army) return 'RepairStationControl.Army.'..tostring(army) end
local function Validate(values)
    if type(values)~='table' or type(values.DontHelpTeam)~='boolean' or type(values.DontHelpNukes)~='boolean' then return false end
    for k in pairs(values) do if k~='DontHelpTeam' and k~='DontHelpNukes' then return false end end
    return true
end
local function Ensure(army)
    if not owners[army] then
        owners[army]=Exchange.PublishConfig(Key(army),{DontHelpTeam=false,DontHelpNukes=false},'ReadWrite',
            function(values)
                import('/mods/RepairStationControl/lua/RepairStationControl/Controller.lua').Export.ApplyArmy(army,values)
            end,Validate,{scope='Sim',authorize=function(source)
                return source.realm=='UI' and source.army==army
            end})
    end
end
Export={Key=Key,Validate=Validate,Ensure=Ensure,Get=function(army)
    Ensure(army)
    return Exchange.Get(Key(army))
end,Start=function()
    for _,brain in pairs(ArmyBrains) do Ensure(brain:GetArmyIndex()) end
end}
return Export
