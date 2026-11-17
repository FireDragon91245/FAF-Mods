-- Local, current-profile persistence shared by FireDragon UI mods.
local Prefs = import('/lua/user/prefs.lua')
local Storage = {}
local profileKey = 'FireDragonStorage'
-- FAF gives ordinary tables a shared empty metatable; stock Lua uses nil.
local plainMetatable = getmetatable({})

local function identifier(value)
    assert(type(value) == 'string' and value ~= '', 'Storage namespace and key must be nonempty strings')
end

-- Copy at the boundary so edits to returned tables never silently change prefs.
-- Only plain, finite data can be serialized by FAF's preference writer.
local function copy(value, seen, depth)
    local kind = type(value)
    if kind == 'nil' or kind == 'string' or kind == 'boolean' then return value end
    if kind == 'number' then
        assert(value - value == 0, 'Storage numbers must be finite')
        return value
    end
    assert(kind == 'table' and getmetatable(value) == plainMetatable, 'Storage values must be plain data')
    seen = seen or {}; depth = depth or 0
    assert(not seen[value], 'Storage values cannot contain cycles')
    assert(depth < 24, 'Storage values exceed maximum depth (24)')
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        assert(type(key) == 'string' or type(key) == 'number', 'Storage table keys must be strings or numbers')
        result[copy(key)] = copy(child, seen, depth + 1)
    end
    seen[value] = nil
    return result
end

local function read()
    local data = Prefs.GetFromCurrentProfile(profileKey)
    if type(data) == 'table' then return data end
    return {}
end

function Storage.Get(namespace, key, default)
    identifier(namespace); identifier(key)
    local data = read()[namespace]
    if type(data) == 'table' and data[key] ~= nil then return copy(data[key]) end
    return copy(default)
end

-- Each write updates the current profile and flushes preferences to disk.
function Storage.Set(namespace, key, value)
    identifier(namespace); identifier(key)
    assert(Prefs.GetCurrentProfile(), 'Storage requires an active FAF profile')
    local saved = copy(value)
    local data = copy(read(), nil, -2)
    if type(data[namespace]) ~= 'table' then data[namespace] = {} end
    data[namespace][key] = saved
    Prefs.SetToCurrentProfile(profileKey, data)
    SavePreferences()
end

function Storage.Remove(namespace, key)
    Storage.Set(namespace, key, nil)
end

function Storage.Open(namespace)
    identifier(namespace)
    local store = {}
    function store:Get(key, default) return Storage.Get(namespace, key, default) end
    function store:Set(key, value) Storage.Set(namespace, key, value) end
    function store:Remove(key) Storage.Remove(namespace, key) end
    return store
end

Export = Storage
return Storage
