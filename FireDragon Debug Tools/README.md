Requires **FireDragon Mod Loader v4** installed and enabled as a normal FAF mod (shared core dependency).

# FireDragon Debug Tools

A small in-game debug panel for testing. It has two toggles:

- **Infinite Energy**: your energy storage gets a +1,000,000 boost and is refilled every tick.
- **Infinite Mass**: the same for mass.

## Usage

1. Enable **FireDragon Debug Tools** in the mod manager. It is a sim mod, so the host enables it.
2. Start a game with **cheats enabled**, or a single-player skirmish.
3. Press **Alt-Shift-D** to show or hide the panel, then tick the toggles.

The toggles always affect the army of the player who clicks them. Without cheats, the
sim refuses the request, unticks the box and the panel shows *Refused: cheats are disabled*.
Turning a toggle off removes the storage boost again.

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
| `src/units/FDT0001`, `src/units/FDT0002` | Hidden energy / mass storage helper units |
| `src/lua/FireDragonDebugTools/Keys.lua` | Key action, default key and game-start bindings |
| `src/lua/FireDragonDebugTools/Panel.lua` | UI panel and sync handling |
| `src/hook/lua/SimCallbacks.lua` | Routes `FireDragonDebugSetResource` to `Economy.lua` |
| `src/hook/lua/UserSync.lua` | Forwards `Sync.FireDragonDebug` to the panel |
| `src/hook/lua/keymap/*.lua` | Registers the key action and its description |
| `src/hook/lua/ui/game/gamemain.lua` | Binds the panel key when the game UI is created |
| `tests/run.lua` | Economy, key binding and hook tests with engine mocks |

To add a toggle, add an entry to `Toggles` in `Panel.lua`. If it needs new sim behaviour,
add a field to the callback data and handle it in `Economy.HandleCallback`, or add a new
module plus a callback name in the `SimCallbacks.lua` hook.

See [../MOD_TEMPLATE.md](../MOD_TEMPLATE.md) for the shared project conventions.
