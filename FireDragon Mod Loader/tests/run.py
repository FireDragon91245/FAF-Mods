"""Independent native loader tests. Only reads the managed game archive."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SURFACE = 'FireDragonTestSurface'
IMPACT = 'FireDragonTestImpact'
SHADER = b'''
float4 FDTestVS(float4 p:POSITION):POSITION { return p; }
float4 FDTestPS():COLOR0 { return float4(0.1,0.3,0.9,0.4); }
technique FireDragonTestSurface { pass P { VertexShader=compile vs_2_0 FDTestVS(); PixelShader=compile ps_2_0 FDTestPS(); } }
technique FireDragonTestImpact { pass P { VertexShader=compile vs_2_0 FDTestVS(); PixelShader=compile ps_2_0 FDTestPS(); } }
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--consumer', type=Path)
    args = parser.parse_args()
    before = hashlib.sha256(args.archive.read_bytes()).digest()
    with zipfile.ZipFile(args.archive) as archive:
        mesh = archive.read('effects/d3d9states.compat') + b'\n' + archive.read('effects/mesh.fx')
    with tempfile.TemporaryDirectory(prefix='FireDragon-loader-test-') as temp:
        base = Path(temp)
        shutil.copy2(ROOT/'dist/dsound.dll', base/'dsound.dll')
        core = base/'FireDragonLoader.dll'
        shutil.copy2(ROOT/'dist/FireDragonLoader.dll', core)
        # A different EXE name ensures no fixed filename/offset dependency.
        shutil.copy2(ROOT/'dist/loader-test.exe', base/'renamed-proof.exe')
        mods = base/'mods'; mods.mkdir()
        config = base/'FireDragonLoader.ini'
        config.write_text(f'[Loader]\nModsDirectory={mods}\nLoaderPath={core}\n', encoding='utf-16')
        source = base/'mesh.fx'; source.write_bytes(mesh)
        manifest = {'name': 'Fixture', 'dlls': [], 'shaders': {SURFACE: 'shaders/test.fx', IMPACT: 'shaders/test.fx'}}

        def put(name, definition=None, shader=SHADER, plugins=False, dependency=True):
            folder = mods/name
            folder.mkdir()
            (folder/'shaders').mkdir()
            (folder/'firedragonmod.json').write_text(json.dumps(manifest if definition is None else definition), encoding='utf-8')
            (folder/'shaders/test.fx').write_bytes(shader)
            if plugins:
                (folder/'dlls').mkdir()
                for dll in ['EngineHooks.dll', 'Failing.dll'] + (['FixtureDependency.dll'] if dependency else []):
                    shutil.copy2(ROOT/'dist'/dll, folder/'dlls'/dll)
            return folder

        def run(label, expected=(), absent=(), required=(), once=()):
            process = subprocess.Popen([str(base/'renamed-proof.exe'), str(source),
                                        *('+'+t for t in expected), *('-'+t for t in absent)],
                                       cwd=base, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            try:
                stdout, _ = process.communicate(timeout=55)
            except subprocess.TimeoutExpired:
                process.kill(); process.communicate()
                raise AssertionError(f'{label}: process stalled (possible initialization deadlock)')
            output = stdout.decode(errors='replace')
            log_path = Path(os.environ['LOCALAPPDATA'])/'FireDragonModLoader'/f'loader-{process.pid}.log'
            log = log_path.read_text() if log_path.exists() else ''
            if process.returncode or any(s not in log for s in required) or any(log.count(s) != 1 for s in once):
                raise AssertionError(f'{label}\n{output}\n{log}')
            print(f'PASS: {label}', flush=True)
            return log

        run('empty install preserves stock effect', absent=[SURFACE], required=['BOOTSTRAP hooks compiler=yes effect=yes', 'BOOT FireDragonLoader', 'READY mods=0'])
        valid = put('A_Fixture')
        run('JSON shaders load through separate core; shared file is appended once', [SURFACE, IMPACT], required=['SHADER_ACCEPT Fixture files=1', 'AVAILABLE '+SURFACE])
        duplicate = put('B_Duplicate')
        run('duplicate mod name is rejected', [SURFACE, IMPACT], required=['REJECT B_Duplicate: duplicate mod name'])
        shutil.rmtree(duplicate)
        duplicate = put('B_DuplicateTechnique', {**manifest, 'name':'AnotherMod'})
        run('duplicate techniques across mods are rejected', [SURFACE, IMPACT], required=['duplicate shader technique'])
        shutil.rmtree(duplicate)
        bad = put('B_Broken', {'name':'Broken', 'shaders':{'BrokenTechnique':'shaders/test.fx'}}, shader=b'this is not valid HLSL!!!')
        run('broken mod cannot remove another mod or stock shaders', [SURFACE, IMPACT], ['BrokenTechnique'], required=['SHADER_REJECT Broken', 'SHADER_ACCEPT Fixture'])
        shutil.rmtree(bad)
        shutil.rmtree(valid)
        bad = put('Broken', shader=b'this is not valid HLSL!!!')
        run('invalid shader retains complete original mesh effect', absent=[SURFACE], required=['SHADER_REJECT Fixture', 'MISSING '+SURFACE])
        shutil.rmtree(bad)
        undeclared = put('Undeclared', {'shaders':{'DoesNotExist':'shaders/test.fx'}})
        run('declared shader names must exist in compiled effect', absent=[SURFACE], required=['SHADER_ERROR missing declared technique DoesNotExist', 'SHADER_REJECT Undeclared'])
        shutil.rmtree(undeclared)

        (mods/'outside.fx').write_bytes(SHADER)
        for label, definition, error in [
            ('relative path escape', {'shaders':{SURFACE:'../outside.fx'}}, 'resource escapes mod directory'),
            ('absolute path', {'shaders':{SURFACE:str(mods/'outside.fx')}}, 'invalid resource path'),
            ('unsupported version', {'schemaVersion':2}, 'unsupported schemaVersion'),
            ('wrong DLL list type', {'dlls':'not an array'}, 'dlls must be an array'),
            ('unknown field', {'shader':{}}, 'unknown manifest field'),
        ]:
            folder = put('Rejected', definition)
            run(label, absent=[SURFACE], required=['REJECT Rejected', error, 'READY mods=0'])
            shutil.rmtree(folder)
        for label, text, error in [('malformed JSON', '{"dlls":', 'parse_error'),
                                    ('duplicate JSON keys', '{"dlls":[],"dlls":[]}', 'duplicate JSON key')]:
            folder = put('Rejected', {})
            (folder/'firedragonmod.json').write_text(text)
            run(label, required=['REJECT Rejected', error])
            shutil.rmtree(folder)

        plugin = put('Fixture', {'dlls':['dlls/EngineHooks.dll']}, plugins=True)
        run('native DLL exact FDEntry name, context, private dependency and reentry',
            required=['fixture entry called once; dependency, context and reentrant D3DX call passed'], once=['DLL_ENTRY FDEntryFixtureEngineHooks result=0'])
        shutil.rmtree(plugin)
        plugin = put('Fixture', {'dlls':['dlls/Failing.dll','dlls/EngineHooks.dll']}, plugins=True)
        log = run('failed DLL entry does not prevent the next component', required=['DLL_ERROR FDEntryFixtureFailing result=1', 'DLL_ENTRY FDEntryFixtureEngineHooks result=0'])
        assert log.index('FDEntryFixtureFailing result=1') < log.index('FDEntryFixtureEngineHooks result=0')
        shutil.rmtree(plugin)
        plugin = put('WrongName', {'dlls':['dlls/EngineHooks.dll']}, plugins=True)
        run('missing exact unmangled export is reported', required=['DLL_ERROR missing exact export FDEntryWrongNameEngineHooks'])
        shutil.rmtree(plugin)
        plugin = put('Fixture', {'dlls':['dlls/EngineHooks.dll']}, plugins=True, dependency=False)
        run('missing private dependency is reported without breaking the game', required=['DLL_ERROR FDEntryFixtureEngineHooks LoadLibraryEx'])
        shutil.rmtree(plugin)
        plugin = put('Fixture', {'dlls':['dlls/EngineHooks.dll']}, plugins=True)
        (plugin/'dlls/EngineHooks.dll').write_bytes(b'not a native PE DLL')
        run('non-x86 DLL is rejected before loading', required=['DLL_REJECT FDEntryFixtureEngineHooks expected an x86 PE DLL'])
        shutil.rmtree(plugin)
        core.rename(base/'temporarily-absent.dll')
        run('missing independent loader core preserves original shader calls', absent=[SURFACE], required=['ERROR cannot load FireDragonLoader.dll'])
        (base/'temporarily-absent.dll').rename(core)

        if args.consumer:
            consumer = mods/args.consumer.resolve().name
            shutil.copytree(args.consumer, consumer)
            definition = json.loads((consumer/'firedragonmod.json').read_text())
            expected = list(definition.get('shaders', {}))
            run('consumer manifest: '+consumer.name, expected, required=['AVAILABLE '+t for t in expected])
    assert hashlib.sha256(args.archive.read_bytes()).digest() == before, 'Managed archive changed!'
    print('PASS: managed archive SHA-256 unchanged throughout all integration cases')


if __name__ == '__main__':
    main()
