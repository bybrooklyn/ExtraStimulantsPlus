extends Node

# Example feature node. Lives at /root/ExampleFeature for the run.
# Pattern: capture api+meta in configure(), subscribe to events, do work in _process.

const MOD_ID := "{{id}}"

var _api: Node
var _meta: Dictionary
var _level_active: bool = false

func configure(api: Node, meta: Dictionary) -> void:
    _api = api
    _meta = meta

func _ready() -> void:
    if _api == null:
        _api = get_node_or_null("/root/ESP")
    if _api and _api.events:
        _api.events.on("level_started", Callable(self, "_on_level_started"), {"owner_id": MOD_ID})
        _api.events.on("level_completed", Callable(self, "_on_level_finished"), {"owner_id": MOD_ID})
        _api.events.on("player_died", Callable(self, "_on_level_finished"), {"owner_id": MOD_ID})

func _on_level_started(_a = null, _b = null) -> void:
    _level_active = true

func _on_level_finished(_a = null, _b = null) -> void:
    _level_active = false

func _process(_delta: float) -> void:
    if not _level_active:
        return
    # Replace this with your feature's per-frame logic.
    pass
