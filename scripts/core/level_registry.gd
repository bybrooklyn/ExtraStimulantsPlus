extends Node

# ESP Level Registry - Framework Owned
# Handles unzipping and mounting .somap files and injecting them into the level browser.

const LEVELS_DIR := "res://levels/"

var custom_levels: Array[CampaignLevelDef] = []

func scan_custom_levels() -> void:
    custom_levels.clear()
    
    # We scan the game folder's 'levels/' directory
    var exe_dir := OS.get_executable_path().get_base_dir()
    var levels_path := exe_dir.path_join("levels")
    
    if not DirAccess.dir_exists_absolute(levels_path):
        DirAccess.make_dir_absolute(levels_path)
        return
        
    var dir := DirAccess.open(levels_path)
    if dir:
        dir.list_dir_begin()
        var file_name := dir.get_next()
        while file_name != "":
            if not dir.current_is_dir() and file_name.ends_with(".somap"):
                _load_somap(levels_path.path_join(file_name))
            file_name = dir.get_next()
        dir.list_dir_end()

func _load_somap(path: String) -> void:
    # A .somap is a ZIP pack. We mount it to res://mods/levels/<name>/
    var base_name := path.get_file().get_basename()
    var mount_path := "res://mods/levels/".path_join(base_name)
    
    var ok := ProjectSettings.load_resource_pack(path)
    if not ok:
        push_error("[ESP LevelRegistry] Failed to mount %s" % path)
        return
        
    # After mounting, we expect a level.tres or mod.json
    # (Implementation details for .somap unzipping and parsing go here)
    # For now, we look for any .tres in the mount root that is a CampaignLevelDef
    var dir := DirAccess.open(mount_path)
    if dir:
        dir.list_dir_begin()
        var file := dir.get_next()
        while file != "":
            if file.ends_with(".tres"):
                var res = load(mount_path.path_join(file))
                if res is CampaignLevelDef:
                    custom_levels.append(res)
            file = dir.get_next()
        dir.list_dir_end()

func inject_levels(existing_levels: Array[CampaignLevelDef]) -> void:
    for cl in custom_levels:
        if not existing_levels.has(cl):
            existing_levels.append(cl)
