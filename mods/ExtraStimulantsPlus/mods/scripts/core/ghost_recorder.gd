extends Node

# GhostRecorder captures player movement and rotation for replay purposes.
# Data is saved to user://ghosts/<level_id>.soghost

var is_recording: bool = false
var _current_data: PackedFloat32Array = PackedFloat32Array()
var _frame_counter: int = 0
const RECORD_INTERVAL = 3 # Record every 3 frames

func start_recording():
    _current_data.clear()
    _frame_counter = 0
    is_recording = true
    print("GhostRecorder: Started recording...")

func stop_recording(level_id: String):
    is_recording = false
    if _current_data.size() > 0:
        _save_ghost(level_id)
    print("GhostRecorder: Stopped recording. Captured ", _current_data.size() / 7, " frames.")

func _process(_delta):
    if not is_recording: return
    
    _frame_counter += 1
    if _frame_counter % RECORD_INTERVAL != 0: return
    
    var player = _find_player()
    if player:
        # Record [Time, Pos.X, Pos.Y, Pos.Z, Rot.X, Rot.Y, Rot.Z]
        # Using 7 floats per keyframe
        var t = Time.get_ticks_msec() / 1000.0
        _current_data.append(t)
        _current_data.append(player.global_position.x)
        _current_data.append(player.global_position.y)
        _current_data.append(player.global_position.z)
        _current_data.append(player.global_rotation.x)
        _current_data.append(player.global_rotation.y)
        _current_data.append(player.global_rotation.z)

func _find_player() -> Node3D:
    # Sensory Overload usually has a Player node in the root or under Game
    var game = get_tree().root.find_child("Game", true, false)
    if game:
        return game.find_child("Player", true, false)
    return get_tree().root.find_child("Player", true, false) as Node3D

func _save_ghost(level_id: String):
    var dir = DirAccess.open("user://")
    if not dir.dir_exists("ghosts"):
        dir.make_dir("ghosts")
        
    var path = "user://ghosts/" + level_id.validate_filename() + ".soghost"
    var file = FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_var(_current_data)
        file.close()
        print("GhostRecorder: Saved ghost to ", path)

func load_ghost_data(level_id: String) -> PackedFloat32Array:
    var path = "user://ghosts/" + level_id.validate_filename() + ".soghost"
    if FileAccess.file_exists(path):
        var file = FileAccess.open(path, FileAccess.READ)
        if file:
            var data = file.get_var()
            file.close()
            if data is PackedFloat32Array:
                return data
    return PackedFloat32Array()
