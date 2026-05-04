extends Node

func esp_init(api, meta: Dictionary) -> void:
    api.log_info("%s initialized" % meta.get("name", "Cool Mod"))
