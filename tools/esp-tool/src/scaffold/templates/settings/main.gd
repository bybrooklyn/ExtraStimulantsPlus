extends Node

# {{name}} — entrypoint with declared settings.
#
# Settings declared in mod.json (see `gameplay.example.*`) automatically appear
# in the SO settings menu under the MODS tab. Read them at runtime via
# api.settings.get(MOD_ID, "gameplay.example.<key>", fallback). Listen for
# changes via the registry's `setting_changed` signal.

const MOD_ID := "{{id}}"

var api: Node
var meta: Dictionary

func esp_init(p_api: Node, p_meta: Dictionary) -> bool:
    api = p_api
    meta = p_meta
    api.log_info("[%s] init" % MOD_ID)

    # Subscribe to setting_changed so live tweaks take effect without a relaunch.
    var registry = api.settings.get_registry()
    if registry and registry.has_signal("setting_changed"):
        registry.setting_changed.connect(_on_setting_changed)

    _apply_settings()
    return true

func _on_setting_changed(mod_id: String, _key: String, _value) -> void:
    if mod_id == MOD_ID:
        _apply_settings()

func _apply_settings() -> void:
    var enabled := bool(api.settings.get(MOD_ID, "gameplay.example.enabled", true))
    var intensity := float(api.settings.get(MOD_ID, "gameplay.example.intensity", 1.0))
    var text := String(api.settings.get(MOD_ID, "gameplay.example.label_text", "Hello, modders."))
    api.log_info("[%s] settings applied: enabled=%s intensity=%s text=%s"
        % [MOD_ID, enabled, intensity, text])
