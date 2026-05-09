# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this project is

ExtraStimulantsPlus (ESP) is a **shim-based modding framework for the Godot 4 game *Sensory Overload***. The repo contains:

- The framework's GDScript runtime (`scripts/core/`, `esp_shim/`, `esp_bootstrap/`).
- A built-in mod that ships with the framework (`mods/ExtraStimulantsPlus/`).
- The Rust orchestrator/installer/GUI (`tools/esp-tool/`).
- A copy of the game's `project.godot` and several game autoloads referenced by the framework — this lets the GDScript code resolve `class_name` and `/root/...` references during development. The actual game source is not committed; the `SensoryOverload/` directory is local-only.

## Architecture: the shim/core split

This is the most important thing to internalize before changing framework code. The framework deliberately splits into **two halves** and they have very different rules.

### 1. The shim — injected into the game's PCK

Files in `esp_shim/`, `esp_bootstrap/`, plus a merged `override.cfg`. Patched into the game once by the Rust installer.

- `override.cfg` autoloads `ESPShim` (`*res://esp_shim/ESPShim.gd`).
- `ESPShim._init()` mounts the external core pack via `ProjectSettings.load_resource_pack()`. This must happen during `_init` because Godot starts touching resources very early.
- `ESPShim._enter_tree()` instantiates `res://scripts/core/esp_core.gd` from the just-mounted pack and adds it under `/root/ESPCore`.
- Keep this layer **tiny**. Do not put gameplay or framework logic in the shim — every byte added here ends up baked into the patched PCK.

### 2. The external core — shipped as `mods/ExtraStimulantsPlus.zip`

Everything under `scripts/core/` (and the bundled mod under `mods/ExtraStimulantsPlus/`). Loaded at runtime as a resource pack, so it does **not** re-run project startup settings — autoloads inside the pack are ignored. That is why `esp_core.gd` manually installs every framework node onto `/root` from `_install_core_nodes()`:

```
/root/ESPLogger, /root/ESPHooks, /root/ESPSettings,
/root/ESPSettingsRegistry, /root/ESPLevelRegistry,
/root/ESPEventAdapter, /root/ESPCampaignAdapter,
/root/ESPModLoader, /root/ESPUIInjector, /root/ESP
```

`/root/ESP` (`esp_api.gd`) is the public API surface mods are expected to use; it holds namespaced helpers (`ESP.mods`, `ESP.settings`, `ESP.hooks`, `ESP.events`, `ESP.game`, `ESP.campaign`, `ESP.assets`, `ESP.saves`). Prefer extending these namespaces over exposing new top-level fields.

### 3. The mod loader — `scripts/core/mod_loader.gd`

After `ESPCore._ready()` runs, `mod_loader.load_external_mods()` scans `mods_dirs` (passed in from the shim's boot info) for folders/zips/pcks containing `mod.json`, mounts them, validates schema/permissions/dependencies, then runs each mod through three lifecycle phases: `esp_preload` → `esp_init` → `esp_ready`. A mod returning `false` (or throwing) in `esp_init` is marked failed; dependents of a failed mod are skipped before `esp_ready`.

### 4. Game integration adapters

The framework never lets mods reach into game internals directly:

- `esp_event_adapter.gd` connects the game's `/root/EventBus` signals and re-emits them as stable hook events on `ESPHooks`. The mapping is the `GAME_EVENT_MAP` table — extend that table when exposing new game signals.
- `esp_campaign_adapter.gd` owns custom-level registration and playback against `CampaignManager`.
- `esp_level_loader_ext.gd` uses `take_over_path()` against `res://scripts/campaign/campaign_level_loader.gd` to extend the game's loader (this is the **only** script-extension hook in the framework right now).
- `ui_injector.gd` watches `SceneTree.node_added` for known game UI node names (`MainMenu`, `SettingsMenu`, etc.) and injects the framework badge plus the "CUSTOM MAPS" entry.

When adding game-side integration, prefer adapter + hook event over mods touching `/root/EventBus` directly.

## Common commands

### Rust orchestrator (`tools/esp-tool/`)

The binary name is `esp` (not `esp-installer` — the older name in `docs/BUILD_AND_INSTALL.md` is stale).

```bash
cd tools/esp-tool
cargo build --release          # produces target/release/esp
./target/release/esp           # no args → launches the GUI orchestrator
./target/release/esp install [/path/to/Game.pck]   # patches the shim into the PCK; auto-detects via Steam if path omitted
./target/release/esp launch [--no-mods]            # writes load plan, launches the game binary
./target/release/esp pack <output.zip>             # zips the current dir into a core pack
```

The Rust binary `include_bytes!`s `esp_shim/ESPShim.gd`, `esp_bootstrap/ESPBootstrap.gd`, and `esp_bootstrap/override.cfg` from the repo root. **Editing those three files requires rebuilding `esp-tool`** for installer behaviour to change.

`install` writes a `Game.pck.esp-backup` next to the PCK and creates `modloader/`, `mods/`, `levels/` dirs in the game folder. `esp uninstall [path/to/Game.pck]` reverses this: it restores the PCK from the backup (or strips injected files in place if the backup is gone) and removes the three managed directories. The GUI exposes the same flow as an "UNINSTALL" button.

### Building the core pack

There is no committed Python patcher (`pck_patcher.py` is referenced in `docs/BUILD_AND_INSTALL.md` but isn't in the tree). Use either:

- `esp pack ExtraStimulantsPlus.zip` from the repo root, or
- zip `mods/ExtraStimulantsPlus/mods/` contents manually if iterating on the bundled mod only.

The result must land at `<GameFolder>/mods/ExtraStimulantsPlus.zip` (or one of the other names in `CORE_PACK_NAMES` inside `esp_shim/ESPShim.gd` / `mod_loader.gd`).

### Tests / lint

There is no test suite, no linter, and no CI in the tree. Don't invent commands.

## Conventions worth following

- **Don't add autoloads to the core pack.** They won't fire. Add the node in `esp_core.gd::_install_core_nodes()` instead, and pass dependencies through `configure({...})` rather than calling `get_node("/root/...")` from constructors.
- **Two `CORE_PACK_NAMES` lists** exist — one in `esp_shim/ESPShim.gd` and one in `scripts/core/mod_loader.gd`. Keep them in sync when adding a recognised pack name.
- **Mod-id constants** (`SUPPORTED_GAME_ID`, `CORE_MOD_ID`, `SUPPORTED_SCHEMA`) live at the top of `mod_loader.gd`. Bumping schema or game-version compatibility goes there plus `mod.json::game_versions`.
- **Settings persistence** is split: `settings_registry.gd` writes to `user://esp_mod_settings.cfg`, `esp_api.gd::saves` writes to `user://esp_mod_saves.cfg`. Settings are typed/registered; saves are free-form per mod.
- **Mod entrypoints** implement any of `esp_preload(api, meta)`, `esp_init(api, meta) -> bool`, `esp_ready(api, meta)`. Returning `false` from `esp_init` is the canonical fail signal.
- **Version strings** live in three places that must stay aligned: `VERSION` file, `mod.json::version`, `esp_core.gd::CORE_VERSION` (and `mod_loader.gd::CORE_VERSION`), and `tools/esp-tool/Cargo.toml`.
