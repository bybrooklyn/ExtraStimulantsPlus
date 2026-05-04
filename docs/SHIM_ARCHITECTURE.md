# ExtraStimulantsPlus Shim Architecture

## Goal

Patch the game PCK once with the smallest possible hook, then load everything else from external `mods/` packs.

## Final layout

```text
Game folder/
├─ Game.exe / Game.app / game binary
├─ Game.pck                      # patched once
└─ mods/
   ├─ ExtraStimulantsPlus.zip     # actual ESP core
   └─ OtherMod.zip                # optional external mods
```

## Injected into the game PCK

Only these files need to be injected:

```text
res://esp_shim/ESPShim.gd
res://esp_bootstrap/ESPBootstrap.gd
res://override.cfg
```

`override.cfg` only contains the shim autoload:

```ini
[autoload]

ESPShim="*res://esp_shim/ESPShim.gd"
```

## Runtime boot order

```text
1. Godot starts the game.
2. Injected override.cfg autoloads ESPShim.
3. ESPShim runs _init() and mounts ExtraStimulantsPlus.zip/.pck from mods/.
4. ESPShim enters the tree and starts res://scripts/core/esp_core.gd from the external core pack.
5. ESPCore creates /root/ESP, /root/ModLoader, settings, hooks, logger, UI injector, etc.
6. ModLoader scans mods/ and activates other mods through mod.json entrypoints.
```

## Why the external core does not use override.cfg

A mod pack loaded with `ProjectSettings.load_resource_pack()` makes resources available, but it does not re-run project startup settings like autoloads from that pack's `override.cfg`.

That means the core pack is started manually:

```gdscript
var loader_script := load("res://scripts/core/esp_core.gd")
var loader = loader_script.new()
get_tree().root.add_child(loader)
```

## External mod format

Preferred packed layout:

```text
res://mods/cool_mod/mod.json
res://mods/cool_mod/main.gd
```

Example `mod.json`:

```json
{
  "schema": 1,
  "id": "cool_mod",
  "name": "Cool Mod",
  "version": "0.1.0",
  "author": "you",
  "dependencies": ["extrastimulants_plus"],
  "priority": 100,
  "entrypoints": ["main.gd"]
}
```

Example `main.gd`:

```gdscript
extends Node

func esp_init(api, meta: Dictionary) -> void:
    api.log_info("Cool Mod initialized")
```

## Load phases

Entrypoints may implement any of these:

```gdscript
func esp_preload(api, meta: Dictionary) -> void:
    pass

func esp_init(api, meta: Dictionary) -> void:
    pass

func esp_ready(api, meta: Dictionary) -> void:
    pass
```

## API object

The core exposes:

```text
/root/ESP
```

Common fields:

```gdscript
ESP.settings
ESP.mods
ESP.hooks
ESP.logger
ESP.audio
ESP.ghost
ESP.mutators
```

Prefer this over directly searching random `/root` nodes from mods.
