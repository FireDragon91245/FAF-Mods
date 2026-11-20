-- Data-only contract; also loaded during blueprint generation.
local fields = {
    {Key='InstantUpgrade',Label='Instant Upgrades',Kind='boolean',Default=false},
    {Key='IgnoreResources',Label='Ignore Resources',Kind='boolean',Default=false},
    {Key='HPMultiplier',Label='HP Multiplier',Kind='integer',Min=1,Max=10,Step=1,Default=1},
    {Key='AdditionalRegen',Label='Additional Regen',Kind='integer',Min=0,Max=10000,Step=100,Default=0},
    {Key='AdditionalSlots',Label='Additional Slots',Kind='integer',Min=0,Max=50,Step=1,Default=0},
    {Key='AdditionalRepair',Label='Additional Repair',Kind='integer',Min=0,Max=1000,Step=10,Default=0},
}
local function Defaults()
    local values={};for _,field in ipairs(fields) do values[field.Key]=field.Default end;return values
end
local function Validate(values)
    assert(type(values)=='table','Expected shield debug settings')
    local known={}
    for _,field in ipairs(fields) do
        local value=values[field.Key];known[field.Key]=true
        if field.Kind=='boolean' then assert(type(value)=='boolean','Expected boolean '..field.Key)
        else assert(type(value)=='number' and value-value==0 and value==math.floor(value)
            and value>=field.Min and value<=field.Max,'Invalid integer '..field.Key) end
    end
    for key in pairs(values) do assert(known[key],'Unknown shield parameter') end
    return true
end
Export={Key='ModularShields.Debug',SchemaKey='ModularShields.DebugSchema',Fields=fields,Defaults=Defaults,Validate=Validate}
return Export
