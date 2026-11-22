"""Exercise native assistance work types, for both workers and all option combinations."""
import sim_runtime as harness
harness.ARTIFACT_NAME='work-runtime'
harness.SUCCESS='PASS: native Kennel and Hive assistance, six work types with all four restriction combinations (48 cases)'
harness.SIM_CHECK = r"""
local previous=BeginSession
function BeginSession()
 local result=previous()
 ForkThread(function()
  WaitTicks(20)
  local C=import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Controller.lua').Export
  local S=import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Settings.lua').Export
  local E=import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua').Export
  local function check(value,message)
   if not value then WARN('RSC_SIM_RUNTIME_FAIL: '..message);error(message) end
  end
  local brain=ArmyBrains[1]
  brain:GiveResource('MASS',1000000);brain:GiveResource('ENERGY',10000000)
  local function spawn(id,x,z) return CreateUnitHPR(id,1,x,GetTerrainHeight(x,z),z,0,0,0) end
  local kennel=spawn('xeb0104',100,100)
  local hive=spawn('xrb0104',160,100)
  WaitTicks(10)
  local drone=kennel.PodData.PodOne.PodHandle
  local fixtures={{worker=drone,x=100,name='Kennel'},{worker=hive,x=160,name='Hive'}}
  for _,f in ipairs(fixtures) do
   local fixture=f
   local original=f.worker.OnStartBuild
   f.worker.OnStartBuild=function(self,target,order)
    if target then fixture.seen[target.UnitId]=true end
    return original(self,target,order)
   end
  end
  for _,options in ipairs({{true,true},{true,false},{false,true},{false,false}}) do
   E.Set(S.Key(1),{DontHelpTeam=options[1],DontHelpNukes=options[2]})
   for _,case in ipairs({
    {name='factory assembly',id='ueb0301',product='uel0303'},
    {name='factory upgrade',id='ueb0101',upgrade='ueb0201'},
    {name='repair station upgrade',id='xrb0104',upgrade='xrb0204'},
    {name='extractor upgrade',id='ueb1103',upgrade='ueb1202'},
    {name='building construction',id='uel0309',construct='ueb1201'},
    {name='damaged building repair',id='ueb1301',repair=true},
   }) do
    for _,f in ipairs(fixtures) do
     C.SetAuto(f.worker,false);IssueClearCommands({f.worker});f.seen={}
     f.target=spawn(case.id,f.x+9,100)
     if case.product then IssueBuildFactory({f.target},case.product,1)
     elseif case.upgrade then IssueUpgrade({f.target},case.upgrade)
     elseif case.construct then brain:BuildStructure(f.target,case.construct,{f.x+9,110,0},false)
     else f.target:SetHealth(f.worker,1) end
    end
    WaitTicks(case.construct and 30 or 10)
    for _,f in ipairs(fixtures) do
     f.focus=f.target:GetFocusUnit()
     if case.construct then check(f.focus,'Engineer started construction '..repr(f.target:GetCommandQueue())) end
     C.SetAuto(f.worker,true)
    end
    WaitTicks(45)
    for _,f in ipairs(fixtures) do
     local expected=case.product or case.upgrade or case.construct or case.id
     check(f.seen[expected],f.name..' '..case.name..' filters='..repr(options)..' seen='..repr(f.seen)..' focus='..tostring(f.focus and f.focus.UnitId)..' worker='..repr(f.worker:GetCommandQueue()))
     if case.repair then check(f.target:GetHealth()>1,f.name..' repair increases health') end
     LOG('RSC_WORK_PASS '..f.name..' '..case.name..' filters='..repr(options))
     C.SetAuto(f.worker,false);IssueClearCommands({f.worker})
     local focus=f.target:GetFocusUnit()
     if focus and focus~=f.target and not focus.Dead then focus:Destroy() end
     if f.focus and f.focus~=f.target and not f.focus.Dead then f.focus:Destroy() end
     if not f.target.Dead then f.target:Destroy() end
    end
    WaitTicks(5)
   end
  end
  LOG('RSC_SIM_RUNTIME_PASS')
 end)
 return result
end
"""
if __name__ == '__main__': harness.main()
