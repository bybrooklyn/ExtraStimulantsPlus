# ExtraStimulantsPlus Shim Loader Quickstart

This source tree is the rewritten shim-loader version.

## Layout

- `esp_shim/ESPShim.gd` is the tiny script injected into the game PCK.
- `scripts/core/esp_core.gd` starts the real external core after the shim mounts `mods/ExtraStimulantsPlus.zip`.
- `scripts/core/mod_loader.gd` scans and loads other external mods.
- `dist/ExtraStimulantsPlus.zip` is the ready-to-drop external core pack.
- `tools/esp-tool/` is the Rust orchestrator binary (`esp`) that handles installing, updating, mod management, and launching.

## Install shape

After patching the game once, the game folder should look like this:

```text
GameFolder/
├─ GameExecutable
├─ Game.pck
└─ mods/
   └─ ExtraStimulantsPlus.zip
```

The game PCK should only contain the shim and an `override.cfg` autoload for the shim.
The external core pack lives in `mods/ExtraStimulantsPlus.zip`.

## Test

1. Copy `dist/ExtraStimulantsPlus.zip` into the game's `mods/` folder.
2. Patch the game PCK so it injects `esp_shim/ESPShim.gd` and the shim `override.cfg`.
3. Launch the game.
4. Check console output for `[ESP Shim]` and `[ESP]` messages.
