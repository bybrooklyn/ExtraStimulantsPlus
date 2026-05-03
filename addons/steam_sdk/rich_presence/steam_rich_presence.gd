extends Node




var steam_available: bool = false


func set_rich_presence(key: String, value: String) -> bool:
    var steam: Object = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
    if not steam_available or steam == null:
        return false
    return steam.setRichPresence(key, value)


func clear_rich_presence() -> void :
    var steam: Object = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
    if not steam_available or steam == null:
        return
    steam.clearRichPresence()
