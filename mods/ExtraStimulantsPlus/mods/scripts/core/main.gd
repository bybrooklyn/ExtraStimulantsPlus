extends Node

# ExtraStimulantsPlus Feature Mod Entrypoint.
# Uses the api.assets mod-relative helpers throughout so this script also
# serves as a reference example for third-party mods.

const VISUALIZER_REL := "scripts/core/audio_visualizer.gd"
const GHOST_RECORDER_REL := "scripts/core/ghost_recorder.gd"
const MUTATOR_MANAGER_REL := "scripts/core/mutator_manager.gd"
const RT_EFFECTS_REL := "scripts/core/rt_effects.gd"

var api: Node
var meta: Dictionary

func esp_init(p_api: Node, p_meta: Dictionary) -> bool:
    api = p_api
    meta = p_meta
    api.log_info("Initializing ExtraStimulantsPlus Features...")

    _apply_script_extensions()
    _install_feature_nodes()

    return true

func _apply_script_extensions() -> void:
    if api.assets.script_extension(meta, "scripts/core/esp_obstacle_manager_ext.gd",
                                   "res://scripts/domains/obstacles/obstacle_manager.gd"):
        api.log_info("Applied Turbo ObstacleManager extension")

func _install_feature_nodes() -> void:
    var root := get_tree().root

    _ensure_node(root, "AudioVisualizer", VISUALIZER_REL)
    _ensure_node(root, "GhostRecorder", GHOST_RECORDER_REL)
    _ensure_node(root, "MutatorManager", MUTATOR_MANAGER_REL)
    _ensure_node(root, "RTEffects", RT_EFFECTS_REL)

func _ensure_node(parent: Node, node_name: String, script_relative: String) -> Node:
    if parent.has_node(node_name):
        return parent.get_node(node_name)

    var script = api.assets.load_from_mod(meta, script_relative)
    if not script:
        api.log_error("Failed to load script: %s" % script_relative)
        return null

    var node = script.new()
    node.name = node_name
    parent.add_child(node)
    if node.has_method("configure"):
        node.configure(api, meta)
    return node
