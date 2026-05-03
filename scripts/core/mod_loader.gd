extends Node

var loaded_mods: Array[Dictionary] = []
var _loaded_ids: Array[String] = []
var _ui_injector: Node

func _enter_tree():
    print("ModLoader: Initializing...")
    _setup_directories()
    _scan_and_load_mods()
    
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
            if not mods_dir.current_is_dir() and (file_name.ends_with(".pck") or file_name.ends_with(".zip")):
                var full_path = dir_path.path_join(file_name)
                _load_mod_pack(full_path, file_name)
            file_name = mods_dir.get_next()
        mods_dir.list_dir_end()

func _load_mod_pack(full_path: String, file_name: String):
    var success = ProjectSettings.load_resource_pack(full_path, true)
    if success:
        var meta = _read_mod_metadata(file_name)
        if _check_dependencies(meta):
            print("ModLoader: Loaded ", meta.name, " v", meta.version)
            loaded_mods.append(meta)
            _loaded_ids.append(meta.get("id", file_name))
        else:
            push_error("ModLoader: Skipping " + file_name + " due to missing dependencies.")
    else:
        push_error("ModLoader: Failed to load mod pack: " + file_name)

func _read_mod_metadata(file_name: String) -> Dictionary:
    var meta = {
        "name": file_name,
        "id": file_name,
        "version": "0.0.0",
        "author": "Unknown",
        "dependencies": []
    }
    
    # We check if the mod provided its own metadata file.
    # Because of how Godot merges packs, we have to be careful not to 
    # read the base game's files or previous mods' files if they share paths.
    # Ideally, mods should use "res://mods/<id>/mod.json"
    
    # For now, we check the standard path.
    if FileAccess.file_exists("res://mod.json"):
        var file = FileAccess.open("res://mod.json", FileAccess.READ)
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
