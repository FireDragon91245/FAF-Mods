-- Explicit packages. Extensions append manifests here; never scan the filesystem.
local function Build(load)
    local config = load('Config.lua')
    config.Debug = load('DebugParameters.lua').Defaults()
    local policies=load('Definitions/ProjectilePolicies.lua')
    for id,enabled in pairs(config.Projectiles.BallisticIds) do policies[id]=enabled end
    config.Projectiles.BallisticIds=policies
    local manifests = { load('Definitions/Manifest.lua') }
    local registry = load('Core/Registry.lua').Build(config, manifests, load)
    return { Config = config, Registry = registry, Core = load('Core/Loadout.lua'),
        Stats = load('Core/Stats.lua'), Neighbors = load('Core/RuleEvaluator.lua') }
end
Export = { Build = Build }

return Export
