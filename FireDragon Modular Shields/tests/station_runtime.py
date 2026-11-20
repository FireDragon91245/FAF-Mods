"""Disposable native FAF station/module test; run once normally and once --rsc."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SIM = r"""
local stationBegin=BeginSession
function BeginSession()
 local result=stationBegin()
 ForkThread(function()
   WaitTicks(20)
   local function check(value,message)
    if not value then WARN('STATION_RUNTIME_FAIL: '..message);error(message) end
   end
   local R=import('/mods/FireDragon Modular Shields/lua/ModularShields/Runtime.lua').Export
   R.Config.Debug.IgnoreResources=false;R.Config.Debug.InstantUpgrade=false
   local brain=ArmyBrains[1]
   ForkThread(function()
    while true do brain:GiveResource('MASS',100000);brain:GiveResource('ENERGY',1000000);WaitTicks(1) end
   end)
   local function spawn(id,x,z) return CreateUnitHPR(id,1,x,GetTerrainHeight(x,z),z,0,0,0) end
   local fixtures={}
   for i,id in ipairs({'xeb0104','xeb0204','xrb0104','xrb0204','xrb0304'}) do
    local x=60+i*70
    local station=spawn(id,x,100)
    local host=spawn('mdeb4401',x+(i<=2 and 14 or 9),100)
    table.insert(fixtures,{Id=id,Station=station,Host=host,MaxRate=0})
   end
   local baseline=spawn('mdeb4401',110,150)
   WaitTicks(40)
   for _,f in fixtures do
    if f.Station.PodData then
     local pods={}
     for _,data in f.Station.PodData do if data.Active and data.PodHandle then table.insert(pods,data.PodHandle) end end
     check(table.getn(pods)>0,f.Id..' did not create pods')
     f.Workers=pods
    else f.Workers={f.Station} end
    for _,worker in f.Workers do
     check(worker.ModuleAutoAssistThread,f.Id..' missing automatic module scan')
     LOG('STATION_IDLE '..f.Id..' auto='..tostring(worker.AutoModeEnabled)..' commands='..repr(worker:GetCommandQueue()))
    end
   end
   local function round(module)
    local start=GetGameTick()
    local baseJob,reason=baseline:RequestModuleInstall(module)
    check(baseJob,'baseline module rejected: '..repr(reason))
    local baseDone
    for _,f in fixtures do
     f.MaxRate=0;f.Done=nil
     f.Job,reason=f.Host:RequestModuleInstall(module)
     check(f.Job,f.Id..' module rejected: '..repr(reason))
    end
    for tick=1,220 do
     WaitTicks(1)
     if tick==25 then
      for _,f in fixtures do for _,u in f.Workers do
       LOG('STATION_TRACE '..f.Id..' '..repr({queue=u:GetCommandQueue(),focus=u:GetFocusUnit() and u:GetFocusUnit().EntityId,
        owner=u.ModuleAutoAssistHost and u.ModuleAutoAssistHost.EntityId,claimed=u.ModularAssistOwner and u.ModularAssistOwner.EntityId,
        auto=u.AutoModeEnabled,parentAuto=f.Station.AutoModeEnabled,paused=u:IsPaused(),parentPaused=f.Station:IsPaused(),
        productionOff=f.Station:GetScriptBit(4),position=u:GetPosition(),host=f.Host:GetPosition(),
        buildDistance=u.Blueprint.Economy.MaxBuildDistance,rate=f.Host.ModuleWorkRate,guards=table.getn(f.Host:GetGuards())}))
      end end
     end
     if baseline.Loadout.Installed[module] then baseDone=baseDone or GetGameTick()-start end
     local done=baseDone~=nil
     for _,f in fixtures do
      f.MaxRate=math.max(f.MaxRate,f.Host.ModuleWorkRate or 0)
      for _,u in f.Host.ModuleAssistants or {} do
       if u.ModularAssistActive then
        check(u==f.Station or u.Parent==f.Station,f.Id..' received worker '..tostring(u.EntityId)
         ..' parent='..tostring(u.Parent and u.Parent.EntityId)..' expected='..tostring(f.Station.EntityId)
         ..' scriptOwner='..tostring(u.ModuleAutoAssistHost and u.ModuleAutoAssistHost.EntityId))
       end
      end
      if f.Host.Loadout.Installed[module] then f.Done=f.Done or GetGameTick()-start end
      done=done and f.Done~=nil
     end
     if done then break end
    end
    check(baseDone,'baseline module never completed')
    for _,f in fixtures do
     check(f.MaxRate>R.Config.InstallRate,f.Id..' never contributed module build rate')
     check(f.Done and f.Done<baseDone,f.Id..' did not complete faster than unassisted shield')
     check(f.Job.MassSpent>0 and f.Job.EnergySpent>0,f.Id..' did not pay normal module costs')
     LOG('STATION_RESULT '..f.Id..' module='..module..' rate='..f.MaxRate..' ticks='..f.Done..' baseline='..baseDone)
    end
    WaitTicks(20)
    for _,f in fixtures do for _,worker in f.Workers do
     check(not worker.ModuleAutoAssistHost and not worker.ModularAssistOwner,f.Id..' did not release completed module')
     check(worker:GetBuildRate()>0,f.Id..' did not restore native build rate')
    end end
   end
   round('range_1')
   if STATION_WITH_RSC then
    local E=import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua').Export
    local S=import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Settings.lua').Export
    E.Set(S.Key(1),{DontHelpTeam=true,DontHelpNukes=true})
    WaitTicks(10)
    round('range_2')
   end
   LOG('STATION_RUNTIME_PASS')
 end)
 return result
end
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rsc', action='store_true')
    args = parser.parse_args()
    running = subprocess.run(['powershell', '-NoProfile', '-Command',
                              'if (Get-Process ForgedAlliance -ErrorAction SilentlyContinue) { exit 1 }'],
                             capture_output=True)
    if running.returncode:
        raise RuntimeError('Close Forged Alliance before running this disposable native test')
    game = Path(os.environ['ProgramData']) / 'FAForever/bin/ForgedAlliance.exe'
    artifacts = ROOT / 'artifacts/station-runtime' / ('both-mods' if args.rsc else 'shield-only')
    overlay = artifacts / 'overlay'
    overlay.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(game.parent.parent / 'gamedata/lua.nx2') as archive:
        def read(path):
            return archive.read(next(n for n in archive.namelist() if n.lower() == path.lower()))
        menu = read('lua/ui/menus/main.lua')
        sim = read('lua/simInit.lua')
    mods = "['3f98ee06-c20c-4fd6-a29e-d7e306fd2026']=true,['bf55b8d0-2026-4115-9000-000000000001']=true"
    if args.rsc:
        mods += ",['9b1b4042-3b48-4ea3-a06b-d7c2e21c4931']=true"
    launch = r"""
local stationCreateUI=CreateUI
function CreateUI(...)
 local result=stationCreateUI(unpack(arg))
 local prefs=import('/lua/user/prefs.lua')
 local old=prefs.GetFromCurrentProfile('LoadingFaction')
 local scenario=import('/lua/ui/maputil.lua').LoadScenario('/maps/SCMP_001/SCMP_001_scenario.lua')
 local data=import('/lua/singleplayerlaunch.lua').SetupCampaignSession(scenario,2,1,nil,false)
 data.scenarioInfo.Options.Victory='sandbox'
 data.scenarioInfo.Options.CheatsEnabled='true'
 data.scenarioInfo.Options.UnitCap=1000
 data.scenarioMods=import('/lua/mods.lua').GetGameMods({MOD_SELECTION})
 prefs.SetToCurrentProfile('LoadingFaction',old)
 LaunchSinglePlayerSession(data)
 return result
end
""".replace('MOD_SELECTION', mods)
    menu_file = overlay / 'lua/ui/menus/main.lua'
    menu_file.parent.mkdir(parents=True, exist_ok=True)
    menu_file.write_bytes(menu + launch.encode())
    # The source mount cannot hide a file removed from an older installed mod.
    # Shadow its obsolete per-drone hook in this disposable overlay only.
    obsolete = overlay / 'mods/ModularShields/hook/units/xea3204/xea3204_script.lua'
    obsolete.parent.mkdir(parents=True, exist_ok=True)
    obsolete.write_text('-- Replaced by the source Unit creation hook.\n')
    (overlay / 'lua/simInit.lua').write_bytes(sim + ('\nlocal STATION_WITH_RSC=' + str(args.rsc).lower() + '\n' + SIM).encode())
    def quote(path):
        return "'" + str(path).replace('\\', '/').replace("'", "\\'") + "'"
    init = artifacts / 'init.lua'
    init_text = 'InitFileDir=' + quote(game.parent) + '\ndofile(' + quote(game.parent / 'init_faf.lua') + ')\n'
    for source, mount in [(ROOT / 'src', '/mods/FireDragon Modular Shields'),
                          (ROOT.parent / 'FireDragon Core & Loader/src', '/mods/FireDragon Core & Loader'),
                          (ROOT.parent / 'FireDragon Repair Station Control/src', '/mods/FireDragon Repair Station Control'),
                          (overlay, '/')]:
        init_text += 'table.insert(path,1,{dir=' + quote(source) + ",mountpoint='" + mount + "'})\n"
    init.write_text(init_text)
    prefs = artifacts / 'Game.prefs'
    shutil.copyfile(Path(os.environ['LOCALAPPDATA']) / 'Gas Powered Games/Supreme Commander Forged Alliance/Game.prefs', prefs)
    log = artifacts / 'game.log'
    log.unlink(missing_ok=True)
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    process = subprocess.Popen([str(game), '/init', str(init), '/prefs', str(prefs),
                                '/log', str(log), '/nobugreport', '/nomovie'],
                               cwd=game.parent, startupinfo=startup)
    try:
        deadline = time.monotonic() + 150
        while time.monotonic() < deadline:
            content = log.read_text(errors='replace') if log.exists() else ''
            if 'STATION_RUNTIME_PASS' in content:
                for line in content.splitlines():
                    if 'STATION_RESULT' in line:
                        print(line, flush=True)
                print('PASS: native paid module speedup and assistant release, ' + ('both mods' if args.rsc else 'shield only'))
                return
            if ('STATION_RUNTIME_FAIL' in content or 'Sim::Create() crashed' in content
                    or re.search(r'Error running lua script: [^\r\n]*siminit\.lua', content, re.I)
                    or process.poll() is not None):
                break
            time.sleep(.25)
        raise RuntimeError('Native station test failed:\n' + '\n'.join(content.splitlines()[-65:]))
    finally:
        # This Popen handle belongs only to this diagnostic launch.
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)


if __name__ == '__main__':
    main()
