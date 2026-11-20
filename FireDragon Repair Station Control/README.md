# FireDragon: Repair Station Control

Army-specific assistance controls for Kennels, Hives, Kennel drones and commander
engineering pods. Requires **FireDragon: Core & Loader v17 or later**. Enable both
simulation mods in the host's lobby; every player needs them.

Version 4 recognizes the Hive's native AssistCommander idle command, allowing
filtered automatic work to start instead of remaining queued behind that task.
Compatibility tests cover docked Kennels and Hives assisting FireDragon: Modular Shields
module installations with all restriction combinations.

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
active, the native automatic search is disabled on affected units. A single
filtered selector chooses only eligible targets before issuing work orders.
Settings changes immediately stop excluded existing work; the drone then picks
eligible work or stays idle. It never repeatedly starts and cancels the same
excluded target. Native scanning returns when both options are off. The usual
drone automation buttons retain their requested state through the shared sync.

Compatible with FireDragon: Modular Shields: its invisible aura construction workers are
excluded from management and assistance searches. Its automatic module guard
orders and claimed module assistants retain their work. The fallback search
respects Kennel automation being turned off, as the shield mod does. The shield
aura itself continues to use the shield's own repair controls.

Communication, authoritative mirrors, optimistic checkbox bindings and window
storage use the shared core libraries. No separate networking or storage system
is installed. No native loader changes are needed by this Lua-only consumer.

Development: `./test.ps1`, then `./build.ps1 -Install`. Source ships from `src/`;
Lua tests live in `tests/`, and generated packages appear in `dist/`.
With the game closed, `python -B tests/ui_runtime.py` runs a disposable native FAF
UI check for the window, bindings, checkbox input and saved geometry. It mounts
temporary test files and closes only its own game process.
After installing the current package, `python -B tests/sim_runtime.py` runs a
disposable FAF skirmish. It checks an already assisting Kennel drone and Hive,
enables the restriction, verifies one stop with no reacquisition, confirms that
the drone repairs an allowed target, and checks restoration of native automation.
The normal Lua suites also reproduce repeated native acquisition attempts and
exercise the shield mod's real dispatch/claim code and the standard drone UI.
Multiplayer behavior still needs in-game testing.
