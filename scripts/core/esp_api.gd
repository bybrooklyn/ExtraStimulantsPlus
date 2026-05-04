extends Node

# Runtime API object exposed at /root/ESP.
# Mods should prefer this over directly hunting random /root nodes.

var core: Node
var mods: Node
var settings: Node
var audio: Node
var ghost: Node
var mutators: Node
var hooks: Node
var logger: Node


func configure(parts: Dictionary) -> void:
    core = parts.get("core")
    mods = parts.get("mods")
    settings = parts.get("settings")
    audio = parts.get("audio")
    ghost = parts.get("ghost")
    mutators = parts.get("mutators")
    hooks = parts.get("hooks")
    logger = parts.get("logger")


func log_info(message: String) -> void:
    if logger and logger.has_method("info"):
        logger.info(message)
    else:
        print("[ESP] ", message)


func log_warn(message: String) -> void:
    if logger and logger.has_method("warn"):
        logger.warn(message)
    else:
        push_warning("[ESP] " + message)


func log_error(message: String) -> void:
    if logger and logger.has_method("error"):
        logger.error(message)
    else:
        push_error("[ESP] " + message)
