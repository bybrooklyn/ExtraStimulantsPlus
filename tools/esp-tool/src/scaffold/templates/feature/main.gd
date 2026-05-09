extends Node

# {{name}} — entrypoint that installs a "feature node" at /root/.
#
# The bundled `esp_features` mod uses this pattern for each capability
# (RTEffects, AudioVisualizer, GhostRecorder, MutatorManager). Feature nodes
# get added under /root/, receive a configure(api, meta) call, and live for
# the duration of the run.

const MOD_ID := "{{id}}"
const FEATURE_SCRIPT_REL := "scripts/core/example_feature.gd"

var api: Node
var meta: Dictionary

func esp_init(p_api: Node, p_meta: Dictionary) -> bool:
    api = p_api
    meta = p_meta
    api.log_info("[%s] init" % MOD_ID)
    _install_feature_nodes()
    return true

func _install_feature_nodes() -> void:
    _ensure_node(get_tree().root, "ExampleFeature", FEATURE_SCRIPT_REL)

func _ensure_node(parent: Node, node_name: String, script_relative: String) -> Node:
    if parent.has_node(node_name):
        return parent.get_node(node_name)

    # api.assets.load_from_mod resolves a path relative to this mod's root,
    # so the same script works whether the mod is a folder or a zip mount.
    var script = api.assets.load_from_mod(meta, script_relative)
    if script == null:
        api.log_error("[%s] failed to load %s" % [MOD_ID, script_relative])
        return null

    var node = script.new()
    node.name = node_name
    parent.add_child(node)
    if node.has_method("configure"):
        node.configure(api, meta)
    return node
