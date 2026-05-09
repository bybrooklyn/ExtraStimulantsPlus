extends Node

# Runtime API object exposed at /root/ESP.
# Mods should prefer this over directly hunting random /root nodes.

const SAVE_DATA_PATH := "user://esp_mod_saves.cfg"
const GAME_SINGLETONS := {
    "EventBus": "/root/EventBus",
    "GameContext": "/root/GameContext",
    "CampaignManager": "/root/CampaignManager",
    "SteamManager": "/root/SteamManager",
    "GameSettings": "/root/GameSettings",
    "RenderingQualityManager": "/root/RenderingQualityManager",
    "PerformanceOverlay": "/root/PerformanceOverlay",
    "PerformanceDiagnostics": "/root/PerformanceDiagnostics",
    "UiSfxManager": "/root/UiSfxManager",
    "GameAnalytics": "/root/GameAnalytics"
}
const SCRIPT_EXTENSION_TARGETS := {
    "res://scripts/campaign/campaign_level_loader.gd": [],
    "res://scripts/domains/obstacles/obstacle_manager.gd": ["esp_features"]
}

class ModsNamespace:
    var _api

    func _init(api_ref) -> void:
        _api = api_ref

    func get_loaded_ids() -> Array[String]:
        return _api.get_loaded_mod_ids()

    func is_loaded(mod_id: String) -> bool:
        return _api.is_mod_loaded(mod_id)

    func get_loaded() -> Array[Dictionary]:
        return _api.get_loaded_mods()

    func get_failed() -> Array[Dictionary]:
        return _api.get_failed_mods()

    func get_status(mod_id: String) -> Dictionary:
        return _api.get_mod_status(mod_id)

    func get_errors(mod_id: String) -> Array:
        return _api.get_mod_errors(mod_id)

    func get_all_statuses() -> Dictionary:
        return _api.get_all_mod_statuses()


class HooksNamespace:
    var _api

    func _init(api_ref) -> void:
        _api = api_ref

    func register(event_name: String, callback: Callable, options: Dictionary = {}) -> bool:
        return _api._register_callable_event(event_name, callback, options, false)

    func on(event_name: String, callback: Callable, options: Dictionary = {}) -> bool:
        return register(event_name, callback, options)

    func once(event_name: String, callback: Callable, options: Dictionary = {}) -> bool:
        return _api._register_callable_event(event_name, callback, options, true)

    func unregister(event_name: String, callback: Callable, owner_id: String = "") -> bool:
        return _api._unregister_callable_event(event_name, callback, owner_id)

    func off(event_name: String, callback: Callable, owner_id: String = "") -> bool:
        return unregister(event_name, callback, owner_id)

    func emit(event_name: String, payload = null) -> Dictionary:
        return _api._emit_event_payload(event_name, payload, false, {})

    func emit_cancellable(event_name: String, payload = null, control: Dictionary = {}) -> Dictionary:
        return _api._emit_event_payload(event_name, payload, true, control)

    func list_registered() -> Array[String]:
        if _api._hooks_node and _api._hooks_node.has_method("get_registered_events"):
            return _api._hooks_node.get_registered_events()
        return []

    func inspect(event_name: String = "") -> Variant:
        if _api._hooks_node and _api._hooks_node.has_method("get_event_hooks"):
            return _api._hooks_node.get_event_hooks(event_name)
        return {}


class EventsNamespace:
    var _api

    func _init(api_ref) -> void:
        _api = api_ref

    func on(event_name: String, callback: Callable, options: Dictionary = {}) -> bool:
        return _api.hooks.register(event_name, callback, options)

    func once(event_name: String, callback: Callable, options: Dictionary = {}) -> bool:
        return _api.hooks.once(event_name, callback, options)

    func off(event_name: String, callback: Callable, owner_id: String = "") -> bool:
        return _api.hooks.off(event_name, callback, owner_id)

    func emit(event_name: String, payload = null) -> Dictionary:
        return _api.hooks.emit(event_name, payload)

    func emit_cancellable(event_name: String, payload = null, control: Dictionary = {}) -> Dictionary:
        return _api.hooks.emit_cancellable(event_name, payload, control)

    func get_available() -> Array[String]:
        return _api.get_available_events()


class SettingsNamespace:
    var _api

    func _init(api_ref) -> void:
        _api = api_ref

    func register(mod_id: String, key: String, type: int, default_value, options: Dictionary = {}) -> void:
        _api.register_setting(mod_id, key, type, default_value, options)

    func get(mod_id: String, key: String, fallback = null):
        return _api.get_setting(mod_id, key, fallback)

    func set(mod_id: String, key: String, value) -> void:
        _api.set_setting(mod_id, key, value)

    func get_all() -> Dictionary:
        return _api.get_all_settings()

    func get_registry() -> Node:
        return _api._settings_registry_node


class GameNamespace:
    var _api

    func _init(api_ref) -> void:
        _api = api_ref

    func get_singleton(singleton_name: String) -> Node:
        return _api.get_game_singleton(singleton_name)

    func get_version() -> String:
        return _api.get_game_version()

    func get_id() -> String:
        return _api.get_game_id()

    func get_event_bus() -> Node:
        return _api.get_event_bus()

    func get_game_context() -> Node:
        return _api.get_game_context()

    func get_campaign_manager() -> Node:
        return _api.get_campaign_manager()

    func get_game_settings() -> Node:
        return _api.get_game_settings()

    func get_ui_sfx_manager() -> Node:
        return _api.get_ui_sfx_manager()

    func play_ui_click() -> void:
        _api.play_ui_click()


class CampaignNamespace:
    var _api

    func _init(api_ref) -> void:
        _api = api_ref

    func play_custom_level_path(path: String, options: Dictionary = {}) -> bool:
        return _api.play_custom_level_path(path, options)

    func play_custom_sequence(sequence: Array, meta: Dictionary = {}, source_path: String = "") -> bool:
        return _api.play_custom_sequence(sequence, meta, source_path)

    func get_custom_levels() -> Array:
        return _api.get_custom_levels()

    func get_registered_custom_levels() -> Array:
        if _api._campaign_node and _api._campaign_node.has_method("get_registered_custom_levels"):
            return _api._campaign_node.get_registered_custom_levels()
        return []

    # Procedural generation. Pure data — does not touch disk.
    # Returns {"sequence": Array, "meta": Dictionary}. See ESPLevelGenerator
    # for option keys (obstacle_count, gap_min, gap_max, difficulty, date_label).
    func generate_sequence(seed_value: int, options: Dictionary = {}) -> Dictionary:
        return ESPLevelGenerator.generate_sequence(seed_value, options)

    # Convenience: generate, write to user://esp/runtime/levels/, and play.
    # Pass options.play_options to forward into play_custom_level_path
    # (e.g. {"practice_mode": false}). Returns false if write or launch fails.
    func play_generated(seed_value: int, options: Dictionary = {}) -> bool:
        var path := ESPLevelGenerator.write_generated_json(seed_value, options)
        if path.is_empty():
            _api.log_warn("ESP.campaign.play_generated: failed to write generated level for seed %d" % seed_value)
            return false
        var play_opts: Dictionary = options.get("play_options", {"practice_mode": false})
        return _api.play_custom_level_path(path, play_opts)


class AssetsNamespace:
    var _api

    func _init(api_ref) -> void:
        _api = api_ref

    func load_resource(path: String, use_cache: bool = true):
        return _api._load_asset(path, use_cache)

    func load_texture(path: String, use_cache: bool = true):
        var res = _api._load_asset(path, use_cache)
        return res if res is Texture2D else null

    func load_audio(path: String, use_cache: bool = true):
        var res = _api._load_asset(path, use_cache)
        return res if res is AudioStream else null

    func load_scene(path: String, use_cache: bool = true):
        var res = _api._load_asset(path, use_cache)
        return res if res is PackedScene else null

    func clear_cache(path: String = "") -> void:
        _api._clear_asset_cache(path)

    # Mod-relative helpers. Mods receive `meta` in their entrypoint callbacks;
    # passing it here removes the need to hardcode "res://mods/<my_id>/...".
    # Folder-mounted mods resolve against meta["path"]; packs resolve against
    # res://mods/<id>/. Mirrors mod_loader._resolve_entrypoint_path.
    func mod_path(meta: Dictionary) -> String:
        return _api._resolve_mod_root(meta)

    func resolve(meta: Dictionary, relative: String) -> String:
        return _api._resolve_mod_relative(meta, relative)

    func load_text(meta: Dictionary, relative: String) -> String:
        return _api._load_mod_text(meta, relative)

    func load_from_mod(meta: Dictionary, relative: String, use_cache: bool = true):
        return _api._load_mod_resource(meta, relative, use_cache)

    func script_extension(meta: Dictionary, ext_relative: String, target_res_path: String) -> bool:
        return _api._apply_script_extension(meta, ext_relative, target_res_path)


class UINamespace:
    var _api

    func _init(api_ref) -> void:
        _api = api_ref

    # Adds a button to the game's MainMenu MenuContainer. Idempotent per
    # owner_id: calling twice with the same owner_id returns the existing
    # button. Options: {"position": "before:CustomMapsButton" | "after:SettingsButton" | "end"}.
    func inject_main_menu_button(label: String, on_click: Callable, owner_id: String, options: Dictionary = {}) -> Button:
        if _api._ui_injector_node == null:
            _api.log_warn("api.ui.inject_main_menu_button: UI injector not ready")
            return null
        return _api._ui_injector_node.inject_main_menu_button(label, on_click, owner_id, options)

    # Adds a CanvasLayer overlay during gameplay. Auto-removed on level_completed
    # or player_died unless options.persistent is true. options.layer = z-index.
    func inject_hud_overlay(node_or_scene, owner_id: String, options: Dictionary = {}) -> CanvasLayer:
        if _api._ui_injector_node == null:
            _api.log_warn("api.ui.inject_hud_overlay: UI injector not ready")
            return null
        return _api._ui_injector_node.inject_hud_overlay(node_or_scene, owner_id, options)

    # One-shot listener that fires `callback` the first time a node with the
    # given name (or matching path suffix) appears in the SceneTree.
    # options.timeout_ms: defaults to 5000.
    func wait_for_node(name_or_path: String, callback: Callable, options: Dictionary = {}) -> void:
        if _api._ui_injector_node == null:
            _api.log_warn("api.ui.wait_for_node: UI injector not ready")
            return
        _api._ui_injector_node.wait_for_node(name_or_path, callback, options)

    # Custom settings tab beyond the auto-generated MODS tab. Reserved for a
    # future pass; currently logs a notice and routes through the declarative
    # mod.json::settings path which works today.
    func inject_settings_tab(label: String, _build_fn: Callable, owner_id: String) -> Control:
        _api.log_warn("api.ui.inject_settings_tab: not yet implemented (label=%s, owner=%s) — declare typed settings in mod.json instead" % [label, owner_id])
        return null

    func set_badge_visible(visible: bool) -> void:
        if _api._ui_injector_node and _api._ui_injector_node.has_method("set_badge_visible"):
            _api._ui_injector_node.set_badge_visible(visible)

    func set_badge_color(c: Color) -> void:
        if _api._ui_injector_node and _api._ui_injector_node.has_method("set_badge_color"):
            _api._ui_injector_node.set_badge_color(c)

    # Returns the framework's accent color (resolved from the menu theme if
    # available). Mods can use this to make their UI feel native.
    func get_theme_accent() -> Color:
        if _api._ui_injector_node and _api._ui_injector_node.has_method("get_theme_accent"):
            return _api._ui_injector_node.get_theme_accent()
        return Color(0.1, 0.8, 1.0, 1.0)


class SavesNamespace:
    var _api

    func _init(api_ref) -> void:
        _api = api_ref

    func get_data(mod_id: String, key: String, fallback = null):
        return _api._get_save_value(mod_id, key, fallback)

    func set_data(mod_id: String, key: String, value) -> void:
        _api._set_save_value(mod_id, key, value)

    func get_mod_data(mod_id: String) -> Dictionary:
        return _api._get_mod_save_data(mod_id)

    func erase_data(mod_id: String, key: String = "") -> void:
        _api._erase_save_value(mod_id, key)

    func save() -> void:
        _api._save_config.save(SAVE_DATA_PATH)

var core: Node
var logger: Node
var audio: Node
var ghost: Node
var mutators: Node
var level_registry: Node
var settings_registry: Node

var mods
var settings
var hooks
var events
var game
var campaign
var assets
var saves
var ui

var _mods_node: Node
var _settings_node: Node
var _settings_registry_node: Node
var _level_registry_node: Node
var _hooks_node: Node
var _event_adapter_node: Node
var _campaign_node: Node
var _ui_injector_node: Node
var _asset_cache: Dictionary = {}
var _save_config: ConfigFile = ConfigFile.new()


func configure(parts: Dictionary) -> void:
    core = parts.get("core")
    logger = parts.get("logger")
    audio = parts.get("audio")
    ghost = parts.get("ghost")
    mutators = parts.get("mutators")

    _mods_node = parts.get("mods")
    _settings_node = parts.get("settings")
    _settings_registry_node = parts.get("settings_registry")
    _level_registry_node = parts.get("level_registry")
    _hooks_node = parts.get("events", parts.get("hooks"))
    _event_adapter_node = parts.get("event_adapter")
    _campaign_node = parts.get("campaign")
    _ui_injector_node = parts.get("ui_injector")

    _save_config.load(SAVE_DATA_PATH)

    level_registry = _level_registry_node
    settings_registry = _settings_registry_node

    mods = ModsNamespace.new(self)
    settings = SettingsNamespace.new(self)
    hooks = HooksNamespace.new(self)
    events = EventsNamespace.new(self)
    game = GameNamespace.new(self)
    campaign = CampaignNamespace.new(self)
    assets = AssetsNamespace.new(self)
    saves = SavesNamespace.new(self)
    ui = UINamespace.new(self)


func register_setting(mod_id: String, key: String, type: int, default_value, options: Dictionary = {}) -> void:
    if _settings_registry_node and _settings_registry_node.has_method("register"):
        _settings_registry_node.register(mod_id, key, type, default_value, options)
    else:
        log_warn("Settings registry is unavailable; could not register %s.%s" % [mod_id, key])


func get_setting(mod_id: String, key: String, fallback = null):
    if _settings_registry_node and _settings_registry_node.has_method("get_value"):
        var value = _settings_registry_node.get_value(mod_id, key)
        if value != null:
            return value
    return fallback


func set_setting(mod_id: String, key: String, value) -> void:
    if _settings_registry_node and _settings_registry_node.has_method("set_value"):
        _settings_registry_node.set_value(mod_id, key, value)
    else:
        log_warn("Settings registry is unavailable; could not set %s.%s" % [mod_id, key])


func get_all_settings() -> Dictionary:
    if _settings_registry_node and _settings_registry_node.has_method("get_all_settings"):
        return _settings_registry_node.get_all_settings()
    return {}


func get_loaded_mod_ids() -> Array[String]:
    if _mods_node and _mods_node.has_method("get_loaded_mod_ids"):
        return _mods_node.get_loaded_mod_ids()
    return []


func is_mod_loaded(mod_id: String) -> bool:
    return get_loaded_mod_ids().has(mod_id)


func get_loaded_mods() -> Array[Dictionary]:
    if _mods_node and _mods_node.has_method("get_loaded_mods"):
        return _mods_node.get_loaded_mods()
    if _mods_node:
        var raw_loaded = _mods_node.get("loaded_mods")
        if raw_loaded is Array:
            var loaded: Array[Dictionary] = []
            for meta in raw_loaded:
                if meta is Dictionary:
                    loaded.append(meta.duplicate(true))
            return loaded
    return []


func get_failed_mods() -> Array[Dictionary]:
    if _mods_node and _mods_node.has_method("get_failed_mods"):
        return _mods_node.get_failed_mods()
    if _mods_node:
        var raw_failed = _mods_node.get("failed_mods")
        if raw_failed is Array:
            var failed: Array[Dictionary] = []
            for failure in raw_failed:
                if failure is Dictionary:
                    failed.append(failure.duplicate(true))
            return failed
    return []


func get_mod_status(mod_id: String) -> Dictionary:
    if _mods_node and _mods_node.has_method("get_mod_status"):
        return _mods_node.get_mod_status(mod_id)
    return {}


func get_all_mod_statuses() -> Dictionary:
    if _mods_node and _mods_node.has_method("get_all_mod_statuses"):
        return _mods_node.get_all_mod_statuses()
    return {}


func get_mod_errors(mod_id: String) -> Array:
    if _mods_node and _mods_node.has_method("get_mod_errors"):
        return _mods_node.get_mod_errors(mod_id)
    return []


func on_event(event_name: String, target: Object, method_name: String, priority: int = 100, owner_id: String = "") -> bool:
    return _register_method_event(event_name, target, method_name, priority, owner_id, false)


func once_event(event_name: String, target: Object, method_name: String, priority: int = 100, owner_id: String = "") -> bool:
    return _register_method_event(event_name, target, method_name, priority, owner_id, true)


func off_event(event_name: String, target: Object, method_name: String, owner_id: String = "") -> bool:
    if _hooks_node and _hooks_node.has_method("off_event"):
        return _hooks_node.off_event(event_name, target, method_name, owner_id)
    return false


func emit_event(event_name: String, args: Array = []) -> Dictionary:
    return _emit_event_internal(event_name, args, false, {})


func emit_cancellable_event(event_name: String, args: Array = [], control: Dictionary = {}) -> Dictionary:
    return _emit_event_internal(event_name, args, true, control)


func get_available_events() -> Array[String]:
    if _event_adapter_node and _event_adapter_node.has_method("get_available_events"):
        return _event_adapter_node.get_available_events()
    if _hooks_node and _hooks_node.has_method("get_registered_events"):
        return _hooks_node.get_registered_events()
    return []


func play_custom_level_path(path: String, options: Dictionary = {}) -> bool:
    if _campaign_node and _campaign_node.has_method("play_custom_level_path"):
        return _campaign_node.play_custom_level_path(path, options)
    log_warn("Campaign adapter is unavailable; cannot play custom level '%s'" % path)
    return false


func play_custom_sequence(sequence: Array, meta: Dictionary = {}, source_path: String = "") -> bool:
    if _campaign_node and _campaign_node.has_method("play_sequence"):
        return _campaign_node.play_sequence(sequence, meta, source_path)
    log_warn("Campaign adapter is unavailable; cannot play custom sequence")
    return false


func get_custom_levels() -> Array:
    if _level_registry_node and _level_registry_node.has_method("get_custom_levels"):
        return _level_registry_node.get_custom_levels()
    return []


func get_game_singleton(singleton_name: String) -> Node:
    var path := String(GAME_SINGLETONS.get(singleton_name, "/root/" + singleton_name))
    return get_node_or_null(path)


func get_event_bus() -> Node:
    return get_game_singleton("EventBus")


func get_game_context() -> Node:
    return get_game_singleton("GameContext")


func get_campaign_manager() -> Node:
    return get_game_singleton("CampaignManager")


func get_game_settings() -> Node:
    return get_game_singleton("GameSettings")


func get_ui_sfx_manager() -> Node:
    return get_game_singleton("UiSfxManager")


func get_game_version() -> String:
    return String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()


func get_game_id() -> String:
    var raw_name := String(ProjectSettings.get_setting("application/config/name", "")).strip_edges().to_lower()
    var normalized := ""
    var previous_was_separator := false

    for i in range(raw_name.length()):
        var ch := raw_name[i]
        var is_alnum := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
        if is_alnum:
            normalized += ch
            previous_was_separator = false
        elif not previous_was_separator and not normalized.is_empty():
            normalized += "_"
            previous_was_separator = true

    return normalized.trim_suffix("_")


func play_ui_click() -> void:
    var sfx := get_ui_sfx_manager()
    if sfx and sfx.has_method("play_click"):
        sfx.play_click()


func _register_method_event(event_name: String, target: Object, method_name: String, priority: int, owner_id: String, once: bool) -> bool:
    if _hooks_node and _hooks_node.has_method("on_event"):
        return _hooks_node.on_event(event_name, target, method_name, priority, owner_id, once)
    log_warn("Event hook runtime is unavailable; could not register '%s'" % event_name)
    return false


func _register_callable_event(event_name: String, callback: Callable, options: Dictionary, once: bool) -> bool:
    var callable_parts := _callable_parts(callback)
    if callable_parts.is_empty():
        log_warn("Ignoring invalid callable hook registration for '%s'" % event_name)
        return false

    var priority := int(options.get("priority", 100))
    var owner_id := String(options.get("owner_id", options.get("mod_id", ""))).strip_edges()
    return _register_method_event(
        event_name,
        callable_parts.get("target"),
        String(callable_parts.get("method", "")),
        priority,
        owner_id,
        once or bool(options.get("once", false))
    )


func _unregister_callable_event(event_name: String, callback: Callable, owner_id: String = "") -> bool:
    var callable_parts := _callable_parts(callback)
    if callable_parts.is_empty():
        return false
    return off_event(event_name, callable_parts.get("target"), String(callable_parts.get("method", "")), owner_id)


func _callable_parts(callback: Callable) -> Dictionary:
    var target = callback.get_object()
    var method_name := String(callback.get_method())
    if target == null or method_name.is_empty():
        return {}
    return {
        "target": target,
        "method": method_name
    }


func _emit_event_internal(event_name: String, args: Array, cancellable: bool, control: Dictionary) -> Dictionary:
    if _hooks_node == null:
        log_warn("Event hook runtime is unavailable; could not emit '%s'" % event_name)
        return {
            "event_name": event_name,
            "invoked": 0,
            "cancelled": false,
            "stopped": false,
            "failures": [],
            "control": control.duplicate(true)
        }

    if cancellable and _hooks_node.has_method("emit_cancellable_event"):
        return _hooks_node.emit_cancellable_event(event_name, args, control)
    if _hooks_node.has_method("emit_event"):
        return _hooks_node.emit_event(event_name, args)
    return {
        "event_name": event_name,
        "invoked": 0,
        "cancelled": false,
        "stopped": false,
        "failures": [],
        "control": control.duplicate(true)
    }


func _emit_event_payload(event_name: String, payload, cancellable: bool, control: Dictionary) -> Dictionary:
    return _emit_event_internal(event_name, _payload_to_args(payload), cancellable, control)


func _payload_to_args(payload) -> Array:
    if payload == null:
        return []
    if payload is Array:
        return payload.duplicate(true)
    return [payload]


func _load_asset(path: String, use_cache: bool = true):
    var clean := path.strip_edges()
    if clean.is_empty():
        return null
    if use_cache and _asset_cache.has(clean):
        return _asset_cache[clean]

    var resource = load(clean)
    if resource != null and use_cache:
        _asset_cache[clean] = resource
    elif resource == null:
        log_warn("Could not load asset '%s'" % clean)
    return resource


func _resolve_mod_root(meta: Dictionary) -> String:
    var kind := String(meta.get("kind", "")).to_lower()
    var path := String(meta.get("path", ""))
    if kind == "folder" and not path.is_empty():
        return path.trim_suffix("/")
    var mod_id := String(meta.get("id", "")).strip_edges()
    if mod_id.is_empty():
        log_warn("Cannot resolve mod root: meta has neither 'path' (folder) nor 'id'")
        return ""
    return "res://mods".path_join(mod_id)


func _resolve_mod_relative(meta: Dictionary, relative: String) -> String:
    var rel := relative.strip_edges()
    if rel.begins_with("res://") or rel.begins_with("user://") or rel.begins_with("/"):
        return rel
    var root := _resolve_mod_root(meta)
    if root.is_empty():
        return ""
    if rel.is_empty():
        return root
    return root.path_join(rel)


func _load_mod_text(meta: Dictionary, relative: String) -> String:
    var path := _resolve_mod_relative(meta, relative)
    if path.is_empty():
        return ""
    if not FileAccess.file_exists(path):
        log_warn("Mod text file not found: %s" % path)
        return ""
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        log_warn("Cannot open mod text file: %s" % path)
        return ""
    var contents := f.get_as_text()
    f.close()
    return contents


func _load_mod_resource(meta: Dictionary, relative: String, use_cache: bool = true):
    var path := _resolve_mod_relative(meta, relative)
    if path.is_empty():
        return null
    return _load_asset(path, use_cache)


func _apply_script_extension(meta: Dictionary, ext_relative: String, target_res_path: String) -> bool:
    var target_path := _normalize_resource_path(target_res_path)
    if target_path.is_empty() or not SCRIPT_EXTENSION_TARGETS.has(target_path):
        log_error("script_extension: target '%s' is not an approved extension point" % target_res_path)
        return false

    var mod_id := String(meta.get("id", "")).strip_edges()
    var allowed_mods: Array = SCRIPT_EXTENSION_TARGETS.get(target_path, [])
    if not allowed_mods.is_empty() and not allowed_mods.has(mod_id):
        log_error("script_extension: mod '%s' cannot extend '%s'" % [mod_id, target_path])
        return false

    if not bool(meta.get("core", false)) and not _meta_has_permission(meta, "patching"):
        log_error("script_extension: mod '%s' must declare the 'patching' permission" % mod_id)
        return false

    var ext_path := _resolve_mod_relative_confined(meta, ext_relative)
    if ext_path.is_empty():
        return false
    var script: Script = load(ext_path)
    if script == null:
        log_error("script_extension: failed to load '%s'" % ext_path)
        return false
    script.take_over_path(target_path)
    log_info("script_extension: %s -> %s" % [ext_path, target_path])
    return true


func _normalize_resource_path(path: String) -> String:
    var clean := path.strip_edges().replace("\\", "/")
    if clean.is_empty() or not clean.begins_with("res://"):
        return ""
    for segment in clean.split("/"):
        if segment == "..":
            return ""
    return clean


func _resolve_mod_relative_confined(meta: Dictionary, relative: String) -> String:
    var rel := relative.strip_edges().replace("\\", "/")
    if rel.is_empty() or rel.begins_with("res://") or rel.begins_with("user://") or rel.begins_with("/"):
        log_error("script_extension: extension source must be relative to the mod")
        return ""
    for segment in rel.split("/"):
        if segment == "..":
            log_error("script_extension: extension source must not contain '..'")
            return ""

    var root := _resolve_mod_root(meta)
    if root.is_empty():
        return ""
    var path := root.path_join(rel)
    if not _path_is_inside(path, root):
        log_error("script_extension: extension source escaped the mod root")
        return ""
    return path


func _path_is_inside(path: String, root: String) -> bool:
    var clean_path := path.strip_edges().replace("\\", "/")
    var clean_root := root.strip_edges().replace("\\", "/").trim_suffix("/")
    return clean_path == clean_root or clean_path.begins_with(clean_root + "/")


func _meta_has_permission(meta: Dictionary, permission: String) -> bool:
    var permissions: Array = meta.get("permissions", [])
    return permissions.has(permission)


func _clear_asset_cache(path: String = "") -> void:
    var clean := path.strip_edges()
    if clean.is_empty():
        _asset_cache.clear()
        return
    _asset_cache.erase(clean)


# Reject section names / keys containing characters that would corrupt the
# ConfigFile on disk or let one mod write into another's section. Mirrors the
# loader's mod-id charset (lowercase + digits + . _ -) but is permissive about
# case for keys (mods may use camelCase keys).
func _is_valid_save_id(s: String) -> bool:
    if s.is_empty() or s.length() > 128:
        return false
    for i in range(s.length()):
        var ch := s[i]
        var ok := (ch >= "a" and ch <= "z") \
            or (ch >= "A" and ch <= "Z") \
            or (ch >= "0" and ch <= "9") \
            or ch == "." or ch == "_" or ch == "-"
        if not ok:
            return false
    return true


func _get_save_value(mod_id: String, key: String, fallback = null):
    if not _is_valid_save_id(mod_id) or not _is_valid_save_id(key):
        log_warn("api.saves.get_data: rejected unsafe section/key '%s' / '%s'" % [mod_id, key])
        return fallback
    return _save_config.get_value(mod_id, key, fallback)


func _set_save_value(mod_id: String, key: String, value) -> void:
    if not _is_valid_save_id(mod_id) or not _is_valid_save_id(key):
        log_warn("api.saves.set_data: rejected unsafe section/key '%s' / '%s'" % [mod_id, key])
        return
    _save_config.set_value(mod_id, key, value)
    _save_config.save(SAVE_DATA_PATH)


func _get_mod_save_data(mod_id: String) -> Dictionary:
    var data := {}
    if not _is_valid_save_id(mod_id):
        log_warn("api.saves.get_mod_data: rejected unsafe mod_id '%s'" % mod_id)
        return data
    if not _save_config.has_section(mod_id):
        return data
    for key in _save_config.get_section_keys(mod_id):
        data[String(key)] = _save_config.get_value(mod_id, key)
    return data


func _erase_save_value(mod_id: String, key: String = "") -> void:
    if not _is_valid_save_id(mod_id):
        log_warn("api.saves.erase_data: rejected unsafe mod_id '%s'" % mod_id)
        return
    if key.strip_edges().is_empty():
        _save_config.erase_section(mod_id)
    else:
        if not _is_valid_save_id(key):
            log_warn("api.saves.erase_data: rejected unsafe key '%s'" % key)
            return
        _save_config.erase_section_key(mod_id, key)
    _save_config.save(SAVE_DATA_PATH)


func log_info(message: String) -> void:
    if logger and logger.has_method("info"):
        logger.info(message)
    else:
        print("[ESP] ", message)


func log_warn(message: String) -> void:
    if logger and logger.has_method("warn"):
        logger.warn(message)
    else:
        push_warning("[ESP] " + message)


func log_error(message: String) -> void:
    if logger and logger.has_method("error"):
        logger.error(message)
    else:
        push_error("[ESP] " + message)
