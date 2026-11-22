"""Disposable real-FAF UI check, using a temporary source mount, never game edits."""
import os
import re
from pathlib import Path
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_NAME = 'sim-runtime'
CHECK = r"""local prefs=import('/lua/user/prefs.lua')
local old=prefs.GetFromCurrentProfile('LoadingFaction')
local scenario=import('/lua/ui/maputil.lua').LoadScenario('/maps/SCMP_001/SCMP_001_scenario.lua')
local data=import('/lua/singleplayerlaunch.lua').SetupCampaignSession(scenario,2,1,nil,false)
data.scenarioInfo.Options.Victory='sandbox'
data.scenarioInfo.Options.CheatsEnabled='true'
data.scenarioInfo.Options.UnitCap=1000
data.scenarioMods=import('/lua/mods.lua').GetGameMods({['3f98ee06-c20c-4fd6-a29e-d7e306fd2026']=true,['9b1b4042-3b48-4ea3-a06b-d7c2e21c4931']=true})
prefs.SetToCurrentProfile('LoadingFaction',old)
LaunchSinglePlayerSession(data)"""
SIM_CHECK = r"""local RSCNativePreviousBegin=BeginSession
function BeginSession()
 local result=RSCNativePreviousBegin()
 ForkThread(function()
  WaitTicks(20)
  local function check(value,message)
   if not value then WARN('RSC_SIM_RUNTIME_FAIL: '..message);error(message) end
  end
   local E=import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua').Export
   local S=import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Settings.lua').Export
   local module=import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Controller.lua')
   local C=module.Export
   local brain=ArmyBrains[1]
   brain:GiveResource('MASS',1000000);brain:GiveResource('ENERGY',10000000)
   local function spawn(id,x,z)
    return CreateUnitHPR(id,1,x,GetTerrainHeight(x,z),z,0,0,0)
   end
   local kennel=spawn('xeb0104',100,100)
   WaitTicks(10)
   local drone=kennel.PodData and kennel.PodData.PodOne and kennel.PodData.PodOne.PodHandle
   check(drone and not drone.Dead,'Kennel created a real attached drone')
   local silo=spawn('ueb2305',105,100)
   IssueSiloBuildNuke({silo})
   C.SetAuto(drone,true)
   IssueGuard({drone},silo)
   WaitTicks(30)
   check(drone:GetGuardedUnit()==silo or drone:GetFocusUnit()==silo,'Precondition: existing silo assist')
   local starts,clears=0,0
   local previous=drone.OnStartBuild
   drone.OnStartBuild=function(self,target,order)
    if target==silo then starts=starts+1 end
    return previous(self,target,order)
   end
   local clear=module.IssueClearCommands
   module.IssueClearCommands=function(units)
    if units[1]==drone then clears=clears+1 end
    clear(units)
   end
   E.SetPath(S.Key(1),{'DontHelpNukes'},true)
   check(drone.AutoModeEnabled,'Native automation stays enabled while candidates are filtered')
   check(clears==1,'Settings change issues exactly one stop')
   WaitTicks(100)
   LOG('RSC_DIAG '..repr(FireDragonLoader.Mods.RepairStationControl.Debug())..' drone='..drone.EntityId..' silo='..silo.EntityId..' starts='..starts..' clears='..clears)
   check(starts==0 and clears==1,'No native reacquisition or stop/start loop beside silo')
   check(not drone:GetFocusUnit() and not drone:GetGuardedUnit(),'Excluded silo leaves drone idle')
   local radar=spawn('ueb3101',110,100)
   radar:SetHealth(drone,1)
   WaitTicks(100)
   check(radar:GetHealth()>1,'Drone finds and performs allowed work')
   check(starts==0,'Allowed work never switches back to silo')
   E.SetPath(S.Key(1),{'DontHelpNukes'},false)
   check(drone.AutoModeEnabled,'Native automation remains enabled with filters removed')
   C.SetAuto(drone,false)
   local hive=spawn('xrb0104',100,112)
   IssueGuard({hive},silo)
   WaitTicks(20)
   check(hive:GetGuardedUnit()==silo or hive:GetFocusUnit()==silo,'Hive precondition: existing silo assist')
   local hiveStarts,hiveClears=0,0
   local hiveBuild=hive.OnStartBuild
   hive.OnStartBuild=function(self,target,order)
    if target==silo then hiveStarts=hiveStarts+1 end
    return hiveBuild(self,target,order)
   end
   local hiveClear=module.IssueClearCommands
   module.IssueClearCommands=function(units)
    if units[1]==hive then hiveClears=hiveClears+1 end
    hiveClear(units)
   end
   E.SetPath(S.Key(1),{'DontHelpNukes'},true)
   check(hive.AutoModeEnabled and hiveClears==1,'Hive stopped once while native search remains enabled')
   WaitTicks(100)
   check(hiveStarts==0 and hiveClears==1,'Hive cannot reacquire prohibited silo')
   LOG('RSC_SIM_RUNTIME_PASS')
 end)
 return result
end
"""

SUCCESS='PASS: real FAF Kennel and Hive, excluded silo stopped once without reacquisition, allowed repair and native automation'

def main():
    if subprocess.run(['powershell','-NoProfile','-Command',"if (Get-Process ForgedAlliance -ErrorAction SilentlyContinue) { exit 1 }"],capture_output=True).returncode:
        raise RuntimeError('Close Forged Alliance before running the disposable UI check')
    game=Path(os.environ['ProgramData'])/'FAForever/bin/ForgedAlliance.exe'
    artifacts=ROOT/'artifacts'/ARTIFACT_NAME;artifacts.mkdir(parents=True,exist_ok=True)
    overlay=artifacts/'overlay';target=overlay/'lua/ui/menus/main.lua';target.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(game.parent.parent/'gamedata/lua.nx2') as archive:
        member=next(n for n in archive.namelist() if n.lower()=='lua/ui/menus/main.lua')
        original=archive.read(member)
    appended="""
local originalCreateUI=CreateUI
function CreateUI(...)
    local result=originalCreateUI(unpack(arg))
    local ok,message=pcall(function()
"""+CHECK+"""
        end)
    if ok then LOG('FD_UI_RUNTIME_PASS') else WARN('FD_UI_RUNTIME_FAIL: '..tostring(message)) end
    return result
end
"""
    target.write_bytes(original+appended.encode())
    with zipfile.ZipFile(game.parent.parent/'gamedata/lua.nx2') as archive:
        member=next(n for n in archive.namelist() if n.lower()=='lua/siminit.lua')
        sim_original=archive.read(member)
    sim_target=overlay/'lua/SimInit.lua'
    sim_target.write_bytes(sim_original+SIM_CHECK.encode())
    def quote(p): return "'"+str(p).replace('\\','/').replace("'","\\'")+"'"
    init=artifacts/'init.lua'
    init.write_text('InitFileDir='+quote(game.parent)+"\ndofile("+quote(game.parent/'init_faf.lua')+")\ntable.insert(path,1,{dir="+quote(overlay)+",mountpoint='/'})\ntable.insert(path,1,{dir="+quote(ROOT.parent/'FireDragon Core & Loader/src')+",mountpoint='/mods/FireDragon Core & Loader'})\n")
    init.write_text(init.read_text()+"table.insert(path,1,{dir="+quote(ROOT/'src')+",mountpoint='/mods/FireDragon Repair Station Control'})\n")
    init.write_text(init.read_text()+"table.insert(path,1,{dir="+quote(overlay)+",mountpoint='/'})\n")
    log=artifacts/'game.log';log.unlink(missing_ok=True)
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    process=subprocess.Popen([str(game),'/init',str(init),'/log',str(log),'/nobugreport','/nomovie'],cwd=game.parent,startupinfo=startup)
    try:
        deadline=time.monotonic()+300
        while time.monotonic()<deadline:
            content=log.read_text(errors='replace') if log.exists() else ''
            if 'RSC_SIM_RUNTIME_PASS' in content:
                print(SUCCESS);return
            if 'BeginSession() failed:' in content or 'RSC_SIM_RUNTIME_FAIL' in content or 'FD_UI_RUNTIME_FAIL' in content or 'Sim::Create() crashed' in content or 'Unknown unit type:' in content or re.search(r'Error running lua script: [^\r\n]*siminit\.lua',content) or process.poll() is not None: break
            time.sleep(.25)
        raise RuntimeError('Actual simulation check failed:\n'+'\n'.join(content.splitlines()[-45:]))
    finally:
        if process.poll() is None: process.terminate();process.wait(timeout=10)

if __name__=='__main__': main()
