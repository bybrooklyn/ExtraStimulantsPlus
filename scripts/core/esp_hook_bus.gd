extends Node

# Small centralized hook bus so every mod does not connect to SceneTree.node_added itself.

signal scene_changed(scene: Node)
signal node_added_to_game(node: Node)

var _node_callbacks: Array[Dictionary] = []
var _scene_callbacks: Array[Dictionary] = []


func _enter_tree() -> void:
    if not get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.connect(_on_node_added)


func on_node_named(node_name: String, target: Object, method_name: String) -> void:
    _node_callbacks.append({
        "node_name": node_name,
        "target": target,
        "method": method_name
    })


func on_scene_changed(target: Object, method_name: String) -> void:
    _scene_callbacks.append({
        "target": target,
        "method": method_name
    })


func emit_scene_changed(scene: Node) -> void:
    scene_changed.emit(scene)
    for callback in _scene_callbacks:
        _safe_call(callback.get("target"), callback.get("method"), [scene])


func _on_node_added(node: Node) -> void:
    node_added_to_game.emit(node)
    for callback in _node_callbacks:
        if node.name == callback.get("node_name", ""):
            _safe_call(callback.get("target"), callback.get("method"), [node])


func _safe_call(target: Object, method_name: String, args: Array) -> void:
    if target == null or method_name.is_empty():
        return
    if not target.has_method(method_name):
        return
    target.callv(method_name, args)
