# ExtraStimulantsPlus v0.0.2

A shim-based modding framework for *Sensory Overload*.

## 1. Install

1. **Download**: Get the latest `esp.exe` (Windows) or Linux binary from [GitHub Releases](https://github.com/bybrooklyn/extrastimulantsplus/releases).
2. **Run**: Open the **ESP Orchestrator GUI**.
3. **Setup**: Click **"ONE-CLICK SETUP"**.
   - The tool attempts to auto-detect your Steam install, patch the game, and download the framework.
4. **Play**: Click **"LAUNCH GAME"**.

---

## 2. Working Now

- **Shim/Core Split**: A tiny injected shim mounts an external ExtraStimulantsPlus core pack.
- **GUI Orchestrator**: A standalone Rust app provides setup, patching, launch, and log output.
- **Strict Loader Lifecycle**: Mods run through validation, preload, init, and ready phases.
- **Settings Registry API**: Mods can register and read persisted settings through the global `ESP` API.
- **External Mods**: Folder and pack candidates are discovered from supported mod directories.

---

## 3. Experimental / Partial

- **Native Settings UI**: Settings can be registered and stored, but full native visual polish is still in progress.
- **Custom Levels**: `.somap` mounting exists as an early implementation; deep audio/metadata loading is still roadmap work.
- **Installer Detection**: Steam/game discovery works for common paths but still needs broader platform hardening.

---

## 4. Release Automation

Release automation is planned. The intended pipeline is:

- Compile the Rust tool for supported platforms.
- Pack the framework core.
- Publish release artifacts from version tags.

---

## 5. Modder Guide

### 5.1 Manifest schema v1

Every mod ships a `mod.json` at its root. `schema_version: 1` is required and the loader rejects mods that omit it.

```json
{
  "schema_version": 1,
  "id": "cool_mod",
  "name": "Cool Mod Example",
  "version": "0.1.0",
  "author": { "name": "you", "url": "https://github.com/you" },
  "description": "What the mod does.",
  "required_framework_version": ">=0.0.2",
  "game_id": "sensory_overload",
  "game_versions": ">=0.13.0 <0.15.0",
  "tags": ["example"],
  "permissions": [],
  "dependencies": {},
  "priority": 100,
  "settings": { ... },
  "hooks":    { ... },
  "entrypoints": ["main.gd"]
}
```

Required fields: `schema_version`, `id`, `name`, `version`, `description`, `author` (string or `{name, url}`).
Optional fields the loader recognises: `icon`, `homepage`, `docs`, `tags`, `permissions`, `settings`, `hooks`, `priority`, `dependencies`, `required_framework_version`, `game_id`, `game_versions`.

`dependencies` is an object mapping mod id → semver range (`{"other_mod": ">=0.2.0"}`). Mods cannot list themselves; circular or missing deps fail validation.

### 5.2 Lifecycle methods

Entrypoint scripts may implement any of:

- `esp_preload(api, meta)` — before init; return `false` to abort.
- `esp_init(api, meta) -> bool` — return `false` to mark the mod failed.
- `esp_ready(api, meta)` — runs after every surviving mod has initialised.

A failure in any phase tears down the entrypoint instances, marks the mod errored, and skips dependents.

### 5.3 Runtime API namespaces

The framework exposes `/root/ESP` with namespaced helpers; prefer these over reaching into `/root/...` directly.

```gdscript
func esp_init(api, meta: Dictionary) -> bool:
    api.settings.register(meta.id, "general.enabled", TYPE_BOOL, true,
                          {"label": "Enabled"})
    api.events.on("level_started", Callable(self, "_on_level_started"),
                  {"priority": 100, "owner_id": meta.id})
    return true

func _on_level_started(a, b):
    pass
```

Available namespaces: `api.mods`, `api.settings`, `api.hooks`, `api.events`, `api.game`, `api.campaign`, `api.assets`, `api.saves`. Legacy direct helpers (`api.register_setting`, `api.get_setting`, …) still exist as compatibility wrappers.

### 5.4 Declarative settings and hooks

Anything you can do imperatively in `esp_init` you can also declare in `mod.json` so it is registered before user code runs.

```json
"settings": {
  "general": {
    "label": "General",
    "settings": {
      "enabled": {
        "type": "boolean",
        "default": true,
        "label": "Enabled",
        "description": "Enable the example mod."
      }
    }
  }
},
"hooks": {
  "events": [
    { "event": "level_started", "method": "_on_esp_event_level_started", "priority": 100 }
  ]
}
```

Settings are flattened to dotted keys (`general.enabled`). Setting `type` must be one of `boolean`, `int`, `float`, `string`. A `default` is required.

Hook entries bind to a method on the mod's entrypoint instance after `esp_init` returns true. The method receives the raw signal args (no `event_name` prefix); see `GAME_EVENT_MAP` in `scripts/core/esp_event_adapter.gd` for the argc each game event delivers. Supported hook kinds: `events`, `cancellable_events`, `scenes`, `nodes`. A manifest hook that names a missing method fails the mod.

### 5.5 Mod error states

Each mod has a status the loader keeps current: `discovered`, `validating`, `preloading`, `preloaded`, `initializing`, `initialized`, `readying`, `loaded`, plus terminal states `disabled`, `invalid`, `failed`, `errored`. Read them through `api.mods.get_status(id)` / `api.mods.get_all_statuses()` / `api.mods.get_errors(id)`. Hook failures during runtime mark the owning mod `errored` and surface in the same status table.

---

## 6. Advanced Roadmap

### I. True Native UI Polish
Upgrade the Settings UI generator to use the game's official `.tres` styleboxes and sound effects, making mod menus indistinguishable from native game tabs.

### II. .somap Deep Loader
Implement a comprehensive audio bridge for custom `.somap` levels, dynamically unzipping and loading `.ogg`/`.wav` music and parsing JSON metadata into native engine resources.

### III. The ESP Update Hub
Activate full GitHub API integration in the Rust CLI to support `esp update` and `esp add <url>`.

### IV. Surgical Regex Patching
Research a runtime "Surgical Patcher" that modifies game scripts in memory via Regex so multiple mods can modify the same file without conflicts or `take_over_path()` overwrites.

---

## 7. License & Legal

- Code: MIT.
- This repo contains no original game assets.
- Do not redistribute the base game's `.pck`, `.exe`, or app bundle.
