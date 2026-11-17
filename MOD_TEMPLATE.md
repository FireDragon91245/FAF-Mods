# FAF mod project template

Every mod in this repository is a self-contained project folder with the same layout,
scripts and conventions. Copy this structure when starting a new mod.

## Layout

```
FAF Mods/
├── MOD_TEMPLATE.md              this file
└── <Project Name>/              human-readable project folder (spaces allowed)
    ├── README.md                player-facing docs; bundled into the mod
    ├── build.ps1                test + bundle (+ optional install)
    ├── test.ps1                 Lua tests + syntax checks + import-path lint
    ├── .gitignore               dist/ and artifacts/
    ├── src/                     exactly what ships in the mod folder
    │   ├── mod_info.lua
    │   ├── hook/lua/...         appended to the matching vanilla /lua/... files
    │   └── lua/<ModFolder>/...  the mod's own modules
    ├── tests/                   plain Lua 5.4 test scripts, one suite per file
    ├── scripts/                 (optional) generators for artifacts, e.g. textures
    ├── docs/                    (optional) design notes, playtest checklists
    ├── artifacts/               (generated, ignored) outputs of scripts/
    └── dist/                    (generated, ignored) bundled mod + zip
```

Reference implementation: `Modular Shields/` (it adds generated icon artifacts and docs).

## Naming

| Thing | Rule | Example |
|---|---|---|
| Project folder | Readable, spaces allowed | `FireDragon Debug Tools` |
| In-game mod folder (`<ModFolder>`) | No spaces or punctuation; it is the import root | `FireDragonDebugTools` |
| Display name | `name` in `mod_info.lua`, anything goes | `FireDragon Debug Tools` |
| Own modules | `src/lua/<ModFolder>/...` | `src/lua/FireDragonDebugTools/Economy.lua` |

FAF loads mod files through `/mods/<ModFolder>/...`. If the installed folder name and the
import paths disagree, the mod silently breaks, so `test.ps1` rejects any `/mods/<X>/`
reference where `X` is neither `<ModFolder>` nor the shared core `FireDragonModLoader`.

## src/mod_info.lua

```lua
name = 'Display Name'
uid = '<new GUID>'          -- [guid]::NewGuid(); never reuse a uid across mods
version = 1                 -- integer; bump for every installed/released change
description = 'One sentence shown in the mod manager.'
author = 'Rick'
selectable = true
enabled = true
exclusive = false
ui_only = false             -- true only when the mod has no sim hooks
requires = { '3f98ee06-c20c-4fd6-a29e-d7e306fd2026' }
requiresNames = { ['3f98ee06-c20c-4fd6-a29e-d7e306fd2026'] = 'FireDragon Mod Loader' }
conflicts = {}
before = {}
after = { '3f98ee06-c20c-4fd6-a29e-d7e306fd2026' }
```

Sim mods (`ui_only = false`) must be enabled by the host and are synced to every player.

New FireDragon mods depend on the normal **FireDragon Mod Loader v4** core mod.
Use `import('/mods/FireDragonModLoader/lua/FireDragon/UI.lua').Export` for shared UI.
See [the UI API](FireDragon%20Mod%20Loader/src/UI_LIBRARY.md).

## Hooks

- A file at `src/hook/lua/<path>.lua` is appended to vanilla `/lua/<path>.lua`.
- Wrap instead of replace, and always call the previous implementation:

  ```lua
  local PreviousDoCallback = DoCallback
  function DoCallback(name, data, units)
      if name == 'MyModAction' then ... return end
      return PreviousDoCallback(name, data, units)
  end
  ```

- Class hooks subclass the existing class and assign it back:
  `local Previous = Unit; Unit = ClassUnit(Previous) { ... Previous.Method(self, ...) ... }`.
- Keep hooks thin. Put the logic in `src/lua/<ModFolder>/` modules so tests can load them without the engine.

## Lua dialect

FAF runs a Lua 5.0 derivative: no `#` (use `table.getn`), no `%` (use `math.mod`), no
`goto`, and varargs use `arg`. The tests run on Lua 5.4, so production code should use
the common subset (`pairs`, `ipairs`, `table.getn`), and tests shim the gaps
(`table.getn = table.getn or function(t) return #t end`).

## Tests (`tests/*.lua`, `test.ps1`)

- Each test file is a standalone script run from the project root (`lua tests/<name>.lua`).
  It exits non-zero on the first failed `assert`.
- Load modules with `loadfile('src/lua/<ModFolder>/X.lua', 't', env)` into an `env`
  table whose `__index` is `_G`. Then mock engine globals (`ForkThread`, `WaitTicks`,
  `ArmyBrains`, `import`, ...) in `env`.
- `tests/run.lua` (if present) runs first; the others run alphabetically.
- `test.ps1`:
  1. runs every suite (`-Filter <wildcard>` to narrow);
  2. `luac -p` every `.lua`/`.bp` in `src/`;
  3. lints `/mods/<X>/` paths in `src/` against `-ModFolder`.
- Requires `lua` and `luac` (5.4) on PATH.

## Build (`build.ps1`)

```powershell
./build.ps1              # test, then bundle to dist/
./build.ps1 -SkipTests   # bundle only
./build.ps1 -Install     # bundle and mirror into the FAF mods folder
```

1. If the project has `scripts/` generators, it runs them when `artifacts/` is missing (or with `-Regenerate`).
2. It runs `test.ps1` unless `-SkipTests` is given.
3. It copies `src/*` and `README.md` (plus any generated artifacts) into `dist/<ModFolder>/`.
4. It writes `dist/<ModFolder>-v<version>.zip`, with the version read from `mod_info.lua`.
5. With `-Install`, it runs `robocopy /MIR` into `Documents\My Games\Gas Powered Games\Supreme Commander Forged Alliance\mods\<ModFolder>`. Override the target with `-ModsDir`.

## README.md

Player-facing and bundled with the mod. Cover:

1. What the mod does and why (one paragraph).
2. How to use it (keybinds, UI, lobby requirements such as cheats).
3. Compatibility and known limitations.
4. Development: `./test.ps1`, `./build.ps1 -Install`, and the project layout.

## Release checklist

1. Bump `version` in `src/mod_info.lua`.
2. `./build.ps1 -Install` and play-test in game (F9 log for errors).
3. Commit with a `<Project>: vN <summary>` style message.

## New project quick start

```powershell
$project = 'My New Mod'; $folder = 'MyNewMod'
New-Item -ItemType Directory "$project/src/lua/$folder", "$project/tests" | Out-Null
Copy-Item 'Insta Build Render My Units/build.ps1', 'Insta Build Render My Units/test.ps1', 'Insta Build Render My Units/.gitignore' $project
# edit $ModFolder in build.ps1 and test.ps1, write src/mod_info.lua with a new uid, README.md, tests/run.lua
```
