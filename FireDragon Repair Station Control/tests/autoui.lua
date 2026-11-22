local New=assert(loadfile('tests/support/Fixture.lua'))()
local w=New()
local drone=w:Unit(1,1,{POD=true,ENGINEER=true});w.C.Track(drone);w:Settings(1,false,true)
local ui=w:Client(1)
local P=w.P
local env=setmetatable({import=function(path)
    return {Export=path:find('Policy.lua',1,true) and P or ui}
end},{__index=_G})
local A=assert(loadfile('src/lua/RepairStationControl/AutoUI.lua','t',env))()
local pod={GetEntityId=function() return 1 end,GetBlueprint=function() return drone.Blueprint end,
    IsAutoMode=function() return drone.NativeAuto end}
assert(pod:IsAutoMode() and A.Mode({pod})==true,'UI shows the actual native automation state')
local previous=0
local hook=setmetatable({import=function() return {Export=A} end,
    ApplyOverrides=function() previous=previous+1 end},{__index=_G})
assert(loadfile('src/hook/lua/ui/game/orders.lua','t',hook))()
local delegated=0
local orders={DroneL={initialStateFunc=function(c) c.Checked=false end,behavior=function() delegated=delegated+1 end}}
hook.ApplyOverrides(orders,{pod});hook.ApplyOverrides(orders,{pod})
local control={_pod={pod},SetCheck=function(c,v) c.Checked=v end,IsChecked=function(c) return c.Checked end}
orders.DroneL.initialStateFunc(control,{pod});assert(control.Checked and previous==2)
orders.DroneL.behavior(control,{Left=true});assert(delegated==1,'Keep normal drone selection')
orders.DroneL.behavior(control,{Right=true});w:Deliver();w:Sync()
assert(not drone.AutoModeEnabled and not drone.NativeAuto and not control.Checked,'Native-off flag must not prevent requested disable')
orders.DroneL.behavior(control,{Right=true});w:Deliver();w:Sync()
assert(drone.AutoModeEnabled and drone.NativeAuto and control.Checked,'Toggle enables native automation')
local other=w:Client(2)
local receipt=other.Sim.Publish('RepairStationControl.SetAuto',{EntityId=1,Enabled=false})
w:Deliver();w:Sync()
assert(drone.AutoModeEnabled and receipt:Status()=='failed','Other army cannot change drone automation')
print('PASS: mirrored logical automation, actual orders hook toggling, left-click behavior and trusted army authorization')
