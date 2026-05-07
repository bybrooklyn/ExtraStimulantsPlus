extends Node

# Real runtime mod loader. This lives in the external ExtraStimulantsPlus core pack,
# not in the injected shim.

const BLACKLIST_PATH := "user://mods.blacklist"
const CORE_MOD_ID := "extrastimulants_plus"
const CORE_VERSION := "0.0.2"
const SUPPORTED_GAME_ID := "sensory_overload"
const SUPPORTED_SCHEMA := 1
const CORE_PACK_NAMES: Array[String] = [
    "000_extrastimulantsplus_core.pck",
    "000_extrastimulantsplus_core.zip",
    "ExtraStimulantsPlus.pck",
    "ExtraStimulantsPlus.zip",
    "ExtraStimulantsPlus-core.pck",
    "ExtraStimulantsPlus-core.zip"
]
const KNOWN_PERMISSIONS: Array[String] = [
    "asset_access",
    "filesystem",
    "hot_reload",
    "internet",
    "patching",
    "raw_api",
    "save_access"
]
const SUPPORTED_SETTING_TYPES := {
    "bool": TYPE_BOOL,
    "boolean": TYPE_BOOL,
    "float": TYPE_FLOAT,
    "int": TYPE_INT,
    "integer": TYPE_INT,
    "number": TYPE_FLOAT,
    "string": TYPE_STRING,
    "text": TYPE_STRING
}

var loaded_mods: Array[Dictionary] = []
var discovered_mods: Array[Dictionary] = []
var failed_mods: Array[Dictionary] = []
var entrypoint_instances: Array[Object] = []
var mod_statuses: Dictionary = {}

var _loaded_ids: Array[String] = []
var _blacklist: Array[String] = []
var _core_context: Dictionary = {}
var _api: Node
var _logger: Node
var _hooks: Node
var _event_adapter: Node
var _settings_registry: Node
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
    _event_adapter = _core_context.get("event_adapter")
    _settings_registry = _core_context.get("settings_registry")


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

    var valid_candidates: Array[Dictionary] = []
    var pending_ids: Array[String] = []
    for candidate in candidates:
        if candidate.get("skip", false) or not candidate.get("mounted", false):
            continue
        if not candidate.has("meta"):
            _fail_candidate(candidate, "Missing mod metadata", "invalid")
            continue

        var meta: Dictionary = candidate.get("meta", {})
        var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))
        _set_mod_status(mod_id, "discovered", meta)

        if is_blacklisted(mod_id):
            _set_mod_status(mod_id, "disabled", meta, "blacklisted")
            _log_info("skipping blacklisted mod: %s" % mod_id)
            candidate["skip"] = true
            continue

        if _loaded_ids.has(mod_id) or pending_ids.has(mod_id):
            _fail_candidate(candidate, "Duplicate mod id: %s" % mod_id, "invalid")
            continue

        _set_mod_status(mod_id, "validating", meta)
        if not _validate_mod(candidate):
            continue

        pending_ids.append(mod_id)
        valid_candidates.append(candidate)

    valid_candidates = _filter_unsatisfied_dependency_candidates(valid_candidates)
    valid_candidates.sort_custom(Callable(self, "_sort_candidates"))

    var ordered_candidates := _resolve_dependency_order(valid_candidates)
    _set_hook_owner_order(ordered_candidates)

    var preloaded_candidates: Array[Dictionary] = []
    for candidate in ordered_candidates:
        var meta: Dictionary = candidate.get("meta", {})
        var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))
        _set_mod_status(mod_id, "preloading", meta)
        _register_manifest_settings(meta)

        var instances = _instantiate_entrypoints(candidate)
        if instances.is_empty() and not meta.get("entrypoints", []).is_empty():
            _fail_candidate(candidate, "Failed to instantiate entrypoints", "failed")
            continue

        candidate["instances"] = instances
        preloaded_candidates.append(candidate)
        var preload_failed := false
        for inst in instances:
            var preload_result := _call_mod_phase_safe(inst, "esp_preload", meta, candidate)
            if not bool(preload_result.get("success", true)):
                preload_failed = true
                break
        if preload_failed:
            _fail_candidate(candidate, "Mod returned failure during esp_preload", "failed")
            _teardown_candidate_instances(candidate)
            preloaded_candidates.erase(candidate)
            continue
        _set_mod_status(mod_id, "preloaded", meta)

    var initialized_candidates: Array[Dictionary] = []
    for candidate in preloaded_candidates:
        var meta: Dictionary = candidate.get("meta", {})
        var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))
        if _dependencies_have_failed(meta):
            _fail_candidate(candidate, "A required dependency failed before initialization", "failed")
            _teardown_candidate_instances(candidate)
            continue

        _set_mod_status(mod_id, "initializing", meta)
        var init_failed := false
        for inst in candidate.get("instances", []):
            var result := _call_mod_phase_safe(inst, "esp_init", meta, candidate)
            if not bool(result.get("success", true)):
                init_failed = true
                break
        if init_failed:
            _fail_candidate(candidate, "Mod returned failure during esp_init", "failed")
            _teardown_candidate_instances(candidate)
            continue

        if not _register_manifest_hooks(candidate):
            _teardown_candidate_instances(candidate)
            continue

        initialized_candidates.append(candidate)
        _set_mod_status(mod_id, "initialized", meta)

    for candidate in initialized_candidates:
        var meta: Dictionary = candidate.get("meta", {})
        var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))
        if _dependencies_have_failed(meta):
            _fail_candidate(candidate, "A required dependency failed before esp_ready", "failed")
            _teardown_candidate_instances(candidate)
            continue

        _set_mod_status(mod_id, "readying", meta)
        var ready_failed := false
        for inst in candidate.get("instances", []):
            var ready_result := _call_mod_phase_safe(inst, "esp_ready", meta, candidate)
            if not bool(ready_result.get("success", true)):
                ready_failed = true
                break
        if ready_failed:
            _fail_candidate(candidate, "Mod returned failure during esp_ready", "failed")
            _teardown_candidate_instances(candidate)
            continue

        loaded_mods.append(meta.duplicate(true))
        _loaded_ids.append(mod_id)
        _set_mod_status(mod_id, "loaded", meta)
        _log_info("Activated %s v%s" % [meta.get("name"), meta.get("version")])

    _log_info("Loaded %d mod(s); %d failed" % [loaded_mods.size(), failed_mods.size()])


func get_loaded_mod_ids() -> Array[String]:
    return _loaded_ids.duplicate()


func get_loaded_mods() -> Array[Dictionary]:
    return loaded_mods.duplicate(true)


func get_failed_mods() -> Array[Dictionary]:
    return failed_mods.duplicate(true)


func get_mod_status(mod_id: String) -> Dictionary:
    var state: Dictionary = mod_statuses.get(mod_id, {})
    return state.duplicate(true)


func get_all_mod_statuses() -> Dictionary:
    return mod_statuses.duplicate(true)


func get_mod_errors(mod_id: String) -> Array:
    var state: Dictionary = mod_statuses.get(mod_id, {})
    var errors: Array = state.get("errors", [])
    return errors.duplicate(true)


func record_mod_error(mod_id: String, message: String, details: Dictionary = {}) -> void:
    var state := get_mod_status(mod_id)
    if state.is_empty():
        state = _make_status_entry(mod_id, {})

    var errors: Array = state.get("errors", [])
    errors.append({
        "message": message,
        "details": details.duplicate(true),
        "timestamp": Time.get_unix_time_from_system()
    })
    state["errors"] = errors
    state["status"] = "errored" if bool(state.get("loaded", false)) else String(state.get("status", "failed"))
    state["reason"] = message
    state["loaded"] = bool(state.get("loaded", false))
    mod_statuses[mod_id] = state
    _update_failed_mod({
        "id": mod_id,
        "name": state.get("name", mod_id),
        "path": state.get("path", ""),
        "reason": message,
        "status": state.get("status", "errored"),
        "details": details.duplicate(true)
    })


func is_blacklisted(mod_id: String) -> bool:
    return _blacklist.has(mod_id)


func get_blacklisted_mod_ids() -> Array[String]:
    return _blacklist.duplicate()


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


func _validate_mod(candidate: Dictionary) -> bool:
    var meta: Dictionary = candidate.get("meta", {})
    var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))
    if candidate.get("metadata_missing", false):
        _fail_candidate(candidate, "Missing mod.json metadata", "invalid")
        return false
    if not bool(meta.get("_has_schema_version", false)):
        _fail_candidate(candidate, "Missing required manifest field 'schema_version'", "invalid")
        return false

    var schema_version := int(meta.get("schema_version", 0))
    if schema_version != SUPPORTED_SCHEMA:
        _fail_candidate(candidate, "Unsupported mod schema_version %d; expected %d" % [schema_version, SUPPORTED_SCHEMA], "invalid")
        return false

    if not bool(meta.get("_has_id", false)):
        _fail_candidate(candidate, "Missing required manifest field 'id'", "invalid")
        return false

    var id_error := _validate_mod_id(mod_id)
    if not id_error.is_empty():
        _fail_candidate(candidate, id_error, "invalid")
        return false

    if mod_id == CORE_MOD_ID and meta.get("core", false):
        _log_info("validated core metadata %s" % mod_id)
        return true

    var required_presence := {
        "name": bool(meta.get("_has_name", false)),
        "version": bool(meta.get("_has_version", false)),
        "description": bool(meta.get("_has_description", false)),
        "author": bool(meta.get("_has_author", false))
    }
    for presence_field in required_presence.keys():
        if not bool(required_presence[presence_field]):
            _fail_candidate(candidate, "Missing required manifest field '%s'" % presence_field, "invalid")
            return false

    var author_info := _normalize_author(meta.get("author_info", meta.get("author", "")))
    var required_fields := {
        "name": String(meta.get("name", "")).strip_edges(),
        "version": String(meta.get("version", "")).strip_edges(),
        "description": String(meta.get("description", "")).strip_edges(),
        "author": String(author_info.get("name", "")).strip_edges()
    }
    for field_name in required_fields.keys():
        if String(required_fields[field_name]).is_empty():
            _fail_candidate(candidate, "Missing required manifest field '%s'" % field_name, "invalid")
            return false

    var version := String(meta.get("version", "")).strip_edges()
    if not _version_string_looks_valid(version):
        _fail_candidate(candidate, "Invalid version string '%s'" % version, "invalid")
        return false

    var req_ver := String(meta.get("required_framework_version", meta.get("loader_version", "*"))).strip_edges()
    if not _version_requirement_satisfied(req_ver, CORE_VERSION):
        _fail_candidate(candidate, "Requires ESP %s, but running %s" % [req_ver, CORE_VERSION], "invalid")
        return false

    if not _game_requirement_satisfied(meta, candidate):
        return false
    if not _validate_dependencies(meta, candidate):
        return false
    if not _validate_hooks_manifest(meta, candidate):
        return false
    if not _validate_permissions(meta, candidate):
        return false
    if not _validate_settings_manifest(meta, candidate):
        return false

    _log_info("validated %s (requires ESP %s)" % [mod_id, req_ver])
    return true


func _call_mod_phase(instance: Object, method_name: String, meta: Dictionary) -> Variant:
    if instance == null or not instance.has_method(method_name):
        return null
    return instance.call(method_name, _api, meta)


func _call_mod_phase_safe(instance: Object, method_name: String, meta: Dictionary, candidate: Dictionary) -> Dictionary:
    if instance == null or not instance.has_method(method_name):
        return {"called": false, "success": true, "return": null}

    var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))
    var result = instance.call(method_name, _api, meta)
    return {
        "called": true,
        "success": result != false,
        "return": result,
        "mod_id": mod_id
    }


func _instantiate_entrypoints(candidate: Dictionary) -> Array:
    var meta: Dictionary = candidate.get("meta", {})
    var instances := []
    for entrypoint in meta.get("entrypoints", []):
        var entry_path := _resolve_entrypoint_path(String(entrypoint), candidate, meta)
        if entry_path.is_empty():
            return []

        var script := load(entry_path)
        if script == null:
            _fail_candidate(candidate, "Missing entrypoint: %s" % entry_path, "failed")
            return []

        var instance = script.new()
        if instance == null:
            _fail_candidate(candidate, "Failed to instantiate entrypoint: %s" % entry_path, "failed")
            return []

        if instance is Node:
            instance.name = "Mod_%s" % String(meta.get("id", "unknown"))
            get_tree().root.add_child(instance)

        entrypoint_instances.append(instance)
        instances.append(instance)
    return instances


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
            "schema_version": 1,
            "id": CORE_MOD_ID,
            "name": "ExtraStimulantsPlus",
            "version": CORE_VERSION,
            "author": {
                "name": "bybrooklyn"
            },
            "description": "Core modding framework and built-in ExtraStimulantsPlus systems.",
            "dependencies": {},
            "entrypoints": []
        }

    meta["id"] = CORE_MOD_ID
    meta["core"] = true
    meta = _normalize_metadata(meta, {"base_id": CORE_MOD_ID, "kind": "core", "path": "res://", "metadata_path": "res://mod.json"})
    loaded_mods.append(meta)
    _loaded_ids.append(CORE_MOD_ID)
    _set_mod_status(CORE_MOD_ID, "loaded", meta)


func _normalize_scan_dirs(mods_dirs: Array) -> Array[String]:
    var dirs: Array[String] = []

    for raw in mods_dirs:
        if raw is String and not raw.is_empty():
            _append_unique(dirs, raw)

    var exe_dir := OS.get_executable_path().get_base_dir()
    _append_unique(dirs, exe_dir.path_join("modloader"))
    _append_unique(dirs, exe_dir.path_join("mods"))

    if OS.get_name() == "macOS":
        var contents_dir := exe_dir.get_base_dir()
        var app_root := contents_dir.get_base_dir()
        var beside_app := app_root.get_base_dir()
        _append_unique(dirs, app_root.path_join("modloader"))
        _append_unique(dirs, app_root.path_join("mods"))
        _append_unique(dirs, beside_app.path_join("mods"))

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
            _fail_candidate(candidate, "Failed to mount pack", "failed")


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
            candidate["metadata_missing"] = true
            meta = _default_metadata(candidate)
        else:
            candidate["metadata_missing"] = false

        meta = _normalize_metadata(meta, candidate)
        candidate["meta"] = meta


func _read_pack_metadata(candidate: Dictionary) -> Dictionary:
    var dir := DirAccess.open("res://mods/")
    if dir:
        dir.list_dir_begin()
        var sub_dir := dir.get_next()
        while sub_dir != "":
            if dir.current_is_dir() and not sub_dir.begins_with("."):
                var meta_path := "res://mods/".path_join(sub_dir).path_join("mod.json")
                if FileAccess.file_exists(meta_path):
                    var meta := _read_mod_metadata_from_path(meta_path)
                    if not meta.is_empty():
                        meta["_metadata_path"] = meta_path
                        return meta
            sub_dir = dir.get_next()
        dir.list_dir_end()

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
    var author_info := _normalize_author(meta.get("author", "Unknown"))
    var dependencies := _normalize_dependencies(meta.get("dependencies", []))
    var framework_requirement := _resolve_framework_requirement(meta, dependencies)
    dependencies.erase("esp")
    dependencies.erase(CORE_MOD_ID)

    var game_req := _normalize_game_requirement(meta)
    var hooks_manifest := _normalize_hooks_manifest(meta.get("hooks", {}))
    var settings_manifest := _normalize_settings_manifest(meta.get("settings", {}))
    var settings_flat := _flatten_settings_manifest(settings_manifest)

    var normalized := {
        "schema_version": int(meta.get("schema_version", meta.get("schema", 1))),
        "schema": int(meta.get("schema_version", meta.get("schema", 1))),
        "_has_schema_version": meta.has("schema_version"),
        "_has_id": meta.has("id"),
        "_has_name": meta.has("name"),
        "_has_version": meta.has("version"),
        "_has_description": meta.has("description"),
        "_has_author": _manifest_has_author(meta),
        "id": String(meta.get("id", base_id)).strip_edges(),
        "name": String(meta.get("name", base_id)).strip_edges(),
        "version": String(meta.get("version", "0.0.0")).strip_edges(),
        "loader_version": framework_requirement,
        "required_framework_version": framework_requirement,
        "author": String(author_info.get("name", "Unknown")).strip_edges(),
        "author_name": String(author_info.get("name", "Unknown")).strip_edges(),
        "author_url": String(author_info.get("url", "")).strip_edges(),
        "author_info": author_info,
        "description": String(meta.get("description", "No description provided.")).strip_edges(),
        "homepage": String(meta.get("homepage", meta.get("docs", meta.get("documentation", "")))).strip_edges(),
        "icon": String(meta.get("icon", "")).strip_edges(),
        "tags": _string_array(meta.get("tags", [])),
        "dependencies": dependencies,
        "dependency_ids": _dependency_ids_from_map(dependencies),
        "entrypoints": _string_array(meta.get("entrypoints", [])),
        "game": game_req,
        "game_id": String(game_req.get("id", SUPPORTED_GAME_ID)).strip_edges(),
        "game_versions": String(game_req.get("versions", "*")).strip_edges(),
        "game_versions_list": _string_array(game_req.get("versions_list", [])),
        "priority": int(meta.get("priority", 100)),
        "permissions": _normalize_permissions(meta.get("permissions", [])),
        "hooks": hooks_manifest,
        "settings": settings_manifest,
        "settings_flat": settings_flat,
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
        "schema_version": 1,
        "id": base_id,
        "name": base_id,
        "version": "0.0.0",
        "author": {
            "name": "Unknown"
        },
        "description": "No mod.json was found. This mod pack was mounted but has no entrypoints.",
        "dependencies": {},
        "entrypoints": [],
        "priority": 100,
        "game_versions": "*"
    }


func _sort_candidates(a: Dictionary, b: Dictionary) -> bool:
    var ma: Dictionary = a.get("meta", {})
    var mb: Dictionary = b.get("meta", {})
    var pa := int(ma.get("priority", 100))
    var pb := int(mb.get("priority", 100))
    if pa == pb:
        return String(ma.get("id", "")) < String(mb.get("id", ""))
    return pa < pb


func _filter_unsatisfied_dependency_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
    var known_versions := _build_known_versions(candidates)
    var survivors: Array[Dictionary] = []
    for candidate in candidates:
        var meta: Dictionary = candidate.get("meta", {})
        var dependency_error := _check_dependency_graph(meta, known_versions)
        if dependency_error.is_empty():
            survivors.append(candidate)
        else:
            _fail_candidate(candidate, dependency_error, "invalid")
    return survivors


func _resolve_dependency_order(candidates: Array[Dictionary]) -> Array[Dictionary]:
    var pending := candidates.duplicate()
    var ordered: Array[Dictionary] = []
    var available_ids := _loaded_ids.duplicate()
    var available_versions := _build_loaded_versions()
    var made_progress := true

    while made_progress and not pending.is_empty():
        made_progress = false
        for candidate in pending.duplicate():
            var meta: Dictionary = candidate.get("meta", {})
            if _dependencies_satisfied(meta, available_ids, available_versions):
                ordered.append(candidate)
                var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))
                available_ids.append(mod_id)
                available_versions[mod_id] = String(meta.get("version", "0.0.0"))
                pending.erase(candidate)
                made_progress = true

    if not pending.is_empty():
        for candidate in pending:
            _fail_candidate(candidate, "Missing or circular dependencies: %s" % JSON.stringify(_dependency_ids_from_map(candidate.get("meta", {}).get("dependencies", {}))), "invalid")

    return ordered


func _dependencies_satisfied(meta: Dictionary, available_ids: Array[String], available_versions: Dictionary) -> bool:
    var dependencies: Dictionary = meta.get("dependencies", {})
    for dep_id in dependencies.keys():
        var dep_name := String(dep_id)
        if not available_ids.has(dep_name):
            return false
        var requirement := String(dependencies.get(dep_name, "*")).strip_edges()
        var current_version := String(available_versions.get(dep_name, "0.0.0")).strip_edges()
        if not _version_requirement_satisfied(requirement, current_version):
            return false
    return true


func _game_requirement_satisfied(meta: Dictionary, candidate: Dictionary) -> bool:
    var expected_id := String(meta.get("game_id", SUPPORTED_GAME_ID)).strip_edges()
    if not expected_id.is_empty() and expected_id != "*" and expected_id != SUPPORTED_GAME_ID:
        _fail_candidate(candidate, "Requires game id '%s', but this framework targets '%s'" % [expected_id, SUPPORTED_GAME_ID], "invalid")
        return false

    var current_version := _get_running_game_version()
    var version_list: Array[String] = meta.get("game_versions_list", [])
    var version_requirement := String(meta.get("game_versions", "*")).strip_edges()

    if not version_list.is_empty() and not version_list.has("*"):
        if current_version.is_empty() or not version_list.has(current_version):
            _fail_candidate(candidate, "Requires game versions %s, but running game version is %s" % [JSON.stringify(version_list), current_version], "invalid")
            return false
        return true

    if version_requirement.is_empty() or version_requirement == "*":
        return true

    if current_version.is_empty():
        _fail_candidate(candidate, "Requires game versions %s, but running game version could not be detected" % version_requirement, "invalid")
        return false

    if not _version_requirement_satisfied(version_requirement, current_version):
        _fail_candidate(candidate, "Requires game versions %s, but running game version is %s" % [version_requirement, current_version], "invalid")
        return false

    return true


func _validate_dependencies(meta: Dictionary, candidate: Dictionary) -> bool:
    var dependencies: Dictionary = meta.get("dependencies", {})
    for dep_id in dependencies.keys():
        var dep_name := String(dep_id).strip_edges()
        var requirement := String(dependencies.get(dep_name, "*")).strip_edges()
        if dep_name.is_empty():
            _fail_candidate(candidate, "Dependency ids must not be empty", "invalid")
            return false
        if not _validate_mod_id(dep_name).is_empty():
            _fail_candidate(candidate, "Invalid dependency id '%s'" % dep_name, "invalid")
            return false
        if requirement.is_empty():
            _fail_candidate(candidate, "Dependency '%s' must declare a version requirement or '*'" % dep_name, "invalid")
            return false
    return true


func _validate_hooks_manifest(meta: Dictionary, candidate: Dictionary) -> bool:
    var hooks_manifest: Dictionary = meta.get("hooks", {})
    var known_events := _get_known_event_names()
    for hook_def in hooks_manifest.get("events", []):
        var event_name := String(hook_def.get("event", hook_def.get("name", ""))).strip_edges()
        if event_name.is_empty():
            _fail_candidate(candidate, "Hook event declarations must not contain empty names", "invalid")
            return false
        if not _declared_event_is_known(event_name, known_events):
            _log_warn("Mod %s declared unknown hook event '%s'" % [meta.get("id", "unknown"), event_name])
    for hook_def in hooks_manifest.get("cancellable_events", []):
        var event_name := String(hook_def.get("event", hook_def.get("name", ""))).strip_edges()
        if event_name.is_empty():
            _fail_candidate(candidate, "Cancellable hook event declarations must not contain empty names", "invalid")
            return false
        if not _declared_event_is_known(event_name, known_events):
            _log_warn("Mod %s declared unknown cancellable hook event '%s'" % [meta.get("id", "unknown"), event_name])
    for hook_def in hooks_manifest.get("scenes", []):
        var scene_name := String(hook_def.get("scene", hook_def.get("name", ""))).strip_edges()
        if scene_name.is_empty():
            _fail_candidate(candidate, "Hook scene declarations must not contain empty names", "invalid")
            return false
    for hook_def in hooks_manifest.get("nodes", []):
        var node_name := String(hook_def.get("node", hook_def.get("name", ""))).strip_edges()
        if node_name.is_empty():
            _fail_candidate(candidate, "Hook node declarations must not contain empty names", "invalid")
            return false
    return true


func _validate_permissions(meta: Dictionary, candidate: Dictionary) -> bool:
    var permissions: Array[String] = meta.get("permissions", [])
    var risky_permissions := ["filesystem", "hot_reload", "internet", "patching", "raw_api", "save_access"]
    for permission in permissions:
        if String(permission).strip_edges().is_empty():
            _fail_candidate(candidate, "Permissions must not contain empty values", "invalid")
            return false
        if not KNOWN_PERMISSIONS.has(String(permission)):
            _log_warn("Mod %s declared unknown permission '%s'" % [meta.get("id", "unknown"), permission])
        elif risky_permissions.has(String(permission)):
            _log_warn("Mod %s requests permission '%s'; treat this as opt-in/advanced access" % [meta.get("id", "unknown"), permission])
    return true


func _validate_settings_manifest(meta: Dictionary, candidate: Dictionary) -> bool:
    var settings_flat: Array = meta.get("settings_flat", [])
    for setting_def in settings_flat:
        var key := String(setting_def.get("key", "")).strip_edges()
        var type_name := String(setting_def.get("type", "")).strip_edges().to_lower()
        if key.is_empty():
            _fail_candidate(candidate, "Setting definitions must have a non-empty key", "invalid")
            return false
        if not SUPPORTED_SETTING_TYPES.has(type_name):
            _fail_candidate(candidate, "Setting '%s' uses unsupported type '%s'" % [key, type_name], "invalid")
            return false
        if not bool(setting_def.get("has_default", false)):
            _fail_candidate(candidate, "Setting '%s' must declare a default value" % key, "invalid")
            return false

        var options: Dictionary = setting_def.get("options", {})
        if options.has("min") and options.has("max"):
            if float(options.get("min")) > float(options.get("max")):
                _fail_candidate(candidate, "Setting '%s' has min greater than max" % key, "invalid")
                return false
    return true


func _validate_mod_id(mod_id: String) -> String:
    var clean := mod_id.strip_edges()
    if clean.is_empty():
        return "Mod id must not be empty"
    for i in range(clean.length()):
        var ch := clean[i]
        var is_lower := ch >= "a" and ch <= "z"
        var is_digit := ch >= "0" and ch <= "9"
        var is_symbol := ch == "." or ch == "_" or ch == "-"
        if not (is_lower or is_digit or is_symbol):
            return "Invalid mod id '%s'. Use lowercase letters, digits, dot, underscore, or hyphen." % clean
    return ""


func _check_dependency_graph(meta: Dictionary, known_versions: Dictionary) -> String:
    var dependencies: Dictionary = meta.get("dependencies", {})
    var mod_id := String(meta.get("id", "unknown"))
    for dep_id in dependencies.keys():
        var dep_name := String(dep_id)
        var requirement := String(dependencies.get(dep_name, "*")).strip_edges()
        if dep_name == mod_id:
            return "Mod cannot depend on itself"
        if not known_versions.has(dep_name):
            return "Missing dependency '%s'" % dep_name
        var dep_version := String(known_versions.get(dep_name, "0.0.0"))
        if not _version_requirement_satisfied(requirement, dep_version):
            return "Dependency '%s' requires %s, but available version is %s" % [dep_name, requirement, dep_version]
    return ""


func _dependencies_have_failed(meta: Dictionary) -> bool:
    var dependencies: Dictionary = meta.get("dependencies", {})
    for dep_id in dependencies.keys():
        var dep_name := String(dep_id)
        var dep_state: Dictionary = mod_statuses.get(dep_name, {})
        var status := String(dep_state.get("status", ""))
        if status == "failed" or status == "invalid" or status == "errored":
            return true
    return false


func _register_manifest_settings(meta: Dictionary) -> void:
    if _settings_registry == null:
        _settings_registry = _core_context.get("settings_registry", get_node_or_null("/root/ESPSettingsRegistry"))
    if _settings_registry == null or not _settings_registry.has_method("register"):
        return

    var mod_id := String(meta.get("id", ""))
    for setting_def in meta.get("settings_flat", []):
        var options: Dictionary = setting_def.get("options", {}).duplicate(true)
        options["manifest_declared"] = true
        options["path"] = setting_def.get("path", [])
        options["group"] = String(setting_def.get("group", ""))
        _settings_registry.register(
            mod_id,
            String(setting_def.get("key", "")),
            int(setting_def.get("variant_type", TYPE_STRING)),
            setting_def.get("default", null),
            options
        )


func _set_hook_owner_order(ordered_candidates: Array[Dictionary]) -> void:
    if _hooks == null:
        _hooks = _core_context.get("hooks", get_node_or_null("/root/ESPHooks"))
    if _hooks == null or not _hooks.has_method("set_owner_order"):
        return

    var owner_ids := _loaded_ids.duplicate()
    for candidate in ordered_candidates:
        var meta: Dictionary = candidate.get("meta", {})
        var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))
        if not owner_ids.has(mod_id):
            owner_ids.append(mod_id)
    _hooks.set_owner_order(owner_ids)


func _register_manifest_hooks(candidate: Dictionary) -> bool:
    if _hooks == null:
        _hooks = _core_context.get("hooks", get_node_or_null("/root/ESPHooks"))
    if _hooks == null:
        _fail_candidate(candidate, "Hook runtime is unavailable", "failed")
        return false

    var meta: Dictionary = candidate.get("meta", {})
    var hooks_manifest: Dictionary = meta.get("hooks", {})
    if hooks_manifest.is_empty():
        return true

    var instances: Array = candidate.get("instances", [])
    if instances.is_empty() and _manifest_has_hook_declarations(hooks_manifest):
        _fail_candidate(candidate, "Manifest declares hooks but no entrypoint instances are available", "failed")
        return false

    for hook_def in hooks_manifest.get("events", []):
        if not _register_manifest_hook(candidate, hook_def, false):
            return false
    for hook_def in hooks_manifest.get("cancellable_events", []):
        if not _register_manifest_hook(candidate, hook_def, true):
            return false
    for hook_def in hooks_manifest.get("scenes", []):
        if not _register_manifest_hook(candidate, hook_def, false):
            return false
    for hook_def in hooks_manifest.get("nodes", []):
        if not _register_manifest_hook(candidate, hook_def, false):
            return false

    return true


func _manifest_has_hook_declarations(hooks_manifest: Dictionary) -> bool:
    for key in ["events", "cancellable_events", "scenes", "nodes"]:
        var values: Array = hooks_manifest.get(key, [])
        if not values.is_empty():
            return true
    return false


func _register_manifest_hook(candidate: Dictionary, hook_def: Dictionary, cancellable: bool) -> bool:
    var meta: Dictionary = candidate.get("meta", {})
    var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))
    var hook_kind := String(hook_def.get("kind", "event"))
    var hook_name := String(hook_def.get("name", hook_def.get(hook_kind, ""))).strip_edges()
    var method_name := String(hook_def.get("method", "")).strip_edges()
    var priority := int(hook_def.get("priority", meta.get("priority", 100)))
    var once := bool(hook_def.get("once", false))

    if hook_name.is_empty() or method_name.is_empty():
        _fail_candidate(candidate, "Invalid hook declaration for mod %s" % mod_id, "invalid")
        return false

    var registered := false
    var missing_targets: Array[String] = []
    for inst in candidate.get("instances", []):
        if inst == null or not is_instance_valid(inst):
            continue
        if not inst.has_method(method_name):
            missing_targets.append(String(inst))
            continue

        var ok := false
        match hook_kind:
            "event":
                if _hooks.has_method("on_event"):
                    ok = _hooks.on_event(hook_name, inst, method_name, priority, mod_id, once)
            "scene":
                if _hooks.has_method("on_scene_named"):
                    ok = _hooks.on_scene_named(hook_name, inst, method_name, priority, mod_id)
                elif _hooks.has_method("on_scene_changed"):
                    ok = _hooks.on_scene_changed(inst, method_name, priority, mod_id)
            "node":
                if _hooks.has_method("on_node_named"):
                    ok = _hooks.on_node_named(hook_name, inst, method_name, priority, mod_id)
            _:
                _fail_candidate(candidate, "Unsupported hook kind '%s'" % hook_kind, "invalid")
                return false

        if ok:
            registered = true
            _log_info("registered %s hook '%s' for %s.%s" % [hook_kind, hook_name, mod_id, method_name])
        elif cancellable:
            _log_info("registered cancellable hook declaration for %s.%s on %s" % [mod_id, method_name, hook_name])

    if not registered:
        var reason := "Manifest hook '%s' could not bind method '%s'" % [hook_name, method_name]
        if not missing_targets.is_empty():
            reason += " on any entrypoint instance"
        _fail_candidate(candidate, reason, "failed")
        return false
    return true


func _teardown_candidate_instances(candidate: Dictionary) -> void:
    for inst in candidate.get("instances", []):
        entrypoint_instances.erase(inst)
        if inst is Node and is_instance_valid(inst):
            inst.queue_free()


func _manifest_has_author(meta: Dictionary) -> bool:
    if not meta.has("author"):
        return false
    var raw_author = meta.get("author")
    if raw_author is Dictionary:
        return not String(raw_author.get("name", "")).strip_edges().is_empty()
    return not String(raw_author).strip_edges().is_empty()


func _normalize_author(value) -> Dictionary:
    if value is Dictionary:
        return {
            "name": String(value.get("name", "Unknown")).strip_edges(),
            "url": String(value.get("url", value.get("homepage", ""))).strip_edges()
        }
    return {
        "name": String(value).strip_edges() if value != null else "Unknown",
        "url": ""
    }


func _normalize_dependencies(value) -> Dictionary:
    var out := {}
    if value is Dictionary:
        for dep_id in value.keys():
            var dep_name := String(dep_id).strip_edges()
            if dep_name.is_empty():
                continue
            var dep_value = value.get(dep_id, "*")
            var requirement := "*"
            if dep_value is Dictionary:
                requirement = String(dep_value.get("version", "*")).strip_edges()
            else:
                requirement = String(dep_value).strip_edges()
            if requirement.is_empty():
                requirement = "*"
            out[dep_name] = requirement
    elif value is Array:
        for dep in value:
            var dep_name := String(dep).strip_edges()
            if not dep_name.is_empty():
                out[dep_name] = "*"
    elif value is String:
        var dep_name := String(value).strip_edges()
        if not dep_name.is_empty():
            out[dep_name] = "*"
    return out


func _normalize_game_requirement(meta: Dictionary) -> Dictionary:
    var raw_game = meta.get("game", {})
    var game_id := String(meta.get("game_id", "")).strip_edges()
    var game_versions := meta.get("game_versions", "")
    var version_list: Array[String] = []
    var version_requirement := ""

    if raw_game is Dictionary:
        if game_id.is_empty():
            game_id = String(raw_game.get("id", SUPPORTED_GAME_ID)).strip_edges()
        var legacy_versions = raw_game.get("versions", [])
        if legacy_versions is Array:
            version_list = _string_array(legacy_versions)
        elif legacy_versions is String:
            version_requirement = String(legacy_versions).strip_edges()

    if game_versions is Array:
        version_list = _string_array(game_versions)
    elif game_versions is String and not String(game_versions).strip_edges().is_empty():
        version_requirement = String(game_versions).strip_edges()

    if game_id.is_empty():
        game_id = SUPPORTED_GAME_ID
    if version_requirement.is_empty() and version_list.is_empty():
        version_requirement = "*"

    return {
        "id": game_id,
        "versions": version_requirement if not version_requirement.is_empty() else "*",
        "versions_list": version_list
    }


func _normalize_hooks_manifest(value) -> Dictionary:
    var normalized := {
        "events": [],
        "cancellable_events": [],
        "scenes": [],
        "nodes": []
    }
    if value is Dictionary:
        normalized["events"] = _normalize_hook_declarations(value.get("events", []), "event", false)
        normalized["cancellable_events"] = _normalize_hook_declarations(value.get("cancellable_events", value.get("cancellable", [])), "event", true)
        normalized["scenes"] = _normalize_hook_declarations(value.get("scenes", []), "scene", false)
        normalized["nodes"] = _normalize_hook_declarations(value.get("nodes", []), "node", false)
    return normalized


func _normalize_hook_declarations(value, hook_kind: String, cancellable: bool) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var raw_items := []
    if value is Array:
        raw_items = value
    elif value is Dictionary or value is String:
        raw_items = [value]

    for raw in raw_items:
        var hook_def := _normalize_hook_declaration(raw, hook_kind, cancellable)
        if not hook_def.is_empty():
            out.append(hook_def)
    return out


func _normalize_hook_declaration(raw, hook_kind: String, cancellable: bool) -> Dictionary:
    var name := ""
    var method := ""
    var priority := 100
    var once := false

    if raw is Dictionary:
        name = String(raw.get(hook_kind, raw.get("name", raw.get("event", raw.get("scene", raw.get("node", "")))))).strip_edges()
        method = String(raw.get("method", "")).strip_edges()
        priority = int(raw.get("priority", 100))
        once = bool(raw.get("once", false))
    elif raw is String:
        name = String(raw).strip_edges()

    if name.is_empty():
        return {}
    if method.is_empty():
        method = _default_hook_method_name(hook_kind, name)

    return {
        "kind": hook_kind,
        "name": name,
        "event": name if hook_kind == "event" else "",
        "scene": name if hook_kind == "scene" else "",
        "node": name if hook_kind == "node" else "",
        "method": method,
        "priority": priority,
        "once": once,
        "cancellable": cancellable
    }


func _default_hook_method_name(hook_kind: String, name: String) -> String:
    var clean := ""
    for i in range(name.length()):
        var ch := name[i].to_lower()
        var is_alnum := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
        clean += ch if is_alnum else "_"
    while clean.contains("__"):
        clean = clean.replace("__", "_")
    clean = clean.strip_edges().trim_prefix("_").trim_suffix("_")
    if clean.is_empty():
        clean = "hook"
    return "_on_esp_%s_%s" % [hook_kind, clean]


func _normalize_permissions(value) -> Array[String]:
    var out: Array[String] = []
    if value is Array:
        out = _string_array(value)
    elif value is Dictionary:
        for permission in value.keys():
            if bool(value.get(permission, false)):
                var name := String(permission).strip_edges()
                if not name.is_empty():
                    out.append(name)
    elif value is String:
        var name := String(value).strip_edges()
        if not name.is_empty():
            out.append(name)
    out.sort()
    return out


func _normalize_settings_manifest(value) -> Dictionary:
    if value is Dictionary:
        return value.duplicate(true)
    return {}


func _flatten_settings_manifest(settings_manifest: Dictionary) -> Array:
    var out: Array = []
    _collect_settings_group(settings_manifest, [], out)
    return out


func _collect_settings_group(group: Dictionary, path: Array, out: Array) -> void:
    for key in group.keys():
        var entry_key := String(key).strip_edges()
        if entry_key.is_empty():
            continue

        var entry = group.get(key)
        if not (entry is Dictionary):
            continue

        if entry.has("settings") and entry.get("settings") is Dictionary:
            var next_path := path.duplicate()
            next_path.append(entry_key)
            _collect_settings_group(entry.get("settings", {}), next_path, out)
            continue

        if entry.has("type"):
            var type_name := String(entry.get("type", "")).strip_edges().to_lower()
            var setting_path := path.duplicate()
            setting_path.append(entry_key)
            var options := entry.duplicate(true)
            options.erase("type")
            options.erase("default")
            options.erase("settings")
            options["label"] = String(entry.get("label", entry_key.capitalize())).strip_edges()
            options["description"] = String(entry.get("description", "")).strip_edges()
            options["group_path"] = path.duplicate()
            out.append({
                "key": ".".join(setting_path),
                "path": setting_path,
                "group": "/".join(path),
                "type": type_name,
                "variant_type": _setting_type_to_variant(type_name),
                "default": entry.get("default", null),
                "has_default": entry.has("default"),
                "options": options
            })


func _resolve_framework_requirement(meta: Dictionary, dependencies: Dictionary) -> String:
    var direct := String(meta.get("required_framework_version", meta.get("loader_version", ""))).strip_edges()
    if not direct.is_empty():
        return direct
    for key in ["esp", CORE_MOD_ID]:
        if dependencies.has(key):
            return String(dependencies.get(key, "*")).strip_edges()
    return "*"


func _setting_type_to_variant(type_name: String) -> int:
    return int(SUPPORTED_SETTING_TYPES.get(type_name, TYPE_STRING))


func _dependency_ids_from_map(dependencies: Dictionary) -> Array[String]:
    var out: Array[String] = []
    for dep_id in dependencies.keys():
        out.append(String(dep_id))
    out.sort()
    return out


func _declared_event_is_known(event_name: String, known_events: Array[String]) -> bool:
    var normalized := event_name.strip_edges().to_lower()
    if normalized.is_empty():
        return false
    if normalized.contains("."):
        return true
    if normalized.contains("*") or normalized.contains("?"):
        for known in known_events:
            if String(known).match(normalized):
                return true
        return true
    return known_events.has(normalized)


func _get_known_event_names() -> Array[String]:
    if _event_adapter == null:
        _event_adapter = _core_context.get("event_adapter", get_node_or_null("/root/ESPEventAdapter"))
    if _event_adapter and _event_adapter.has_method("get_available_events"):
        return _event_adapter.get_available_events()
    return []


func _build_loaded_versions() -> Dictionary:
    var versions := {}
    for meta in loaded_mods:
        if meta is Dictionary:
            versions[String(meta.get("id", ""))] = String(meta.get("version", "0.0.0"))
    return versions


func _build_known_versions(candidates: Array[Dictionary]) -> Dictionary:
    var versions := _build_loaded_versions()
    for candidate in candidates:
        var meta: Dictionary = candidate.get("meta", {})
        versions[String(meta.get("id", candidate.get("base_id", "unknown")))] = String(meta.get("version", "0.0.0"))
    return versions


func _get_running_game_version() -> String:
    return String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()


func _version_requirement_satisfied(requirement: String, current: String) -> bool:
    var req := requirement.strip_edges()
    if req.is_empty() or req == "*":
        return true

    for clause in req.replace(",", " ").split("||", false):
        if _version_clause_satisfied(String(clause).strip_edges(), current):
            return true
    return false


func _version_clause_satisfied(clause: String, current: String) -> bool:
    if clause.is_empty() or clause == "*":
        return true

    var tokens := clause.split(" ", false)
    for token in tokens:
        if not _version_token_satisfied(String(token).strip_edges(), current):
            return false
    return true


func _version_token_satisfied(token: String, current: String) -> bool:
    if token.is_empty() or token == "*":
        return true

    var operators := [">=", "<=", "==", ">", "<", "="]
    for op in operators:
        if token.begins_with(op):
            var expected := token.substr(op.length()).strip_edges()
            var cmp := _compare_versions(current, expected)
            match op:
                ">=":
                    return cmp >= 0
                "<=":
                    return cmp <= 0
                ">":
                    return cmp > 0
                "<":
                    return cmp < 0
                "=", "==":
                    return cmp == 0
    return _compare_versions(current, token) == 0


func _version_string_looks_valid(version: String) -> bool:
    var clean := version.strip_edges().trim_prefix("v")
    if clean.is_empty():
        return false
    for i in range(clean.length()):
        var ch := clean[i]
        var is_digit := ch >= "0" and ch <= "9"
        var is_alpha := (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")
        if not is_digit and not is_alpha and ch != "." and ch != "-" and ch != "+" and ch != "_":
            return false
    return true


func _compare_versions(a: String, b: String) -> int:
    var av := _parse_version(a)
    var bv := _parse_version(b)
    for i in range(3):
        if av[i] < bv[i]:
            return -1
        if av[i] > bv[i]:
            return 1
    return 0


func _parse_version(version: String) -> Array[int]:
    var out: Array[int] = [0, 0, 0]
    var clean := version.strip_edges().trim_prefix("v")
    var suffix_idx := clean.find("-")
    if suffix_idx >= 0:
        clean = clean.substr(0, suffix_idx)

    if clean.find(".") == -1 and clean.is_valid_int():
        out[0] = 0
        out[1] = int(clean)
        out[2] = 0
        return out

    var parts := clean.split(".")
    for i in range(min(parts.size(), 3)):
        var digits := ""
        for j in range(String(parts[i]).length()):
            var ch := String(parts[i])[j]
            if ch >= "0" and ch <= "9":
                digits += ch
            else:
                break
        out[i] = int(digits) if not digits.is_empty() else 0
    return out


func _resolve_entrypoint_path(entrypoint: String, candidate: Dictionary, meta: Dictionary) -> String:
    if entrypoint.is_empty():
        return ""
    if entrypoint.begins_with("res://") or entrypoint.begins_with("user://") or entrypoint.begins_with("/"):
        return entrypoint

    if candidate.get("kind", "") == "folder":
        return String(candidate.get("path", "")).path_join(entrypoint)

    var mod_id := String(meta.get("id", candidate.get("base_id", "")))
    return "res://mods".path_join(mod_id).path_join(entrypoint)


func _make_status_entry(mod_id: String, meta: Dictionary) -> Dictionary:
    return {
        "id": mod_id,
        "name": String(meta.get("name", mod_id)),
        "version": String(meta.get("version", "0.0.0")),
        "author": String(meta.get("author", "Unknown")),
        "description": String(meta.get("description", "")),
        "status": "unknown",
        "reason": "",
        "path": String(meta.get("path", "")),
        "kind": String(meta.get("kind", "unknown")),
        "metadata_path": String(meta.get("metadata_path", "")),
        "loaded": false,
        "disabled": false,
        "errors": [],
        "hooks": meta.get("hooks", {}).duplicate(true) if meta.has("hooks") else {},
        "permissions": meta.get("permissions", []).duplicate() if meta.has("permissions") else [],
        "tags": meta.get("tags", []).duplicate() if meta.has("tags") else []
    }


func _set_mod_status(mod_id: String, status: String, meta: Dictionary = {}, reason: String = "") -> void:
    var state: Dictionary = mod_statuses.get(mod_id, _make_status_entry(mod_id, meta))
    for key in ["name", "version", "author", "description", "path", "kind", "metadata_path", "hooks", "permissions", "tags"]:
        if meta.has(key):
            state[key] = meta.get(key)
    state["status"] = status
    state["reason"] = reason
    state["disabled"] = status == "disabled"
    state["loaded"] = status == "loaded" or status == "errored"
    mod_statuses[mod_id] = state


func _fail_candidate(candidate: Dictionary, reason: String, status: String = "failed") -> void:
    var meta: Dictionary = candidate.get("meta", _default_metadata(candidate))
    var mod_id := String(meta.get("id", candidate.get("base_id", "unknown")))
    var failure := {
        "id": mod_id,
        "name": meta.get("name", candidate.get("file_name", mod_id)),
        "path": candidate.get("path", meta.get("path", "")),
        "reason": reason,
        "status": status
    }
    _update_failed_mod(failure)
    _set_mod_status(mod_id, status, meta, reason)
    _append_status_error(mod_id, reason, {
        "source": "loader",
        "status": status,
        "path": String(failure.get("path", ""))
    })
    _log_warn("mod failed: %s" % JSON.stringify(failure))


func _append_status_error(mod_id: String, message: String, details: Dictionary = {}) -> void:
    var state: Dictionary = mod_statuses.get(mod_id, _make_status_entry(mod_id, {}))
    var errors: Array = state.get("errors", [])
    errors.append({
        "message": message,
        "details": details.duplicate(true),
        "timestamp": Time.get_unix_time_from_system()
    })
    state["errors"] = errors
    mod_statuses[mod_id] = state


func _update_failed_mod(failure: Dictionary) -> void:
    var failure_id := String(failure.get("id", ""))
    for i in range(failed_mods.size()):
        if String(failed_mods[i].get("id", "")) == failure_id:
            failed_mods[i] = failure.duplicate(true)
            return
    failed_mods.append(failure.duplicate(true))


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
    var paths = [
        "/root/ObstacleManager",
        "/root/Game/Managers/ObstacleManager",
        "/root/Main/Game/Managers/ObstacleManager"
    ]
    for p in paths:
        var n = root.get_node_or_null(p)
        if n:
            return n
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
