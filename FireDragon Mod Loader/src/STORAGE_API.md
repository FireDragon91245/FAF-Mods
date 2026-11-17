# FireDragon storage API

Enable FireDragon Mod Loader v7 or newer and import the shared Lua module:

```lua
local Storage = import('/mods/FireDragonModLoader/lua/FireDragon/Storage.lua').Export
local data = Storage.Open('MyMod')

local enabled = data:Get('enabled', true)
data:Set('enabled', false)
data:Set('window', {left = 100, top = 120, width = 500, height = 360})
local window = data:Get('window')
data:Remove('window')
```

`Open(namespace)` returns a handle with `Get`, `Set` and `Remove` methods (colon
syntax). Use a stable, unique mod name or UID for the namespace. The equivalent
module functions are `Storage.Get(namespace, key, default)`,
`Storage.Set(namespace, key, value)` and `Storage.Remove(namespace, key)`.

Namespaces and keys must be nonempty strings. They are exact and case sensitive;
dots are ordinary characters. Each namespace owns its own keys. `Get` returns the
default only when the key is absent, preserving `false`, zero and empty strings.
`Set` saves immediately through FAF's current profile and calls `SavePreferences()`
to flush to disk. Setting `nil` removes the key. Writes require an active profile.

Values may contain strings, finite numbers, booleans, and nested plain tables
with string or number keys, up to 24 table levels. Functions, userdata, metatables,
cycles and non-finite numbers are rejected before writing. Numbers use the game's
normal precision. Reads and writes copy tables: edit a returned table and call
`Set` to save it. Defaults are copied too.

Data lives under the current FAF profile's `FireDragonStorage` preference and
survives game restarts. Handles follow profile switches; data is never cached in
the module. This API is for local User/UI preferences, available without the native
DLL. Do not use local profile values to drive synchronized simulation behavior.
It does not share data between players or serialize simulation savegames.

UI windows use namespace `FireDragon.UI` and their exact `prefKey` as the storage
key. Version 7 deliberately does not migrate old flat window preferences; windows
start with default geometry until saved through the new API.
