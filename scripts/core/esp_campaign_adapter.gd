extends Node

# Framework-owned campaign adapter. Custom levels and editor playtests should go
# through this node instead of mutating CampaignManager internals directly.

signal custom_level_registered(level_def: CampaignLevelDef, source_path: String)
signal custom_level_play_started(level_def: CampaignLevelDef, source_path: String)

const DEFAULT_THEME := "tornado"
const DEFAULT_SONG := "res://audio/Song-1.wav"
const DEFAULT_RUNTIME_DIR := "user://esp/runtime/levels"

# Allowlists for resource paths that mod-supplied level metadata can name
# directly. Anything outside falls back to the default. Without this, a mod
# could pass `res://scripts/core/esp_core.gd` as a "theme" and force load()
# to deserialize arbitrary framework resources.
const SAFE_THEME_PREFIXES: Array[String] = [
    "res://resources/themes/",
]
const SAFE_THEME_EXTS: Array[String] = ["tres", "res"]
const SAFE_SONG_PREFIXES: Array[String] = [
    "res://audio/",
]
const SAFE_SONG_EXTS: Array[String] = ["wav", "ogg", "mp3"]

var logger: Node
var hooks: Node
var level_registry: Node
var levels_dirs: Array[String] = []
var campaigns_dirs: Array[String] = []

var registered_custom_levels: Array[CampaignLevelDef] = []
var custom_level_sources: Dictionary = {}


func configure(parts: Dictionary) -> void:
    logger = parts.get("logger", logger)
    hooks = parts.get("hooks", hooks)
    level_registry = parts.get("level_registry", level_registry)
    levels_dirs = parts.get("levels_dirs", levels_dirs)
    campaigns_dirs = parts.get("campaigns_dirs", campaigns_dirs)


func register_custom_level(level_def: CampaignLevelDef, source_path: String = "") -> bool:
    if level_def == null:
        _log_warn("Cannot register null custom level")
        return false
    if level_def.stages.is_empty():
        _log_warn("Cannot register custom level '%s' without stages" % level_def.level_name)
        return false

    level_def.validate_stage_ids()
    if not registered_custom_levels.has(level_def):
        registered_custom_levels.append(level_def)
    if not source_path.is_empty():
        custom_level_sources[level_def] = source_path

    custom_level_registered.emit(level_def, source_path)
    _emit_hook("custom_level_registered", [level_def, source_path])
    _log_info("registered custom level '%s'" % level_def.level_name)
    return true


func unregister_custom_level(level_def: CampaignLevelDef) -> void:
    if registered_custom_levels.has(level_def):
        registered_custom_levels.erase(level_def)
    custom_level_sources.erase(level_def)


func get_registered_custom_levels() -> Array[CampaignLevelDef]:
    return registered_custom_levels.duplicate()


func load_custom_level_from_path(path: String, options: Dictionary = {}) -> CampaignLevelDef:
    var sequence := _load_sequence(path)
    var meta := _load_metadata(path)
    if meta.is_empty():
        meta = {}
    for key in options.keys():
        meta[key] = options[key]

    if sequence.is_empty():
        _log_warn("Custom level '%s' has no obstacles" % path)

    var runtime_path := _ensure_runtime_json(path, sequence, meta)
    if runtime_path.is_empty():
        return null

    return build_level_from_sequence(sequence, runtime_path, meta, path)


func build_level_from_sequence(sequence: Array, runtime_sequence_path: String, meta: Dictionary = {}, source_path: String = "") -> CampaignLevelDef:
    var title := String(meta.get("title", meta.get("name", ""))).strip_edges()
    if title.is_empty():
        title = source_path.get_file().get_basename() if not source_path.is_empty() else "Custom Level"

    var level_def := CampaignLevelDef.new()
    level_def.level_name = title
    level_def.description = String(meta.get("description", "Custom ExtraStimulantsPlus level"))
    level_def.difficulty_rating = int(meta.get("difficulty", meta.get("difficulty_rating", 1)))
    level_def.sort_order = int(meta.get("sort_order", 10000))
    level_def.endless = false
    level_def.length_rings = _estimate_length_rings(sequence)

    var stage := StageDef.new()
    stage.stage_name = String(meta.get("stage_name", "Custom Stage"))
    stage.stage_id = String(meta.get("stage_id", "custom_stage"))
    stage.obstacle_count = max(sequence.size(), 1)
    stage.ranked_enabled = false
    stage.zen_enabled = false
    stage.normal_enabled = true

    var theme_name := String(meta.get("theme", DEFAULT_THEME))
    var theme_res = _load_theme(theme_name)
    if theme_res:
        stage.theme = theme_res
        level_def.preview_theme = theme_res

    var song_path := String(meta.get("song", DEFAULT_SONG))
    var song_res := _load_song(song_path)
    if song_res:
        stage.song = song_res
        level_def.song = song_res

    var substage := SubStageDef.new()
    substage.obstacle_sequence_path = runtime_sequence_path
    substage.obstacle_count = max(sequence.size(), 1)
    substage.scripted_mode = true
    if theme_res:
        substage.theme = theme_res

    stage.substages.append(substage)
    level_def.stages.append(stage)
    level_def.validate_stage_ids()
    return level_def


func play_custom_level_path(path: String, options: Dictionary = {}) -> bool:
    var level_def := load_custom_level_from_path(path, options)
    if level_def == null:
        return false
    return play_custom_level(level_def, path, options)


func play_sequence(sequence: Array, meta: Dictionary = {}, source_path: String = "") -> bool:
    var runtime_path := _ensure_runtime_json(source_path, sequence, meta)
    if runtime_path.is_empty():
        return false
    var level_def := build_level_from_sequence(sequence, runtime_path, meta, source_path)
    return play_custom_level(level_def, source_path, meta)


func play_custom_level(level_def: CampaignLevelDef, source_path: String = "", options: Dictionary = {}) -> bool:
    if level_def == null:
        _log_warn("Cannot play null custom level")
        return false

    register_custom_level(level_def, source_path)

    var campaign_manager := get_node_or_null("/root/CampaignManager")
    if campaign_manager == null:
        _log_warn("CampaignManager is unavailable; cannot start custom level")
        return false

    campaign_manager.selected_campaign_level = level_def
    campaign_manager.set_meta("selected_stage_index", int(options.get("stage_index", 0)))
    campaign_manager.set_meta("practice_mode", bool(options.get("practice_mode", true)))
    campaign_manager.set_meta("esp_custom_level", true)
    campaign_manager.set_meta("esp_custom_level_source", source_path)

    var game_context := get_node_or_null("/root/GameContext")
    if game_context and game_context.has_method("set_mode"):
        game_context.set_mode(game_context.GameMode.CAMPAIGN)

    custom_level_play_started.emit(level_def, source_path)
    _emit_hook("custom_level_play_started", [level_def, source_path])
    _log_info("starting custom level '%s'" % level_def.level_name)
    get_tree().change_scene_to_file("res://scenes/game.tscn")
    return true


func inject_registered_levels(existing_levels: Array[CampaignLevelDef]) -> void:
    if level_registry and level_registry.has_method("scan_custom_levels"):
        level_registry.scan_custom_levels()
        if level_registry.has_method("get_custom_levels"):
            for level in level_registry.get_custom_levels():
                if level is CampaignLevelDef and not existing_levels.has(level):
                    existing_levels.append(level)
    for level in registered_custom_levels:
        if level is CampaignLevelDef and not existing_levels.has(level):
            existing_levels.append(level)


func _load_sequence(path: String) -> Array:
    if path.is_empty() or not FileAccess.file_exists(path):
        _log_warn("Custom level file not found: %s" % path)
        return []
    if ObstacleSequenceSerializer.has_method("load_from_path"):
        return ObstacleSequenceSerializer.load_from_path(path)
    if path.get_extension().to_lower() == "json":
        return ObstacleSequenceSerializer.load_from_json(path)
    _log_warn("This ObstacleSequenceSerializer cannot load '%s'" % path)
    return []


func _load_metadata(path: String) -> Dictionary:
    if ObstacleSequenceSerializer.has_method("load_metadata_from_path"):
        return ObstacleSequenceSerializer.load_metadata_from_path(path)
    return {}


func _ensure_runtime_json(source_path: String, sequence: Array, meta: Dictionary) -> String:
    if sequence.is_empty():
        return ""

    var ext := source_path.get_extension().to_lower()
    if ext == "json":
        return source_path

    _ensure_dir(DEFAULT_RUNTIME_DIR)
    var base_name := source_path.get_file().get_basename()
    if base_name.is_empty():
        base_name = "editor_test"
    var runtime_path := DEFAULT_RUNTIME_DIR.path_join("%s_runtime.json" % base_name)

    if ObstacleSequenceSerializer.has_method("save_to_json"):
        var ok: bool
        if ObstacleSequenceSerializer.has_method("save_to_path"):
            ok = ObstacleSequenceSerializer.save_to_json(sequence, runtime_path, meta)
        else:
            ok = ObstacleSequenceSerializer.save_to_json(sequence, runtime_path)
        if ok:
            return runtime_path
    _log_warn("Failed to create runtime JSON sequence at '%s'" % runtime_path)
    return ""


func _load_theme(theme_name: String) -> Resource:
    var clean := theme_name.strip_edges()
    if clean.is_empty():
        clean = DEFAULT_THEME
    # Short name (no scheme) maps to the canonical theme directory.
    var path := clean
    if not (clean.begins_with("res://") or clean.begins_with("user://")):
        path = "res://resources/themes/%s.tres" % clean
    if not _is_safe_resource_path(path, SAFE_THEME_PREFIXES, SAFE_THEME_EXTS):
        _log_warn("Theme path '%s' is outside the allowed prefixes; falling back to default" % path)
        path = "res://resources/themes/%s.tres" % DEFAULT_THEME
    var theme = load(path)
    if theme == null:
        _log_warn("Could not load theme '%s'" % path)
    return theme


func _load_song(song_path: String) -> AudioStream:
    var clean := song_path.strip_edges()
    if clean.is_empty():
        clean = DEFAULT_SONG
    if clean.begins_with("user://"):
        var loader = load("res://scripts/core/external_audio_loader.gd")
        if loader and loader.has_method("load_external_audio"):
            var external_song = loader.load_external_audio(clean)
            if external_song is AudioStream:
                return external_song
        _log_warn("Could not load external song '%s'" % clean)
        return null

    if not _is_safe_resource_path(clean, SAFE_SONG_PREFIXES, SAFE_SONG_EXTS):
        _log_warn("Song path '%s' is outside the allowed prefixes; falling back to default" % clean)
        clean = DEFAULT_SONG

    var song = load(clean)
    if song is AudioStream:
        return song
    _log_warn("Could not load song '%s'" % clean)
    return null


# Returns true iff `path` begins with one of `allowed_prefixes` AND has an
# extension in `allowed_exts`. Rejects `..` segments and anything that doesn't
# match the expected shape — defense-in-depth against `load()` being called
# on attacker-supplied paths.
func _is_safe_resource_path(path: String, allowed_prefixes: Array[String], allowed_exts: Array[String]) -> bool:
    if path.is_empty() or path.contains(".."):
        return false
    var prefix_ok := false
    for prefix in allowed_prefixes:
        if path.begins_with(prefix):
            prefix_ok = true
            break
    if not prefix_ok:
        return false
    var ext := path.get_extension().to_lower()
    return allowed_exts.has(ext)


func _estimate_length_rings(sequence: Array) -> int:
    var max_ring := 0
    for entry in sequence:
        if entry is ScriptedObstacleEntry:
            max_ring = maxi(max_ring, int(entry.ring_position))
    return max_ring


func _ensure_dir(path: String) -> void:
    var absolute := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
    if not DirAccess.dir_exists_absolute(absolute):
        DirAccess.make_dir_recursive_absolute(absolute)


func _emit_hook(event_name: String, args: Array) -> void:
    if hooks and hooks.has_method("emit_event"):
        hooks.emit_event(event_name, args)


func _log_info(message: String) -> void:
    if logger and logger.has_method("info"):
        logger.info("[CampaignAdapter] " + message)
    else:
        print("[ESP CampaignAdapter] ", message)


func _log_warn(message: String) -> void:
    if logger and logger.has_method("warn"):
        logger.warn("[CampaignAdapter] " + message)
    else:
        push_warning("[ESP CampaignAdapter] " + message)
