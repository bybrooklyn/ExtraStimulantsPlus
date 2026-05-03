extends Node

const BLACKLIST_PATH: = "user://mods.blacklist"

var loaded_mods: Array[Dictionary] = []
var _loaded_ids: Array[String] = []
var _blacklist: Array[String] = []
var _ui_injector: Node


func _enter_tree():
    var mode = "Standalone"
    if OS.has_feature("editor") or OS.is_debug_build():
        mode = "Development/Loose Files"
    
    print("ModLoader: Initializing in ", mode, " mode...")
    _setup_directories()
    _scan_and_load_mods()
    
    # Enable high-performance mode if optimizations are detected
    if _is_turbo_active():
        print("ModLoader: Turbo Optimizations verified and active.")

func _is_turbo_active() -> bool:
    # Check if we are running our optimized ObstacleManager
    var om = get_node_or_null("/root/ObstacleManager")
    if om and om.has_method("_check_hit_direct"):
        return true
    return false


func _load_blacklist():
    if FileAccess.file_exists(BLACKLIST_PATH):
        var file = FileAccess.open(BLACKLIST_PATH, FileAccess.READ)
        if file:
            var content = file.get_as_text()
            _blacklist = Array(content.split("\n", false))
            file.close()


func save_blacklist():
    var file = FileAccess.open(BLACKLIST_PATH, FileAccess.WRITE)
    if file:
        file.store_string("\n".join(_blacklist))
        file.close()


func is_blacklisted(mod_id: String) -> bool:
    return _blacklist.has(mod_id)


func set_blacklisted(mod_id: String, blacklisted: bool):
    if blacklisted and not _blacklist.has(mod_id):
        _blacklist.append(mod_id)
    elif not blacklisted and _blacklist.has(mod_id):
        _blacklist.erase(mod_id)
    save_blacklist()
    
    # Initialize UI Injector
    _ui_injector = load("res://scripts/core/ui_injector.gd").new()
    add_child(_ui_injector)
    
    get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node):
    if node is Camera3D:
        node.keep_aspect = Camera3D.KEEP_HEIGHT

func _setup_directories():
    var dir = DirAccess.open("user://")
    if not dir: return
    for folder in ["mods", "custom_levels", "custom_obstacles", "custom_music"]:
        if not dir.dir_exists(folder):
            dir.make_dir(folder)

func _scan_and_load_mods():
    # Check for "Self" source mod extraction (Zero-Setup)
    if FileAccess.file_exists("res://mod.json"):
        var self_meta = _read_mod_metadata_from_path("res://mod.json")
        if self_meta:
            var mid = self_meta.get("id", "core")
            if not is_blacklisted(mid):
                print("ModLoader: Detected source mod extraction: ", self_meta.name)
                loaded_mods.append(self_meta)
                _loaded_ids.append(mid)
            else:
                print("ModLoader: Skipping blacklisted source mod: ", self_meta.name)

    var scan_dirs = ["user://mods"]
    
    # Also scan next to executable for "just works" experience
    var exe_dir = OS.get_executable_path().get_base_dir()
    var local_mods = exe_dir.path_join("mods")
    if DirAccess.dir_exists_absolute(local_mods):
        scan_dirs.append(local_mods)

    for dir_path in scan_dirs:
        var mods_dir = DirAccess.open(dir_path)
        if not mods_dir: continue
        
        mods_dir.list_dir_begin()
        var file_name = mods_dir.get_next()
        while file_name != "":
            var full_path = dir_path.path_join(file_name)
            var mod_id = file_name.get_basename()
            
            if is_blacklisted(mod_id):
                print("ModLoader: Skipping blacklisted mod: ", file_name)
            else:
                # Handle .pck and .zip packs
                if not mods_dir.current_is_dir() and (file_name.ends_with(".pck") or file_name.ends_with(".zip")):
                    _load_mod_pack(full_path, file_name)
                    
                # Handle uncompressed mod folders (Zero-Setup for other mods)
                elif mods_dir.current_is_dir() and not file_name.begins_with("."):
                    _load_mod_folder(full_path, file_name)
                
            file_name = mods_dir.get_next()
        mods_dir.list_dir_end()

func _load_mod_pack(full_path: String, file_name: String):
    var success = ProjectSettings.load_resource_pack(full_path, true)
    if success:
        var mod_id = file_name.get_basename()
        var meta = _read_mod_metadata(mod_id)
        if _check_dependencies(meta):
            print("ModLoader: Loaded pack ", meta.name, " v", meta.version)
            loaded_mods.append(meta)
            _loaded_ids.append(meta.get("id", mod_id))
        else:
            push_error("ModLoader: Skipping " + file_name + " due to missing dependencies.")
    else:
        push_error("ModLoader: Failed to load mod pack: " + file_name)

func _load_mod_folder(full_path: String, folder_name: String):
    # For folders, we expect a mod.json inside. 
    var meta_path = full_path.path_join("mod.json")
    if FileAccess.file_exists(meta_path):
        var meta = _read_mod_metadata_from_path(meta_path)
        if _check_dependencies(meta):
            print("ModLoader: Detected mod folder ", meta.name, " v", meta.version)
            loaded_mods.append(meta)
            _loaded_ids.append(meta.get("id", folder_name))

func _read_mod_metadata(mod_id: String) -> Dictionary:
    # 1. Try isolated path: res://mods/<id>/mod.json
    var isolated_path = "res://mods/".path_join(mod_id).path_join("mod.json")
    if FileAccess.file_exists(isolated_path):
        return _read_mod_metadata_from_path(isolated_path)
        
    # 2. Try global res://mod.json (fallback for legacy or source mods)
    if FileAccess.file_exists("res://mod.json"):
        return _read_mod_metadata_from_path("res://mod.json")
        
    return {
        "name": mod_id,
        "id": mod_id,
        "version": "0.0.0",
        "author": "Unknown",
        "dependencies": []
    }

func _read_mod_metadata_from_path(path: String) -> Dictionary:
    var meta = {
        "name": "Unnamed Mod",
        "id": "unknown",
        "version": "0.0.0",
        "author": "Unknown",
        "dependencies": []
    }
    
    var file = FileAccess.open(path, FileAccess.READ)
    if file:
        var json = JSON.parse_string(file.get_as_text())
        if json is Dictionary:
            for key in json:
                meta[key] = json[key]
        file.close()
    return meta

func _check_dependencies(meta: Dictionary) -> bool:
    var deps = meta.get("dependencies", [])
    for dep in deps:
        if not _loaded_ids.has(dep):
            push_error("ModLoader: Missing dependency: " + dep + " for mod " + meta.name)
            return false
    return true
