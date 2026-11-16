local function Apply(shield,instigator,amount,vector)
    local before=shield.ModularImpactSerial or 0
    shield:ApplyDamage(instigator,amount,vector,'Normal',false)
    -- Native ApplyDamage can throttle impacts in heavy fights. Guarantee a ripple
    -- for a special interception even when that cosmetic throttle skips it.
    if shield.CreateImpactEffect and (shield.ModularImpactSerial or 0)==before then
        ForkThread(shield.CreateImpactEffect,shield,vector)
    end
end
Export={Apply=Apply}
return Export
