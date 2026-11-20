local RSCAuto=import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/AutoUI.lua').Export
local RSCPreviousApplyOverrides=ApplyOverrides
function ApplyOverrides(orders,selection)
    RSCPreviousApplyOverrides(orders,selection)
    for _,name in ipairs({'DroneL','DroneR'}) do
        local entry=orders[name]
        if entry and not entry.RSCAutoWrapped then
            entry.RSCAutoWrapped=true
            local previousInit=entry.initialStateFunc
            local previousBehavior=entry.behavior
            entry.initialStateFunc=function(control,units)
                previousInit(control,units)
                local mode,mixed=RSCAuto.Mode(control._pod or {})
                if mode~=nil then
                    control:SetCheck(mode and not mixed)
                    if control._mixedIcon then control._mixedIcon:Destroy();control._mixedIcon=nil end
                    if mixed then
                        control._mixedIcon=import('/lua/maui/bitmap.lua').Bitmap(control,
                            import('/lua/ui/uiutil.lua').UIFile('/game/orders-panel/question-mark_bmp.dds'))
                        import('/lua/maui/layouthelpers.lua').AtRightTopIn(control._mixedIcon,control,-2,2)
                    end
                end
            end
            entry.behavior=function(control,modifiers)
                if modifiers.Right and RSCAuto.Managed(control._pod or {}) then
                    local enabled=not control:IsChecked()
                    for _,pod in ipairs(control._pod or {}) do RSCAuto.Set(pod,enabled) end
                    control:SetCheck(enabled)
                    if control._mixedIcon then control._mixedIcon:Destroy();control._mixedIcon=nil end
                else previousBehavior(control,modifiers) end
            end
        end
    end
end
