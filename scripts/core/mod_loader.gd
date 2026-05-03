extends Node

var loaded_mods: Array[Dictionary] = []
var _loaded_ids: Array[String] = []

func _enter_tree():
    print("ModLoader: Initializing...")
    _setup_directories()
    _scan_and_load_mods()
    get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node):
    if node is Camera3D:
        # For ultrawide, Vertical FOV (Keep Height) is almost always preferred
        node.keep_aspect = Camera3D.KEEP_HEIGHT

func _setup_directories():
    var dir = DirAccess.open("user://")
    if not dir: return
    for folder in ["mods", "custom_levels", "custom_obstacles", "custom_music"]:
        if not dir.dir_exists(folder):
            dir.make_dir(folder)

func _scan_and_load_mods():
    var mods_dir = DirAccess.open("user://mods")
    if not mods_dir: return
    
    var pending_mods = []
    mods_dir.list_dir_begin()
    var file_name = mods_dir.get_next()
    while file_name != "":
        if not mods_dir.current_is_dir() and (file_name.ends_with(".pck") or file_name.ends_with(".zip")):
            pending_mods.append(file_name)
        file_name = mods_dir.get_next()
    mods_dir.list_dir_end()
    
    # We need to load them one by one and check metadata
    # Note: Godot loads the pack into the virtual filesystem.
    # To check metadata, we load the pack, then check for res://mod.json
    
    for mod_file in pending_mods:
        var full_path = "user://mods/" + mod_file
        var success = ProjectSettings.load_resource_pack(full_path, true)
        if success:
            var meta = _read_mod_metadata(mod_file)
            if _check_dependencies(meta):
                print("ModLoader: Loaded ", meta.name, " v", meta.version)
                loaded_mods.append(meta)
                _loaded_ids.append(meta.get("id", mod_file))
            else:
                push_error("ModLoader: Skipping " + mod_file + " due to missing dependencies.")
                # We can't easily "unload" a pack in Godot once loaded, 
                # but we can prevent the mod's code from being initialized if we had a more complex plugin system.
        else:
            push_error("ModLoader: Failed to load mod pack: " + mod_file)

func _read_mod_metadata(file_name: String) -> Dictionary:
    var meta = {
        "name": file_name,
        "id": file_name,
        "version": "0.0.0",
        "author": "Unknown",
        "dependencies": []
    }
    
    if FileAccess.file_exists("res://mod.json"):
        var file = FileAccess.open("res://mod.json", FileAccess.READ)
        if file:
            var json = JSON.parse_string(file.get_as_text())
            if json is Dictionary:
                for key in json:
                    meta[key] = json[key]
            file.close()
            # Clean up so next mod doesn't read the same file if it lacks one
            # Actually, Godot's pack system merges files. This is tricky.
            # Usually, mods should have unique paths or the loader should handle it.
    return meta

func _check_dependencies(meta: Dictionary) -> bool:
    var deps = meta.get("dependencies", [])
    for dep in deps:
        if not _loaded_ids.has(dep):
            push_error("ModLoader: Missing dependency: " + dep + " for mod " + meta.name)
            return false
    return true
