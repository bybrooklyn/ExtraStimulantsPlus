extends Node

# MutatorManager — gameplay modifiers driven by the gameplay.mutators.* settings.
#
# Mirror Mode: swaps the InputMap events for move_left and move_right. Stored
# original events are restored on disable. This is the InputMap-remap path
# (chosen over a script extension since it doesn't require visibility into
# the game source). If the actions don't exist, the swap is a no-op.
#
# Turbo Mode: sets Engine.time_scale = 1.2 while a level is active and the
# toggle is on. Resets to 1.0 on level end so menus aren't sped up.

const MOD_ID := "esp_features"
const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"
const TURBO_TIME_SCALE := 1.2

var _api: Node
var _meta: Dictionary
var _registry: Node
var _level_active: bool = false

var _mirror_active: bool = false
var _orig_left_events: Array = []
var _orig_right_events: Array = []

func configure(api: Node, meta: Dictionary) -> void:
    _api = api
    _meta = meta

func _ready() -> void:
    if _api == null:
        _api = get_node_or_null("/root/ESP")

    if _api and _api.events:
        _api.events.on("level_started", Callable(self, "_on_level_started"), {"owner_id": MOD_ID})
        _api.events.on("level_completed", Callable(self, "_on_level_ended"), {"owner_id": MOD_ID})
        _api.events.on("player_died", Callable(self, "_on_level_ended"), {"owner_id": MOD_ID})

    if _api and _api.settings and _api.settings.has_method("get_registry"):
        _registry = _api.settings.get_registry()
        if _registry and _registry.has_signal("setting_changed"):
            _registry.setting_changed.connect(_on_setting_changed)

    _apply_state()

func _on_level_started(_a = null, _b = null) -> void:
    _level_active = true
    _apply_state()

func _on_level_ended(_a = null, _b = null) -> void:
    _level_active = false
    # Always reset time scale at level boundaries so menus run at normal speed.
    Engine.time_scale = 1.0

func _on_setting_changed(mod_id: String, key: String, _value) -> void:
    if mod_id != MOD_ID:
        return
    if key == "gameplay.mutators.mirror_mode" or key == "gameplay.mutators.turbo_mode":
        _apply_state()

func _apply_state() -> void:
    var want_mirror := _get_bool("gameplay.mutators.mirror_mode", false)
    var want_turbo := _get_bool("gameplay.mutators.turbo_mode", false)

    if want_mirror != _mirror_active:
        if want_mirror:
            _enable_mirror()
        else:
            _disable_mirror()

    Engine.time_scale = TURBO_TIME_SCALE if (want_turbo and _level_active) else 1.0

func _enable_mirror() -> void:
    if not InputMap.has_action(ACTION_LEFT) or not InputMap.has_action(ACTION_RIGHT):
        push_warning("[MutatorManager] InputMap missing %s/%s; Mirror Mode disabled" % [ACTION_LEFT, ACTION_RIGHT])
        return
    _orig_left_events = InputMap.action_get_events(ACTION_LEFT)
    _orig_right_events = InputMap.action_get_events(ACTION_RIGHT)
    InputMap.action_erase_events(ACTION_LEFT)
    InputMap.action_erase_events(ACTION_RIGHT)
    for ev in _orig_right_events:
        InputMap.action_add_event(ACTION_LEFT, ev)
    for ev in _orig_left_events:
        InputMap.action_add_event(ACTION_RIGHT, ev)
    _mirror_active = true

func _disable_mirror() -> void:
    if not _mirror_active:
        return
    InputMap.action_erase_events(ACTION_LEFT)
    InputMap.action_erase_events(ACTION_RIGHT)
    for ev in _orig_left_events:
        InputMap.action_add_event(ACTION_LEFT, ev)
    for ev in _orig_right_events:
        InputMap.action_add_event(ACTION_RIGHT, ev)
    _orig_left_events.clear()
    _orig_right_events.clear()
    _mirror_active = false

func _get_bool(key: String, fallback: bool) -> bool:
    if _api == null or _api.settings == null:
        return fallback
    var v = _api.settings.get(MOD_ID, key, fallback)
    return bool(v) if v != null else fallback

func _exit_tree() -> void:
    # Always restore InputMap and time scale so we don't leave the game in a
    # mutated state if the mod is unloaded mid-run.
    _disable_mirror()
    Engine.time_scale = 1.0
