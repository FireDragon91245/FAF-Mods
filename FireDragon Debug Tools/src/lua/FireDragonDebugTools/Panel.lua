-- Vanilla tools and optional mod-owned configuration, using only the shared API.
local UI = import('/mods/FireDragonModLoader/lua/FireDragon/UI.lua').Export
local Exchange = import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export
local Keys = import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Keys.lua')
local Messages=import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Messages.lua').Export
local ShieldKey = 'ModularShields.Debug'
local Toggles = {
    { Key = 'Energy', Resource = 'ENERGY', Label = 'Infinite Energy' },
    { Key = 'Mass', Resource = 'MASS', Label = 'Infinite Mass' },
}
local view

local function AddShieldTab()
    if view.ModularControls or not Exchange.HasConfig(ShieldKey) then return end
    local page = view.Tabs:Add('shields', 'Modular Shields')
    local scroll = UI.Scroll(page, {contentWidth=function() return math.max(280,page.Width()-20) end,contentHeight=350})
    UI.Fill(scroll,page,4)
    local content, controls, y = scroll.Content, {}, 6
    local fields = Exchange.Get('ModularShields.DebugSchema')
    for _,field in ipairs(fields) do
        local key = field.Key
        local width = function() return math.max(260,content.Width()-20) end
        if field.Kind == 'boolean' then
            controls[key] = UI.Checkbox(content, {x=8,y=y,width=width,height=28,text=field.Label,
                onCheck=function(_,value) return Exchange.SetPath(ShieldKey,{key},value) end})
            y=y+32
        else
            UI.Label(content,{x=8,y=y,width=width,height=20,text=field.Label})
            controls[key] = UI.NumberInput(content,{x=8,y=y+22,width=width,height=24,
                min=field.Min,max=field.Max,step=field.Step,value=field.Default,
                onChange=function(_,value) return Exchange.SetPath(ShieldKey,{key},value) end})
            y=y+62
        end
    end
    UI.Label(content,{x=8,y=y+4,width=280,height=18,size=11,text='Enter applies typed values. Changes affect all shields.'})
    content.Height:Set(y+30)
    view.ModularControls=controls
end
local function Refresh()
    if not view then return end
    local state=Exchange.GetState(Messages.Economy,tostring(GetFocusArmy())) or {}
    local active={}
    for _,ticket in ipairs(view.Requests) do
        local result=ticket:Poll()
        if result then view.Denied=result.error=='denied' end
        if ticket:Status()=='pending' then table.insert(active,ticket)
        elseif ticket.Error then view.Denied=ticket.Error=='denied' end
    end
    view.Requests=active
    for _,toggle in ipairs(Toggles) do view.Boxes[toggle.Key]:SetCheck(state[toggle.Key] == true,true) end
    local present=Exchange.HasConfig(ShieldKey)
    if present then
        AddShieldTab()
        local values=Exchange.Get(ShieldKey)
        for key,control in pairs(view.ModularControls) do
            if control.SetCheck then control:SetCheck(values[key],true)
            elseif control.Value~=values[key] then control:SetValue(values[key],true) end
        end
    elseif view.ModularControls then
        view.Tabs:Remove('shields');view.ModularControls=nil
    end
    local denied=view.Denied
    if present and Exchange.ConfigStatus then
        denied=denied or Exchange.ConfigStatus(ShieldKey).denied
    end
    view.Status:SetText(denied and 'Refused: cheats are disabled' or Keys.DefaultKey .. ' toggles this panel')
    view.Status:SetColor(denied and 'ffff6060' or 'ff9fb3c8')
end
local function Create()
    local frame=GetFrame(0)
    local panel=UI.Window(frame,{name='FireDragon Debug Tools',title='FireDragon Debug Tools',
        x=frame.Width()-440,y=150,width=420,height=450,minWidth=360,minHeight=220})
    local tabs=UI.Tabs(panel.Client,{tabWidth=160})
    UI.At(tabs,panel.Client,8,8,function() return panel.Client.Width()-16 end,function() return math.max(0,panel.Client.Height()-42) end)
    local vanilla=tabs:Add('vanilla','Vanilla')
    local boxes={}
    for index,toggle in ipairs(Toggles) do
        local resource=toggle.Resource
        boxes[toggle.Key]=UI.Checkbox(vanilla,{x=10,y=(index-1)*32+8,width=280,height=28,text=toggle.Label,
            onCheck=function(_,checked)
                local ticket=Exchange.Sim.Request(Messages.SetResource,{Resource=resource,Enabled=checked},{replyMode='First'})
                table.insert(view.Requests,ticket);return ticket
            end})
    end
    local status=UI.Label(panel.Client,{x=12,y=function() return panel.Client.Height()-24 end,
        width=function() return panel.Client.Width()-24 end,height=18,size=11})
    UI.Bind(panel,function() return {} end,Refresh,.1)
    return {Panel=panel,Tabs=tabs,Boxes=boxes,Status=status,Requests={}}
end
function Toggle()
    if not view then view=Create()
    elseif view.Panel:IsHidden() then view.Panel:Show();view.Panel:Focus()
    else view.Panel:Hide();return end
    Refresh()
end
