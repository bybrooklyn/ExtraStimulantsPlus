extends Node

# ExtraStimulantsPlus Feature Mod Entrypoint

const VISUALIZER_SCRIPT := "res://mods/esp_features/scripts/core/audio_visualizer.gd"
const GHOST_RECORDER_SCRIPT := "res://mods/esp_features/scripts/core/ghost_recorder.gd"
const MUTATOR_MANAGER_SCRIPT := "res://mods/esp_features/scripts/core/mutator_manager.gd"
const RT_EFFECTS_SCRIPT := "res://mods/esp_features/scripts/core/rt_effects.gd"

var api: Node

func esp_init(p_api: Node, _meta: Dictionary) -> bool:
    api = p_api
    api.log_info("Initializing ExtraStimulantsPlus Features...")
    
    _apply_script_extensions()
    _install_feature_nodes()
    
    return true

func _apply_script_extensions() -> void:
    # Path is relative to mod root if using the new loader, but here we use absolute res://
    # because the pack is mounted at res://mods/esp_features/
    var ext_script = load("res://mods/esp_features/scripts/core/esp_obstacle_manager_ext.gd")
    if ext_script:
        ext_script.take_over_path("res://scripts/domains/obstacles/obstacle_manager.gd")
        api.log_info("Applied Turbo ObstacleManager extension")

func _install_feature_nodes() -> void:
    var root := get_tree().root
    
    _ensure_node(root, "AudioVisualizer", VISUALIZER_SCRIPT)
    _ensure_node(root, "GhostRecorder", GHOST_RECORDER_SCRIPT)
    _ensure_node(root, "MutatorManager", MUTATOR_MANAGER_SCRIPT)
    _ensure_node(root, "RTEffects", RT_EFFECTS_SCRIPT)

func _ensure_node(parent: Node, node_name: String, script_path: String) -> Node:
    if parent.has_node(node_name):
        return parent.get_node(node_name)
        
    var script = load(script_path)
    if not script:
        api.log_error("Failed to load script: %s" % script_path)
        return null
        
    var node = script.new()
    node.name = node_name
    parent.add_child(node)
    return node
