"""Opt-in, disposable real-FAF Lua smoke check. Never modifies managed game files.

Normal installation needs no arguments. /log and the temporary script overlay
below are diagnostic instrumentation for this test process only.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CHECK = r'''
local fd = FireDragonLoader
assert(fd and fd.IsPresent()==true and type(fd.IsPresent())=='boolean')
assert(fd.Version()==2 and type(fd.Version())=='number')
local probe=fd.Mods.FireDragonLuaProbe
assert(probe and probe.Answer()==42 and probe.Config.enabled)
assert(probe.Config.nested.value==17 and probe.Config.items[2]=='two')
local number,text=probe.Echo(3,'hello')
assert(number==4 and text=='hello')
assert(fd.Mods.Fixture.ShouldNotExist==nil)
local found=false
for _,mod in fd.LoadedMods() do
    assert(type(mod.name)=='string' and type(mod.version)=='number')
    assert(type(mod.dlls)=='table' and type(mod.shaders)=='table')
    assert(mod.name~='Fixture')
    assert(mod.name~='RejectedShader')
    if mod.name=='FireDragonLuaProbe' then
        found=true
        assert(mod.version==7 and mod.dlls[1]=='dlls/Probe.dll')
        assert(table.getn(mod.shaders)==1 and mod.shaders[1]=='FireDragonSmokeSurface')
    end
end
assert(found)
local errorFound=false
for _,row in fd.Logs() do
    assert(type(row.level)=='string' and type(row.msg)=='string')
    if row.level=='error' and string.find(row.msg,'FDEntryFixtureFailing',1,true) then errorFound=true end
end
assert(errorFound)
LOG('FD_LUA_'..(FDProbeContext or 'UI')..'_PASS')
'''


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--game',type=Path,default=Path(os.environ['ProgramData'])/'FAForever/bin/ForgedAlliance.exe')
    parser.add_argument('--mods',type=Path,required=True)
    parser.add_argument('--replay',type=Path)
    args=parser.parse_args()
    mods=args.mods.resolve(strict=True)
    artifacts=ROOT/'artifacts/lua-smoke';artifacts.mkdir(parents=True,exist_ok=True)
    fixture=mods/'FireDragonLuaProbe'
    failing=mods/'FireDragonLuaProbeFailure'
    rejected=mods/'FireDragonLuaProbeRejectedShader'
    if fixture.exists() or failing.exists() or rejected.exists(): raise RuntimeError('Smoke fixture folder already exists; refusing overwrite')
    managed={p:hashlib.sha256(p.read_bytes()).digest() for p in [args.game,args.game.parent/'init_faf.lua',args.game.parent.parent/'gamedata/effects.nx2']}
    created=[]
    process=None
    try:
        for folder,name,dll,version in [(fixture,'FireDragonLuaProbe','Probe',7),(failing,'Fixture','Failing',1)]:
            (folder/'dlls').mkdir(parents=True)
            shutil.copy2(ROOT/'dist'/f'{dll}.dll',folder/'dlls'/f'{dll}.dll')
            (folder/'firedragonmod.json').write_text(json.dumps({'name':name,'version':version,'dlls':[f'dlls/{dll}.dll']}))
            created.append(folder)
        (fixture/'shaders').mkdir()
        (fixture/'shaders/probe.fx').write_text('''
float4 FDSmokeVS(float4 p:POSITION):POSITION {return p;}
float4 FDSmokePS():COLOR0 {return float4(0,0.2,1,0.3);}
technique FireDragonSmokeSurface {pass P {VertexShader=compile vs_2_0 FDSmokeVS();PixelShader=compile ps_2_0 FDSmokePS();}}
''')
        definition=json.loads((fixture/'firedragonmod.json').read_text())
        definition['shaders']={'FireDragonSmokeSurface':'shaders/probe.fx'}
        (fixture/'firedragonmod.json').write_text(json.dumps(definition))
        rejected.mkdir();created.append(rejected)
        (rejected/'broken.fx').write_text('invalid shader !!!')
        (rejected/'firedragonmod.json').write_text(json.dumps({'name':'RejectedShader','shaders':{'RejectedSurface':'broken.fx'}}))
        (fixture/'check.lua').write_text(CHECK)
        log=artifacts/('sim.log' if args.replay else 'ui.log')
        log.unlink(missing_ok=True)
        command=[str(args.game),'/log',str(log),'/nobugreport']
        overlay=artifacts/('overlay-sim' if args.replay else 'overlay-ui')
        wanted='lua/siminit.lua' if args.replay else 'lua/ui/menus/main.lua'
        with zipfile.ZipFile(args.game.parent.parent/'gamedata/lua.nx2') as archive:
            member=next(n for n in archive.namelist() if n.lower()==wanted)
            original=archive.read(member)
        instrumented=overlay/member
        instrumented.parent.mkdir(parents=True,exist_ok=True)
        instrumented.write_bytes(original+b"\nFDProbeContext='"+(b'SIM' if args.replay else b'UI')+b"'\n"+CHECK.encode())
        init=artifacts/'init.lua'
        def lua_path(path): return "'"+str(path).replace('\\','/').replace("'","\\'")+"'"
        init.write_text('InitFileDir='+lua_path(args.game.parent)+"\ndofile("+lua_path(args.game.parent/'init_faf.lua')+")\ntable.insert(path,1,{dir="+lua_path(overlay)+",mountpoint='/'})\n")
        command+=['/init',str(init)]
        if args.replay:
            command+=['/replay',str(args.replay.resolve(strict=True))]
            expected='FD_LUA_SIM_PASS'
        else:
            expected='FD_LUA_UI_PASS'
        startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
        process=subprocess.Popen(command,cwd=args.game.parent,startupinfo=startup)
        deadline=time.monotonic()+45
        content=''
        while time.monotonic()<deadline:
            if log.exists(): content=log.read_text(errors='replace')
            if expected in content:break
            if process.poll() is not None:break
            time.sleep(.25)
        native=Path(os.environ['LOCALAPPDATA'])/'FireDragonModLoader'/f'loader-{process.pid}.log'
        if native.exists(): shutil.copy2(native,artifacts/('native-sim.log' if args.replay else 'native-ui.log'))
        if expected not in content:
            raise RuntimeError('Actual Lua smoke did not pass:\n'+'\n'.join(content.splitlines()[-45:]))
        print('PASS: actual FAF '+expected+'; built-ins, loaded resources, logs, native callbacks, nested values and failed-entry rollback')
    finally:
        if process and process.poll() is None:
            process.terminate();process.wait(timeout=10)
        for folder in created:
            target=folder.resolve()
            if target.parent!=mods or target.name not in ('FireDragonLuaProbe','FireDragonLuaProbeFailure','FireDragonLuaProbeRejectedShader'): raise RuntimeError('Unsafe fixture cleanup target')
            shutil.rmtree(target)
        assert all(hashlib.sha256(p.read_bytes()).digest()==h for p,h in managed.items()),'Managed game file changed'


if __name__=='__main__': main()
