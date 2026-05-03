extends Node

signal settings_changed

const CONFIG_PATH: = "user://extra_stimulants_plus.cfg"
const SECTION_UI: = "ui"
const KEY_SHOW_VERSION_BADGE: = "show_version_badge"
const KEY_SHOW_MOD_STATUS: = "show_mod_status"
const KEY_PREFER_SOMAP: = "prefer_somap"
const SECTION_GAMEPLAY: = "gameplay"
const KEY_REACTIVITY_INTENSITY: = "reactivity_intensity"
const KEY_DEFORMATION_REACTIVITY: = "deformation_reactivity"

var _config: ConfigFile = ConfigFile.new()


func _ready() -> void:
    _config.load(CONFIG_PATH)
    _ensure_defaults()


func _ensure_defaults() -> void:
    var changed: bool = false
    changed = _ensure_default(SECTION_UI, KEY_SHOW_VERSION_BADGE, true) or changed
    changed = _ensure_default(SECTION_UI, KEY_SHOW_MOD_STATUS, true) or changed
    changed = _ensure_default(SECTION_UI, KEY_PREFER_SOMAP, true) or changed
    changed = _ensure_default(SECTION_UI, KEY_SHOW_EDITOR_ENTRY, true) or changed
    
    changed = _ensure_default(SECTION_GAMEPLAY, KEY_REACTIVITY_INTENSITY, 0.5) or changed
    changed = _ensure_default(SECTION_GAMEPLAY, KEY_DEFORMATION_REACTIVITY, true) or changed
    
    if changed:
        save()


func _ensure_default(section: String, key: String, value: Variant) -> bool:
    if _config.has_section_key(section, key):
        return false
    _config.set_value(section, key, value)
    return true


func save() -> void:
    _config.save(CONFIG_PATH)
    settings_changed.emit()


func get_reactivity_intensity() -> float:
    return _config.get_value(SECTION_GAMEPLAY, KEY_REACTIVITY_INTENSITY, 0.5)


func set_reactivity_intensity(value: float) -> void:
    _config.set_value(SECTION_GAMEPLAY, KEY_REACTIVITY_INTENSITY, clampf(value, 0.0, 1.0))
    save()


func is_deformation_reactivity_enabled() -> bool:
    return _config.get_value(SECTION_GAMEPLAY, KEY_DEFORMATION_REACTIVITY, true)


func set_deformation_reactivity(enabled: bool) -> void:
    _config.set_value(SECTION_GAMEPLAY, KEY_DEFORMATION_REACTIVITY, enabled)
    save()


func should_show_version_badge() -> bool:
    return _config.get_value(SECTION_UI, KEY_SHOW_VERSION_BADGE, true)


func set_show_version_badge(enabled: bool) -> void:
    _config.set_value(SECTION_UI, KEY_SHOW_VERSION_BADGE, enabled)
    save()


func should_show_mod_status() -> bool:
    return _config.get_value(SECTION_UI, KEY_SHOW_MOD_STATUS, true)


func set_show_mod_status(enabled: bool) -> void:
    _config.set_value(SECTION_UI, KEY_SHOW_MOD_STATUS, enabled)
    save()


func prefers_somap() -> bool:
    return _config.get_value(SECTION_UI, KEY_PREFER_SOMAP, true)


func set_prefer_somap(enabled: bool) -> void:
    _config.set_value(SECTION_UI, KEY_PREFER_SOMAP, enabled)
    save()


func should_show_editor_entry() -> bool:
    return _config.get_value(SECTION_UI, KEY_SHOW_EDITOR_ENTRY, true)


func set_show_editor_entry(enabled: bool) -> void:
    _config.set_value(SECTION_UI, KEY_SHOW_EDITOR_ENTRY, enabled)
    save()


func get_version() -> String:
    if not FileAccess.file_exists("res://VERSION"):
        return "v0.0.1"
    var file: FileAccess = FileAccess.open("res://VERSION", FileAccess.READ)
    if file == null:
        return "v0.0.1"
    var version: String = file.get_as_text().strip_edges()
    file.close()
    return version if not version.is_empty() else "v0.0.1"
