local function ValidateResource(data)
    return type(data)=='table' and (data.Resource=='ENERGY' or data.Resource=='MASS') and type(data.Enabled)=='boolean'
end
Export={SetResource='FireDragonDebugTools.SetResource',Economy='FireDragonDebugTools.Economy',ValidateResource=ValidateResource}
return Export
