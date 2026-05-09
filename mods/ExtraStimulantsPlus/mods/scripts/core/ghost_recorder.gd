extends Node

# GhostRecorder captures player movement and rotation for replay purposes.
# Binary frames live under user://esp_features/ghosts/<level_id>.soghost; recording
# metadata (last-recorded timestamps, retention bookkeeping) goes through api.saves.

const MOD_ID := "esp_features"
const GHOST_DIR := "user://esp_features/ghosts"
# Pre-namespacing location; load_ghost_data falls back here so recordings made
# before the rename remain visible.
const LEGACY_GHOST_DIR := "user://ghosts"

var _api: Node
var _meta: Dictionary

var is_recording: bool = false
var _current_data: PackedFloat32Array = PackedFloat32Array()
var _current_level_id: String = ""
var _frame_counter: int = 0

func configure(api: Node, meta: Dictionary) -> void:
    _api = api
    _meta = meta

func _ready() -> void:
    if _api == null:
        _api = get_node_or_null("/root/ESP")
    _ensure_ghost_dir()

    if _api and _api.events:
        _api.events.on("level_started", Callable(self, "_on_level_started"), {"owner_id": MOD_ID})
        _api.events.on("level_completed", Callable(self, "_on_level_completed"), {"owner_id": MOD_ID})
        _api.events.on("player_died", Callable(self, "_on_player_died"), {"owner_id": MOD_ID})

func _on_level_started(level_id = null, _b = null) -> void:
    if not _get_bool("gameplay.ghost.enabled", true):
        return
    _current_level_id = String(level_id) if level_id != null else ""
    start_recording()

func _on_level_completed(_a = null, _b = null) -> void:
    if is_recording:
        stop_recording(_current_level_id)

func _on_player_died(_a = null, _b = null) -> void:
    # Discard a death-run rather than overwrite a successful ghost.
    is_recording = false
    _current_data.clear()

func start_recording():
    _current_data.clear()
    _frame_counter = 0
    is_recording = true

func stop_recording(level_id: String):
    is_recording = false
    if _current_data.size() > 0 and not level_id.is_empty():
        _save_ghost(level_id)

func _process(_delta):
    if not is_recording: return

    var record_interval := clampi(_get_int("gameplay.ghost.record_interval", 3), 1, 30)
    _frame_counter += 1
    if _frame_counter % record_interval != 0: return

    var player = _find_player()
    if player:
        var t = Time.get_ticks_msec() / 1000.0
        _current_data.append(t)
        _current_data.append(player.global_position.x)
        _current_data.append(player.global_position.y)
        _current_data.append(player.global_position.z)
        _current_data.append(player.global_rotation.x)
        _current_data.append(player.global_rotation.y)
        _current_data.append(player.global_rotation.z)

func _find_player() -> Node3D:
    var game = get_tree().root.find_child("Game", true, false)
    if game:
        return game.find_child("Player", true, false)
    return get_tree().root.find_child("Player", true, false) as Node3D

func _ensure_ghost_dir() -> void:
    if not DirAccess.dir_exists_absolute(GHOST_DIR):
        DirAccess.make_dir_recursive_absolute(GHOST_DIR)

func _save_ghost(level_id: String):
    _ensure_ghost_dir()
    var safe_id := level_id.validate_filename()
    var path := GHOST_DIR.path_join(safe_id + ".soghost")
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_var(_current_data)
        file.close()
        if _api and _api.saves:
            _api.saves.set_data(MOD_ID, "ghost_last_recorded_" + safe_id,
                Time.get_unix_time_from_system())
        if _api and _api.has_method("log_info"):
            _api.log_info("[GhostRecorder] saved %d frames for %s" % [_current_data.size() / 7, safe_id])

func load_ghost_data(level_id: String) -> PackedFloat32Array:
    var safe_id := level_id.validate_filename()
    var paths := [
        GHOST_DIR.path_join(safe_id + ".soghost"),
        LEGACY_GHOST_DIR.path_join(safe_id + ".soghost"),
    ]
    for path in paths:
        if FileAccess.file_exists(path):
            var file := FileAccess.open(path, FileAccess.READ)
            if file:
                var data = file.get_var()
                file.close()
                if data is PackedFloat32Array:
                    return data
    return PackedFloat32Array()

func _get_bool(key: String, fallback: bool) -> bool:
    if _api == null or _api.settings == null:
        return fallback
    var v = _api.settings.get(MOD_ID, key, fallback)
    return bool(v) if v != null else fallback

func _get_int(key: String, fallback: int) -> int:
    if _api == null or _api.settings == null:
        return fallback
    var v = _api.settings.get(MOD_ID, key, fallback)
    return int(v) if v != null else fallback
