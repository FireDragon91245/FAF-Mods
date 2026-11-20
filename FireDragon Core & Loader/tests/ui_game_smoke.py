"""Disposable real-FAF UI check, using a temporary source mount, never game edits."""
import os
from pathlib import Path
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CHECK = r"""
local UI=import('/mods/FireDragon Core & Loader/lua/FireDragon/UI.lua').Export
local window=UI.Window(GetFrame(0),{x=100,y=100,width=400,height=240,title='UI runtime check'})
local checkbox=UI.Checkbox(window.Client,{x=20,y=20,width=240,height=26,text='Native checkbox'})
local close=window.CloseButton
assert(checkbox.FDHit:HitTest(checkbox.Left()+10,checkbox.Top()+10),'Checkbox native hit bounds')
assert(close.FDHit:HitTest(close.Left()+12,close.Top()+12),'Close native hit bounds')
assert(not checkbox.FDHit:HitTest(checkbox.Left()-10,checkbox.Top()-10),'No offset hit region')
checkbox.FDHit:HandleEvent({Type='MouseEnter'})
checkbox.FDHit:HandleEvent({Type='ButtonPress',Modifiers={Left=true}})
assert(checkbox:IsChecked(),'Native checkbox input')
local scroll=UI.Scroll(window.Client,{x=10,y=70,width=200,height=100,contentWidth=400,contentHeight=60})
assert(scroll.Scrollbar:IsHidden(),'No vertical scrollbar without overflow')
assert(not scroll.HorizontalScrollbar:IsHidden(),'Horizontal overflow exposes a scrollbar')
assert(scroll.HorizontalThumb.FDHit:HitTest(scroll.HorizontalThumb.Left()+2,scroll.HorizontalThumb.Top()+2),'Native horizontal thumb hit bounds')
scroll.Content.Height:Set(300);scroll:RefreshScrollbars()
assert(not scroll.Scrollbar:IsHidden(),'Scrollbar appears')
scroll:ScrollTo(30,90)
assert(scroll.Content.Left()==scroll.Left()-30 and scroll.Content.Top()==scroll.Top()-90,'Native cached scroll layout invalidates')
local icon=UI.Icon(scroll.Content,{x=0,y=90,width=80,height=40,texture='/textures/ui/common/CHECKBOX/d_up.dds'})
UI.Interactive(icon);icon:OnFrame(0)
assert(icon.FDHit.Left()==scroll.Left() and icon.FDHit.Width()==50,'Native clip and hit bounds agree')
local paths={
 '/CHECKBOX/d_up.dds','/CHECKBOX/s_over.dds',
 '/dialogs/close_btn/close_btn_up.dds',
 '/scx_menu/small-btn/small_btn_up.dds',
 '/SCROLLBAR_VERT/back_scr_mid.dds','/SCROLLBAR_VERT/bar-mid_scr_up.dds',
 '/game/options_brd/options_brd_ul.dds','/game/options_brd/options_brd_m.dds',
}
local util=import('/lua/ui/uiutil.lua')
for _,path in ipairs(paths) do
 local file=util.SkinnableFile(path);if type(file)=='function' then file=file() end
 assert(DiskGetFileInfo(file),'Missing vanilla asset: '..path)
end
window:Close();assert(window:IsHidden(),'Window closes')
local function refreshTree(node)
 if node.OnFrame then node:OnFrame(0.2) end
 for _,child in ipairs(node.FDChildren or {}) do refreshTree(child) end
end
refreshTree(window)
assert(window.FDVisual:IsHidden() and checkbox.Check.FDVisual:IsHidden() and checkbox.Label.FDVisual:IsHidden(),'Closed window stays rendered-hidden after frame callbacks')
assert(scroll.Scrollbar:IsHidden(),'Closed viewport cannot re-show scrollbar')
checkbox.Label:SetText('Update while closed')
assert(checkbox.Label.FDVisual:IsHidden(),'Data refresh cannot reveal closed window')
window:Show();refreshTree(window)
assert(not window.FDVisual:IsHidden() and not checkbox.Check.FDVisual:IsHidden() and not checkbox.Label.FDVisual:IsHidden(),'Reopened window renders again')
window:Destroy()
local prefs=import('/lua/user/prefs.lua')
local key='FireDragon_UI_RuntimeSmoke_Window'
local original=prefs.GetFromCurrentProfile('FireDragonStorage')
local ok,message=pcall(function()
 local remembered=UI.Window(GetFrame(0),{prefKey=key,x=40,y=60,width=400,height=240})
 remembered:SetSize(450,280);remembered:Close();remembered:Destroy()
 local restored=UI.Window(GetFrame(0),{prefKey=key,width=200,height=100})
 assert(restored.Width()>=449 and restored.Width()<=451 and restored.Height()>=279 and restored.Height()<=281,'Native profile geometry restoration')
 restored:Destroy()
end)
prefs.SetToCurrentProfile('FireDragonStorage',original)
SavePreferences()
assert(ok,message)
"""

def main():
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
    ForkThread(function()
        WaitSeconds(1)
        local ok,message=pcall(function()
"""+CHECK+"""
        end)
        if ok then LOG('FD_UI_RUNTIME_PASS') else WARN('FD_UI_RUNTIME_FAIL: '..tostring(message)) end
    end)
    return result
end
"""
    target.write_bytes(original+appended.encode())
    def quote(p): return "'"+str(p).replace('\\','/').replace("'","\\'")+"'"
    init=artifacts/'init.lua'
    init.write_text('InitFileDir='+quote(game.parent)+"\ndofile("+quote(game.parent/'init_faf.lua')+")\ntable.insert(path,1,{dir="+quote(overlay)+",mountpoint='/'})\ntable.insert(path,1,{dir="+quote(ROOT/'src')+",mountpoint='/mods/FireDragon Core & Loader'})\n")
    log=artifacts/'game.log';log.unlink(missing_ok=True)
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    process=subprocess.Popen([str(game),'/init',str(init),'/log',str(log),'/nobugreport','/nomovie'],cwd=game.parent,startupinfo=startup)
    try:
        deadline=time.monotonic()+45
        while time.monotonic()<deadline:
            content=log.read_text(errors='replace') if log.exists() else ''
            if 'FD_UI_RUNTIME_PASS' in content:
                print('PASS: actual FAF native hit tests, checkbox input, cached scrolling, clipping, window lifecycle and vanilla assets');return
            if 'FD_UI_RUNTIME_FAIL' in content or process.poll() is not None: break
            time.sleep(.25)
        raise RuntimeError('Actual UI check failed:\n'+'\n'.join(content.splitlines()[-45:]))
    finally:
        if process.poll() is None: process.terminate();process.wait(timeout=10)

if __name__=='__main__': main()
