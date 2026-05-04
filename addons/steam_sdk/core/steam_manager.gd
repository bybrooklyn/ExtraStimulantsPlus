extends Node





signal overlay_activated(active: bool)

var _steam_available: bool = false

var achievements: Node
var stats: Node
var rich_presence: Node
var cloud: Node


func _ready() -> void :
    process_mode = Node.PROCESS_MODE_ALWAYS
    _initialize_steam()
    _setup_modules()
    _connect_overlay_callback()


func _process(_delta: float) -> void :
    if _steam_available and Engine.has_singleton("Steam"):
        Engine.get_singleton("Steam").run_callbacks()


func _initialize_steam() -> void :
    print("[Steam] Has singleton: ", Engine.has_singleton("Steam"))
    if not Engine.has_singleton("Steam"):
        print("[Steam] Steam singleton not found - GDExtension not loaded")
        return
    var steam: Object = Engine.get_singleton("Steam")
    var response: Dictionary = steam.steamInitEx()
    var status: int = response.get("status", 1)
    _steam_available = (status == 0)
    print("[Steam] Init response: ", response)
    print("[Steam] Available: ", _steam_available)


func _connect_overlay_callback() -> void :
    if not _steam_available or not Engine.has_singleton("Steam"):
        return
    var steam: Object = Engine.get_singleton("Steam")
    if not steam.has_method("connect"):
        return
    if not steam.has_signal("game_overlay_activated"):
        return
    var err = steam.connect("game_overlay_activated", _on_steam_overlay_activated)
    if err != OK:
        pass


func _on_steam_overlay_activated(active) -> void :
    overlay_activated.emit(bool(active))


func _setup_modules() -> void :
    var achievements_script: GDScript = preload("res://addons/steam_sdk/achievements/steam_achievements.gd")
    achievements = achievements_script.new()
    achievements.set("steam_available", _steam_available)
    add_child(achievements)

    var stats_script: GDScript = preload("res://addons/steam_sdk/stats/steam_stats.gd")
    stats = stats_script.new()
    stats.set("steam_available", _steam_available)
    add_child(stats)

    var rich_presence_script: GDScript = preload("res://addons/steam_sdk/rich_presence/steam_rich_presence.gd")
    rich_presence = rich_presence_script.new()
    rich_presence.set("steam_available", _steam_available)
    add_child(rich_presence)

    var cloud_script: GDScript = preload("res://addons/steam_sdk/cloud/steam_cloud.gd")
    cloud = cloud_script.new()
    cloud.set("steam_available", _steam_available)
    add_child(cloud)

    if _steam_available and rich_presence:
        _set_rich_presence_default()


func is_steam_available() -> bool:
    return _steam_available


func is_steam_deck() -> bool:
    if not _steam_available or not Engine.has_singleton("Steam"):
        return false
    var steam: Object = Engine.get_singleton("Steam")
    if steam.has_method("isSteamRunningOnSteamDeck"):
        return steam.isSteamRunningOnSteamDeck()
    return false



func set_achievement(achievement_api_name: String) -> void :
    if achievements:
        achievements.set_achievement(achievement_api_name)


func _set_rich_presence_default() -> void :
    if not rich_presence or not rich_presence.has_method("set_rich_presence"):
        return
    rich_presence.set_rich_presence("status", "In Main Menu")
