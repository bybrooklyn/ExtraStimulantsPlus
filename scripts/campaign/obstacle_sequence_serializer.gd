class_name ObstacleSequenceSerializer
extends RefCounted






const FORMAT_VERSION: = 2
const SOMAP_MAGIC: = "EXTRASTIMULANTSPLUS_SOMAP"
const SOMAP_VERSION: = "v0.0.1"


const DEFAULTS: = {
    "cruise_gap_sec": 1.0, 
    "ring_position": 0, 
    "type_id": "cross_wall", 
    "starting_angle": -1.0, 
    "rotation_speed": 0.0, 
    "rotation_cw": true, 
    "swing_amplitude": 0.0, 
    "swing_speed": 1.0, 
    "swing_phase": 0.0, 
    "slide_angle": 0.0, 
    "slide_speed": 1.0, 
    "slide_amplitude": 0.0, 
    "slide_phase": 0.0, 
    "pulse_axis": 0, 
    "pulse_speed": 1.0, 
    "pulse_amplitude": 0.0, 
    "pulse_phase": 0.0, 



    "swap_period_sec": 0.0, 
    "swap_phase_sec": 0.0, 
    "color_mode": 0, 
    "custom_color": Color.WHITE, 
}


const KEY_MAP: = {
    "t": "type_id", 
    "g": "cruise_gap_sec", 
    "r": "ring_position", 
    "sa": "starting_angle", 
    "rs": "rotation_speed", 
    "rc": "rotation_cw", 
    "swa": "swing_amplitude", 
    "sws": "swing_speed", 
    "swp": "swing_phase", 
    "sla": "slide_angle", 
    "sls": "slide_speed", 
    "slam": "slide_amplitude", 
    "slp": "slide_phase", 
    "pa": "pulse_axis", 
    "ps": "pulse_speed", 
    "pam": "pulse_amplitude", 
    "pp": "pulse_phase", 
    "mst": "swap_targets", 
    "msp": "swap_period_sec", 
    "mph": "swap_phase_sec", 
    "cm": "color_mode", 
    "cc": "custom_color", 
}




static func save_to_path(sequence: Array, path: String, meta_data: Dictionary = {}) -> bool:
    if path.get_extension().to_lower() == "somap":
        return save_to_somap(sequence, path, meta_data)
    return save_to_json(sequence, path, meta_data)


static func load_from_path(path: String) -> Array:
    if path.get_extension().to_lower() == "somap":
        return load_from_somap(path)
    return load_from_json(path)


static func load_metadata_from_path(path: String) -> Dictionary:
    if path.get_extension().to_lower() == "somap":
        return load_metadata_from_somap(path)
    return load_metadata_from_json(path)


static func save_to_json(sequence: Array, path: String, meta_data: Dictionary = {}) -> bool:
    if sequence.is_empty():
        push_warning("ObstacleSequenceSerializer: Cannot save empty sequence to '%s'" % path)
        return false


    var dir_path: = path.get_base_dir()
    if not _ensure_directory(dir_path):
        return false


    var obstacles: Array = []
    for entry in sequence:
        if entry is ScriptedObstacleEntry:
            obstacles.append(serialize_compact(entry))
        else:
            push_warning("ObstacleSequenceSerializer: Skipping non-ScriptedObstacleEntry in sequence")

    var json_data: = _build_payload(obstacles, meta_data)


    var file: = FileAccess.open(path, FileAccess.WRITE)
    if not file:
        push_error("ObstacleSequenceSerializer: Could not write to '%s'" % path)
        return false

    file.store_string(JSON.stringify(json_data, "\t"))
    file.close()

    print("ObstacleSequenceSerializer: Saved %d obstacles to %s" % [obstacles.size(), path])
    return true


static func save_to_somap(sequence: Array, path: String, meta_data: Dictionary = {}) -> bool:
    if sequence.is_empty():
        push_warning("ObstacleSequenceSerializer: Cannot save empty .somap to '%s'" % path)
        return false

    var dir_path: = path.get_base_dir()
    if not _ensure_directory(dir_path):
        return false

    var obstacles: Array = []
    for entry in sequence:
        if entry is ScriptedObstacleEntry:
            obstacles.append(serialize_compact(entry))

    var payload_text: String = JSON.stringify(_build_payload(obstacles, meta_data), "\t")
    var file: = FileAccess.open(path, FileAccess.WRITE)
    if not file:
        push_error("ObstacleSequenceSerializer: Could not write to '%s'" % path)
        return false

    file.store_line(SOMAP_MAGIC)
    file.store_line(SOMAP_VERSION)
    file.store_string(payload_text)
    file.close()

    print("ObstacleSequenceSerializer: Exported %d obstacles to %s" % [obstacles.size(), path])
    return true




static func load_from_json(path: String) -> Array:
    return _load_sequence_from_payload(_load_json_payload(path), path)


static func load_from_somap(path: String) -> Array:
    return _load_sequence_from_payload(_load_somap_payload(path), path)




static func serialize_compact(entry: ScriptedObstacleEntry) -> Dictionary:
    var dict: = {}





    dict["t"] = entry.type_id
    dict["g"] = entry.cruise_gap_sec


    if entry.starting_angle != DEFAULTS["starting_angle"]:
        dict["sa"] = entry.starting_angle

    if entry.rotation_speed != DEFAULTS["rotation_speed"]:
        dict["rs"] = entry.rotation_speed

    if entry.rotation_cw != DEFAULTS["rotation_cw"]:
        dict["rc"] = entry.rotation_cw

    if entry.swing_amplitude != DEFAULTS["swing_amplitude"]:
        dict["swa"] = entry.swing_amplitude

    if entry.swing_speed != DEFAULTS["swing_speed"]:
        dict["sws"] = entry.swing_speed

    if entry.swing_phase != DEFAULTS["swing_phase"]:
        dict["swp"] = entry.swing_phase

    if entry.slide_angle != DEFAULTS["slide_angle"]:
        dict["sla"] = entry.slide_angle

    if entry.slide_speed != DEFAULTS["slide_speed"]:
        dict["sls"] = entry.slide_speed

    if entry.slide_amplitude != DEFAULTS["slide_amplitude"]:
        dict["slam"] = entry.slide_amplitude

    if entry.slide_phase != DEFAULTS["slide_phase"]:
        dict["slp"] = entry.slide_phase

    if entry.pulse_axis != DEFAULTS["pulse_axis"]:
        dict["pa"] = entry.pulse_axis

    if entry.pulse_speed != DEFAULTS["pulse_speed"]:
        dict["ps"] = entry.pulse_speed

    if entry.pulse_amplitude != DEFAULTS["pulse_amplitude"]:
        dict["pam"] = entry.pulse_amplitude

    if entry.pulse_phase != DEFAULTS["pulse_phase"]:
        dict["pp"] = entry.pulse_phase

    if not entry.swap_targets.is_empty():

        var arr: Array = []
        for s in entry.swap_targets:
            arr.append(s)
        dict["mst"] = arr

    if entry.swap_period_sec != DEFAULTS["swap_period_sec"]:
        dict["msp"] = entry.swap_period_sec

    if entry.swap_phase_sec != DEFAULTS["swap_phase_sec"]:
        dict["mph"] = entry.swap_phase_sec

    if entry.color_mode != DEFAULTS["color_mode"]:
        dict["cm"] = entry.color_mode

    if entry.custom_color != DEFAULTS["custom_color"]:

        dict["cc"] = [entry.custom_color.r, entry.custom_color.g, entry.custom_color.b, entry.custom_color.a]

    return dict




static func deserialize(dict: Dictionary) -> ScriptedObstacleEntry:
    if not dict.has("t") or not dict.has("g"):
        push_warning("ObstacleSequenceSerializer: Missing required fields 't' and/or 'g' in obstacle dict")
        return null

    var entry: = ScriptedObstacleEntry.new()


    entry.type_id = dict.get("t", DEFAULTS["type_id"])
    entry.cruise_gap_sec = dict.get("g", DEFAULTS["cruise_gap_sec"])
    entry.ring_position = dict.get("r", DEFAULTS["ring_position"])


    entry.starting_angle = dict.get("sa", DEFAULTS["starting_angle"])
    entry.rotation_speed = dict.get("rs", DEFAULTS["rotation_speed"])
    entry.rotation_cw = dict.get("rc", DEFAULTS["rotation_cw"])
    entry.swing_amplitude = dict.get("swa", DEFAULTS["swing_amplitude"])
    entry.swing_speed = dict.get("sws", DEFAULTS["swing_speed"])
    entry.swing_phase = dict.get("swp", DEFAULTS["swing_phase"])
    entry.slide_angle = dict.get("sla", DEFAULTS["slide_angle"])
    entry.slide_speed = dict.get("sls", DEFAULTS["slide_speed"])
    entry.slide_amplitude = dict.get("slam", DEFAULTS["slide_amplitude"])
    entry.slide_phase = dict.get("slp", DEFAULTS["slide_phase"])
    entry.pulse_axis = dict.get("pa", DEFAULTS["pulse_axis"])
    entry.pulse_speed = dict.get("ps", DEFAULTS["pulse_speed"])
    entry.pulse_amplitude = dict.get("pam", DEFAULTS["pulse_amplitude"])
    entry.pulse_phase = dict.get("pp", DEFAULTS["pulse_phase"])


    if dict.has("mst") and dict["mst"] is Array:
        var pkg: = PackedStringArray()
        for s in dict["mst"]:
            if s is String:
                pkg.append(s)
        entry.swap_targets = pkg
    else:
        entry.swap_targets = PackedStringArray()
    entry.swap_period_sec = dict.get("msp", DEFAULTS["swap_period_sec"])
    entry.swap_phase_sec = dict.get("mph", DEFAULTS["swap_phase_sec"])

    entry.color_mode = dict.get("cm", DEFAULTS["color_mode"])


    if dict.has("cc"):
        var color_array = dict["cc"]
        if color_array is Array and color_array.size() == 4:
            entry.custom_color = Color(color_array[0], color_array[1], color_array[2], color_array[3])
        else:
            entry.custom_color = DEFAULTS["custom_color"]
    else:
        entry.custom_color = DEFAULTS["custom_color"]

    return entry



static func _ensure_directory(dir_path: String) -> bool:
    var dir: = DirAccess.open(dir_path)
    if dir:
        return true


    var parent_path: = dir_path.get_base_dir()
    if not parent_path.is_empty() and parent_path != dir_path:
        if not _ensure_directory(parent_path):
            return false


    var parent_dir: = DirAccess.open(parent_path if not parent_path.is_empty() else "res://")
    if not parent_dir:
        push_error("ObstacleSequenceSerializer: Could not open parent directory '%s'" % parent_path)
        return false

    var err: = parent_dir.make_dir(dir_path.get_file())
    if err != OK:
        push_error("ObstacleSequenceSerializer: Could not create directory '%s' (error %d)" % [dir_path, err])
        return false

    return true


static func load_metadata_from_json(path: String) -> Dictionary:
    var payload: Dictionary = _load_json_payload(path)
    return payload.get("metadata", {})


static func load_metadata_from_somap(path: String) -> Dictionary:
    var payload: Dictionary = _load_somap_payload(path)
    return payload.get("metadata", {})


static func _build_payload(obstacles: Array, meta_data: Dictionary) -> Dictionary:
    return {
        "format_version": FORMAT_VERSION,
        "obstacles": obstacles,
        "metadata": meta_data,
    }


static func _load_json_payload(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_warning("ObstacleSequenceSerializer: JSON file not found at '%s'" % path)
        return {}

    var file: = FileAccess.open(path, FileAccess.READ)
    if not file:
        push_error("ObstacleSequenceSerializer: Could not read from '%s'" % path)
        return {}

    var json_text: = file.get_as_text()
    file.close()

    var json: = JSON.new()
    var error: = json.parse(json_text)
    if error != OK:
        push_error("ObstacleSequenceSerializer: JSON parse error in '%s' at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
        return {}

    if not json.data is Dictionary:
        push_error("ObstacleSequenceSerializer: JSON root is not a Dictionary in '%s'" % path)
        return {}
    return json.data


static func _load_somap_payload(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_warning("ObstacleSequenceSerializer: .somap file not found at '%s'" % path)
        return {}

    var file: = FileAccess.open(path, FileAccess.READ)
    if not file:
        push_error("ObstacleSequenceSerializer: Could not read from '%s'" % path)
        return {}

    var magic: String = file.get_line().strip_edges()
    var _version: String = file.get_line().strip_edges()
    var payload_text: String = file.get_as_text()
    file.close()
    if magic != SOMAP_MAGIC:
        push_error("ObstacleSequenceSerializer: '%s' is not an ExtraStimulantsPlus .somap file" % path)
        return {}

    var json: = JSON.new()
    if json.parse(payload_text) != OK:
        push_error("ObstacleSequenceSerializer: Invalid .somap payload in '%s'" % path)
        return {}
    if not json.data is Dictionary:
        return {}
    return json.data


static func _load_sequence_from_payload(payload: Dictionary, path: String) -> Array:
    if payload.is_empty():
        return []
    var obstacles_data = payload.get("obstacles", [])
    if not obstacles_data is Array:
        push_error("ObstacleSequenceSerializer: 'obstacles' field is not an Array in '%s'" % path)
        return []

    var sequence: Array = []
    for idx in range(obstacles_data.size()):
        var dict = obstacles_data[idx]
        if dict is Dictionary:
            var entry: = deserialize(dict)
            if entry:
                sequence.append(entry)
        else:
            push_warning("ObstacleSequenceSerializer: Skipping non-Dictionary obstacle at index %d in '%s'" % [idx, path])

    print("ObstacleSequenceSerializer: Loaded %d obstacles from %s" % [sequence.size(), path])
    return sequence
