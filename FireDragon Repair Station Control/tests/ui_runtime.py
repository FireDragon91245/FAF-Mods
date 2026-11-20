"""Disposable real-FAF UI check, using a temporary source mount, never game edits."""
import os
from pathlib import Path
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CHECK = r"""
local prefs=import('/lua/user/prefs.lua')
local original=prefs.GetFromCurrentProfile('FireDragonStorage')
local focusValue=1
local function unit(id,army,cats)
 return {GetArmy=function() return army end,GetEntityId=function() return id end,
  GetBlueprint=function() return {CategoriesHash=cats} end}
end
local drone=unit(1,1,{POD=true,ENGINEER=true})
local station=unit(2,1,{ENGINEERSTATION=true,TECH3=true})
local selection={drone}
local ok,message=pcall(function()
 local panel=import('/rsc-runtime-panel.lua')
 panel.GetFocusArmy=function() return focusValue end
 panel.GetSelectedUnits=function() return selection end
 local exchangeModule=import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua')
 exchangeModule.GetGameTimeSeconds=function() return 0 end
 local exchange=exchangeModule.Export
 exchange.PublishConfig('RepairStationControl.Army.1',{DontHelpTeam=false,DontHelpNukes=false},'ReadWrite',function() end)
 panel.Update()
 local w=panel.TestWindow()
 assert(w and not w:IsHidden(),'Window opens in actual FAF')
 assert(w.Title.FDText=='FireDragon: Repair Station Control','Window title')
 local checks={}
 local function walk(node)
  if node.IsChecked then table.insert(checks,node) end
  for _,child in ipairs(node.FDChildren or {}) do walk(child) end
 end
 walk(w)
 assert(table.getn(checks)==2,'Exactly two checkboxes')
 assert(not checks[1]:IsChecked() and not checks[2]:IsChecked(),'Defaults unchecked')
 checks[1].FDHit:HandleEvent({Type='ButtonPress',Modifiers={Left=true}})
 assert(checks[1]:IsChecked(),'Native checkbox input')
 w:SetSize(470,240);w:SaveGeometry()
 w:Close();panel.Update();assert(w:IsHidden(),'Close remains effective')
 selection={station,drone};panel.Update();assert(not w:IsHidden(),'Multi-selection reopens')
 selection={};panel.Update();assert(not panel.TestWindow(),'Deselect destroys window')
 selection={drone};panel.Update();w=panel.TestWindow()
 assert(w and not w:IsHidden(),'Reselect opens window')
 focusValue=2;selection={unit(3,2,{ENGINEERSTATION=true})}
 panel.Update()
 w=panel.TestWindow()
 assert(w.Width()>=469 and w.Width()<=471,'Width restored')
 assert(w.Height()>=239 and w.Height()<=241,'Height restored')
 w:Destroy()
end)
prefs.SetToCurrentProfile('FireDragonStorage',original)
SavePreferences()
assert(ok,message)
"""

def main():
    if subprocess.run(['powershell','-NoProfile','-Command',"if (Get-Process ForgedAlliance -ErrorAction SilentlyContinue) { exit 1 }"],capture_output=True).returncode:
        raise RuntimeError('Close Forged Alliance before running the disposable UI check')
    game=Path(os.environ['ProgramData'])/'FAForever/bin/ForgedAlliance.exe'
    artifacts=ROOT/'artifacts/ui-runtime';artifacts.mkdir(parents=True,exist_ok=True)
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
    probe=overlay/'rsc-runtime-panel.lua'
    probe.parent.mkdir(parents=True,exist_ok=True)
    (overlay/'rsc-runtime-policy.lua').write_text((ROOT/'src/lua/RepairStationControl/Policy.lua').read_text())
    probe.write_text((ROOT/'src/lua/RepairStationControl/Panel.lua').read_text().replace('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Policy.lua','/rsc-runtime-policy.lua')+"\nfunction TestWindow() return window end\n")
    def quote(p): return "'"+str(p).replace('\\','/').replace("'","\\'")+"'"
    init=artifacts/'init.lua'
    init.write_text('InitFileDir='+quote(game.parent)+"\ndofile("+quote(game.parent/'init_faf.lua')+")\ntable.insert(path,1,{dir="+quote(overlay)+",mountpoint='/'})\ntable.insert(path,1,{dir="+quote(ROOT.parent/'FireDragon Core & Loader/src')+",mountpoint='/mods/FireDragon Core & Loader'})\n")
    init.write_text(init.read_text()+"table.insert(path,1,{dir="+quote(ROOT/'src')+",mountpoint='/mods/FireDragon Repair Station Control'})\n")
    init.write_text(init.read_text()+"table.insert(path,1,{dir="+quote(overlay)+",mountpoint='/'})\n")
    log=artifacts/'game.log';log.unlink(missing_ok=True)
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    process=subprocess.Popen([str(game),'/init',str(init),'/log',str(log),'/nobugreport','/nomovie'],cwd=game.parent,startupinfo=startup)
    try:
        deadline=time.monotonic()+120
        while time.monotonic()<deadline:
            content=log.read_text(errors='replace') if log.exists() else ''
            if 'FD_UI_RUNTIME_PASS' in content:
                print('PASS: actual FAF selection window, two bound checkboxes, native input, multi-selection and saved geometry');return
            if 'FD_UI_RUNTIME_FAIL' in content or process.poll() is not None: break
            time.sleep(.25)
        raise RuntimeError('Actual UI check failed:\n'+'\n'.join(content.splitlines()[-45:]))
    finally:
        if process.poll() is None: process.terminate();process.wait(timeout=10)

if __name__=='__main__': main()
