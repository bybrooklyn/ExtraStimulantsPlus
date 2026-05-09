extends Node

# ESP Level Registry - Framework Owned
# Scans standalone custom levels and grouped custom campaigns, then converts
# them into runtime CampaignLevelDef resources through the ESP campaign adapter.

const LEGACY_LEVELS_DIR := "user://custom_levels"
const LEVEL_EXTENSIONS := ["json", "somap"]
const CAMPAIGN_EXTENSION := "somapbundle"
const RUNTIME_CAMPAIGNS_DIR := "user://esp/runtime/campaigns"
const CUSTOM_SORT_BASE := 100000

var logger: Node
var levels_dirs: Array[String] = []
var campaigns_dirs: Array[String] = []

var custom_levels: Array[CampaignLevelDef] = []
var custom_level_records: Array[Dictionary] = []
var custom_campaign_records: Array[Dictionary] = []


func configure(parts: Dictionary) -> void:
    logger = parts.get("logger", logger)
    levels_dirs = _normalize_dir_list(parts.get("levels_dirs", []), "levels")
    campaigns_dirs = _normalize_dir_list(parts.get("campaigns_dirs", []), "campaigns")
    _ensure_dir(RUNTIME_CAMPAIGNS_DIR)


func scan_custom_levels() -> void:
    custom_levels.clear()
    custom_level_records.clear()
    custom_campaign_records.clear()

    var seen_paths: Array[String] = []
    for path in levels_dirs:
        _scan_levels_dir(path, seen_paths)
    if not seen_paths.has(LEGACY_LEVELS_DIR):
        _scan_levels_dir(LEGACY_LEVELS_DIR, seen_paths)

    for path in campaigns_dirs:
        _scan_campaigns_dir(path, seen_paths)


func get_custom_levels() -> Array[CampaignLevelDef]:
    return custom_levels.duplicate()


func get_custom_level_records() -> Array[Dictionary]:
    return custom_level_records.duplicate(true)


func get_custom_campaign_records() -> Array[Dictionary]:
    return custom_campaign_records.duplicate(true)


func get_primary_levels_dir() -> String:
    if not levels_dirs.is_empty():
        return levels_dirs[0]
    return LEGACY_LEVELS_DIR


func get_primary_campaigns_dir() -> String:
    if not campaigns_dirs.is_empty():
        return campaigns_dirs[0]
    return "user://campaigns"


func get_editor_backups_dir() -> String:
    return "user://esp/editor/backups"


func inject_levels(existing_levels: Array[CampaignLevelDef]) -> void:
    scan_custom_levels()
    for cl in custom_levels:
        if not existing_levels.has(cl):
            existing_levels.append(cl)


func _normalize_dir_list(raw_dirs: Array, folder_name: String) -> Array[String]:
    var out: Array[String] = []
    for raw in raw_dirs:
        if raw is String and not String(raw).strip_edges().is_empty():
            _append_unique(out, String(raw).strip_edges())
    if out.is_empty():
        _append_unique(out, "user://%s" % folder_name)
    for path in out:
        _ensure_dir(path)
    return out


func _scan_levels_dir(path: String, seen_paths: Array[String]) -> void:
    _append_unique(seen_paths, path)
    _ensure_dir(path)
    var dir := DirAccess.open(path)
    if dir == null:
        _log_warn("Could not open custom level directory: %s" % path)
        return

    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        if not dir.current_is_dir():
            var ext := file_name.get_extension().to_lower()
            if LEVEL_EXTENSIONS.has(ext):
                _load_level_document(path.path_join(file_name), {}, {
                    "content_kind": "level",
                    "sort_order": CUSTOM_SORT_BASE + custom_levels.size()
                })
        file_name = dir.get_next()
    dir.list_dir_end()


func _scan_campaigns_dir(path: String, seen_paths: Array[String]) -> void:
    _append_unique(seen_paths, path)
    _ensure_dir(path)
    var dir := DirAccess.open(path)
    if dir == null:
        _log_warn("Could not open custom campaign directory: %s" % path)
        return

    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        if not dir.current_is_dir() and file_name.get_extension().to_lower() == CAMPAIGN_EXTENSION:
            _load_campaign_bundle(path.path_join(file_name))
        file_name = dir.get_next()
    dir.list_dir_end()


func _load_campaign_bundle(path: String) -> void:
    var extracted_root := _extract_campaign_bundle(path)
    if extracted_root.is_empty():
        return

    var campaign_meta := _read_campaign_bundle_manifest(extracted_root)
    var campaign_title := String(campaign_meta.get("title", path.get_file().get_basename())).strip_edges()
    if campaign_title.is_empty():
        campaign_title = path.get_file().get_basename()

    var bundle_records: Array[Dictionary] = []
    var declared_levels = campaign_meta.get("levels", [])
    if declared_levels is Array and not declared_levels.is_empty():
        for idx in range(declared_levels.size()):
            var entry = declared_levels[idx]
            var level_path := _bundle_level_path(extracted_root, entry)
            if level_path.is_empty():
                continue
            var overrides := _bundle_level_overrides(campaign_title, entry, idx)
            var level_record := _load_level_document(level_path, overrides.get("meta", {}), overrides.get("record", {}))
            if not level_record.is_empty():
                bundle_records.append(level_record)
    else:
        var inferred := _find_bundle_level_files(extracted_root)
        for idx in range(inferred.size()):
            var inferred_path := inferred[idx]
            var inferred_record := _load_level_document(inferred_path, {
                "campaign_title": campaign_title
            }, {
                "campaign_title": campaign_title,
                "content_kind": "campaign_level",
                "sort_order": CUSTOM_SORT_BASE + 1000 + (custom_levels.size() * 10) + idx
            })
            if not inferred_record.is_empty():
                bundle_records.append(inferred_record)

    custom_campaign_records.append({
        "path": path,
        "title": campaign_title,
        "description": String(campaign_meta.get("description", "")),
        "level_count": bundle_records.size(),
        "levels": bundle_records.duplicate(true),
        "valid": not bundle_records.is_empty()
    })


func _bundle_level_path(extracted_root: String, entry) -> String:
    if entry is String:
        return extracted_root.path_join(String(entry))
    if entry is Dictionary:
        var rel_path := String(entry.get("path", entry.get("file", ""))).strip_edges()
        if not rel_path.is_empty():
            return extracted_root.path_join(rel_path)
    return ""


func _bundle_level_overrides(campaign_title: String, entry, idx: int) -> Dictionary:
    var meta: Dictionary = {"campaign_title": campaign_title}
    var record: Dictionary = {
        "campaign_title": campaign_title,
        "content_kind": "campaign_level",
        "sort_order": CUSTOM_SORT_BASE + 1000 + (custom_levels.size() * 10) + idx
    }
    if entry is Dictionary:
        for key in ["title", "name", "description", "theme", "song", "stage_name"]:
            if entry.has(key):
                meta[key] = entry.get(key)
        if entry.has("sort_order"):
            record["sort_order"] = int(entry.get("sort_order", record.get("sort_order", 0)))
    return {
        "meta": meta,
        "record": record
    }


func _find_bundle_level_files(extracted_root: String) -> Array[String]:
    var out: Array[String] = []
    var dir := DirAccess.open(extracted_root)
    if dir == null:
        return out
    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        if not dir.current_is_dir() and file_name.get_extension().to_lower() == "somap":
            out.append(extracted_root.path_join(file_name))
        file_name = dir.get_next()
    dir.list_dir_end()
    out.sort()
    return out


const MAX_BUNDLE_ENTRIES := 10_000
const MAX_BUNDLE_FILE_BYTES := 64 * 1024 * 1024     # 64 MB per file
const MAX_BUNDLE_TOTAL_BYTES := 512 * 1024 * 1024   # 512 MB across the bundle

func _extract_campaign_bundle(path: String) -> String:
    if not FileAccess.file_exists(path):
        _log_warn("Campaign bundle not found: %s" % path)
        return ""

    var zip_reader := ZIPReader.new()
    if zip_reader.open(path) != OK:
        _log_warn("Could not open campaign bundle: %s" % path)
        return ""

    var bundle_root := RUNTIME_CAMPAIGNS_DIR.path_join(_safe_bundle_name(path))
    _ensure_dir(bundle_root)
    var files: PackedStringArray = zip_reader.get_files()
    if files.size() > MAX_BUNDLE_ENTRIES:
        _log_warn("Campaign bundle '%s' has %d entries (cap %d); refusing to extract." % [path, files.size(), MAX_BUNDLE_ENTRIES])
        zip_reader.close()
        return ""
    var total_bytes: int = 0
    for raw_path in files:
        var clean_path := String(raw_path).replace("\\", "/").strip_edges()
        # Reject empty, absolute, parent-traversal, and embedded-null paths.
        if clean_path.is_empty() or clean_path.begins_with("/") \
                or clean_path.contains("../") or clean_path.contains(" "):
            continue
        var out_path := bundle_root.path_join(clean_path)
        if clean_path.ends_with("/"):
            _ensure_dir(out_path)
            continue
        var bytes := zip_reader.read_file(clean_path)
        if bytes.size() > MAX_BUNDLE_FILE_BYTES:
            _log_warn("Skipping oversized bundle entry '%s' (%d bytes)" % [clean_path, bytes.size()])
            continue
        total_bytes += bytes.size()
        if total_bytes > MAX_BUNDLE_TOTAL_BYTES:
            _log_warn("Campaign bundle '%s' exceeded %d-byte cumulative cap; aborting." % [path, MAX_BUNDLE_TOTAL_BYTES])
            zip_reader.close()
            return ""
        _ensure_dir(out_path.get_base_dir())
        var file := FileAccess.open(out_path, FileAccess.WRITE)
        if file == null:
            continue
        file.store_buffer(bytes)
        file.close()
    zip_reader.close()
    return bundle_root


func _safe_bundle_name(path: String) -> String:
    var base_name := path.get_file().get_basename()
    var clean := ""
    for i in range(base_name.length()):
        var ch := base_name[i]
        var is_alnum := (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")
        clean += ch.to_lower() if is_alnum else "_"
    while clean.contains("__"):
        clean = clean.replace("__", "_")
    clean = clean.strip_edges().trim_prefix("_").trim_suffix("_")
    return clean if not clean.is_empty() else "campaign_bundle"


func _read_campaign_bundle_manifest(extracted_root: String) -> Dictionary:
    var manifest_path := extracted_root.path_join("campaign.json")
    if not FileAccess.file_exists(manifest_path):
        return {}
    var file := FileAccess.open(manifest_path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    file.close()
    return parsed if parsed is Dictionary else {}


func _load_level_document(path: String, extra_meta: Dictionary = {}, record_overrides: Dictionary = {}) -> Dictionary:
    var campaign_adapter := _get_campaign_adapter()
    if campaign_adapter == null or not campaign_adapter.has_method("load_custom_level_from_path"):
        _log_warn("Campaign adapter unavailable; cannot load custom level '%s'" % path)
        return {}

    var level_def = campaign_adapter.load_custom_level_from_path(path, extra_meta)
    var sequence := _load_sequence(path)
    var meta := _load_metadata(path)
    for key in extra_meta.keys():
        meta[key] = extra_meta[key]

    var title := String(meta.get("title", meta.get("name", path.get_file().get_basename()))).strip_edges()
    if title.is_empty():
        title = path.get_file().get_basename()
    var campaign_title := String(record_overrides.get("campaign_title", meta.get("campaign_title", ""))).strip_edges()

    if level_def is CampaignLevelDef:
        level_def.sort_order = int(record_overrides.get("sort_order", CUSTOM_SORT_BASE + custom_levels.size()))
        if not campaign_title.is_empty() and not String(level_def.level_name).begins_with(campaign_title + " / "):
            level_def.level_name = "%s / %s" % [campaign_title, level_def.level_name]
        level_def.set_meta("esp_custom_content", true)
        level_def.set_meta("esp_custom_source_path", path)
        level_def.set_meta("esp_content_kind", String(record_overrides.get("content_kind", "level")))
        if not campaign_title.is_empty():
            level_def.set_meta("esp_campaign_title", campaign_title)

    var record := {
        "path": path,
        "file_name": path.get_file(),
        "title": title,
        "display_title": ("%s / %s" % [campaign_title, title]) if not campaign_title.is_empty() else title,
        "theme": String(meta.get("theme", "tornado")),
        "song": String(meta.get("song", "res://audio/Song-1.wav")),
        "obstacle_count": sequence.size(),
        "format": path.get_extension().to_lower(),
        "valid": level_def is CampaignLevelDef,
        "level": level_def,
        "campaign_title": campaign_title,
        "content_kind": String(record_overrides.get("content_kind", "level"))
    }

    custom_level_records.append(record)
    if level_def is CampaignLevelDef:
        custom_levels.append(level_def)
    return record


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


func _append_unique(list: Array[String], value: String) -> void:
    if value.is_empty():
        return
    if not list.has(value):
        list.append(value)


func _log_warn(message: String) -> void:
    var active_logger := logger if logger != null else get_node_or_null("/root/ESPLogger")
    if active_logger and active_logger.has_method("warn"):
        active_logger.warn("[LevelRegistry] " + message)
    else:
        push_warning("[ESP LevelRegistry] " + message)
