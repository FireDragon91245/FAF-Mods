table.getn=table.getn or function(value) return #value end
local engine=assert(loadfile('src/lua/FireDragon/Engine.lua'))()
local unit={Blueprint={CategoriesHash={ENGINEERSTATION=true}},Queue={}}
function unit:GetCommandQueue() return self.Queue end
assert(not engine.IsAutomaticAssistance(unit))
unit.Queue={{commandType=engine.Command.AssistCommander}};assert(engine.IsAutomaticAssistance(unit))
unit.Queue[2]={commandType=1};assert(not engine.IsAutomaticAssistance(unit))
unit.Queue={{commandType=1}};assert(not engine.IsAutomaticAssistance(unit))
unit.Blueprint.CategoriesHash={POD=true};unit.Parent={}
unit.Queue={{commandType=engine.Command.AssistCommander}};assert(engine.IsAutomaticAssistance(unit))
unit.Parent=nil;assert(not engine.IsAutomaticAssistance(unit))
print('PASS: named simulation command metadata and native assistance state')
