-- Pure once-only transaction boundary for future projectile/crash adapters.
-- Never call a projectile's stock impact handler after a contained resolution.
local function Resolve(threat, context, outcome)
    if threat.ModularResolution or not context.Operational or not context.Hostile then return false end
    if not outcome or not outcome.Suppress or type(outcome.Damage) ~= 'number'
        or outcome.Damage ~= outcome.Damage or outcome.Damage < 0 or outcome.Damage - outcome.Damage ~= 0 then return false end
    threat.ModularResolution = { HostId = context.HostId, Kind = outcome.Kind }
    -- These callbacks must be non-yielding, prevalidated adapter operations.
    outcome.Suppress(threat)
    context.DamageShield(outcome.Damage)
    if outcome.Visual then outcome.Visual(context) end
    return true
end
Export = { Resolve = Resolve }

return Export
