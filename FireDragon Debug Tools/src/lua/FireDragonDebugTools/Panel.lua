-- Vanilla tools and optional mod-owned configuration, using only the shared API.
local UI = import('/mods/FireDragonModLoader/lua/FireDragon/UI.lua').Export
local Exchange = import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export
local Keys = import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Keys.lua')
local Messages=import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Messages.lua').Export
local Bindings=import('/mods/FireDragonModLoader/lua/FireDragon/Bindings.lua').Export
local Economy=Bindings.DefineState(Exchange,{
    stateTopic=Messages.Economy,topic=Messages.SetResource,ordered=true,
    payload=function(op) return {Resource=op.Resource,Enabled=op.Value} end,
    project=function(state,ops) for _,op in ipairs(ops) do state[op.Key]=op.Value end;return state end,
})
-- Expected failures are journal outcomes. Presentation and dismissal policy belong
-- here: show unresolved failures per field/resource, never hide one for another.
local function Problem(status)
    local latest={}
    for _,outcome in ipairs(status.outcomes) do
        local key=outcome.Intent.Key or table.concat(outcome.Path or {},'.')
        if not latest[key] or outcome.ID>latest[key].ID then latest[key]=outcome end
    end
    local problem
    for _,outcome in pairs(latest) do
        if outcome.Reason and (not problem or outcome.ID>problem.ID) then problem=outcome end
    end
    if not problem then return nil end
    if problem.Status=='unknown' then return 'Outcome unknown; awaiting authoritative state' end
    if problem.Reason=='denied' then return 'Refused: cheats are disabled' end
    return 'Request refused: '..tostring(problem.Reason)
end
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
                binding={config=ShieldKey,path={key}}})
            y=y+32
        else
            UI.Label(content,{x=8,y=y,width=width,height=20,text=field.Label})
            controls[key] = UI.NumberInput(content,{x=8,y=y+22,width=width,height=24,
                min=field.Min,max=field.Max,step=field.Step,value=field.Default,
                binding={config=ShieldKey,path={key}}})
            y=y+62
        end
    end
    UI.Label(content,{x=8,y=y+4,width=280,height=18,size=11,text='Enter applies typed values. Changes affect all shields.'})
    content.Height:Set(y+30)
    view.ModularControls=controls
end
local function Refresh()
    if not view then return end
    local present=Exchange.HasConfig(ShieldKey)
    if present then
        AddShieldTab()
    elseif view.ModularControls then
        view.Tabs:Remove('shields');view.ModularControls=nil
    end
    local problem=Problem(Economy:For(tostring(GetFocusArmy())):Status())
    if present then problem=problem or Problem(Bindings.Status{config=ShieldKey}) end
    view.Status:SetText(problem or Keys.DefaultKey .. ' toggles this panel')
    view.Status:SetColor(problem and 'ffff6060' or 'ff9fb3c8')
end
local function Create()
    local frame=GetFrame(0)
    local panel=UI.Window(frame,{name='FireDragon Debug Tools',title='FireDragon Debug Tools',
        x=frame.Width()-480,y=150,width=460,height=450,minWidth=420,minHeight=220})
    local tabs=UI.Tabs(panel.Client,{tabHeight=34})
    UI.At(tabs,panel.Client,8,8,function() return panel.Client.Width()-16 end,function() return math.max(0,panel.Client.Height()-42) end)
    local vanilla=tabs:Add('vanilla','Vanilla')
    local boxes={}
    for index,toggle in ipairs(Toggles) do
        local t=toggle
        boxes[toggle.Key]=UI.Checkbox(vanilla,{x=10,y=(index-1)*32+8,width=280,height=28,text=toggle.Label,
            binding={source=Economy,target=function() return tostring(GetFocusArmy()) end,path={t.Key},
                intent=function(value) return {Key=t.Key,Resource=t.Resource,Value=value} end}})
    end
    local status=UI.Label(panel.Client,{x=12,y=function() return panel.Client.Height()-24 end,
        width=function() return panel.Client.Width()-24 end,height=18,size=11})
    UI.Bind(panel,function() return {} end,Refresh,.1)
    return {Panel=panel,Tabs=tabs,Boxes=boxes,Status=status}
end
function Toggle()
    if not view then view=Create()
    elseif view.Panel:IsHidden() then view.Panel:Show();view.Panel:Focus()
    else view.Panel:Hide();return end
    Refresh()
end
