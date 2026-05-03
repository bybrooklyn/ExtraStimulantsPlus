extends Node

# ExtraStimulantsPlus: Permanent PCK Bootstrap
# This script is injected into the game's main .pck and runs automatically.
# It handles loading external mod packs from the /mods directory.

func _enter_tree():
    print("[ESP] Bootstrap: Initializing permanent mod support...")
    _scan_and_load_mods()

func _scan_and_load_mods():
    var exe_dir = OS.get_executable_path().get_base_dir()
    
    # On macOS, the exe is deep in the .app bundle
    if OS.get_name() == "macOS":
        exe_dir = exe_dir.get_base_dir().get_base_dir().get_base_dir()
        
    var mods_dir_path = exe_dir.path_join("mods")
    
    if not DirAccess.dir_exists_absolute(mods_dir_path):
        print("[ESP] Bootstrap: creating mods directory at ", mods_dir_path)
        DirAccess.make_dir_absolute(mods_dir_path)
        
    var mods_dir = DirAccess.open(mods_dir_path)
    if not mods_dir:
        push_error("[ESP] Bootstrap: Failed to open mods directory.")
        return
        
    mods_dir.list_dir_begin()
    var file_name = mods_dir.get_next()
    while file_name != "":
        if not mods_dir.current_is_dir() and (file_name.ends_with(".pck") or file_name.ends_with(".zip")):
            var full_path = mods_dir_path.path_join(file_name)
            print("[ESP] Bootstrap: Loading mod pack: ", file_name)
            var success = ProjectSettings.load_resource_pack(full_path, true)
            if not success:
                push_error("[ESP] Bootstrap: Failed to load " + file_name)
        file_name = mods_dir.get_next()
    mods_dir.list_dir_end()
    
    print("[ESP] Bootstrap: External mods loaded.")
