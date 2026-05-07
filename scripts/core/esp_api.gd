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

var mods
var settings
var hooks
var events
var game
var campaign
var assets
var saves

var _mods_node: Node
var _settings_node: Node
var _settings_registry_node: Node
var _level_registry_node: Node
var _hooks_node: Node
var _event_adapter_node: Node
var _campaign_node: Node
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

    _save_config.load(SAVE_DATA_PATH)

    mods = ModsNamespace.new(self)
    settings = SettingsNamespace.new(self)
    hooks = HooksNamespace.new(self)
    events = EventsNamespace.new(self)
    game = GameNamespace.new(self)
    campaign = CampaignNamespace.new(self)
    assets = AssetsNamespace.new(self)
    saves = SavesNamespace.new(self)


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


func _clear_asset_cache(path: String = "") -> void:
    var clean := path.strip_edges()
    if clean.is_empty():
        _asset_cache.clear()
        return
    _asset_cache.erase(clean)


func _get_save_value(mod_id: String, key: String, fallback = null):
    return _save_config.get_value(mod_id, key, fallback)


func _set_save_value(mod_id: String, key: String, value) -> void:
    _save_config.set_value(mod_id, key, value)
    _save_config.save(SAVE_DATA_PATH)


func _get_mod_save_data(mod_id: String) -> Dictionary:
    var data := {}
    if not _save_config.has_section(mod_id):
        return data
    for key in _save_config.get_section_keys(mod_id):
        data[String(key)] = _save_config.get_value(mod_id, key)
    return data


func _erase_save_value(mod_id: String, key: String = "") -> void:
    if key.strip_edges().is_empty():
        _save_config.erase_section(mod_id)
    else:
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
