# {{name}}

A mod for [Sensory Overload](https://store.steampowered.com/app/2780820/Sensory_Overload/) built on the [ExtraStimulantsPlus](https://github.com/bybrooklyn/extrastimulantsplus) framework.

## Install

1. Make sure ESP is installed in your game (`esp install`).
2. Drop this folder (or a zip of it) into `<GameFolder>/mods/`.
3. Launch the game; check the orchestrator GUI's Mods panel to confirm the mod loaded.

## ESP API cheat-sheet

The framework exposes `/root/ESP` as `api` in your entrypoint callbacks. Namespaces:

| Namespace | What it does |
|---|---|
| `api.events` | Subscribe to game events (`level_started`, `obstacle_passed`, `player_died`, `score_updated`, …). Full list in `scripts/core/esp_event_adapter.gd::GAME_EVENT_MAP`. |
| `api.settings` | Read/write typed settings declared in `mod.json`. Subscribe to changes via `api.settings.get_registry().setting_changed`. |
| `api.assets` | Load textures/audio/scripts, including mod-relative paths (`api.assets.load_text(meta, "shaders/foo.glsl")`). |
| `api.saves` | Per-mod save data (`api.saves.set_data(MOD_ID, key, value)`). Stored under `user://esp_mod_saves.cfg`. |
| `api.campaign` | Register and play custom levels (`api.campaign.play_custom_level_path(path)`). |
| `api.game` | Access game singletons (`api.game.get_event_bus()`, `api.game.get_campaign_manager()`). |
| `api.hooks` | Lower-level event registry; usually `api.events` is what you want. |
| `api.mods` | Inspect loaded mods (`api.mods.is_loaded("other_mod")`). |
| `api.ui` | Inject menu buttons, HUD overlays, and other UI (`api.ui.inject_main_menu_button`). |

## Next steps

- Look at the bundled `esp_features` mod (in the framework repo at `mods/ExtraStimulantsPlus/mods/`) for a worked example of every namespace.
- Run `esp create --here events` to add an events template's files to this mod.
- Run `esp validate .` (when implemented) to lint your mod.json.
