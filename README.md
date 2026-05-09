# ExtraStimulantsPlus

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

## 6. Changelog

### Unreleased — post-v0.0.2

Procedural level generator (`ESP.campaign.generate_sequence` /
`ESP.campaign.play_generated`), Daily Challenge mod, GitHub releases-API
framework download (no more hardcoded URL/hash per release), Windows + Linux
GitHub Actions build workflow, Steam-via-Proton launch on Linux, `repository`
field in `mod.json`, 21 framework bug fixes, 12 audit fixes. macOS is no
longer a shipped target — Sensory Overload has no native Mac build, so
esp-tool there would have nothing to install or launch. Mac developers can
still `cargo build` locally for `esp pack` / `esp create` mod authoring.

### v0.0.2

A near-rewrite of the framework. Everything in **§2 Working Now** and most of **§3 Experimental** is new since v0.0.1.

#### Framework architecture
- **Shim/core split.** A tiny PCK-injected shim (`esp_shim/ESPShim.gd`) mounts an external core pack at `_init`, then hands control to the full loader. The core is shipped separately as `mods/ExtraStimulantsPlus.zip`, so iterating on framework code does not require re-patching the game PCK.
- **Schema v1 mod manifests** are required; the loader rejects mods without `schema_version: 1`.
- **`/root/ESP` namespaced API** with 9 namespaces: `mods`, `settings`, `hooks`, `events`, `game`, `campaign`, `assets`, `saves`, `ui`. Legacy direct helpers retained as compatibility wrappers.
- **Priority-ordered cancellable hook bus** (`ESPHooks`) replaces ad-hoc signal wiring.
- **EventBus → ESP hook adapter** (`scripts/core/esp_event_adapter.gd`): the GAME_EVENT_MAP table re-emits 25+ game signals as stable framework events (`level_started`, `obstacle_passed`, `player_died`, `score_updated`, etc.).
- **Campaign adapter** for custom level registration (`api.campaign.play_custom_level_path`).
- **Mod status lifecycle tracking**: `discovered → validating → preloading → preloaded → initializing → initialized → readying → loaded` plus terminal `disabled / invalid / failed / errored`. Persisted to `<game_dir>/modloader/mod_statuses.json` so the orchestrator GUI can show live state.
- **User profile state file** (`modloader/user_profile.json`) — godot-mod-loader-compatible schema (`mod_list[mod_id] = {enabled}`); leaves room for named profiles and per-mod configs without changing the on-disk shape.

#### Built-in mod (`esp_features`)
- **Screen-space path tracer** as a Forward+ `CompositorEffect`. 4-pass pipeline: trace (half-res, N cosine-weighted hemisphere rays per pixel) → temporal reproject (per-pixel EMA, disocclusion check) → 3-iter à-trous denoise (edge-stops on depth + normal) → composite (full-res depth-aware bilateral upsample, additive). Octahedral normal decode for `normal_roughness`. Tunable sky/miss color so corners no longer go pitch-black. **Quality presets**: `off / gameplay / cinematic / custom` (dropdown in the settings UI).
- **Audio visualizer** wired into `api.settings` and `api.events`; samples the Music bus during levels and drives the `mod_music_pulse` shader global.
- **Ghost recorder** writes to `user://esp_features/ghosts/<level>.soghost`; reads with a fallback to the legacy `user://ghosts/` path so existing recordings stay visible.
- **Mutators** — actual implementations: **Mirror Mode** (InputMap swap of `move_left ↔ move_right`, originals restored on disable) and **Turbo Mode** (`Engine.time_scale = 1.2` while a level is active). Live `setting_changed` listener so toggles take effect immediately.
- **Custom level browser & level editor** scenes ship with the bundled mod.

#### `api.ui` namespace (new)
- `inject_main_menu_button(label, callback, owner_id, options)` — namespaced, idempotent, supports `position: "before:Foo"` / `"after:Bar"` / `"end"`.
- `inject_hud_overlay(scene_or_node, owner_id, options)` — CanvasLayer with z-index control, auto-removed on `level_completed` / `player_died` unless `persistent: true`.
- `wait_for_node(name_or_path, callback, options)` — one-shot listener with a 5-second default timeout.
- `set_badge_visible / set_badge_color / get_theme_accent`.
- The framework's own Custom Maps button now uses `inject_main_menu_button` as the canonical example.

#### `api.assets` mod-relative helpers
- `mod_path(meta)` / `resolve(meta, relative)` / `load_text(meta, relative)` / `load_from_mod(meta, relative)` / `script_extension(meta, ext_relative, target_res_path)`. Lets mods avoid hardcoding `res://mods/<my_id>/...` paths and works whether the mod is mounted as a folder or a zip.

#### Settings UI
- Native MODS tab injected into the game's `SettingsMenu`.
- Type-correct controls: bool → pill toggle, int/float → SpinBox (with `min/max/step`), string → LineEdit, **string + `choices` array → OptionButton dropdown** (new — used by the path tracer presets).
- `setting_changed` signal so live tweaks propagate to listening mods.
- Idempotent injection guards via `has_meta`.
- Dynamic native-tab style anchor (no more hardcoded `NATIVE_STYLE_TAB_INDEX = 3`).
- Bounded retry on the deferred SettingsMenu hook (gives up after ~2 s instead of looping forever).
- Theme-aware badge accent — pulls from the menu theme if it defines `esp_accent` / `accent`, falls back to the framework's cyan.

#### ESP Orchestrator (Rust app)
- **Module split.** `main.rs` went from 671 lines to ~38; everything else lives in dedicated modules (`cli`, `config`, `error`, `gamelog`, `gui`, `install`, `launch`, `loadplan`, `modmgr`, `pack`, `pck`, `scaffold`, `steam`).
- **`esp create` wizard** with 6 templates (`minimal`, `events`, `settings`, `feature`, `ui`, `campaign`). Interactive (`dialoguer` prompts) or one-shot (`--template <name> --no-prompt`). `--here` adds a template's files to the current mod. Generated source files include API signatures inline as comments — the docs are the scaffold.
- **`esp uninstall`** subcommand and GUI button. Restores the PCK from `.esp-backup` (or strips injected entries in place) and removes `modloader/`, `mods/`, `levels/`.
- **Mod manager UI panel** in the GUI: lists every discovered mod with status indicators, enable/disable toggle (writes `user_profile.json`), `Install Mod...` file picker (drops zip/pck into `mods/`), Refresh, auto-refresh on `mods/` mtime change, expandable per-mod details.
- **`UPDATE FRAMEWORK` button** redownloads the core pack zip.
- **Live game-log viewer** tails `user://logs/godot.log` with platform-correct path resolution; throttles to 2 s polling when the file's idle for >10 s.
- **Steam VDF parser** rewritten with a real tokenizer; correctly handles multi-library installs.
- **Linux/macOS Steam paths** broadened (`~/.steam/steam`, `~/.steam/root`, `~/Library/Application Support/Steam`).
- **macOS launch** probes `<App>.app/Contents/MacOS/SensoryOverload`, then bare and `.x86_64` fallbacks.
- **Config moved** from CWD `.esp-config.json` to `dirs::config_dir()/esp/config.json` with one-time migration from the legacy location.
- **`LoadPlan`** populates `generated_at` (RFC3339), reads `framework_version` from the bundled core pack manifest, scans `levels/`, and discovers `.zip`/`.pck` mods alongside folders.
- **`fetch_framework`** returns `Err` on non-2xx HTTP (was silently `Ok(())`).
- **MD5** swapped from a 22-line hand-roll to the `md5` crate.
- **Dependencies cleaned**: dropped `tokio` and `colored` (unused); added `md5`, `dialoguer`, `rfd` (file picker).

#### Notable bug fixes since v0.0.1
- macOS `modloader_dir` mismatch — the orchestrator wrote to `<App>.app/Contents/Resources/modloader/` but the shim looked in `<App>.app/Contents/MacOS/modloader/`. Toggling mods on Mac silently did nothing. Resolver now probes both and prefers the existing one.
- Path tracer same-dispatch read/write race on the color buffer — fixed via a host-managed `color_history` snapshot bound separately.
- Octahedral normal decode TODO (`#define OCT_DECODE 0`) removed — Forward+ uses octahedral encoding unconditionally.
- Half-res output 2×2 quad blockiness — replaced by full-res bilateral upsample.
- `fetch_framework` silent download failure (see above).

---

## 7. What's still pending

Tracked roughly in priority order. Items completed in v0.0.2 are listed in the Changelog above.

### Near-term polish
- **Path tracer uniform-set cache thrash.** Per-frame ping-pong RIDs (history, atrous) cause `UniformSetCacheRD.get_cache(...)` to allocate fresh sets every frame instead of reusing them. Not wrong, but a perf cliff worth fixing.
- **`api.ui.inject_settings_tab` is a stub** that warns and returns null. Mods needing custom tabs route through declarative `mod.json::settings` for now.
- **Hand-rolled `GodotPck` reader** has not been stress-tested against PCK v1 or non-default flag combinations. May panic on real-world games beyond Sensory Overload's specific build.
- **`SettingsNamespace.has_method("get_registry")` brittleness.** Several call sites rely on this returning true for the `class` keyword; if Godot ever changes how nested classes inherit from `Object`, callers fall over silently. Replace with a typed null check.

### Developer tooling (deferred from the `esp create` pass)
- **`esp validate <path>`** — lint a mod against the schema; resolve script-extension targets against the installed PCK.
- **`esp doctor`** — diagnose a broken install (PCK has shim? `modloader/` exists? statuses sane?) with one-line fixes.
- **`esp open mods | game | userdata`** — open the relevant directory in the OS file manager.
- **Hot reload during development** — file watcher on `mods/` plus a "reload mods" event mods can opt into. State management is the hard part; start with "reload settings only".
- **Tests, CI, and a linter** for the GDScript side. None of the framework code is currently covered.

### godot-mod-loader feature parity
- **Named user profiles** — switch between curated mod sets (e.g. *default* / *minimal* / *challenge*). The `user_profile.json` schema already has the `name` field; needs orchestrator UI for create/switch/delete.
- **Per-mod runtime configuration.** GML's `current_config` field. Pairs with `api.settings` to let users pick between mod-defined named presets at runtime.
- **Restart-required hot-toggle prompts** when toggling mods that can't safely live-swap (most of them).
- **JSON Schema validator** borrowed from GML's `addons/JSON_Schema_Validator/` for richer manifest validation than our current ad-hoc `_normalize_metadata`.

### Larger items still on the original 0.0.2 roadmap
- **True Native UI Polish.** Brittleness fixes landed (anchors, theme accent, retry-bounded polling); the deeper goal of pulling SO's `.tres` styleboxes and SFX so framework-injected widgets are byte-for-byte indistinguishable from native ones is still outstanding.
- **`.somap` Deep Loader.** Comprehensive audio bridge for custom levels — unzip + load `.ogg`/`.wav` music, parse JSON metadata into native engine resources. The custom level browser and editor exist; the `.somap` packaging path does not.
- **ESP Update Hub.** `UPDATE FRAMEWORK` re-downloads the core pack today. Still missing: `esp update` (self-update), `esp add <url>` (install a third-party mod from a GitHub release URL), and a "new version available" indicator in the GUI.
- **Surgical regex patcher.** Runtime in-memory script patcher so multiple mods can modify the same file without `take_over_path` collisions. Still research-grade.

### Smaller items worth doing eventually
- Pack-core CLI invocation should exclude the `GML/` clone alongside `tools/` and `.git/`.
- Search box and keyboard navigation in the orchestrator's mod manager.
- Settings search across all mods inside the in-game MODS tab.
- A "what's running" debug overlay in-game (mod count, framework version, hotkey to toggle).
- Crash recovery: if a mod's `esp_init` throws, surface a one-click "disable this mod" in the orchestrator on next launch.

---

## 8. License & Legal

- Code: MIT.
- This repo contains no original game assets.
- Do not redistribute the base game's `.pck`, `.exe`, or app bundle.
