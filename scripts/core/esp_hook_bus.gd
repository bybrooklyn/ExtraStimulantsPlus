extends Node

# Centralized runtime hook bus. Mods should register callbacks here instead of
# connecting directly to SceneTree or game internals.

signal scene_changed(scene: Node)
signal node_added_to_game(node: Node)
signal event_emitted(event_name: String, args: Array)
signal hook_failed(owner_id: String, event_name: String, message: String)

const DEFAULT_PRIORITY := 100
const ORDER_FALLBACK := 1000000
const USER_PRIORITY_MIN := 0
const USER_PRIORITY_MAX := 10000

var _event_callbacks: Dictionary = {}
var _node_callbacks: Array[Dictionary] = []
var _scene_callbacks: Array[Dictionary] = []
var _owner_order: Dictionary = {}


func _enter_tree() -> void:
    if not get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.connect(_on_node_added)


func set_owner_order(owner_ids: Array[String]) -> void:
    _owner_order.clear()
    var index := 0
    for owner_id in owner_ids:
        var normalized := String(owner_id).strip_edges()
        if normalized.is_empty() or _owner_order.has(normalized):
            continue
        _owner_order[normalized] = index
        index += 1


func on(event_name: String, target: Object, method_name: String, priority: int = DEFAULT_PRIORITY, owner_id: String = "") -> bool:
    return on_event(event_name, target, method_name, priority, owner_id, false)


func once(event_name: String, target: Object, method_name: String, priority: int = DEFAULT_PRIORITY, owner_id: String = "") -> bool:
    return once_event(event_name, target, method_name, priority, owner_id)


func off(event_name: String, target: Object, method_name: String, owner_id: String = "") -> bool:
    return off_event(event_name, target, method_name, owner_id)


func emit(event_name: String, args: Array = []) -> Dictionary:
    return emit_event(event_name, args)


func on_event(event_name: String, target: Object, method_name: String, priority: int = DEFAULT_PRIORITY, owner_id: String = "", once: bool = false) -> bool:
    var normalized := _normalize_event_name(event_name)
    if normalized.is_empty():
        _log_warn("Ignoring empty event hook registration")
        return false
    if target == null or method_name.is_empty():
        _log_warn("Ignoring invalid hook registration for event '%s'" % normalized)
        return false
    if not target.has_method(method_name):
        _report_hook_failure(owner_id, normalized, "Hook target is missing method '%s'" % method_name)
        return false

    if not _event_callbacks.has(normalized):
        _event_callbacks[normalized] = []

    var callbacks: Array = _event_callbacks[normalized]
    for existing in callbacks:
        if _callback_matches(existing, target, method_name, owner_id):
            return false

    var callback := _make_callback(target, method_name, priority, owner_id, once)
    callback["event_pattern"] = normalized
    callback["wildcard"] = _is_wildcard_pattern(normalized)
    callbacks.append(callback)
    callbacks.sort_custom(Callable(self, "_sort_callbacks"))
    _event_callbacks[normalized] = callbacks
    return true


func once_event(event_name: String, target: Object, method_name: String, priority: int = DEFAULT_PRIORITY, owner_id: String = "") -> bool:
    return on_event(event_name, target, method_name, priority, owner_id, true)


func off_event(event_name: String, target: Object, method_name: String, owner_id: String = "") -> bool:
    var normalized := _normalize_event_name(event_name)
    if not _event_callbacks.has(normalized):
        return false

    var callbacks: Array = _event_callbacks[normalized]
    for callback in callbacks.duplicate():
        if _callback_matches(callback, target, method_name, owner_id):
            callbacks.erase(callback)
            _event_callbacks[normalized] = callbacks
            return true
    return false


func emit_event(event_name: String, args: Array = []) -> Dictionary:
    return _dispatch_event(event_name, args, false, {})


func emit_cancellable_event(event_name: String, args: Array = [], control: Dictionary = {}) -> Dictionary:
    return _dispatch_event(event_name, args, true, control)


func on_node_named(node_name: String, target: Object, method_name: String, priority: int = DEFAULT_PRIORITY, owner_id: String = "") -> bool:
    if node_name.is_empty() or target == null or method_name.is_empty():
        return false
    if not target.has_method(method_name):
        _report_hook_failure(owner_id, "node:%s" % node_name, "Hook target is missing method '%s'" % method_name)
        return false

    for existing in _node_callbacks:
        if String(existing.get("node_name", "")) == node_name and _callback_matches(existing, target, method_name, owner_id):
            return false

    var callback := _make_callback(target, method_name, priority, owner_id, false)
    callback["node_name"] = node_name
    _node_callbacks.append(callback)
    _node_callbacks.sort_custom(Callable(self, "_sort_callbacks"))
    return true


func off_node_named(node_name: String, target: Object, method_name: String, owner_id: String = "") -> bool:
    for callback in _node_callbacks.duplicate():
        if String(callback.get("node_name", "")) == node_name and _callback_matches(callback, target, method_name, owner_id):
            _node_callbacks.erase(callback)
            return true
    return false


func on_scene_changed(target: Object, method_name: String, priority: int = DEFAULT_PRIORITY, owner_id: String = "") -> bool:
    return on_scene_named("", target, method_name, priority, owner_id)


func on_scene_named(scene_name: String, target: Object, method_name: String, priority: int = DEFAULT_PRIORITY, owner_id: String = "") -> bool:
    if target == null or method_name.is_empty():
        return false
    if not target.has_method(method_name):
        _report_hook_failure(owner_id, "scene:%s" % scene_name, "Hook target is missing method '%s'" % method_name)
        return false

    var normalized_scene := scene_name.strip_edges()
    for existing in _scene_callbacks:
        if String(existing.get("scene_name", "")) == normalized_scene and _callback_matches(existing, target, method_name, owner_id):
            return false

    var callback := _make_callback(target, method_name, priority, owner_id, false)
    callback["scene_name"] = normalized_scene
    _scene_callbacks.append(callback)
    _scene_callbacks.sort_custom(Callable(self, "_sort_callbacks"))
    return true


func off_scene_changed(target: Object, method_name: String, owner_id: String = "") -> bool:
    return off_scene_named("", target, method_name, owner_id)


func off_scene_named(scene_name: String, target: Object, method_name: String, owner_id: String = "") -> bool:
    var normalized_scene := scene_name.strip_edges()
    for callback in _scene_callbacks.duplicate():
        if String(callback.get("scene_name", "")) == normalized_scene and _callback_matches(callback, target, method_name, owner_id):
            _scene_callbacks.erase(callback)
            return true
    return false


func emit_scene_changed(scene: Node) -> void:
    scene_changed.emit(scene)
    for callback in _scene_callbacks.duplicate():
        var scene_name := String(callback.get("scene_name", ""))
        if scene_name.is_empty() or _scene_matches(scene, scene_name):
            var event_label := "scene:%s" % scene_name if not scene_name.is_empty() else "scene_changed"
            _safe_call_callback(callback, [scene], event_label)


func get_registered_events() -> Array[String]:
    var events: Array[String] = []
    for event_name in _event_callbacks.keys():
        events.append(String(event_name))
    events.sort()
    return events


func get_event_hooks(event_name: String = "") -> Variant:
    var normalized := _normalize_event_name(event_name)
    if not normalized.is_empty():
        return _summarize_callbacks(_event_callbacks.get(normalized, []))

    var out := {}
    for key in _event_callbacks.keys():
        out[String(key)] = _summarize_callbacks(_event_callbacks[key])
    return out


func get_node_hooks() -> Array[Dictionary]:
    return _summarize_callbacks(_node_callbacks)


func get_scene_hooks() -> Array[Dictionary]:
    return _summarize_callbacks(_scene_callbacks)


func _dispatch_event(event_name: String, args: Array, cancellable: bool, control: Dictionary) -> Dictionary:
    var normalized := _normalize_event_name(event_name)
    var result := {
        "event_name": normalized,
        "invoked": 0,
        "cancelled": false,
        "stopped": false,
        "failures": [],
        "control": {
            "cancelled": false,
            "default_prevented": false,
            "stop_propagation": false,
            "cancellable": cancellable
        }
    }
    if normalized.is_empty():
        return result

    for key in control.keys():
        result["control"][key] = control[key]

    event_emitted.emit(normalized, args)
    var callbacks := _collect_matching_event_callbacks(normalized)
    for callback in callbacks:
        var call_args := args.duplicate()
        if cancellable:
            call_args.append(result["control"])

        var response := _safe_call_callback(callback, call_args, normalized)
        if bool(response.get("called", false)):
            result["invoked"] = int(result.get("invoked", 0)) + 1
        if not bool(response.get("success", false)):
            var failures: Array = result.get("failures", [])
            failures.append(String(response.get("error", "unknown hook error")))
            result["failures"] = failures
        if bool(response.get("success", false)) and bool(callback.get("once", false)):
            _remove_callback_everywhere(callback)

        if not cancellable:
            continue

        var hook_return = response.get("return", null)
        if hook_return == false:
            result["control"]["cancelled"] = true
            result["control"]["default_prevented"] = true
        elif hook_return is Dictionary:
            if bool(hook_return.get("cancel", false)) or bool(hook_return.get("cancelled", false)):
                result["control"]["cancelled"] = true
                result["control"]["default_prevented"] = true
            if bool(hook_return.get("stop_propagation", false)):
                result["control"]["stop_propagation"] = true

        if bool(result["control"].get("cancelled", false)) or bool(result["control"].get("stop_propagation", false)):
            result["cancelled"] = bool(result["control"].get("cancelled", false))
            result["stopped"] = bool(result["control"].get("stop_propagation", false)) or bool(result["cancelled"])
            return result

    result["cancelled"] = bool(result["control"].get("cancelled", false))
    result["stopped"] = bool(result["control"].get("stop_propagation", false))
    return result


func _collect_matching_event_callbacks(event_name: String) -> Array:
    var matched: Array = []
    for pattern in _event_callbacks.keys():
        var normalized_pattern := String(pattern)
        if _event_pattern_matches(normalized_pattern, event_name):
            matched.append_array(_event_callbacks.get(normalized_pattern, []))
    matched.sort_custom(Callable(self, "_sort_callbacks"))
    return matched


func _event_pattern_matches(pattern: String, event_name: String) -> bool:
    if _is_wildcard_pattern(pattern):
        return event_name.match(pattern)
    return pattern == event_name


func _scene_matches(scene: Node, scene_name: String) -> bool:
    if scene == null:
        return false
    var pattern := scene_name.strip_edges().to_lower()
    if pattern.is_empty():
        return true

    var candidates: Array[String] = [
        scene.name.to_lower(),
        String(scene.scene_file_path).to_lower(),
        String(scene.scene_file_path).get_file().get_basename().to_lower()
    ]
    for candidate in candidates:
        if candidate.is_empty():
            continue
        if _is_wildcard_pattern(pattern):
            if candidate.match(pattern):
                return true
        elif candidate == pattern:
            return true
    return false


func _is_wildcard_pattern(pattern: String) -> bool:
    return pattern.contains("*") or pattern.contains("?")


func _on_node_added(node: Node) -> void:
    node_added_to_game.emit(node)
    for callback in _node_callbacks.duplicate():
        if node.name == String(callback.get("node_name", "")):
            _safe_call_callback(callback, [node], "node:%s" % node.name)


func _make_callback(target: Object, method_name: String, priority: int, owner_id: String, once: bool) -> Dictionary:
    return {
        "target": target,
        "target_id": target.get_instance_id() if target else 0,
        "method": method_name,
        "priority": _normalize_priority(priority, owner_id),
        "owner_id": owner_id,
        "once": once
    }


func _normalize_priority(priority: int, owner_id: String) -> int:
    if _is_framework_owner(owner_id):
        return priority
    return clampi(priority, USER_PRIORITY_MIN, USER_PRIORITY_MAX)


func _is_framework_owner(owner_id: String) -> bool:
    var clean := owner_id.strip_edges().to_lower()
    return clean.is_empty() or clean == "extrastimulants_plus" or clean.begins_with("esp.") or clean.begins_with("framework.")


func _callback_matches(callback: Dictionary, target: Object, method_name: String, owner_id: String = "") -> bool:
    if target == null:
        return false
    if int(callback.get("target_id", 0)) != target.get_instance_id():
        return false
    if String(callback.get("method", "")) != method_name:
        return false
    if not owner_id.is_empty() and String(callback.get("owner_id", "")) != owner_id:
        return false
    return true


func _sort_callbacks(a: Dictionary, b: Dictionary) -> bool:
    var ap := int(a.get("priority", DEFAULT_PRIORITY))
    var bp := int(b.get("priority", DEFAULT_PRIORITY))
    if ap != bp:
        return ap < bp

    var a_owner := String(a.get("owner_id", ""))
    var b_owner := String(b.get("owner_id", ""))
    var a_order := int(_owner_order.get(a_owner, ORDER_FALLBACK))
    var b_order := int(_owner_order.get(b_owner, ORDER_FALLBACK))
    if a_order != b_order:
        return a_order < b_order

    if a_owner != b_owner:
        return a_owner < b_owner
    return String(a.get("method", "")) < String(b.get("method", ""))


func _safe_call_callback(callback: Dictionary, args: Array, event_name: String) -> Dictionary:
    var target: Object = callback.get("target")
    var method_name := String(callback.get("method", ""))
    var owner_id := String(callback.get("owner_id", ""))
    if target == null or not is_instance_valid(target):
        var stale_error := "Removing stale hook callback for method '%s'" % method_name
        _report_hook_failure(owner_id, event_name, stale_error)
        _remove_callback_everywhere(callback)
        return {"called": false, "success": false, "error": stale_error}
    if method_name.is_empty() or not target.has_method(method_name):
        var missing_error := "Hook callback target %s does not have method '%s'" % [target, method_name]
        _report_hook_failure(owner_id, event_name, missing_error)
        _remove_callback_everywhere(callback)
        return {"called": false, "success": false, "error": missing_error}

    var return_value = target.callv(method_name, args)
    return {
        "called": true,
        "success": true,
        "return": return_value
    }


func _report_hook_failure(owner_id: String, event_name: String, message: String) -> void:
    hook_failed.emit(owner_id, event_name, message)
    _log_warn("[%s] %s" % [event_name, message])
    if owner_id.is_empty():
        return

    var mod_loader := get_node_or_null("/root/ESPModLoader")
    if mod_loader and mod_loader.has_method("record_mod_error"):
        mod_loader.record_mod_error(owner_id, message, {
            "source": "hooks",
            "event": event_name
        })


func _remove_callback_record(callbacks: Array, callback: Dictionary) -> void:
    if callbacks.has(callback):
        callbacks.erase(callback)


func _remove_callback_everywhere(callback: Dictionary) -> void:
    for key in _event_callbacks.keys():
        _remove_callback_record(_event_callbacks[key], callback)
    _remove_callback_record(_node_callbacks, callback)
    _remove_callback_record(_scene_callbacks, callback)


func _summarize_callbacks(callbacks: Array) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for callback in callbacks:
        out.append({
            "owner_id": String(callback.get("owner_id", "")),
            "method": String(callback.get("method", "")),
            "priority": int(callback.get("priority", DEFAULT_PRIORITY)),
            "target_id": int(callback.get("target_id", 0)),
            "node_name": String(callback.get("node_name", "")),
            "scene_name": String(callback.get("scene_name", "")),
            "event_pattern": String(callback.get("event_pattern", "")),
            "once": bool(callback.get("once", false))
        })
    return out


func _normalize_event_name(event_name: String) -> String:
    return event_name.strip_edges().to_lower()


func _log_warn(message: String) -> void:
    var logger := get_node_or_null("/root/ESPLogger")
    if logger and logger.has_method("warn"):
        logger.warn(message)
    else:
        push_warning("[ESPHooks] " + message)
