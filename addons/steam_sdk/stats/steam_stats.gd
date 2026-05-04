extends Node



signal leaderboard_score_submitted(success: bool)

var steam_available: bool = false

var _upload_queue: Array = []
var _current_upload: Dictionary = {}


func _ready() -> void :
    if not steam_available or not Engine.has_singleton("Steam"):
        return
    var steam: Object = Engine.get_singleton("Steam")
    if steam.has_signal("leaderboard_find_result"):
        steam.leaderboard_find_result.connect(_on_leaderboard_find_result)


func _steam() -> Object:
    return Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null


func _process_next_in_queue() -> void :
    if _upload_queue.is_empty():
        return
    var steam: Object = _steam()
    if not steam_available or steam == null:
        _upload_queue.clear()
        _current_upload = {}
        return
    _current_upload = _upload_queue.pop_front()
    find_leaderboard(_current_upload.get("name", ""))


func _on_leaderboard_find_result(_new_handle: int, was_found: int) -> void :
    if _current_upload.is_empty():
        return
    var steam: Object = _steam()
    var score: int = _current_upload.get("score", 0)
    var keep_best: bool = _current_upload.get("keep_best", true)
    _current_upload = {}
    if not steam or was_found != 1:
        leaderboard_score_submitted.emit(false)
        _process_next_in_queue()
        return
    steam.uploadLeaderboardScore(score, 1 if keep_best else 0, [])
    leaderboard_score_submitted.emit(true)
    _process_next_in_queue()





func submit_leaderboard_score_by_name(leaderboard_name: String, score: int, keep_best: bool = true) -> void :
    if not steam_available or not _steam():
        return
    _upload_queue.append({"name": leaderboard_name, "score": score, "keep_best": keep_best})
    if _current_upload.is_empty():
        _process_next_in_queue()


func set_stat_int(stat_name: String, value: int) -> bool:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return false
    return steam.setStatInt(stat_name, value)


func get_stat_int(stat_name: String) -> int:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return 0
    return steam.getStatInt(stat_name)


func set_stat_float(stat_name: String, value: float) -> bool:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return false
    return steam.setStatFloat(stat_name, value)


func get_stat_float(stat_name: String) -> float:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return 0.0
    return steam.getStatFloat(stat_name)


func store_stats() -> bool:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return false
    return steam.storeStats()


func find_leaderboard(leaderboard_name: String) -> void :
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return
    steam.findLeaderboard(leaderboard_name)


func upload_leaderboard_score(score: int, keep_best: bool = false, details: PackedInt32Array = []) -> void :
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return
    steam.uploadLeaderboardScore(score, keep_best, details)


func download_leaderboard_entries(start: int, end: int, request_type: int = 0) -> void :
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return
    steam.downloadLeaderboardEntries(start, end, request_type)


func request_global_achievement_percentages() -> void :
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return
    steam.requestGlobalAchievementPercentages()


func request_global_stats(history_days: int = 0) -> void :
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return
    steam.requestGlobalStats(history_days)


func get_leaderboard_entry_count() -> int:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return 0
    return steam.getLeaderboardEntryCount()
