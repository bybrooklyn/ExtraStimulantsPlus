extends Node

# ESP Settings Registry - Framework Owned
# Manages mod-specific settings and provides persistence.

signal setting_changed(mod_id: String, key: String, value: Variant)
signal setting_registered(mod_id: String, key: String, data: Dictionary)

const CONFIG_PATH := "user://esp_mod_settings.cfg"

var _registry: Dictionary = {} # { mod_id: { key: { type, default, options, value } } }
var _config: ConfigFile = ConfigFile.new()

func _ready() -> void:
    _config.load(CONFIG_PATH)

func register(mod_id: String, key: String, type: int, default: Variant, options: Dictionary = {}) -> void:
    if not _registry.has(mod_id):
        _registry[mod_id] = {}
        
    var saved_value = _config.get_value(mod_id, key, default)
    
    _registry[mod_id][key] = {
        "type": type,
        "default": default,
        "options": options,
        "value": saved_value
    }
    setting_registered.emit(mod_id, key, _registry[mod_id][key].duplicate(true))

func get_value(mod_id: String, key: String) -> Variant:
    if _registry.has(mod_id) and _registry[mod_id].has(key):
        return _registry[mod_id][key]["value"]
    return null

func set_value(mod_id: String, key: String, value: Variant) -> void:
    if _registry.has(mod_id) and _registry[mod_id].has(key):
        _registry[mod_id][key]["value"] = value
        _config.set_value(mod_id, key, value)
        _config.save(CONFIG_PATH)
        setting_changed.emit(mod_id, key, value)

func get_all_settings() -> Dictionary:
    return _registry.duplicate(true)
