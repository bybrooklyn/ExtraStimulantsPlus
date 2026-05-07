extends Node

# Minimal example mod demonstrating the ESP schema v1 loader.
#
# - manifest declares the `general.enabled` setting and a `level_started` hook
# - esp_init also re-registers the same setting through the runtime API to
#   show the imperative path
# - the declarative hook callback receives the raw signal args from the
#   game's EventBus (see GAME_EVENT_MAP in scripts/core/esp_event_adapter.gd
#   for argc per event)

var _api
var _mod_id := "cool_mod"


func esp_init(api, meta: Dictionary) -> bool:
    _api = api
    _mod_id = String(meta.get("id", _mod_id))
    api.settings.register(_mod_id, "general.enabled", TYPE_BOOL, true, {
        "label": "Enabled",
        "description": "Enable the example mod."
    })
    api.log_info("%s initialized" % meta.get("name", "Cool Mod"))
    return true


func esp_ready(_api_ref, meta: Dictionary) -> void:
    if _api.settings.get(_mod_id, "general.enabled", true):
        _api.log_info("%s is enabled" % meta.get("name", "Cool Mod"))


func _on_esp_event_level_started(_a, _b) -> void:
    if _api == null:
        return
    _api.log_info("[%s] level_started fired (declarative hook)" % _mod_id)
