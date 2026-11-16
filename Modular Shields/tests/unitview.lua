local received
function UpdateWindow(info) received=info end
local text
controls={shieldText={IsHidden=function() return false end,SetText=function(_,s) text=s end}}
UnitData={[1]={ModularShield={},ModularShieldRepairMass=3.75,ModularShieldLive={HP=1234,MaxHP=2000,Regen=12.5}}}
assert(loadfile('ModularShields/hook/lua/ui/game/unitview.lua'))()
local original={entityId=1,massConsumed=2,massRequested=4}
UpdateWindow(original)
assert(received.massConsumed==5.75 and received.massRequested==7.75,'Repair spending must add to native work rather than replace it')
assert(original.massConsumed==2 and original.massRequested==4,'Rollover data must stay reusable')
UpdateWindow(original)
assert(received.massConsumed==5.75,'Repeated native updates cannot duplicate attributed spending')
assert(text=='1234 / 2000 +12/s','Native shield label must use live capacity and regeneration')
UnitData[1].ModularShieldRepairMass=0;UpdateWindow(original)
assert(received.massConsumed==2,'Inactive repair preserves native consumption')
local other={entityId=2,massConsumed=8};UpdateWindow(other)
assert(received==other,'Non-modular units keep native behavior')
controls.shieldText.IsHidden=function() return true end;text=nil;UpdateWindow(original)
assert(text==nil,'Detailed shield view visibility remains a native user preference')
print('PASS: 7 native unit-view attribution checks')
