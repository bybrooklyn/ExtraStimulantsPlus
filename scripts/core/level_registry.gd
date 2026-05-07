extends Node

# ESP Level Registry - Framework Owned
# Treats .somap as the editor-exported map document format and converts it into
# runtime CampaignLevelDef objects through the ESP campaign adapter.

const LEVELS_DIR := "user://custom_levels"
const SUPPORTED_EXTENSIONS := ["json", "somap"]

var custom_levels: Array[CampaignLevelDef] = []
var custom_level_records: Array[Dictionary] = []


func scan_custom_levels() -> void:
    custom_levels.clear()
    custom_level_records.clear()

    _ensure_dir(LEVELS_DIR)
    _scan_dir(LEVELS_DIR)


func get_custom_levels() -> Array[CampaignLevelDef]:
    return custom_levels.duplicate()


func get_custom_level_records() -> Array[Dictionary]:
    return custom_level_records.duplicate(true)


func inject_levels(existing_levels: Array[CampaignLevelDef]) -> void:
    scan_custom_levels()
    for cl in custom_levels:
        if not existing_levels.has(cl):
            existing_levels.append(cl)


func _scan_dir(path: String) -> void:
    var dir := DirAccess.open(path)
    if dir == null:
        _log_warn("Could not open custom level directory: %s" % path)
        return

    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        if not dir.current_is_dir():
            var ext := file_name.get_extension().to_lower()
            if SUPPORTED_EXTENSIONS.has(ext):
                _load_level_document(path.path_join(file_name))
        file_name = dir.get_next()
    dir.list_dir_end()


func _load_level_document(path: String) -> void:
    var campaign_adapter := _get_campaign_adapter()
    if campaign_adapter == null or not campaign_adapter.has_method("load_custom_level_from_path"):
        _log_warn("Campaign adapter unavailable; cannot load custom level '%s'" % path)
        return

    var level_def = campaign_adapter.load_custom_level_from_path(path)
    var sequence := _load_sequence(path)
    var meta := _load_metadata(path)
    var record := {
        "path": path,
        "file_name": path.get_file(),
        "title": String(meta.get("title", meta.get("name", path.get_file().get_basename()))),
        "theme": String(meta.get("theme", "tornado")),
        "song": String(meta.get("song", "res://audio/Song-1.wav")),
        "obstacle_count": sequence.size(),
        "format": path.get_extension().to_lower(),
        "valid": level_def is CampaignLevelDef,
        "level": level_def
    }

    custom_level_records.append(record)
    if level_def is CampaignLevelDef:
        custom_levels.append(level_def)


func _load_sequence(path: String) -> Array:
    if not FileAccess.file_exists(path):
        return []
    if ObstacleSequenceSerializer.has_method("load_from_path"):
        return ObstacleSequenceSerializer.load_from_path(path)
    if path.get_extension().to_lower() == "json" and ObstacleSequenceSerializer.has_method("load_from_json"):
        return ObstacleSequenceSerializer.load_from_json(path)
    return []


func _load_metadata(path: String) -> Dictionary:
    if ObstacleSequenceSerializer.has_method("load_metadata_from_path"):
        return ObstacleSequenceSerializer.load_metadata_from_path(path)
    return {}


func _get_campaign_adapter() -> Node:
    var esp := get_node_or_null("/root/ESP")
    if esp and esp.get("campaign"):
        return esp.get("campaign")
    return get_node_or_null("/root/ESPCampaignAdapter")


func _ensure_dir(path: String) -> void:
    var absolute := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
    if not DirAccess.dir_exists_absolute(absolute):
        DirAccess.make_dir_recursive_absolute(absolute)


func _log_warn(message: String) -> void:
    var logger := get_node_or_null("/root/ESPLogger")
    if logger and logger.has_method("warn"):
        logger.warn("[LevelRegistry] " + message)
    else:
        push_warning("[ESP LevelRegistry] " + message)
