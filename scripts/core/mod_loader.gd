extends Node

# Real runtime mod loader. This lives in the external ExtraStimulantsPlus core pack,
# not in the injected shim.

const BLACKLIST_PATH := "user://mods.blacklist"
const CORE_MOD_ID := "extrastimulants_plus"
const CORE_PACK_NAMES: Array[String] = [
    "000_extrastimulantsplus_core.pck",
    "000_extrastimulantsplus_core.zip",
    "ExtraStimulantsPlus.pck",
    "ExtraStimulantsPlus.zip",
    "ExtraStimulantsPlus-core.pck",
    "ExtraStimulantsPlus-core.zip"
]

var loaded_mods: Array[Dictionary] = []
var discovered_mods: Array[Dictionary] = []
var failed_mods: Array[Dictionary] = []
var entrypoint_instances: Array[Object] = []

var _loaded_ids: Array[String] = []
var _blacklist: Array[String] = []
var _core_context: Dictionary = {}
var _api: Node
var _logger: Node
var _hooks: Node
var _has_loaded_external_mods := false


func _enter_tree() -> void:
    _setup_directories()
    _load_blacklist()
    _register_core_mod()
    _log_info("mod loader initialized")


func set_core_context(context: Dictionary) -> void:
    _core_context = context.duplicate(true)
    _api = _core_context.get("api")
    _logger = _core_context.get("logger")
    _hooks = _core_context.get("hooks")


func load_external_mods(mods_dirs: Array = [], core_pack_path: String = "") -> void:
    if _has_loaded_external_mods:
        _log_warn("external mods already loaded; ignoring duplicate scan")
        return
    _has_loaded_external_mods = true

    var scan_dirs := _normalize_scan_dirs(mods_dirs)
    _log_info("scanning mod directories: %s" % JSON.stringify(scan_dirs))

    var candidates := _discover_candidates(scan_dirs, core_pack_path)
    _mount_pack_candidates(candidates)
    _read_candidate_metadata(candidates)
    
    # 1. VALIDATION PHASE
    var valid_candidates: Array[Dictionary] = []
    for candidate in candidates:
        if candidate.get("skip", false) or not candidate.get("mounted", false):
            continue
        if not _validate_mod(candidate):
            _fail_fatal(candidate, "Strict version validation failed")
            return # FATAL
        valid_candidates.append(candidate)
    
    valid_candidates.sort_custom(Callable(self, "_sort_candidates"))

    # 2. PRELOAD PHASE
    var mod_instances: Array[Dictionary] = []
    for candidate in valid_candidates:
        var instances = _instantiate_entrypoints(candidate)
        if instances.is_empty() and not candidate.get("meta").get("entrypoints").is_empty():
             _fail_fatal(candidate, "Failed to instantiate entrypoints")
             return # FATAL
        candidate["instances"] = instances
        mod_instances.append(candidate)
        
        for inst in instances:
            _call_mod_phase(inst, "esp_preload", candidate.get("meta"))

    # 3. INIT PHASE
    for candidate in mod_instances:
        var meta = candidate.get("meta")
        for inst in candidate.get("instances"):
            var result = _call_mod_phase(inst, "esp_init", meta)
            if result == false: # Strict check
                _fail_fatal(candidate, "Mod returned failure during esp_init")
                return # FATAL

    # 4. READY PHASE
    for candidate in mod_instances:
        var meta = candidate.get("meta")
        for inst in candidate.get("instances"):
            _call_mod_phase(inst, "esp_ready", meta)
            
        # Officially mark as loaded
        var mod_id = meta.get("id")
        loaded_mods.append(meta)
        _loaded_ids.append(mod_id)
        _log_info("Activated %s v%s" % [meta.get("name"), meta.get("version")])

    _log_info("Loaded %d mod(s)" % loaded_mods.size())


func _validate_mod(candidate: Dictionary) -> bool:
    var meta = candidate.get("meta", {})
    var req_ver = meta.get("required_framework_version", "0.0.0")
    # Simple semantic version check could go here. For now, just logging.
    _log_info("Validating %s (requires ESP %s)" % [meta.get("id"), req_ver])
    return true


func _fail_fatal(candidate: Dictionary, reason: String) -> void:
    var mod_name = candidate.get("meta", {}).get("name", candidate.get("base_id", "Unknown"))
    var error_msg = "FATAL MOD ERROR: [%s] %s" % [mod_name, reason]
    _log_error(error_msg)
    
    # Professional Crash
    OS.alert(error_msg, "ESP ModLoader - Fatal Error")
    get_tree().quit(1)


func _call_mod_phase(instance: Object, method_name: String, meta: Dictionary) -> Variant:
    if instance == null or not instance.has_method(method_name):
        return null
    return instance.call(method_name, _api, meta)


func _instantiate_entrypoints(candidate: Dictionary) -> Array:
    var meta = candidate.get("meta")
    var instances = []
    for entrypoint in meta.get("entrypoints", []):
        var entry_path := _resolve_entrypoint_path(String(entrypoint), candidate, meta)
        var script := load(entry_path)
        if script == null: return []

        var instance = script.new()
        if instance == null: return []

        if instance is Node:
            instance.name = "Mod_%s" % String(meta.get("id", "unknown"))
            get_tree().root.add_child(instance)

        entrypoint_instances.append(instance)
        instances.append(instance)
    return instances


func get_loaded_mod_ids() -> Array[String]:
    return _loaded_ids.duplicate()


func is_blacklisted(mod_id: String) -> bool:
    return _blacklist.has(mod_id)


func set_blacklisted(mod_id: String, blacklisted: bool) -> void:
    if blacklisted and not _blacklist.has(mod_id):
        _blacklist.append(mod_id)
    elif not blacklisted and _blacklist.has(mod_id):
        _blacklist.erase(mod_id)
    save_blacklist()


func save_blacklist() -> void:
    var file := FileAccess.open(BLACKLIST_PATH, FileAccess.WRITE)
    if file:
        file.store_string("\n".join(_blacklist))
        file.close()


func _load_blacklist() -> void:
    _blacklist.clear()
    if not FileAccess.file_exists(BLACKLIST_PATH):
        return
    var file := FileAccess.open(BLACKLIST_PATH, FileAccess.READ)
    if file:
        for line in file.get_as_text().split("\n", false):
            var trimmed := line.strip_edges()
            if not trimmed.is_empty() and not _blacklist.has(trimmed):
                _blacklist.append(trimmed)
        file.close()


func _register_core_mod() -> void:
    if _loaded_ids.has(CORE_MOD_ID):
        return

    var meta := _read_mod_metadata_from_path("res://mod.json")
    if meta.is_empty() or meta.get("id", "") == "unknown":
        meta = {
            "schema": 1,
            "id": CORE_MOD_ID,
            "name": "ExtraStimulantsPlus",
            "version": "0.0.0",
            "author": "bybrooklyn",
            "description": "Core modding framework and built-in ExtraStimulantsPlus systems.",
            "dependencies": [],
            "entrypoints": []
        }

    meta["id"] = CORE_MOD_ID
    meta["core"] = true
    loaded_mods.append(meta)
    _loaded_ids.append(CORE_MOD_ID)


func _normalize_scan_dirs(mods_dirs: Array) -> Array[String]:
    var dirs: Array[String] = []

    for raw in mods_dirs:
        if raw is String and not raw.is_empty():
            _append_unique(dirs, raw)

    # Standard locations
    var exe_dir := OS.get_executable_path().get_base_dir()
    
    # 1. Framework Internal (The Core itself)
    _append_unique(dirs, exe_dir.path_join("modloader"))
    
    # 2. User Mods
    _append_unique(dirs, exe_dir.path_join("mods"))

    if OS.get_name() == "macOS":
        var contents_dir := exe_dir.get_base_dir()
        var app_root := contents_dir.get_base_dir()
        var beside_app := app_root.get_base_dir()
        _append_unique(dirs, app_root.path_join("modloader"))
        _append_unique(dirs, app_root.path_join("mods"))
        _append_unique(dirs, beside_app.path_join("mods"))

    # 3. Persistent User Data (Steam Deck / Sandbox safe)
    _append_unique(dirs, OS.get_user_data_dir().path_join("mods"))

    for dir in dirs:
        _ensure_dir(dir)

    return dirs


func _discover_candidates(scan_dirs: Array[String], core_pack_path: String) -> Array[Dictionary]:
    var candidates: Array[Dictionary] = []
    var seen_paths: Array[String] = []

    for dir_path in scan_dirs:
        var mods_dir := DirAccess.open(dir_path)
        if mods_dir == null:
            continue

        mods_dir.list_dir_begin()
        var file_name := mods_dir.get_next()
        while file_name != "":
            var full_path := dir_path.path_join(file_name)
            var is_dir := mods_dir.current_is_dir()

            if file_name.begins_with("."):
                file_name = mods_dir.get_next()
                continue

            if seen_paths.has(full_path):
                file_name = mods_dir.get_next()
                continue
            seen_paths.append(full_path)

            if is_dir:
                var meta_path := full_path.path_join("mod.json")
                if FileAccess.file_exists(meta_path):
                    candidates.append({
                        "kind": "folder",
                        "path": full_path,
                        "file_name": file_name,
                        "base_id": file_name,
                        "metadata_path": meta_path,
                        "mounted": true
                    })
            elif file_name.ends_with(".pck") or file_name.ends_with(".zip"):
                if _is_core_pack(full_path, file_name, core_pack_path):
                    file_name = mods_dir.get_next()
                    continue
                candidates.append({
                    "kind": "pack",
                    "path": full_path,
                    "file_name": file_name,
                    "base_id": file_name.get_basename(),
                    "metadata_path": "",
                    "mounted": false
                })

            file_name = mods_dir.get_next()
        mods_dir.list_dir_end()

    discovered_mods = candidates.duplicate(true)
    return candidates


func _mount_pack_candidates(candidates: Array[Dictionary]) -> void:
    for candidate in candidates:
        if candidate.get("kind", "") != "pack":
            continue

        var base_id := String(candidate.get("base_id", ""))
        if is_blacklisted(base_id):
            _log_info("skipping blacklisted pack by filename: %s" % candidate.get("file_name", base_id))
            candidate["skip"] = true
            continue

        var path := String(candidate.get("path", ""))
        var ok := ProjectSettings.load_resource_pack(path, true)
        candidate["mounted"] = ok
        if ok:
            _log_info("mounted mod pack: %s" % path)
        else:
            _fail_candidate(candidate, "failed to mount pack")


func _read_candidate_metadata(candidates: Array[Dictionary]) -> void:
    for candidate in candidates:
        if candidate.get("skip", false):
            continue
        if not candidate.get("mounted", false):
            continue

        var meta := {}
        if candidate.get("kind", "") == "folder":
            meta = _read_mod_metadata_from_path(candidate.get("metadata_path", ""))
        else:
            meta = _read_pack_metadata(candidate)

        if meta.is_empty():
            meta = _default_metadata(candidate)

        meta = _normalize_metadata(meta, candidate)
        candidate["meta"] = meta


func _read_pack_metadata(candidate: Dictionary) -> Dictionary:
    # First, try to find a mod.json in the standard isolated location
    # Since we don't know the ID yet, we have to look in res://mods/
    var dir := DirAccess.open("res://mods/")
    if dir:
        dir.list_dir_begin()
        var sub_dir := dir.get_next()
        while sub_dir != "":
            if dir.current_is_dir() and not sub_dir.begins_with("."):
                var meta_path := "res://mods/".path_join(sub_dir).path_join("mod.json")
                if FileAccess.file_exists(meta_path):
                    # Check if this meta belongs to the pack we just mounted
                    # (Simplified: just take the first new one we find)
                    var meta := _read_mod_metadata_from_path(meta_path)
                    if not meta.is_empty():
                         meta["_metadata_path"] = meta_path
                         return meta
            sub_dir = dir.get_next()
        dir.list_dir_end()

    # Fallback to root mod.json
    if FileAccess.file_exists("res://mod.json"):
        var legacy := _read_mod_metadata_from_path("res://mod.json")
        legacy["_metadata_path"] = "res://mod.json"
        if legacy.get("id", "") == CORE_MOD_ID and not _looks_like_core_pack(candidate):
            return {}
        return legacy

    return {}


func _read_mod_metadata_from_path(path: String) -> Dictionary:
    if path.is_empty() or not FileAccess.file_exists(path):
        return {}

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}

    var parsed = JSON.parse_string(file.get_as_text())
    file.close()

    if parsed is Dictionary:
        return parsed
    return {}


func _normalize_metadata(meta: Dictionary, candidate: Dictionary) -> Dictionary:
    var base_id := String(candidate.get("base_id", "unknown"))
    var normalized := {
        "schema": int(meta.get("schema", 1)),
        "id": String(meta.get("id", base_id)).strip_edges(),
        "name": String(meta.get("name", base_id)).strip_edges(),
        "version": String(meta.get("version", "0.0.0")).strip_edges(),
        "author": String(meta.get("author", "Unknown")).strip_edges(),
        "description": String(meta.get("description", "No description provided.")).strip_edges(),
        "dependencies": _string_array(meta.get("dependencies", [])),
        "entrypoints": _string_array(meta.get("entrypoints", [])),
        "priority": int(meta.get("priority", 100)),
        "path": String(candidate.get("path", "")),
        "kind": String(candidate.get("kind", "unknown")),
        "metadata_path": String(meta.get("_metadata_path", candidate.get("metadata_path", "")))
    }

    if normalized["id"].is_empty():
        normalized["id"] = base_id
    if normalized["name"].is_empty():
        normalized["name"] = normalized["id"]

    return normalized


func _default_metadata(candidate: Dictionary) -> Dictionary:
    var base_id := String(candidate.get("base_id", "unknown"))
    return {
        "schema": 1,
        "id": base_id,
        "name": base_id,
        "version": "0.0.0",
        "author": "Unknown",
        "description": "No mod.json was found. This mod pack was mounted but has no entrypoints.",
        "dependencies": [],
        "entrypoints": [],
        "priority": 100
    }


func _activate_candidates(candidates: Array[Dictionary]) -> void:
    var pending: Array[Dictionary] = []

    for candidate in candidates:
        if candidate.get("skip", false):
            continue
        if not candidate.get("mounted", false):
            continue
        if not candidate.has("meta"):
            continue

        var meta: Dictionary = candidate.get("meta")
        var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))

        if is_blacklisted(mod_id):
            _log_info("skipping blacklisted mod: %s" % mod_id)
            continue

        pending.append(candidate)

    pending.sort_custom(Callable(self, "_sort_candidates"))

    var made_progress := true
    while made_progress and not pending.is_empty():
        made_progress = false

        for candidate in pending.duplicate():
            var meta: Dictionary = candidate.get("meta")
            if _dependencies_satisfied(meta):
                _activate_mod(candidate)
                pending.erase(candidate)
                made_progress = true

    for candidate in pending:
        var meta: Dictionary = candidate.get("meta", _default_metadata(candidate))
        _fail_candidate(candidate, "missing or circular dependencies: %s" % JSON.stringify(meta.get("dependencies", [])))


func _sort_candidates(a: Dictionary, b: Dictionary) -> bool:
    var ma: Dictionary = a.get("meta", {})
    var mb: Dictionary = b.get("meta", {})
    var pa := int(ma.get("priority", 100))
    var pb := int(mb.get("priority", 100))
    if pa == pb:
        return String(ma.get("id", "")) < String(mb.get("id", ""))
    return pa < pb


func _dependencies_satisfied(meta: Dictionary) -> bool:
    for dep in meta.get("dependencies", []):
        if not _loaded_ids.has(String(dep)):
            return false
    return true


func _activate_mod(candidate: Dictionary) -> void:
    var meta: Dictionary = candidate.get("meta", _default_metadata(candidate))
    var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))

    if _loaded_ids.has(mod_id):
        _log_warn("duplicate mod id skipped: %s" % mod_id)
        return

    loaded_mods.append(meta)
    _loaded_ids.append(mod_id)
    _log_info("activated %s v%s" % [meta.get("name", mod_id), meta.get("version", "0.0.0")])

    _instantiate_entrypoints(candidate, meta)


func _instantiate_entrypoints(candidate: Dictionary, meta: Dictionary) -> void:
    for entrypoint in meta.get("entrypoints", []):
        var entry_path := _resolve_entrypoint_path(String(entrypoint), candidate, meta)
        if entry_path.is_empty():
            continue

        var script := load(entry_path)
        if script == null:
            _fail_candidate(candidate, "missing entrypoint: %s" % entry_path)
            continue

        var instance = script.new()
        if instance == null:
            _fail_candidate(candidate, "failed to instantiate entrypoint: %s" % entry_path)
            continue

        if instance is Node:
            instance.name = "ESPMod_%s" % String(meta.get("id", "unknown"))
            get_tree().root.add_child(instance)

        entrypoint_instances.append(instance)

        _call_mod_phase(instance, "esp_preload", meta)
        _call_mod_phase(instance, "esp_init", meta)
        _call_mod_phase(instance, "esp_ready", meta)


func _resolve_entrypoint_path(entrypoint: String, candidate: Dictionary, meta: Dictionary) -> String:
    if entrypoint.is_empty():
        return ""
    if entrypoint.begins_with("res://") or entrypoint.begins_with("user://") or entrypoint.begins_with("/"):
        return entrypoint

    if candidate.get("kind", "") == "folder":
        return String(candidate.get("path", "")).path_join(entrypoint)

    var mod_id := String(meta.get("id", candidate.get("base_id", "")))
    return "res://mods".path_join(mod_id).path_join(entrypoint)


func _call_mod_phase(instance: Object, method_name: String, meta: Dictionary) -> void:
    if instance == null or not instance.has_method(method_name):
        return
    instance.call(method_name, _api, meta)


func _fail_candidate(candidate: Dictionary, reason: String) -> void:
    var meta: Dictionary = candidate.get("meta", _default_metadata(candidate))
    var failure := {
        "id": meta.get("id", candidate.get("base_id", "unknown")),
        "name": meta.get("name", candidate.get("file_name", "unknown")),
        "path": candidate.get("path", ""),
        "reason": reason
    }
    failed_mods.append(failure)
    _log_warn("mod failed: %s" % JSON.stringify(failure))


func _setup_directories() -> void:
    for folder in ["user://mods", "user://custom_levels", "user://custom_obstacles", "user://custom_music", "user://esp/logs"]:
        _ensure_dir(folder)


func _ensure_dir(path: String) -> void:
    if path.begins_with("user://"):
        var absolute := ProjectSettings.globalize_path(path)
        if not DirAccess.dir_exists_absolute(absolute):
            DirAccess.make_dir_recursive_absolute(absolute)
        return

    if not DirAccess.dir_exists_absolute(path):
        DirAccess.make_dir_recursive_absolute(path)


func _append_unique(list: Array[String], value: String) -> void:
    if value.is_empty():
        return
    if not list.has(value):
        list.append(value)


func _is_core_pack(path: String, file_name: String, core_pack_path: String) -> bool:
    if not core_pack_path.is_empty() and path == core_pack_path:
        return true
    return CORE_PACK_NAMES.has(file_name)


func _looks_like_core_pack(candidate: Dictionary) -> bool:
    return CORE_PACK_NAMES.has(String(candidate.get("file_name", "")))


func _string_array(value) -> Array[String]:
    var out: Array[String] = []
    if value is Array:
        for item in value:
            var text := String(item).strip_edges()
            if not text.is_empty():
                out.append(text)
    elif value is String and not String(value).strip_edges().is_empty():
        out.append(String(value).strip_edges())
    return out


func _is_turbo_active() -> bool:
    var om = _find_obstacle_manager()
    return om != null and om.has_method("_check_hit_direct")


func _find_obstacle_manager() -> Node:
    var root = get_tree().root
    # Check common locations
    var paths = [
        "/root/ObstacleManager",
        "/root/Game/Managers/ObstacleManager",
        "/root/Main/Game/Managers/ObstacleManager"
    ]
    for p in paths:
        var n = root.get_node_or_null(p)
        if n: return n
        
    # Recursive fallback
    return root.find_child("ObstacleManager", true, false)


func _log_info(message: String) -> void:
    if _logger and _logger.has_method("info"):
        _logger.info(message)
    else:
        print("[ESP ModLoader] ", message)


func _log_warn(message: String) -> void:
    if _logger and _logger.has_method("warn"):
        _logger.warn(message)
    else:
        push_warning("[ESP ModLoader] " + message)


func _log_error(message: String) -> void:
    if _logger and _logger.has_method("error"):
        _logger.error(message)
    else:
        push_error("[ESP ModLoader] " + message)
