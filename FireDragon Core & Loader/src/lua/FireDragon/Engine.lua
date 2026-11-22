-- Shared names and queries for engine-owned simulation commands.
local Command={AssistCommander=29}
local function IsAutomaticAssistance(unit)
    local queue=unit:GetCommandQueue() or {}
    local cats=unit.Blueprint.CategoriesHash or {}
    return (cats.ENGINEERSTATION or (unit.Parent and cats.POD)) and table.getn(queue)==1
        and queue[1].commandType==Command.AssistCommander
end
Export={Command=Command,IsAutomaticAssistance=IsAutomaticAssistance}
return Export
