local function ValidateResource(data)
    return type(data)=='table' and (data.Resource=='ENERGY' or data.Resource=='MASS') and type(data.Enabled)=='boolean'
end
local function ValidateInstantBuild(data)
    return type(data)=='table' and type(data.Enabled)=='boolean'
end
Export={SetResource='FireDragonDebugTools.SetResource',Economy='FireDragonDebugTools.Economy',ValidateResource=ValidateResource,
    SetInstantBuild='FireDragonDebugTools.SetInstantBuild',InstantBuild='FireDragonDebugTools.InstantBuild',
    ValidateInstantBuild=ValidateInstantBuild}
return Export
