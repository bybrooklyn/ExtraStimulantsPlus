extends Node

# Bridges Sensory Overload's raw EventBus signals into stable ESP hook events.
# Mods should subscribe through /root/ESP.events instead of connecting to /root/EventBus directly.

const GAME_EVENT_MAP: Array[Dictionary] = [
    {"signal": "game_state_changed", "event": "game_state_changed", "argc": 1},
    {"signal": "game_started", "event": "game_started", "argc": 0},
    {"signal": "game_over", "event": "game_over", "argc": 1},
    {"signal": "game_reset", "event": "game_reset", "argc": 0},
    {"signal": "level_started", "event": "level_started", "argc": 2},
    {"signal": "level_completed", "event": "level_completed", "argc": 0},
    {"signal": "difficulty_increased", "event": "difficulty_increased", "argc": 2},
    {"signal": "speed_changed", "event": "speed_changed", "argc": 1},
    {"signal": "tunnel_moved", "event": "tunnel_moved", "argc": 1},
    {"signal": "origin_shifted", "event": "origin_shifted", "argc": 1},
    {"signal": "chunk_spawned", "event": "chunk_spawned", "argc": 1},
    {"signal": "chunk_recycled", "event": "chunk_recycled", "argc": 1},
    {"signal": "player_died", "event": "player_died", "argc": 0},
    {"signal": "player_moved", "event": "player_moved", "argc": 1},
    {"signal": "shield_restoration_requested", "event": "shield_restoration_requested", "argc": 1},
    {"signal": "obstacle_hit", "event": "obstacle_hit", "argc": 1},
    {"signal": "obstacle_passed", "event": "obstacle_passed", "argc": 1},
    {"signal": "score_updated", "event": "score_updated", "argc": 1},
    {"signal": "vfx_hit", "event": "vfx_hit", "argc": 2},
    {"signal": "vfx_graze", "event": "vfx_graze", "argc": 2},
    {"signal": "invincibility_pulse_fired", "event": "invincibility_pulse_fired", "argc": 1},
    {"signal": "death_sequence_finished", "event": "death_sequence_finished", "argc": 0},
    {"signal": "vfx_clutch", "event": "vfx_clutch", "argc": 1},
    {"signal": "vfx_boost", "event": "vfx_boost", "argc": 1},
    {"signal": "vfx_proximity", "event": "vfx_proximity", "argc": 1},
    {"signal": "hit_stop_started", "event": "hit_stop_started", "argc": 1},
    {"signal": "hit_stop_ended", "event": "hit_stop_ended", "argc": 0},
    {"signal": "beat_lights_changed", "event": "beat_lights_changed", "argc": 1},
    {"signal": "beat_walls_changed", "event": "beat_walls_changed", "argc": 1},
    {"signal": "beat_obstacles_changed", "event": "beat_obstacles_changed", "argc": 1},
    {"signal": "tutorial_section_started", "event": "tutorial_section_started", "argc": 2},
    {"signal": "tutorial_objective_progress", "event": "tutorial_objective_progress", "argc": 3},
    {"signal": "tutorial_section_completed", "event": "tutorial_section_completed", "argc": 1},
    {"signal": "tutorial_section_failed", "event": "tutorial_section_failed", "argc": 1},
    {"signal": "tutorial_all_sections_complete", "event": "tutorial_all_sections_complete", "argc": 0},
    {"signal": "tutorial_prompt_dismissed", "event": "tutorial_prompt_dismissed", "argc": 0},
    {"signal": "music_changed", "event": "music_changed", "argc": 4},
    {"signal": "setting_changed", "event": "game_setting_changed", "argc": 3},
    {"signal": "pause_toggled", "event": "pause_toggled", "argc": 1},
    {"signal": "practice_checkpoint_dropped", "event": "practice_checkpoint_dropped", "argc": 0},
    {"signal": "practice_checkpoint_deleted", "event": "practice_checkpoint_deleted", "argc": 0}
]

var hooks: Node
var logger: Node
var event_bus: Node

var _connected_signals: Dictionary = {}


func configure(parts: Dictionary) -> void:
    hooks = parts.get("hooks", hooks)
    logger = parts.get("logger", logger)
    call_deferred("connect_game_event_bus")


func _ready() -> void:
    call_deferred("connect_game_event_bus")


func connect_game_event_bus() -> void:
    if hooks == null:
        hooks = get_node_or_null("/root/ESPHooks")
    if hooks == null:
        _log_warn("ESPHooks is unavailable; game events cannot be bridged yet")
        return

    event_bus = get_node_or_null("/root/EventBus")
    if event_bus == null:
        _log_warn("/root/EventBus is unavailable; game events cannot be bridged yet")
        return

    for mapping in GAME_EVENT_MAP:
        _connect_signal(mapping)

    _log_info("bridged %d game EventBus signal(s)" % _connected_signals.size())


func get_available_events() -> Array[String]:
    var events: Array[String] = []
    for mapping in GAME_EVENT_MAP:
        events.append(String(mapping.get("event", "")))
    events.sort()
    return events


func get_connected_signals() -> Array[String]:
    var signals: Array[String] = []
    for signal_name in _connected_signals.keys():
        signals.append(String(signal_name))
    signals.sort()
    return signals


func _connect_signal(mapping: Dictionary) -> void:
    var signal_name := String(mapping.get("signal", ""))
    var event_name := String(mapping.get("event", signal_name))
    var argc := int(mapping.get("argc", 0))
    if signal_name.is_empty() or event_name.is_empty():
        return
    if _connected_signals.has(signal_name):
        return
    if not event_bus.has_signal(signal_name):
        _log_warn("EventBus signal '%s' is unavailable; event '%s' disabled" % [signal_name, event_name])
        return

    if argc < 0 or argc > 8:
        _log_warn("EventBus signal '%s' takes %d args; ESP forwarders only handle 0..8 — skipping." % [signal_name, argc])
        return
    var method_name := "_forward_%d" % argc
    var callback := Callable(self, method_name).bind(event_name)
    if not event_bus.is_connected(signal_name, callback):
        var err := event_bus.connect(signal_name, callback)
        if err != OK:
            _log_warn("Failed to connect EventBus.%s to ESP event '%s' (error %d)" % [signal_name, event_name, err])
            return
    _connected_signals[signal_name] = callback


func _forward_0(event_name: String) -> void:
    _emit_esp_event(event_name, [])


func _forward_1(a: Variant, event_name: String) -> void:
    _emit_esp_event(event_name, [a])


func _forward_2(a: Variant, b: Variant, event_name: String) -> void:
    _emit_esp_event(event_name, [a, b])


func _forward_3(a: Variant, b: Variant, c: Variant, event_name: String) -> void:
    _emit_esp_event(event_name, [a, b, c])


func _forward_4(a: Variant, b: Variant, c: Variant, d: Variant, event_name: String) -> void:
    _emit_esp_event(event_name, [a, b, c, d])


func _forward_5(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant, event_name: String) -> void:
    _emit_esp_event(event_name, [a, b, c, d, e])


func _forward_6(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant, f: Variant, event_name: String) -> void:
    _emit_esp_event(event_name, [a, b, c, d, e, f])


func _forward_7(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant, f: Variant, g: Variant, event_name: String) -> void:
    _emit_esp_event(event_name, [a, b, c, d, e, f, g])


func _forward_8(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant, f: Variant, g: Variant, h: Variant, event_name: String) -> void:
    _emit_esp_event(event_name, [a, b, c, d, e, f, g, h])


func _emit_esp_event(event_name: String, args: Array) -> void:
    if hooks and hooks.has_method("emit_event"):
        hooks.emit_event(event_name, args)


func _log_info(message: String) -> void:
    if logger and logger.has_method("info"):
        logger.info("[EventAdapter] " + message)
    else:
        print("[ESP EventAdapter] ", message)


func _log_warn(message: String) -> void:
    if logger and logger.has_method("warn"):
        logger.warn("[EventAdapter] " + message)
    else:
        push_warning("[ESP EventAdapter] " + message)
