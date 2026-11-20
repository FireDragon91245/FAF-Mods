local received
function UpdateWindow(info) received=info end
local text
controls={shieldText={IsHidden=function() return false end,SetText=function(_,s) text=s end}}
local Exchange=assert(loadfile('../FireDragon Core & Loader/src/lua/FireDragon/InformationExchange.lua'))()
local Messages=assert(loadfile('src/lua/ModularShields/Messages.lua'))()
function import(path)
    if path:find('InformationExchange.lua',1,true) then return {Export=Exchange} end
    return {Export=Messages}
end
Exchange.PublishState(Messages.Status,1,{})
Exchange.PublishState(Messages.Live,1,{HP=1234,MaxHP=2000,Regen=12.5,RepairMass=3.75,RepairMassRequested=5,RepairEnergy=20,RepairEnergyRequested=30})
assert(loadfile('src/hook/lua/ui/game/unitview.lua'))()
local original={entityId=1,massConsumed=2,massRequested=4,energyConsumed=100,energyRequested=150}
UpdateWindow(original)
assert(received.massConsumed==5.75 and received.massRequested==9,'Repair spending must add to native work rather than replace it')
assert(original.massConsumed==2 and original.massRequested==4,'Rollover data must stay reusable')
UpdateWindow(original)
assert(received.massConsumed==5.75,'Repeated native updates cannot duplicate attributed spending')
assert(received.energyConsumed==120 and received.energyRequested==180,'Native panel attributes helper energy as well as mass')
assert(original.energyConsumed==100 and original.energyRequested==150,'Attribution cannot mutate native cached energy data')
assert(text=='1234 / 2000 +12/s','Native shield label must use live capacity and regeneration')
Exchange.PublishState(Messages.Live,1,{HP=1234,MaxHP=2000,Regen=12.5,RepairMass=0});UpdateWindow(original)
assert(received.massConsumed==2,'Inactive repair preserves native consumption')
local other={entityId=2,massConsumed=8};UpdateWindow(other)
assert(received==other,'Non-modular units keep native behavior')
controls.shieldText.IsHidden=function() return true end;text=nil;UpdateWindow(original)
assert(text==nil,'Detailed shield view visibility remains a native user preference')
print('PASS: 9 native unit-view attribution checks')
