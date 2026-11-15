-- Runtime loader; blueprint loading uses doscript instead.
local root = '/mods/ModularShields/lua/ModularShields/'
Export = import(root .. 'Bootstrap.lua').Export.Build(function(path) return import(root .. path).Export end)

return Export
