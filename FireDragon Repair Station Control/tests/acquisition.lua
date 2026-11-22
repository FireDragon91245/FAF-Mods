local New=assert(loadfile('tests/support/Fixture.lua'))()
local w=New()
local own=w:Unit(1,1,{ENGINEERSTATION=true})
local other=w:Unit(2,2,{POD=true,ENGINEER=true})
w.C.Track(own);w.C.Track(other)
for _,option in ipairs({{true,false,1},{false,true,2},{true,true,3},{false,false,0}}) do
    w:Settings(1,option[1],option[2])
    assert(w.workerSettings[1].DontHelpTeam==option[1] and w.workerSettings[1].DontHelpNukes==option[2] and not w.workerSettings[2].DontHelpTeam and not w.workerSettings[2].DontHelpNukes,'Native restrictions are per army')
    assert(own.NativeAuto and other.NativeAuto,'Restrictions must never disable native acquisition')
    for i=1,100 do w.C.Update(own) end
    assert(#w.orders==0 and w.clears==0,'Lua must never replace the native selector or issue assistance')
end
for _,cat in ipairs({'NUKE','ANTIMISSILE'}) do
    local silo=w:Unit(3,1,{SILO=true,[cat]=true});w.C.Track(silo)
    assert(not silo.RepairStationControlThread,'Targets need no Lua/native metadata registration')
    w:Settings(1,false,false)
    own.Focus=silo;own.Guard=silo;own.Queue={{commandType=29}}
    w:Settings(1,false,true)
    assert(not own.Focus and own.NativeAuto,'Settings immediately stop excluded work without disabling native selection')
    local clears=w.clears
    for i=1,100 do w.C.Update(own) end
    assert(w.clears==clears,'No repeated cancellation')
    w.C.Remove(silo)
end
own.Queue={{commandType=2}};w.C.Update(own);assert(own.Queue[1].commandType==2,'Manual commands remain intact')
w.C.SetAuto(own,false);assert(not own.NativeAuto and not own.AutoModeEnabled)
w.C.SetAuto(own,true);assert(own.NativeAuto and own.AutoModeEnabled)
own.Army=2;w.C.Update(own);assert(not w.workerSettings[1].DontHelpTeam and not w.workerSettings[1].DontHelpNukes,'Transfers adopt new owner policy')
w.C.Remove(own);assert(not w.workerSettings[1])
w.C.Reset();assert(not next(w.workerSettings),'New sessions clear native metadata')
print('PASS: native acquisition retained, per-army candidate flags, immediate cancellation, automation, transfers and session reset')


local stringId=w:Unit(11,1,{ENGINEERSTATION=true});stringId.EntityId='11'
w.C.Track(stringId);w:Settings(1,false,true)
assert(w.workerSettings[11].DontHelpNukes and w.workerSettings['11']==nil,'Engine string entity IDs are converted at the native boundary')

local native=w:Unit(12,1,{ENGINEERSTATION=true});w.C.Track(native)
local engineer=w:Unit(13,1,{ENGINEER=true});engineer.Health=50
local silo=w:Unit(14,1,{SILO=true,NUKE=true});engineer.Focus=silo
native.Focus=engineer;native.Queue={{commandType=29}}
local clears=w.clears;w.C.Update(native)
assert(w.clears==clears,'Native repair of an allowed engineer must not be cancelled because of the engineer work queue')
native.Focus=silo;w.C.Update(native);assert(w.clears==clears+1,'The actual excluded native repair recipient is still released')
