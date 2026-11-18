Requires **FireDragon Mod Loader v17** installed and enabled as a normal FAF mod (shared core dependency).

# FireDragon Debug Tools

A small in-game debug panel for testing. The **Vanilla** tab has three toggles and a game-speed slider:

- **Infinite Energy**: your energy storage gets a +1,000,000 boost and is refilled every tick.
- **Infinite Mass**: the same for mass.
- **Instant Build (all armies)**: sets the engine's `ai_InstaBuild` boolean on or off for the whole match.
  The checkbox tracks menu requests; changes entered separately in the console are not detected.
  It starts unchecked each match without changing the engine value until clicked.

The **Game speed** slider affects the whole match:

- **0** pauses the simulation while the UI remains usable.
- **1** is normal speed (FAF speed +0).
- **2-10** select FAF speed +1 through +9, not literal speed multipliers.

The slider uses FAF's normal session pause, including its pause indicator and
paused audio. Moving it above 0 resumes at the selected speed. Changes entered
with keyboard shortcuts or the console are reflected automatically; external
speeds outside the slider range are displayed without changing them.
Actual speed depends on simulation performance.

Choose **Game Speed: Adjustable** in the lobby to enable speed changes.
With a fixed lobby speed, 0 still pauses, and the matching positive preset resumes;
other speed requests are refused. Live observers cannot use the control.
Multiplayer pause limits and resume delays still apply. The slider waits for
session confirmation before accepting another request and reports refusals/timeouts.

The **Modular Shields** tab appears only when the shield mod publishes
`ModularShields.Debug` through the shared Information Exchange. It edits the
mod-owned ReadWrite configuration without importing Modular Shields. Boolean
controls toggle instant module upgrades and ignored resource costs. Each numeric
control has an integer text field (Enter to apply) and a stepped slider:

| Parameter | Default | Slider range / step |
| --- | --- | --- |
| HP multiplier | 1 | 1–10 / 1 |
| Additional regen | 0 | 0–10000 / 100 |
| Additional slots | 0 | 0–50 / 1 |
| Additional repair | 0 | 0–1000 / 10 |

Shield settings affect all modular shields in the match. Modular Shields publishes
one Sim-owned configuration with validation and a Cheats authorization policy.
The shared loader handles UI-to-Sim commands and authoritative sync internally;
Debug Tools uses normal Get/SetPath access and generic ConfigStatus for refusals.
UI reads show confirmed values; controls keep the latest requested value visible
while waiting for Sim, then reconcile on acceptance/rejection. Slider previews
are local and send only on release or after 300 ms without movement.
Typed values may use any integer within the range; slider dragging uses the
listed steps. These settings reset each match.

## Usage

1. Enable **FireDragon Debug Tools** in the mod manager. It is a sim mod, so the host enables it.
2. Start a game with **cheats enabled**, or a single-player skirmish.
3. Press **Alt-Shift-D** to show or hide the panel, then use the toggles or game-speed slider.

The resource toggles affect the army of the player who clicks them; Instant Build affects all armies. Without cheats, the
sim refuses those toggles, unticks the box and the panel shows *Refused: cheats are disabled*.
Turning a resource toggle off removes the storage boost again.

Both tabs use Information Exchange exclusively for UI/Sim traffic. Vanilla
resource actions are `FireDragonDebugTools.SetResource` requests with a Cheats
authorization policy; `FireDragonDebugTools.Economy` retained events carry each
army's confirmed resource state. Named payload contracts live in `Messages.lua`.
Instant Build uses the cheats-gated `FireDragonDebugTools.SetInstantBuild` request
and the shared `FireDragonDebugTools.InstantBuild` state with key `match`.
There are no mod-specific SimCallback or UserSync handlers.
Speed/pause controls call FAF's UI-side session APIs directly, not the Sim
request transport. Their state and confirmation timeout update on UI frames,
so resuming never depends on advancing simulation ticks.

### How the boost works

Enabling a toggle spawns an invisible, unselectable and invulnerable helper unit at your
start position (`FDT0001` for energy, `FDT0002` for mass) whose blueprint has 1,000,000
storage. The engine adds it to your max storage like any other storage unit, so building,
upgrading or losing storages, generators or the ACU changes max storage normally without
dropping the boost. A loop refills the resource every tick and respawns the helper if it
is ever destroyed. Turning the toggle off destroys the helper.

`brain:GiveStorage` is not used: the engine keeps a single bonus slot for it, shared by
both resources, so it is recalculated away by storage changes and a mass boost wipes the
energy boost (and vice versa).

### Changing the key

The action is listed as *Toggle FireDragon Debug Tools panel* in the **F1** key bindings
dialog, under **Mods**. A key you bind there is applied from the next game on. Alt-Shift-D
is only bound by default when it is not already used for something else.

## Development

```powershell
./test.ps1              # Lua tests, syntax checks and import-path lint (needs lua/luac 5.4)
./build.ps1             # test + bundle into dist/FireDragonDebugTools (+ versioned zip)
./build.ps1 -Install    # also mirror into the FAF mods folder
```

| Path | Purpose |
|---|---|
| `src/mod_info.lua` | Mod metadata (bump `version` per release) |
| `src/lua/FireDragonDebugTools/Economy.lua` | Sim: per-army toggles, storage helpers, refill loop, cheat gate |
| `src/lua/FireDragonDebugTools/InstantBuild.lua` | Sim: match-wide engine instant-build toggle and shared menu state |
| `src/units/FDT0001`, `src/units/FDT0002` | Hidden energy / mass storage helper units |
| `src/lua/FireDragonDebugTools/Keys.lua` | Key action, default key and game-start bindings |
| `src/lua/FireDragonDebugTools/Panel.lua` | UI panel and sync handling |
| `src/hook/lua/simInit.lua` | Registers the economy request handler with Exchange |
| `src/lua/FireDragonDebugTools/Messages.lua` | Static request/event names and payload validation |
| `src/hook/lua/keymap/*.lua` | Registers the key action and its description |
| `src/hook/lua/ui/game/gamemain.lua` | Binds the panel key when the game UI is created |
| `tests/run.lua` | Economy, key binding and hook tests with engine mocks |

Tests run with Lua 5.4, but game sources must remain compatible with FAF's Lua 5.0.
The source lint rejects the unsupported `#` length operator; use `table.getn` instead.

To add a tool, define its plain payload in `Messages.lua`, register an authorized
Exchange request handler in Sim, and call it with `Exchange.Sim.Request` from UI.
Publish status through retained events. Keep engine transport in the shared loader.

See [../MOD_TEMPLATE.md](../MOD_TEMPLATE.md) for the shared project conventions.
