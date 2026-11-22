# FireDragon: Repair Station Control

Army-specific assistance controls for Kennels, Hives, Kennel drones and commander
engineering pods. Requires **FireDragon: Core & Loader v27 or later**. Enable both
simulation mods in the host's lobby; every player needs them.

Version 16 uses the generated native engine classes and shared patch SDK. Its DLL
owns assistance policy, function signatures, injection selectors, register mappings
and continuations. Core supplies shared game bindings and generic patch scanning,
assembly, instruction relocation and installation.
Categories are queried through the engine API, so Lua no longer registers type
flags for every target. Only managed workers' boolean restrictions cross the
Lua bridge. The original FAF targeting order and task handling remain intact.
The initial shared adapter is verified against FAF 3841.

Select one or more of your engineering drones or repair stations, at any level,
to open the window automatically. Mixed selections containing these units also
work. Selecting only other units or clearing the selection closes it. There is
no keyboard shortcut. Closing the window keeps it hidden until you change the
selected drones/stations.
Move and resize the window as desired. Its geometry persists through the core UI
library, just like FireDragon: Modular Shields.

- **Dont help Team**: excludes other armies' construction and assistance targets,
  including allied factories and engineers. Repairing damaged, completed allied
  units remains eligible. Your own army remains eligible.
- **Dont help Nukes**: excludes nuclear and anti-nuclear silos from target
  selection, including damaged and unfinished silos. Uncheck it to assist them.

Both start unchecked each match. Each army controls only its own values; allies
and opponents cannot edit them. Changes affect existing and future units,
including captured/transferred stations, which use their current owner's values.
Move, reclaim, pause, upgrades and ordinary engineers retain their normal behavior.
Assistance orders to excluded targets are released even if explicitly ordered;
uncheck the relevant setting when you want an exception. While a restriction is
active, native automatic targeting continues to run. The policy rejects excluded
candidates before selection, including a factory/engineer's resolved work target.
Settings changes immediately stop excluded existing work. The normal drone
automation buttons continue to control the engine's actual auto mode.

Compatible with FireDragon: Modular Shields: its invisible aura construction workers are
excluded from management and assistance searches. Its automatic module guard
orders and claimed module assistants retain their work. Native acquisition
respects Kennel automation controls. The shield aura continues to use the
shield's own repair controls.

Communication, authoritative mirrors, optimistic checkbox bindings and window
storage use the shared core libraries. No separate networking or storage system
is installed. The package includes `dlls/TargetFilter.dll` and its resource
manifest. Core & Loader v27 supplies the required ABI v5 and native SDK.

Development: `./test.ps1`, then `./build.ps1 -Install`. Source ships from `src/`;
Lua tests live in `tests/`, and generated packages appear in `dist/`.
With the game closed, `python -B tests/ui_runtime.py` runs a disposable native FAF
UI check for the window, bindings, checkbox input and saved geometry. It mounts
temporary test files and closes only its own game process.
After installing the current package, `python -B tests/sim_runtime.py` runs a
disposable FAF skirmish. It checks an already assisting Kennel drone and Hive,
enables the restriction, verifies one stop with no reacquisition, confirms that
the drone repairs an allowed target, and checks restoration of native automation.
`python -B tests/work_runtime.py` exercises factory assembly, factory/station/mex
upgrades, construction and damaged-building repair on Kennel drones and Hives,
with all four option combinations. `test.ps1` also runs the C++ predicate and
Lua policy/UI/module compatibility tests.

Native implementation: `native/AssistanceHooks.hpp` owns the FAF 3841 function
signatures, byte selectors, task/target register mappings and continuation
signatures. It defines the two stripped functions through Core's generic
`DefineSymbol` API and installs four `Filter` selectors. Each selector passes `IsAssistanceAllowed` directly through Core's `CallWith`
API. Register declarations and a generated `CCommandTask::Unit` field projection
supply its two typed arguments. Core has no assistance-specific
symbols or injection sites.

`native/TargetFilter.cpp` contains the policy, state and Lua bindings.
`MeetsRestrictions` evaluates assistance rules without changing filter state.
`IsAssistanceAllowed` coordinates session synchronization, settings lookup and
diagnostics under one lock. Core's typed adapter prepares the arguments and applies the declared false-result
continuation when work is excluded.
Hook selection and register declarations belong to this consumer; executable
memory allocation, assembly and patch installation remain in Core. Core's
`NATIVE_SDK.md` documents the verified engine adapter and injection framework. Build with an x86 MinGW-w64 compiler supporting C++26
(tested with GCC 15.2.0); `std::optional` tracks the active simulation.
`FD_CXX` overrides the default compiler path.
Multiplayer behavior still needs in-game testing.
