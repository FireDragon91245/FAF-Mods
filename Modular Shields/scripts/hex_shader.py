"""Generate assets and validate HLSL, reading FAF's archive without modifying it.

Runtime loading is handled exclusively by the native FireDragon Mod Loader.
"""
from pathlib import Path
import argparse
import ctypes as C
import hashlib
import json
import math
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BEGIN = b'\n// BEGIN MODULAR_SHIELDS_UEF_T4_HEX\n'
END = b'\n// END MODULAR_SHIELDS_UEF_T4_HEX\n'
MEMBER = 'effects/mesh.fx'
MARKER = 'effects/modular_shields_hex_v1.marker'


def clean(data):
    if BEGIN not in data:
        return data
    if data.count(BEGIN) != 1 or data.count(END) != 1:
        raise RuntimeError('Ambiguous shader patch markers; archive left unchanged')
    start = data.index(BEGIN)
    end = data.index(END, start) + len(END)
    return data[:start] + data[end:]


def compile_shaders(data):
    """Use the Windows D3D9 compiler on the real production VS/PS functions."""
    compiler = C.WinDLL('d3dcompiler_47.dll').D3DCompile
    compiler.argtypes = [C.c_void_p,C.c_size_t,C.c_char_p,C.c_void_p,C.c_void_p,
                         C.c_char_p,C.c_char_p,C.c_uint,C.c_uint,
                         C.POINTER(C.c_void_p),C.POINTER(C.c_void_p)]
    compiler.restype = C.c_long
    base = clean(data).split(b'\ntechnique ', 1)[0]
    fragment = (ROOT/'shaders/UEFT4Hex.fx').read_bytes().split(b'\ntechnique ', 1)[0]
    # The engine injects this compatibility macro before compiling on D3D9.
    source = b'#define CompatSwizzle(x)\n' + base + b'\n' + fragment
    source += b'\nfloat4 ModularHexHitCompile(MODULAR_HEX_VERTEX v):COLOR0 {return ModularHexHitPS(v,float3(0.055,0.42,1));}\n'

    def blob_bytes(blob):
        table = C.cast(blob,C.POINTER(C.POINTER(C.c_void_p))).contents
        ptr = C.WINFUNCTYPE(C.c_void_p,C.c_void_p)(table[3])(blob)
        size = C.WINFUNCTYPE(C.c_size_t,C.c_void_p)(table[4])(blob)
        return C.string_at(ptr,size)

    for entry, profile in [('ModularHexVS','vs_2_0'),('ModularHexDomePS','ps_2_0'),
                           ('ModularHexHitCompile','ps_2_0')]:
        code,error = C.c_void_p(),C.c_void_p()
        result = compiler(source,len(source),b'modular_hex.fx',None,None,
                          entry.encode(),profile.encode(),1<<15,0,
                          C.byref(code),C.byref(error))
        message = blob_bytes(error).decode(errors='replace') if error else ''
        try:
            if result < 0:
                raise RuntimeError(f'{entry} ({profile}) compilation failed:\n' + '\n'.join(x for x in message.splitlines() if 'error' in x))
            print(f'PASS: D3D9 {profile} {entry} ({len(blob_bytes(code))} bytes)')
        finally:
            for blob in [code,error]:
                if blob:
                    table = C.cast(blob,C.POINTER(C.POINTER(C.c_void_p))).contents
                    C.WINFUNCTYPE(C.c_ulong,C.c_void_p)(table[2])(blob)


def assets():
    out = ROOT/'src/effects/entities/UEFT4Hex'
    out.mkdir(parents=True,exist_ok=True)
    from hex_mesh import generate
    generate(out/'HexDome_lod0.scm')
    for name,shader in [('Dome','ModularHexDome'),('HitBlue','ModularHexHitBlue'),
                        ('HitYellow','ModularHexHitYellow'),('HitRed','ModularHexHitRed')]:
        (out/f'{name}_mesh.bp').write_text('''MeshBlueprint {
    LODs = {{
        MeshName = '/mods/ModularShields/effects/entities/UEFT4Hex/HexDome_lod0.scm',
        ShaderName = '%s',
        LODCutoff = 1000,
    }},
    SortOrder = %d,
    StraddleWater = true,
}
''' % (shader,1000 if name=='Dome' else 1001),encoding='utf-8')
    print('Generated geodesic dome and four mesh blueprints')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path,default=Path('C:/ProgramData/FAForever/gamedata/effects.nx2'))
    parser.add_argument('--assets',action='store_true')
    args = parser.parse_args()
    if args.assets:
        assets()
    with zipfile.ZipFile(args.archive) as z:
        original = z.read(MEMBER)
    base = clean(original)
    compile_shaders(base)
    patched = base + BEGIN + (ROOT/'shaders/UEFT4Hex.fx').read_bytes() + END
    out = ROOT/'dist/UEFT4HexShader'
    out.mkdir(parents=True,exist_ok=True)
    (out/'mesh.fx').write_bytes(patched)
    manifest = {'archive':str(args.archive),'base_sha256':hashlib.sha256(base).hexdigest(),
                'patched_sha256':hashlib.sha256(patched).hexdigest()}
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print('Shader package: '+str(out))


if __name__ == '__main__':
    main()
