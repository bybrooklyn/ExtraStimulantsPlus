extends Node



var steam_available: bool = false


func _steam() -> Object:
    return Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null


func set_achievement(achievement_name: String) -> bool:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return false
    var ok: bool = steam.setAchievement(achievement_name)
    if ok:
        store_stats()
    return ok


func get_achievement(achievement_name: String) -> Dictionary:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return {"ret": false, "achieved": false}
    return steam.getAchievement(achievement_name)


func clear_achievement(achievement_name: String) -> bool:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return false
    var ok: bool = steam.clearAchievement(achievement_name)
    if ok:
        store_stats()
    return ok


func store_stats() -> bool:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return false
    return steam.storeStats()


func get_achievement_display_name(achievement_name: String) -> String:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return ""
    return steam.getAchievementDisplayAttribute(achievement_name, "name")


func get_achievement_description(achievement_name: String) -> String:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return ""
    return steam.getAchievementDisplayAttribute(achievement_name, "desc")


func is_achievement_hidden(achievement_name: String) -> bool:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return false
    return steam.getAchievementDisplayAttribute(achievement_name, "hidden") == "1"


func get_achievement_and_unlock_time(achievement_name: String) -> Dictionary:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return {"retrieve": false, "achieved": false, "unlocked": 0}
    return steam.getAchievementAndUnlockTime(achievement_name)


func indicate_achievement_progress(achievement_name: String, current_progress: int, max_progress: int) -> bool:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return false
    return steam.indicateAchievementProgress(achievement_name, current_progress, max_progress)


func get_num_achievements() -> int:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return 0
    return steam.getNumAchievements()


func get_achievement_name_by_index(achievement_index: int) -> String:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return ""
    return steam.getAchievementName(achievement_index)
