"""Test installation ownership and rollback boundaries in an isolated fake FAF tree."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix='FireDragon-installer-') as temporary:
        base = Path(temporary).resolve()
        faf, mods, local = base/'FAF', base/'mods', base/'local'
        mods.mkdir(); local.mkdir()
        managed = []
        for relative in ['bin/ForgedAlliance.exe', 'replaydata/bin/ForgedAlliance.exe', 'bin/init.lua', 'gamedata/effects.nx2']:
            path = faf/relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'original managed fixture: '+relative.encode())
            managed.append(path)
        original = {p: hashlib.sha256(p.read_bytes()).digest() for p in managed}
        env = dict(os.environ, LOCALAPPDATA=str(local))
        powershell = Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe'

        def run(script=ROOT/'install.ps1', uninstall=False, succeeds=True):
            command = [str(powershell), '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                       '-FafDirectory', str(faf), '-ModsDirectory', str(mods)]
            if uninstall:
                command.append('-Uninstall')
            result = subprocess.run(command, env=env, capture_output=True, timeout=30, creationflags=subprocess.CREATE_NO_WINDOW)
            assert (result.returncode == 0) == succeeds, result.stdout.decode(errors='replace')+result.stderr.decode(errors='replace')
            assert all(hashlib.sha256(p.read_bytes()).digest() == h for p,h in original.items()), 'Managed fixture changed'
            return result

        # Existing third-party proxies must be rejected before installing anything.
        conflict = faf/'bin/dsound.dll'; conflict.write_bytes(b'third-party proxy')
        run(succeeds=False)
        assert conflict.read_bytes() == b'third-party proxy'
        assert not (mods/'FireDragonModLoader/mod_info.lua').exists()
        conflict.unlink()
        print('PASS: installer refuses another proxy without partial installation', flush=True)

        run()
        installed = mods/'FireDragonModLoader'
        receipt_path = local/'FireDragonModLoader/installation.json'
        receipt = json.loads(receipt_path.read_text(encoding='utf-8-sig'))
        assert (installed/'bin/FireDragonLoader.dll').is_file()
        assert (installed/'lua/FireDragon/UI.lua').is_file(), 'Normal mod must ship shared Lua library'
        assert 'ui_only = false' in (installed/'mod_info.lua').read_text()
        assert (faf/'bin/dsound.dll').is_file() and (faf/'replaydata/bin/dsound.dll').is_file()
        assert str(installed/'bin/FireDragonLoader.dll') in (faf/'bin/FireDragonLoader.ini').read_text(encoding='utf-16')
        assert not any('Fixture' in f['Path'] or 'loader-test.exe' in f['Path'] for f in receipt['Files'])
        print('PASS: Windows PowerShell installer installs independent mod/core and both bootstraps', flush=True)

        run(script=installed/'install.ps1')
        print('PASS: installed release can reinstall itself', flush=True)
        documentation = installed/'README.md'
        saved = documentation.read_bytes()
        documentation.write_bytes(saved+b'\nuser change\n')
        run(succeeds=False)
        run(uninstall=True, succeeds=False)
        assert (faf/'bin/dsound.dll').exists()
        documentation.write_bytes(saved)
        print('PASS: modified owned files block overwrite and uninstall before mutation', flush=True)

        extra = installed/'user-notes.txt'; extra.write_text('keep this')
        run(uninstall=True)
        assert extra.read_text() == 'keep this'
        assert not receipt_path.exists()
        assert all(not Path(f['Path']).exists() for f in receipt['Files'])
        print('PASS: uninstall removes only owned files and preserves every managed hash', flush=True)


if __name__ == '__main__':
    main()
