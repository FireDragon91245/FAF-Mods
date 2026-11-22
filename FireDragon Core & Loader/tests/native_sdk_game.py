"""Disposable FAF test: exported-DLL reflection, shared hooks and mod-owned assistance hooks."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    if subprocess.run(['powershell','-NoProfile','-Command',
                       'if (Get-Process ForgedAlliance -ErrorAction SilentlyContinue) { exit 1 }'],
                      capture_output=True).returncode:
        raise RuntimeError('Close Forged Alliance before running the disposable SDK check')
    config=Path(os.environ['ProgramData'])/'FAForever/fa_path.lua'
    match=re.search(r'''custom_vault_path\s*=\s*["']([^"']+)["']''',config.read_text())
    mods=(Path(match[1])/'mods') if match else Path.home()/'Documents/My Games/Gas Powered Games/Supreme Commander Forged Alliance/mods'
    mods=mods.resolve(strict=True)
    fixture=mods/'FireDragon Native SDK Test'
    if fixture.exists(): raise RuntimeError('SDK fixture already exists; refusing overwrite')
    spec=importlib.util.spec_from_file_location('rsc_runtime',ROOT.parent/'FireDragon Repair Station Control/tests/sim_runtime.py')
    harness=importlib.util.module_from_spec(spec);spec.loader.exec_module(harness)
    harness.ARTIFACT_NAME='native-sdk-runtime'
    harness.SUCCESS='PASS: real FAF export reflection, shared Start/End hooks and mod-owned silo exclusion/allowed repair'
    checks=r"""
   local probe=FireDragonLoader.Mods.NativeExample
   check(probe and probe.Exercise,'Dynamically resolved example DLL loaded')
   local before=probe.VisitCount()
   local completed=probe.ReturnCount()
   check(probe.Exercise(5)==6,'Patched native DLL function retains its behavior')
   check(probe.LastInput()==5 and probe.LastOutput()==6,'Typed stack and return-register arguments reach callbacks')
   check(probe.VisitCount()==before+1,'Entry callback executes')
   check(probe.ReturnCount()==completed+1,'Exit callback executes')
"""
    harness.SIM_CHECK=harness.SIM_CHECK.replace("   LOG('RSC_SIM_RUNTIME_PASS')",checks+"   LOG('RSC_SIM_RUNTIME_PASS')")
    try:
        (fixture/'dlls').mkdir(parents=True)
        shutil.copy2(ROOT/'dist/NativePatches.dll',fixture/'dlls/NativePatches.dll')
        (fixture/'firedragonmod.json').write_text(json.dumps({
            'schemaVersion':1,'name':'NativeExample','version':1,'dlls':['dlls/NativePatches.dll']}))
        harness.main()
    finally:
        # Only this test-created folder, after the harness closes its own process.
        if fixture.exists():
            assert fixture.resolve().parent==mods
            shutil.rmtree(fixture)

if __name__=='__main__': main()
