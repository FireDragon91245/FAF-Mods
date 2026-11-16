-- In-game debug panel: two toggles that ask the sim for infinite resources.
local Group = import('/lua/maui/group.lua').Group
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
local UIUtil = import('/lua/ui/uiutil.lua')
local Keys = import('/mods/FireDragonDebugTools/lua/FireDragonDebugTools/Keys.lua')

local Toggles = {
    { Key = 'Energy', Resource = 'ENERGY', Label = 'Infinite Energy' },
    { Key = 'Mass', Resource = 'MASS', Label = 'Infinite Mass' },
}
local State = { Energy = false, Mass = false, Denied = false }
local view

local function At(control, parent, x, y)
    control.Left:Set(function() return parent.Left() + x end)
    control.Top:Set(function() return parent.Top() + y end)
    control.Depth:Set(function() return parent.Depth() + 2 end)
end

local function Rect(parent, x, y, color, depth)
    local b = Bitmap(parent)
    b:SetSolidColor(color)
    b:DisableHitTest()
    b.Left:Set(function() return parent.Left() + x end)
    b.Top:Set(function() return parent.Top() + y end)
    b.Right:Set(function() return parent.Right() - x end)
    b.Bottom:Set(function() return parent.Bottom() - y end)
    b.Depth:Set(function() return parent.Depth() + depth end)
    return b
end

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
    local panel = Group(frame, 'FireDragon Debug Tools')
    panel.Depth:Set(200)
    panel.Width:Set(230)
    panel.Height:Set(112)
    panel.Left:Set(function() return frame.Right() - panel.Width() - 24 end)
    panel.Top:Set(function() return frame.Top() + 150 end)
    panel.HandleEvent = function(_, event) return event.Type == 'ButtonPress' or event.Type == 'ButtonDClick' end

    Rect(panel, 0, 0, 'ff344958', 0)
    Rect(panel, 1, 1, 'f20a141f', 1)

    local title = UIUtil.CreateText(panel, 'FireDragon Debug Tools', 14, UIUtil.titleFont)
    title:DisableHitTest()
    At(title, panel, 10, 8)

    local boxes = {}
    for index, toggle in ipairs(Toggles) do
        local resource = toggle.Resource
        local box = UIUtil.CreateCheckbox(panel, '/CHECKBOX/', toggle.Label, true, 13)
        At(box, panel, 10, 8 + index * 24)
        box.OnCheck = function(_, checked)
            SimCallback({ Func = 'FireDragonDebugSetResource', Args = { Resource = resource, Enabled = checked } })
        end
        boxes[toggle.Key] = box
    end

    local status = UIUtil.CreateText(panel, '', 11, UIUtil.bodyFont)
    status:DisableHitTest()
    At(status, panel, 10, 88)

    return { Panel = panel, Boxes = boxes, Status = status }
end

function Toggle()
    if not view then
        view = Create()
    elseif view.Panel:IsHidden() then
        view.Panel:Show()
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
