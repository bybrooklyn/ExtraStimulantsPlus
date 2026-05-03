extends Node

var loaded_mods: Array[String] = []

func _enter_tree():
    print("ModLoader: Initializing...")
    var dir = DirAccess.open("user://")
    if dir:
        if not dir.dir_exists("mods"):
            print("ModLoader: Creating mods directory...")
            dir.make_dir("mods")
        if not dir.dir_exists("custom_levels"):
            dir.make_dir("custom_levels")
        if not dir.dir_exists("custom_obstacles"):
            dir.make_dir("custom_obstacles")
        if not dir.dir_exists("custom_music"):
            dir.make_dir("custom_music")
            
        var mods_dir = DirAccess.open("user://mods")
        if mods_dir:
            mods_dir.list_dir_begin()
            var file_name = mods_dir.get_next()
            while file_name != "":
                if not mods_dir.current_is_dir() and (file_name.ends_with(".pck") or file_name.ends_with(".zip")):
                    var full_path = "user://mods/" + file_name
                    var success = ProjectSettings.load_resource_pack(full_path, true)
                    if success:
                        print("ModLoader: Successfully loaded mod pack: ", file_name)
                        loaded_mods.append(file_name)
                    else:
                        push_error("ModLoader: Failed to load mod pack: ", file_name)
                file_name = mods_dir.get_next()
            mods_dir.list_dir_end()
