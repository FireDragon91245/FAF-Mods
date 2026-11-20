-- Explicit sandbox-only demo. Never runs during normal games.
-- Console: SimLua import('/mods/FireDragon Modular Shields/lua/ModularShields/Diagnostics/HexDomeTest.lua').Export.Start()
local function Start(army,x,z)
    army=army or GetFocusArmy()
    if army < 1 then army=1 end
    x=x or ScenarioInfo.size[1]/2
    z=z or ScenarioInfo.size[2]/2
    local unit=CreateUnitHPR('mdeb4401',army,x,GetSurfaceHeight(x,z),z,0,0,0)
    ForkThread(function()
        WaitTicks(20)
        local s=unit.MyShield
        if not s or not s.HexVisualsAttached then
            WARN('HEX DEMO: custom shader not installed, or shield not ready')
            unit:Destroy()
            return
        end
        LOG('HEX DEMO: blue, yellow, red, collapse/recharge, cleanup (about 40 seconds)')
        for _,ratio in ipairs({1,0.5,0.15}) do
            for tick=1,100 do
                if IsDestroyed(unit) or IsDestroyed(s) then return end
                s:SetHealth(unit,s:GetMaxHealth()*ratio)
                s:UpdateShieldRatio(ratio)
                if math.mod(tick,10)==1 and s:IsUp() then
                    local angle=tick*0.09
                    ForkThread(s.CreateImpactEffect,s,{math.cos(angle)*s.Size/2,s.Size*0.12,math.sin(angle)*s.Size/2})
                end
                WaitTicks(1)
            end
            LOG('HEX DEMO: health state complete ',ratio)
        end
        s:TurnOff()
        WaitTicks(20)
        s:SetHealth(unit,s:GetMaxHealth())
        s:TurnOn()
        WaitTicks(50)
        if not IsDestroyed(unit) then unit:Destroy() end
        LOG('HEX DEMO: finished; test generator removed')
    end)
    return unit
end
Export={Start=Start}
return Export
