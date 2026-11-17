-- In-game debug panel: two toggles that ask the sim for infinite resources.
local UI = import('/mods/FireDragonModLoader/lua/FireDragon/UI.lua').Export
local Keys = import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Keys.lua')

local Toggles = {
    { Key = 'Energy', Resource = 'ENERGY', Label = 'Infinite Energy' },
    { Key = 'Mass', Resource = 'MASS', Label = 'Infinite Mass' },
}
local State = { Energy = false, Mass = false, Denied = false }
local view

local function Refresh()
    if not view then return end
    for _, toggle in ipairs(Toggles) do
        view.Boxes[toggle.Key]:SetCheck(State[toggle.Key] == true, true)
    end
    if State.Denied then
        view.Status:SetText('Refused: cheats are disabled')
        view.Status:SetColor('ffff6060')
    else
        view.Status:SetText(Keys.DefaultKey .. ' toggles this panel')
        view.Status:SetColor('ff9fb3c8')
    end
end

local function Create()
    local frame = GetFrame(0)
    local panel = UI.Window(frame, { name='FireDragon Debug Tools', title='FireDragon Debug Tools',
        x=frame.Width()-320,y=150,width=300,height=200,minWidth=260,minHeight=170 })
    local scroll = UI.Scroll(panel.Client,{contentWidth=270,contentHeight=100});UI.Fill(scroll,panel.Client,8)
    local content = scroll.Content

    local boxes = {}
    for index, toggle in ipairs(Toggles) do
        local resource = toggle.Resource
        local box = UI.Checkbox(content, {x=10,y=(index-1)*28,width=245,height=26,text=toggle.Label,
            onCheck = function(_, checked)
            SimCallback({ Func = 'FireDragonDebugSetResource', Args = { Resource = resource, Enabled = checked } })
        end })
        boxes[toggle.Key] = box
    end

    local status = UI.Label(content,{x=10,y=64,width=250,height=18,size=11})

    return { Panel = panel, Boxes = boxes, Status = status }
end

function Toggle()
    if not view then
        view = Create()
    elseif view.Panel:IsHidden() then
        view.Panel:Show();view.Panel:Focus()
    else
        view.Panel:Hide()
        return
    end
    Refresh()
end

--- Receives Sync.FireDragonDebug (army string -> snapshot) and keeps the focus army's state.
function OnSync(data)
    local snapshot = data[tostring(GetFocusArmy())]
    if not snapshot then return end
    State.Energy = snapshot.Energy == true
    State.Mass = snapshot.Mass == true
    State.Denied = snapshot.Denied == true
    Refresh()
end
