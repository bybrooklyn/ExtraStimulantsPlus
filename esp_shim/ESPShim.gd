extends Node

# ExtraStimulantsPlus Shim
#
# This is the ONLY script that should be injected into the game's main PCK.
# It mounts the external ExtraStimulantsPlus core pack as early as possible,
# then starts the real loader from that pack once this shim enters the tree.

const SHIM_VERSION := "0.2.0"
const CORE_LOADER_PATH := "res://scripts/core/esp_core.gd"
const CORE_PACK_NAMES: Array[String] = [
    "000_extrastimulantsplus_core.pck",
    "000_extrastimulantsplus_core.zip",
    "ExtraStimulantsPlus.pck",
    "ExtraStimulantsPlus.zip",
    "ExtraStimulantsPlus-core.pck",
    "ExtraStimulantsPlus-core.zip"
]

var _core_pack_path := ""
var _core_pack_loaded := false
var _core_started := false


func _init() -> void:
    # Runtime pack mounting needs to happen before the game starts touching/preloading
    # resources. Keep this tiny: do not instantiate gameplay systems here.
    _log("starting shim v%s" % SHIM_VERSION)
    _core_pack_loaded = _mount_core_pack()


func _enter_tree() -> void:
    # At this point get_tree()/root are available. Starting the external core here
    # avoids touching the SceneTree during _init(), while the pack was still mounted early.
    _start_core_loader()


func _mount_core_pack() -> bool:
    for mods_dir in _get_mod_dirs():
        _ensure_dir(mods_dir)
        for pack_name in CORE_PACK_NAMES:
            var candidate := mods_dir.path_join(pack_name)
            if FileAccess.file_exists(candidate):
                _core_pack_path = candidate
                var ok := ProjectSettings.load_resource_pack(candidate, true)
                if ok:
                    _log("mounted core pack: %s" % candidate)
                    return true
                push_error("[ESP Shim] failed to mount core pack: %s" % candidate)

    push_error("[ESP Shim] core pack not found. Put ExtraStimulantsPlus.pck or .zip in a mods folder.")
    return false


func _start_core_loader() -> void:
    if _core_started:
        return
    _core_started = true

    if not _core_pack_loaded:
        return

    var root := get_tree().root
    if root.get_node_or_null("ESP") or root.get_node_or_null("ESPModLoader"):
        _log("core already started; skipping duplicate startup")
        return

    var loader_script := load(CORE_LOADER_PATH)
    if loader_script == null:
        push_error("[ESP Shim] mounted core pack, but missing core loader: %s" % CORE_LOADER_PATH)
        return

    var loader = loader_script.new()
    loader.name = "ESPCore"

    if loader.has_method("set_boot_info"):
        loader.set_boot_info({
            "shim_version": SHIM_VERSION,
            "core_pack_path": _core_pack_path,
            "mods_dirs": _get_mod_dirs(),
            "modloader_dir": _resolve_modloader_dir(),
            "levels_dirs": _get_content_dirs("levels"),
            "campaigns_dirs": _get_content_dirs("campaigns")
        })

    root.add_child(loader)
    _log("started external core loader")


func _get_mod_dirs() -> Array[String]:
    var dirs: Array[String] = []
    var exe_dir := OS.get_executable_path().get_base_dir()

    # Priority 1: Framework Directory
    _append_unique(dirs, exe_dir.path_join("modloader"))
    
    # Priority 2: User Mods Beside Executable
    _append_unique(dirs, exe_dir.path_join("mods"))

    if OS.get_name() == "macOS":
        var contents_dir := exe_dir.get_base_dir()           # .app/Contents
        var resources_dir := contents_dir.path_join("Resources")
        var app_root := contents_dir.get_base_dir()          # .app
        var beside_app := app_root.get_base_dir()            # parent of .app
        # Priority: where `esp install` actually wrote things (next to PCK).
        _append_unique(dirs, resources_dir.path_join("modloader"))
        _append_unique(dirs, resources_dir.path_join("mods"))
        # Legacy fallbacks, kept for users who installed outside the bundle.
        _append_unique(dirs, app_root.path_join("modloader"))
        _append_unique(dirs, app_root.path_join("mods"))
        _append_unique(dirs, beside_app.path_join("mods"))

    # Priority 3: Persistent User Data
    _append_unique(dirs, OS.get_user_data_dir().path_join("mods"))

    return dirs


func _get_content_dirs(folder_name: String) -> Array[String]:
    var dirs: Array[String] = []
    var exe_dir := OS.get_executable_path().get_base_dir()
    _append_unique(dirs, exe_dir.path_join(folder_name))

    if OS.get_name() == "macOS":
        var contents_dir := exe_dir.get_base_dir()           # .app/Contents
        var resources_dir := contents_dir.path_join("Resources")
        var app_root := contents_dir.get_base_dir()          # .app
        var beside_app := app_root.get_base_dir()
        _append_unique(dirs, resources_dir.path_join(folder_name))
        _append_unique(dirs, app_root.path_join(folder_name))
        _append_unique(dirs, beside_app.path_join(folder_name))

    _append_unique(dirs, OS.get_user_data_dir().path_join(folder_name))
    for path in dirs:
        _ensure_dir(path)
    return dirs


# Mirrors the macOS candidate set in _get_mod_dirs(). Picks the first existing
# modloader/ directory so we read user_profile.json / write mod_statuses.json
# in the same place the Rust orchestrator wrote them. Falls back to exe-dir
# on a fresh install where no candidate exists yet.
func _resolve_modloader_dir() -> String:
    var exe_dir := OS.get_executable_path().get_base_dir()
    var candidates: Array[String] = [exe_dir.path_join("modloader")]
    if OS.get_name() == "macOS":
        var contents_dir := exe_dir.get_base_dir()
        candidates.append(contents_dir.path_join("Resources/modloader"))
        candidates.append(contents_dir.get_base_dir().path_join("modloader"))  # .app/modloader
    for path in candidates:
        if DirAccess.dir_exists_absolute(path):
            return path
    # No existing candidate — try to create the primary one so callers get a
    # path that actually resolves. If creation fails, return "" so the caller
    # can bail out instead of silently writing into a nonexistent dir.
    var err := DirAccess.make_dir_recursive_absolute(candidates[0])
    if err == OK or DirAccess.dir_exists_absolute(candidates[0]):
        return candidates[0]
    push_warning("[ESP Shim] failed to create modloader dir %s: %s" % [candidates[0], str(err)])
    return ""


func _append_unique(list: Array[String], value: String) -> void:
    if value.is_empty():
        return
    if not list.has(value):
        list.append(value)


func _ensure_dir(path: String) -> void:
    if DirAccess.dir_exists_absolute(path):
        return
    var err := DirAccess.make_dir_recursive_absolute(path)
    if err != OK:
        push_warning("[ESP Shim] failed to create mods directory %s: %s" % [path, str(err)])


func _log(message: String) -> void:
    print("[ESP Shim] ", message)
