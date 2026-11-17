-- Profile-backed persistence, snapshots, validation and recreated module state.
local profiles = {{}, {}}
local current = 1
local saves = 0
function import(path)
    assert(path == '/lua/user/prefs.lua')
    return {
        GetCurrentProfile = function() return profiles[current] end,
        GetFromCurrentProfile = function(key) return profiles[current][key] end,
        SetToCurrentProfile = function(key, value) profiles[current][key] = value end,
    }
end
function SavePreferences() saves = saves + 1 end
local function load() return assert(loadfile('src/lua/FireDragon/Storage.lua'))() end
local storage = load()
local a = storage.Open('Mod.A')
local b = storage.Open('Mod_B')
assert(a:Get('missing', false) == false)
a:Set('enabled', false)
assert(a:Get('enabled', true) == false and saves == 1)
a:Set('count', 0)
a:Set('text', '')
assert(a:Get('count') == 0 and a:Get('text') == '')
local data = {array = {1, 2, 3}, nested = {name = 'test', flag = false}}
a:Set('settings.window', data)
data.nested.name = 'changed'
local result = a:Get('settings.window')
assert(result.nested.name == 'test' and result.array[3] == 3)
result.nested.name = 'changed again'
assert(a:Get('settings.window').nested.name == 'test')
local default = {value = 5}
result = a:Get('missing', default); result.value = 6
assert(default.value == 5)
b:Set('enabled', true)
assert(a:Get('enabled') == false and b:Get('enabled') == true)
a:Set('settings_window', 'distinct')
assert(a:Get('settings.window').nested.name == 'test')
-- A new module instance reads persisted preferences, without a module cache.
storage = load()
assert(storage.Get('Mod.A', 'settings.window').array[2] == 2)
current = 2
assert(a:Get('count') == nil)
a:Set('count', 99)
current = 1
assert(a:Get('count') == 0)
a:Remove('enabled')
assert(a:Get('enabled', true) == true and b:Get('enabled') == true)
a:Set('count', nil)
assert(a:Get('count') == nil)
local function rejected(fn)
    local before = saves
    assert(not pcall(fn))
    assert(saves == before, 'Rejected writes must not save')
end
rejected(function() storage.Open('') end)
rejected(function() a:Set('', 1) end)
rejected(function() a:Set(2, 1) end)
rejected(function() a:Set('bad', function() end) end)
rejected(function() a:Set('bad', math.huge) end)
rejected(function() a:Set('bad', 0/0) end)
rejected(function() a:Set('bad', {nested = {callback = function() end}}) end)
rejected(function() a:Set('bad', setmetatable({}, {})) end)
rejected(function() a:Set('bad', {[true] = 1}) end)
local cycle = {}; cycle.self = cycle
rejected(function() a:Set('bad', cycle) end)
local deep = {}; local child = deep
for i = 1, 23 do child.next = {}; child = child.next end
a:Set('deep', deep)
a:Set('afterDeep', true)
assert(a:Get('deep').next and a:Get('afterDeep'))
child.next = {}
rejected(function() a:Set('tooDeep', deep) end)
assert(a:Get('bad') == nil and a:Get('tooDeep') == nil)
current = 3
rejected(function() a:Set('missingProfile', true) end)
print('PASS: shared storage persistence, isolation, snapshots and validation')
