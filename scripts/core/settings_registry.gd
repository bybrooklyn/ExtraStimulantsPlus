extends Node

# ESP Settings Registry - Framework Owned
# Manages mod-specific settings and provides persistence.

signal setting_changed(mod_id: String, key: String, value: Variant)
signal setting_registered(mod_id: String, key: String, data: Dictionary)

const CONFIG_PATH := "user://esp_mod_settings.cfg"
const SAVE_DEBOUNCE_SEC := 0.25

var _registry: Dictionary = {} # { mod_id: { key: { type, default, options, value } } }
var _config: ConfigFile = ConfigFile.new()
var _save_timer: Timer
var _save_pending: bool = false

func _ready() -> void:
    _config.load(CONFIG_PATH)
    _save_timer = Timer.new()
    _save_timer.one_shot = true
    _save_timer.wait_time = SAVE_DEBOUNCE_SEC
    _save_timer.timeout.connect(_on_save_timeout)
    add_child(_save_timer)

func _exit_tree() -> void:
    flush()

func register(mod_id: String, key: String, type: int, default: Variant, options: Dictionary = {}) -> void:
    if not _registry.has(mod_id):
        _registry[mod_id] = {}

    var saved_value = _config.get_value(mod_id, key, default)
    # If the stored type doesn't match the declared type (e.g. a mod changed
    # the setting's type between versions), drop the stored value rather than
    # silently coercing — coercion can produce surprising defaults.
    if saved_value != null and typeof(saved_value) != type:
        push_warning("[ESPSettingsRegistry] %s.%s: stored type %d != declared type %d, resetting to default" % [mod_id, key, typeof(saved_value), type])
        saved_value = default

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
        _schedule_save()
        setting_changed.emit(mod_id, key, value)

func get_all_settings() -> Dictionary:
    return _registry.duplicate(true)

# Force any pending debounced write to disk immediately. Called on tree exit
# and from settings UIs that close (e.g. the in-game settings menu).
func flush() -> void:
    if _save_pending:
        _save_pending = false
        if is_instance_valid(_save_timer):
            _save_timer.stop()
        _config.save(CONFIG_PATH)

func _schedule_save() -> void:
    _save_pending = true
    if is_instance_valid(_save_timer):
        _save_timer.start(SAVE_DEBOUNCE_SEC)

func _on_save_timeout() -> void:
    if _save_pending:
        _save_pending = false
        _config.save(CONFIG_PATH)
