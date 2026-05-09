extends Node

# {{name}} — entrypoint that ships a custom level.
#
# api.campaign surface:
#   play_custom_level_path(path: String, options: Dictionary = {}) -> bool
#   play_custom_sequence(sequence: Array, meta: Dictionary, source_path: String) -> bool
#   get_custom_levels() -> Array
#
# Level files live alongside this entrypoint and are resolved via
# api.assets.resolve(meta, relative). The framework's CampaignAdapter takes
# care of registration once a path is provided to play_custom_level_path.

const MOD_ID := "{{id}}"
const LEVEL_REL := "levels/example.json"

var api: Node
var meta: Dictionary

func esp_init(p_api: Node, p_meta: Dictionary) -> bool:
    api = p_api
    meta = p_meta
    api.log_info("[%s] init" % MOD_ID)
    return true

func esp_ready(_api: Node, _meta: Dictionary) -> void:
    var path := api.assets.resolve(meta, LEVEL_REL)
    api.log_info("[%s] custom level path: %s" % [MOD_ID, path])
    # To start playing the level immediately:
    # api.campaign.play_custom_level_path(path)

func play() -> bool:
    return api.campaign.play_custom_level_path(api.assets.resolve(meta, LEVEL_REL))
