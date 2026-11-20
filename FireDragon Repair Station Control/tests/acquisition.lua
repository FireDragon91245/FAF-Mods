local New=assert(loadfile('tests/support/Fixture.lua'))()
for _,category in ipairs({'NUKE','ANTIMISSILE'}) do
    local w=New()
    local drone=w:Unit(1,1,{POD=true,ENGINEER=true})
    local silo=w:Unit(2,1,{SILO=true,[category]=true});silo.State='SiloBuildingAmmo'
    local project=w:Unit(3);project.Fraction=.5;project.Position={10,0,0}
    w.nearby={silo,project};w.C.Track(drone)
    -- Reproduce enabling the checkbox while native assistance is already active.
    drone.Focus=silo;drone.Guard=silo;drone.Queue={{commandType=15,target=silo}}
    local ui=w:Client(1)
    ui.SetPath(w.S.Key(1),{'DontHelpNukes'},true);w:Deliver()
    assert(not drone.NativeAuto and drone.AutoModeEnabled,'Suspend native acquisition, preserve requested automation')
    assert(not drone.Focus and w.clears==1,'Accepted setting stops ongoing assistance immediately')
    for tick=1,100 do
        -- Model the competing native selector. This caused the v2 flicker.
        if drone.NativeAuto and not next(drone.Queue) then w.env.IssueGuard({drone},silo) end
        w.C.Update(drone)
    end
    assert(w.clears==1 and #w.orders==1 and drone.Focus==project,'No repeated stops and useful work is not starved')
    for _,order in ipairs(w.orders) do assert(order.target~=silo,'Excluded silo must never receive an order') end
    project.Fraction=1;w.C.Update(drone)
    local clears=w.clears
    for tick=1,100 do w.C.Update(drone) end
    assert(not drone.Focus and w.clears==clears,'Idle beside excluded silos without starting or cancelling work')
    w:Settings(1,false,false)
    assert(drone.NativeAuto and drone.AutoModeEnabled,'Restore native automation when filters are removed')
end
local w=New()
local own=w:Unit(1,1,{ENGINEERSTATION=true});local other=w:Unit(2,2,{ENGINEERSTATION=true})
local ally=w:Unit(3,2);ally.Fraction=.5
w.nearby={ally};w.C.Track(own);w.C.Track(other)
w:Settings(1,true,false)
assert(not own.NativeAuto and other.NativeAuto,'Acquisition filtering is per army')
for i=1,20 do w.C.Update(own) end
assert(#w.orders==0 and w.clears==0,'Allied projects are filtered before orders')
own.Focus=ally;own.Paused=true;w:Settings(1,true,true)
assert(w.clears==1 and not own.Focus,'Settings release prohibited work even while paused')
local project=w:Unit(4);project.Fraction=.5;w.nearby={project}
own.Paused=false;own.Queue={{commandType=2}};w.C.Update(own);assert(#w.orders==0,'Manual movement is preserved')
own.Queue={};w.C.SetAuto(own,false);w.C.Update(own);assert(#w.orders==0 and not own.AutoModeEnabled)
w.C.SetAuto(own,true);assert(own.AutoModeEnabled and not own.NativeAuto)
w.C.Update(own);assert(own.Focus==project)
own.Army=2;own.Queue={};own.Focus=nil;w.C.Update(own)
assert(own.NativeAuto,'Transfer restores the new army mode')
print('PASS: pre-acquisition filtering, 200-step no-flicker reproduction, immediate UI setting changes, toggles and transfers')
local w=New()
local parent=w:Unit(1,1,{ENGINEERSTATION=true,PODSTAGINGPLATFORM=true})
local drone=w:Unit(2,1,{POD=true,ENGINEER=true});drone.Parent=parent
local project=w:Unit(3);project.Fraction=.5;w.nearby={project}
w.C.Track(drone);w:Settings(1,false,true)
drone.Queue={{commandType=29}};drone.State='Attached'
w.C.Update(drone)
assert(drone.Focus==project and w.clears==1,'Replace the native idle return task to dispatch docked pods')
w.C.Update(drone);assert(w.clears==1,'Do not continually replace active work')
local hive=w:Unit(4,1,{ENGINEER=true,ENGINEERSTATION=true})
w.C.Track(hive);hive.Queue={{commandType=29}}
w.C.Update(hive)
assert(hive.Focus==project and w.clears==2,'Hive AssistCommander is also native idle work, not a player order')
