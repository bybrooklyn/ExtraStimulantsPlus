@tool
extends EditorPlugin

func _enter_tree() -> void :
    _register_optional_secret_settings()
    _register_debug_logging_setting()


func _exit_tree() -> void :
    pass




func _register_optional_secret_settings() -> void :
    var items: Array[Dictionary] = [
        {
            "path": "game_analytics/api_key", 
            "default": "", 
            "hint_string": "Same as server GAME_API_KEY. Optional if SENSORY_GAME_API_KEY or GAME_API_KEY is set in the environment.", 
        }, 
        {
            "path": "game_analytics/hmac_secret", 
            "default": "", 
            "hint_string": "Same as server HMAC_SECRET when the API uses it. Leave empty if the server only uses the game key for signing.", 
        }, 
    ]
    for item in items:
        var path: String = item["path"]
        var default_val: String = item["default"]
        if not ProjectSettings.has_setting(path):
            ProjectSettings.set_setting(path, default_val)
        ProjectSettings.set_initial_value(path, default_val)
        ProjectSettings.add_property_info({
            "name": path, 
            "type": TYPE_STRING, 
            "hint": PROPERTY_HINT_PASSWORD, 
            "hint_string": str(item["hint_string"]), 
        })


func _register_debug_logging_setting() -> void :
    var path:= "game_analytics/debug_logging"
    if not ProjectSettings.has_setting(path):
        ProjectSettings.set_setting(path, false)
    ProjectSettings.set_initial_value(path, false)
    ProjectSettings.add_property_info({
        "name": path, 
        "type": TYPE_BOOL, 
        "hint_string":
        "When enabled, the GameAnalytics autoload prints HTTP send/receive lines to the Output panel (prefix \"GameAnalytics: \"). Off by default."
    })
