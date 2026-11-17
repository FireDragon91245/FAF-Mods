The loader also installs as a normal FAF core mod. Enable **FireDragon Mod Loader** alongside FireDragon mods. Its standalone shared UI library provides windows, tabs, clipping, scrolling, layouts, controls, live bindings and image effects. See [UI library API](src/UI_LIBRARY.md) (installed package: `UI_LIBRARY.md`).

# FireDragon Mod Loader

Independent native resource loader for Supreme Commander: Forged Alliance / FAF.
`FireDragonLoader.dll` scans installed mod folders for `firedragonmod.json`, loads
their shader techniques, initializes their native DLL components and publishes
the shared Lua bridge. It contains
no Modular Shields integration code; that mod is an ordinary manifest consumer.

## Installation

Close the game, extract `FireDragonModLoader-v6.zip`, and run `install.cmd`.
The installer detects the FAF vault from the client's `fa_path.lua`. Nonstandard
paths can be supplied to `install.ps1 -FafDirectory <path> -ModsDirectory <path>`.
No game launch arguments, executable decorator or runtime compiler is required.

Installed layout:

```text
mods/FireDragonModLoader/
    mod_info.lua
    bin/FireDragonLoader.dll     native loader core
    bootstrap/dsound.dll         bootstrap copy for installation
    sdk/FireDragonLoader.h       public C ABI
    examples/                   manifest and plugin examples
    install.ps1, install.cmd, uninstall.cmd
FAForever/bin/
    dsound.dll                  small bootstrap proxy
    FireDragonLoader.ini        generated paths to the core and mod vault
```

The current replay binary directory gets the same bootstrap/config. The core is
loaded from the separate FireDragonModLoader mod folder. Native loading occurs
before Lua mod activation; the mod-manager checkbox does not enable/disable the
native core. Use the installer/uninstaller for native installation state.

Installation never overwrites managed executables, archives or init scripts.
It refuses to overwrite unowned/modified files, checks original managed hashes,
and records ownership in `%LOCALAPPDATA%/FireDragonModLoader/installation.json`.
An existing 0.1 FireDragon installation is upgraded using that receipt.
`uninstall.cmd` removes only owned files whose hashes still match. Disable mods
that require native resources before playing without the loader.

## Manifest

Place this file at the root of each unpacked mod folder:

```json
{
  "schemaVersion": 1,
  "name": "ModularShields",
  "version": 19,
  "dlls": ["dlls/EngineHooks.dll"],
  "shaders": {
    "ModularHexDome": "shaders/UEFT4Hex.fx",
    "ModularHexHitBlue": "shaders/UEFT4Hex.fx"
  }
}
```

`dlls` and `shaders` are independently optional. The minimum manifest is the
user-facing `{ "dlls": [], "shaders": {} }` shape. `schemaVersion` defaults to 1.
`version` defaults to 1 and is an integer in 1..16777215, exactly representable by
the game's float-number Lua runtime. It is the version reported to Lua; keep it in
sync with your mod release.
`name` defaults to the folder name with characters outside ASCII letters, digits
and underscores removed: `Modular Shields` becomes `ModularShields`. An explicit
`name` must already be a valid C identifier, with its case preserved.

Shader keys are exact HLSL **technique names**, usable as a mesh blueprint's
`ShaderName`. Values are UTF-8 paths relative to the owning mod. Multiple technique
names can share a file; its source is appended once. Multiple files per mod are
supported. Files are mesh-effect HLSL fragments and can use stock mesh helpers and
globals. They are not standalone shader-model bytecode or new render passes.

The loader scans immediate installed-mod folders in sorted order. Within a mod,
shader keys are sorted and DLLs retain their JSON array order. Names and techniques
must be unique across accepted mods. A malformed manifest is rejected as a unit;
other valid mods continue loading. Duplicate JSON keys, unknown fields, unsupported
versions, resource paths outside the owning mod, NUL-containing source, excessive
nesting and oversized manifests/sources are rejected. See
`sdk/firedragonmod.schema.json` for the machine-readable schema.

## DLL entry contract

Each declared DLL must be **x86**, with an exact, case-sensitive, unmangled export:

```text
FDEntry{ModName}{DllFileStem}
```

For `Modular Shields/dlls/EngineHooks.dll`, that is:
`FDEntryModularShieldsEngineHooks`. Folder-derived mod names and DLL stems are
normalized by removing punctuation/spaces; ambiguous duplicate DLL symbols are
rejected. Use the installed SDK header to get the export and calling convention:

```cpp
#include "FireDragonLoader.h"

FD_MOD_ENTRY(ModularShields, EngineHooks) {
    if (!context || context->apiVersion != FD_API_VERSION)
        return FD_FAILURE;
    context->log(FD_LOG_INFO, "EngineHooks initialized");
    return FD_SUCCESS;
}
```

This expands to an `extern "C"` exported `int __cdecl` function receiving
`const FDModContext*`. Success is **0**, failure is nonzero. The context supplies
its byte size, ABI version, stable mod name, absolute UTF-16 mod directory and a
logging callback and the centrally managed `lua` registration service. SDK ABI v2
adds that service; rebuild native components against the v2 header and check
`context->apiVersion`/`structSize`. The context and its borrowed pointers remain valid for the
process lifetime. Do not pass C++ objects, allocator ownership or exceptions across
this ABI. Build plugins with a static runtime or ship their own dependencies.

Initialization runs once per declared DLL, on the first D3DX resource call, outside
Windows' loader lock. Put initialization in this function and keep plugin `DllMain`
minimal. Same-thread reentrant D3DX calls are supported; entry callbacks must not
wait on another thread that is itself waiting for loader initialization. Native
components share the game process and must return normally; an access violation
inside a plugin is not isolated from the game.

DLLs are loaded by absolute path with their own directory included for private
dependencies. Dependency basenames should be unique across unrelated mods because
Windows shares loaded dependency modules. Missing exports, architecture errors,
missing dependencies and failed entry returns are logged; subsequent components
still initialize. Loaded components are retained until process exit, including
ones whose entry failed, because their code may already have registered callbacks.
There is no live unload/reload contract.

## Lua API

The loader publishes these native functions in each executing Lua runtime,
including User/UI and Sim. New/recreated states receive the same registrations:

```lua
FireDragonLoader.IsPresent()   -- boolean true; table is absent without the bridge
FireDragonLoader.Version()     -- integer-valued Lua number, currently 2
FireDragonLoader.LoadedMods()  -- array of {name, version, dlls, shaders}
FireDragonLoader.Logs()        -- array of {level, msg}
FireDragonLoader.Mods          -- plugin-owned namespaces
```

`LoadedMods()` returns only mods for which **every** declared DLL entry succeeded
and **every** declared shader technique compiled and validated on the actual D3D9
device. Pending, rejected and partly failed mods are excluded. `dlls` contains
relative DLL paths; `shaders` contains technique names. Empty manifests have no
resource requirements and are ready. Manifest presence alone never reports a
shader as loaded. Results are newly allocated Lua tables; editing them does not
change the native registry.

`Logs()` returns the most recent 512 core/plugin records, oldest first, with
`level` equal to `info`, `warning` or `error` and a UTF-8 `msg`. Records are bounded
to 16000 bytes each. These are snapshots of loader diagnostics, not the game's
entire log. The bootstrap's earlier file diagnostics remain in the disk log.

Example readiness check in an ordinary Lua module:

```lua
local function NativeResourcesReady()
    local loader = rawget(_G, 'FireDragonLoader')
    if not loader or not loader.IsPresent() then return false end
    for _, mod in ipairs(loader.LoadedMods()) do
        if mod.name == 'ModularShields' and mod.version >= 19 then return true end
    end
    return false
end
```

The bridge is present before resource scanning finishes, so presence/version do
not imply readiness. `Mods.<name>` may exist before the mod's resources are ready
and is not a readiness flag. The API does not automatically disable consumer
mods. `mod_info.lua` has an isolated execution environment and does not inherit
ordinary globals; an activation gate there needs explicit integration. Local
readiness must not select different synchronized gameplay on different clients;
reject incompatible multiplayer startup through a shared preflight protocol.

## Registering plugin functions, tables and values

During `FDEntry`, a component registers paths relative to its own namespace:

```cpp
int FD_CALL Answer(const FDLuaStack* lua, FDLuaCall* call, void*) {
    lua->pushNumber(call, 42);
    return 1; // number of pushed Lua results
}

FD_MOD_ENTRY(ModularShields, EngineHooks) {
    if (!context || context->apiVersion != FD_API_VERSION || !context->lua)
        return FD_FAILURE;
    const auto* lua = context->lua;
    if (lua->createTable(context, "Config") != FD_SUCCESS ||
        lua->setJson(context, "Config.Values", "{\"enabled\":true,\"power\":3.5}") != FD_SUCCESS ||
        lua->registerFunction(context, "Answer", Answer, nullptr) != FD_SUCCESS)
        return FD_FAILURE;
    return FD_SUCCESS;
}
```

Lua then sees `FireDragonLoader.Mods.ModularShields.Answer()` and
`FireDragonLoader.Mods.ModularShields.Config.Values.power`. `setJson` accepts
strings, numbers, booleans, null, arrays and nested objects. `createTable` is
idempotent for existing tables. Paths contain 1..16 ASCII identifier segments.
Registration cannot overwrite an existing value, cross a scalar as if it were a
table, write another mod's namespace or replace the loader's own API.

Registrations are staged for the owning FDEntry call and committed only if it
returns success. Failed/thrown entries discard their staged bindings. Registrations
outside that entry call are rejected. Values are copied and native function
callbacks are retained centrally for the process lifetime. The component retains
ownership of its callback userdata. The loader applies committed registrations
to existing states on their next engine Lua call and to new states before script
execution. Existing root/namespace table references remain stable.

Callbacks use `FDLuaStack`: inspect argument count/types, read boolean/number/string
arguments, and push nil/boolean/number/string/JSON results. They receive an opaque
call token, never a raw engine `lua_State`. Return the pushed result count, up to
64, or a negative value for failure. Invalid results and C++ exceptions produce
`nil, errorMessage` plus a log record. Access violations are not isolated. JSON
values are limited to 64 KiB and depth 24. Lua numbers use the host's float
precision. Function bindings use stable integer upvalues rather than native
addresses in Lua values. Callbacks execute on the calling Lua thread; marshal
background work yourself and do not retain the borrowed call/argument pointers.

## Bootstrap and shaders

The default `dsound.dll` proxy forwards Windows' sound API and installs named
import dispatchers for D3DX and the main executable's normal `GetCommandLineA`
startup call. It contains no manifest parser, shader logic or mod DLL manager.
On that early executable call, it loads `FireDragonLoader.dll` by its
configured absolute path and obtains `FDInitializeV1`. Core loading, JSON scanning
and plugin entry calls all occur outside `DllMain`. A missing/incompatible core
leaves the original shader calls working.

The Lua bridge verifies the main executable's SHA-256 against the supported FAF
3841 image before resolving any internal Lua addresses. MinHook redirects the
engine's protected/unprotected Lua call entry points in memory. Bindings are
installed on the thread executing Lua, before the original call runs; the loader
does not touch a Lua state from a background/render callback. Unknown executable
fingerprints leave Lua untouched and report `LUA_UNSUPPORTED`. No second Lua
runtime is loaded into the game. Shader calls remain a bootstrap fallback.

The core recognizes the engine's mesh-effect source and appends mod fragments in
memory. Each mod's complete effect is validated in turn, retaining previously
accepted mods if a later mod fails. Declared techniques must exist in the compiled
effect. The original engine macros, includes and compiler flags are retained.
The engine registers techniques normally and Lua/mesh blueprints reference them
through the normal mod asset paths. Shader failures retain stock/accepted effects;
consumer mods still require their custom techniques to render correctly.

Logs: `%LOCALAPPDATA%/FireDragonModLoader/loader-<process id>.log`. Useful entries
include `BOOTSTRAP`, `MOD`, `DLL_ENTRY`, `DLL_ERROR`, `SHADER_ACCEPT`, `SHADER_REJECT`
and `AVAILABLE`. Runtime does not read any repository/source paths.

## Development

```powershell
./build.ps1                 # CMake build, native tests, mod bundle and ZIP
./build.ps1 -Install        # same, then install
./test.ps1                 # rebuild and run native tests
./build.ps1 -SkipTests      # incremental build/package only
```

Requires Windows, CMake, Ninja, Python for the test runner, Lua/luac for mod metadata,
and 32-bit MinGW-w64 GCC with D3DX9 headers/import libraries. Supply `-Compiler` or
`FD_CXX` for a nondefault toolchain. nlohmann/json 3.12.0 is vendored with its MIT
license and upstream-verified SHA-256. MinHook and the test-only FAF Lua source
are pinned in their vendored `UPSTREAM.json` files; no network access is needed to build.
Both runtime DLLs statically link their C++ runtime.

`native/src` contains the core/bootstrap, `native/include` the public SDK, `src`
the FAF mod metadata, and `tests` native resource contracts, real plugin/dependency
DLL fixtures and a real D3DX/D3D9 integration harness. The tests exercise actual
Windows automatic proxy loading, the separate core, valid/invalid JSON and HLSL,
per-mod failure isolation, GPU-valid techniques, DLL export lookup, call counts,
context, private dependencies, initialization failures and reentry. A separate
float-number Lua VM tests the built-ins, callback facade, values/tables, scoped
registration, failed-entry rollback, stable table references and recreated states.
That VM is linked only into `lua-test.exe`, never the production DLL. Managed game
archives are read only. Test DLLs/executables are excluded from release packages.

Modular Shields' build/test scripts also build/test these C++ targets and pass its
own manifest to the generic consumer test. The loader's standalone tests do not
depend on Modular Shields or any of its shaders.

Optional actual-engine probes (close other game processes first):

```powershell
python -B tests/game_smoke.py --mods <installed-mods-directory>
python -B tests/game_smoke.py --mods <installed-mods-directory> --replay <test.scfareplay>
```

These create temporary native fixtures and a disposable Lua script overlay for
the test process. They assert the API in real User/UI and Sim states, including
successful shader/DLL readiness and exclusion of failed components. Test-only
`/init` and `/log` instrumentation is not part of normal installation. Fixtures
are removed afterwards; managed file hashes are checked. Results are retained
under `artifacts/lua-smoke`. Real FAF UI and Sim startup probes passed on this host.

## Compatibility boundary

The tested Lua host is the fingerprinted Windows FAF 3841 executable. A new game
binary needs a verified address profile before the Lua bridge enables itself.
Current FAF clears its effect cache
at startup; launchers/versions retaining cached effects need a separate cache-key
strategy. Only mesh-effect techniques are currently extended. Manifests are read
from **all installed unpacked mods**, including disabled ones, before active Lua
mods are known. Packed mods, native dependency graphs, multiplayer/replay resource
negotiation and coexistence with other proxy loaders are not implemented. Another
proxy at the same filename is never overwritten. An updater removing the added
bootstrap requires reinstalling it. These limits do not require editing managed
game files or changing game launch arguments. UI/Sim startup and VM recreation
are tested; multiplayer determinism and savegame serialization of arbitrary
native plugin bindings are not certified by these tests.
