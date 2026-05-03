extends Node


const MIN_SEGMENT_SEC: = 0.05

var _screen: String = ""
var _segment_start_sec: float = 0.0
var _settings_open: bool = false
var _settings_start_sec: float = 0.0
var _base_before_settings: String = ""
var _session_start_sent: bool = false
var _navigation_path: Array[Dictionary] = []

func _ready() -> void :
    _segment_start_sec = _now_sec()
    EventBus.game_state_changed.connect(_on_game_state_changed)

    call_deferred("_emit_session_start")

func _now_sec() -> float:
    return Time.get_ticks_msec() / 1000.0

func _sanitize_screen_id(name: String) -> String:
    var s: = name.strip_edges().replace(" ", "_")
    if s.is_empty():
        s = "Unknown"
    return s

func _ui_map_id(screen_name: String) -> String:
    return "ui_" + _sanitize_screen_id(screen_name)

func _flush_segment(screen_name: String, duration_sec: float) -> void :
    if screen_name.is_empty() or duration_sec < MIN_SEGMENT_SEC:
        return
    _navigation_path.append({
        "screen": screen_name, 
        "duration_sec": snappedf(duration_sec, 0.01), 
        "timestamp": Time.get_datetime_string_from_system(true), 
    })
    var ga: Node = get_parent()
    if ga == null or not ga.has_method("record_anonymous_event"):
        return
    var mid: = _ui_map_id(screen_name)
    ga.record_anonymous_event("ui_screen_time", mid)
    if ga.analytics_consented():
        var ev: = {
            "type": "ui_screen_time", 
            "run_id": "", 
            "map_id": mid, 
            "mode": "ui", 
            "screen_id": screen_name, 
            "session_time_seconds": duration_sec, 
        }
        ev.merge(ga.build_context_dict(), true)
        ga.record_analytics_events([ev], ga.make_uuid_v4() + "_ui_" + mid + "_" + str(randi()))

func _on_game_state_changed(new_state_name: String) -> void :
    if _settings_open:
        _close_settings_segment()
    var now: = _now_sec()
    if not _screen.is_empty():
        _flush_segment(_screen, now - _segment_start_sec)
    _screen = new_state_name
    _segment_start_sec = now

func _close_settings_segment() -> void :
    if not _settings_open:
        return
    var now: = _now_sec()
    _flush_segment("Settings", now - _settings_start_sec)
    _settings_open = false
    _screen = _base_before_settings if not _base_before_settings.is_empty() else "Menu"
    _base_before_settings = ""
    _segment_start_sec = now


func notify_settings_visibility(visible: bool) -> void :
    if visible:
        if _settings_open:
            return
        var now: = _now_sec()
        if not _screen.is_empty():
            _flush_segment(_screen, now - _segment_start_sec)
        _base_before_settings = _screen
        _settings_open = true
        _settings_start_sec = now
        _screen = "Settings"
        _segment_start_sec = now
    else:
        if not _settings_open:
            return
        var now: = _now_sec()
        _flush_segment("Settings", now - _settings_start_sec)
        _settings_open = false
        _screen = _base_before_settings if not _base_before_settings.is_empty() else "Menu"
        _base_before_settings = ""
        _segment_start_sec = now


func _emit_session_start() -> void :
    if _session_start_sent:
        return
    _session_start_sent = true
    var ga: Node = get_parent()
    if ga and ga.has_method("record_session_start"):
        ga.record_session_start()


func _notification(what: int) -> void :
    match what:
        NOTIFICATION_WM_CLOSE_REQUEST:
            var ga: Node = get_parent()
            if ga and ga.has_method("record_session_end"):
                ga.record_session_end()
        NOTIFICATION_APPLICATION_FOCUS_IN:
            var ga: Node = get_parent()
            if ga and ga.has_method("record_app_focus_change"):
                ga.record_app_focus_change(true)
        NOTIFICATION_APPLICATION_FOCUS_OUT:
            var ga: Node = get_parent()
            if ga and ga.has_method("record_app_focus_change"):
                ga.record_app_focus_change(false)


func get_navigation_path() -> Array[Dictionary]:

    if not _screen.is_empty():
        var now: = _now_sec()
        var dur: = now - _segment_start_sec
        if dur >= MIN_SEGMENT_SEC:
            _navigation_path.append({
                "screen": _screen, 
                "duration_sec": snappedf(dur, 0.01), 
                "timestamp": Time.get_datetime_string_from_system(true), 
            })
    return _navigation_path
