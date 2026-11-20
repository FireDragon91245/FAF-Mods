local UI=import('/mods/FireDragonModLoader/lua/FireDragon/UI.lua').Export
local Policy=import('/mods/RepairStationControl/lua/RepairStationControl/Policy.lua').Export
local window
local army
local selected
local function Create(focus)
    local w=UI.Window(GetFrame(0),{title='Repair Station Control',prefKey='RepairStationControl.Window',
        x=160,y=180,width=430,height=205,minWidth=380,minHeight=190})
    local scroll=UI.Scroll(w.Client,{contentWidth=355,contentHeight=135});UI.Fill(scroll,w.Client,8)
    local p=scroll.Content
    local config='RepairStationControl.Army.'..tostring(focus)
    UI.Label(p,{x=8,y=2,width=345,height=20,text='Settings for army '..tostring(focus),size=14})
    UI.Checkbox(p,{x=8,y=30,width=340,height=26,text='Dont help Team',binding={config=config,path={'DontHelpTeam'}}})
    UI.Checkbox(p,{x=8,y=63,width=340,height=26,text='Dont help Nukes',binding={config=config,path={'DontHelpNukes'}}})
    UI.Label(p,{x=8,y=103,width=345,height=20,text='Applies to your stations and build drones.',size=12})
    return w
end
function Update()
    local focus=GetFocusArmy()
    local ids={}
    if focus and focus>0 then
        for _,unit in ipairs(GetSelectedUnits() or {}) do
            if unit:GetArmy()==focus and Policy.ManagedBlueprint(unit:GetBlueprint()) then
                table.insert(ids,tostring(unit:GetEntityId()))
            end
        end
    end
    if not next(ids) then
        if window then window:Destroy();window=nil end
        army=nil;selected=nil
        return
    end
    table.sort(ids)
    local signature=table.concat(ids,',')
    if window and army~=focus then window:Destroy();window=nil end
    if not window then
        army=focus;window=Create(focus)
    elseif signature~=selected then
        window:Show();window:Focus()
    end
    -- Closing stays effective until the selected drones/stations change.
    selected=signature
end
