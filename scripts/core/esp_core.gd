extends Node

# External ExtraStimulantsPlus core entrypoint.
# The injected shim manually instantiates this from the mounted core pack.

const CORE_VERSION := "0.0.2"

const API_SCRIPT := "res://scripts/core/esp_api.gd"
const LOGGER_SCRIPT := "res://scripts/core/esp_logger.gd"
const HOOK_BUS_SCRIPT := "res://scripts/core/esp_hook_bus.gd"
const SETTINGS_SCRIPT := "res://scripts/core/extra_stimulants_plus_settings.gd"
const AUDIO_VISUALIZER_SCRIPT := "res://scripts/core/audio_visualizer.gd"
const GHOST_RECORDER_SCRIPT := "res://scripts/core/ghost_recorder.gd"
const MUTATOR_MANAGER_SCRIPT := "res://scripts/core/mutator_manager.gd"
const UI_INJECTOR_SCRIPT := "res://scripts/core/ui_injector.gd"
const MOD_LOADER_SCRIPT := "res://scripts/core/mod_loader.gd"
const EVENT_ADAPTER_SCRIPT := "res://scripts/core/esp_event_adapter.gd"
const CAMPAIGN_ADAPTER_SCRIPT := "res://scripts/core/esp_campaign_adapter.gd"

var boot_info: Dictionary = {}
var api: Node
var logger: Node
var hooks: Node
var settings: Node
var audio_visualizer: Node
var ghost_recorder: Node
var mutator_manager: Node
var ui_injector: Node
var mod_loader: Node
var event_adapter: Node
var campaign_adapter: Node


func set_boot_info(info: Dictionary) -> void:
    boot_info = info.duplicate(true)


func _enter_tree() -> void:
    name = "ESPCore"
    _apply_script_extensions()
    _install_core_nodes()


func _apply_script_extensions() -> void:
    var ext_script = load("res://scripts/core/esp_level_loader_ext.gd")
    if ext_script:
        ext_script.take_over_path("res://scripts/campaign/campaign_level_loader.gd")
        if logger: logger.info("Applied CampaignLevelLoader script extension")


func _ready() -> void:
    if logger:
        logger.info("ESP Framework Ready v%s" % CORE_VERSION)
    
    if mod_loader and mod_loader.has_method("load_external_mods"):
        mod_loader.load_external_mods(boot_info.get("mods_dirs", []), boot_info.get("core_pack_path", ""))


const SETTINGS_REGISTRY_SCRIPT := "res://scripts/core/settings_registry.gd"
const LEVEL_REGISTRY_SCRIPT := "res://scripts/core/level_registry.gd"

var settings_registry: Node
var level_registry: Node

func _install_core_nodes() -> void:
    var root := get_tree().root

    # Framework Infrastructure
    logger = _ensure_root_node("ESPLogger", LOGGER_SCRIPT)
    hooks = _ensure_root_node("ESPHooks", HOOK_BUS_SCRIPT)
    settings = _ensure_root_node("ESPSettings", SETTINGS_SCRIPT)
    
    settings_registry = _ensure_root_node("ESPSettingsRegistry", SETTINGS_REGISTRY_SCRIPT)
    level_registry = _ensure_root_node("ESPLevelRegistry", LEVEL_REGISTRY_SCRIPT)
    event_adapter = _ensure_root_node("ESPEventAdapter", EVENT_ADAPTER_SCRIPT)
    campaign_adapter = _ensure_root_node("ESPCampaignAdapter", CAMPAIGN_ADAPTER_SCRIPT)
    
    mod_loader = _ensure_root_node("ESPModLoader", MOD_LOADER_SCRIPT)
    ui_injector = _ensure_root_node("ESPUIInjector", UI_INJECTOR_SCRIPT)
    api = _ensure_root_node("ESP", API_SCRIPT)

    if event_adapter and event_adapter.has_method("configure"):
        event_adapter.configure({
            "hooks": hooks,
            "logger": logger
        })

    if campaign_adapter and campaign_adapter.has_method("configure"):
        campaign_adapter.configure({
            "hooks": hooks,
            "logger": logger,
            "level_registry": level_registry
        })

    if api and api.has_method("configure"):
        api.configure({
            "core": self,
            "mods": mod_loader,
            "settings": settings,
            "hooks": hooks,
            "events": hooks,
            "logger": logger,
            "settings_registry": settings_registry,
            "level_registry": level_registry,
            "event_adapter": event_adapter,
            "campaign": campaign_adapter
        })

    if mod_loader and mod_loader.has_method("set_core_context"):
        mod_loader.set_core_context({
            "api": api,
            "logger": logger,
            "hooks": hooks,
            "settings": settings,
            "event_adapter": event_adapter,
            "campaign": campaign_adapter,
            "level_registry": level_registry,
            "core_pack_path": boot_info.get("core_pack_path", "")
        })


func _ensure_root_node(node_name: String, script_path: String) -> Node:
    var root := get_tree().root
    var existing := root.get_node_or_null(node_name)
    if existing:
        return existing

    var script := load(script_path)
    if script == null:
        push_error("[ESP Core] missing script: %s" % script_path)
        return null

    var node = script.new()
    node.name = node_name
    root.add_child(node)
    return node
