extends Node

# RTEffects: controller for the screen-space path tracer compositor effect.
# Attaches one RtPathTraceEffect to the active Camera3D and keeps it attached
# across camera changes. Reads its parameters from the ESP settings registry
# under mod id "esp_features", group "rendering.rt.*".

const MOD_ID := "esp_features"
const EFFECT_SCRIPT_REL := "scripts/core/rt_path_trace_effect.gd"

var _api: Node
var _meta: Dictionary
var _effect: CompositorEffect
var _attached_camera: Camera3D
var _attached_compositor: Compositor
var _renderer_supported: bool = false
var _logged_unsupported: bool = false
var _settings_dirty: bool = true

func configure(api: Node, meta: Dictionary) -> void:
    _api = api
    _meta = meta

func _ready() -> void:
    if _api == null:
        _api = get_node_or_null("/root/ESP")
    _renderer_supported = RenderingServer.get_rendering_device() != null
    if not _renderer_supported:
        if not _logged_unsupported:
            _log_warn("path tracer unavailable on gl_compatibility renderer")
            _logged_unsupported = true
        set_process(false)
        return

    var effect_script: Script
    if _api and _api.assets and not _meta.is_empty():
        effect_script = _api.assets.load_from_mod(_meta, EFFECT_SCRIPT_REL)
    else:
        effect_script = load("res://mods/esp_features/" + EFFECT_SCRIPT_REL)
    if effect_script == null:
        _log_error("failed to load rt_path_trace_effect.gd")
        set_process(false)
        return
    _effect = effect_script.new()
    if _effect.has_method("configure"):
        _effect.configure(_api, _meta)

    if _api and _api.events:
        _api.events.on("level_started", Callable(self, "_on_level_started"), {"owner_id": MOD_ID})

    var registry: Node = null
    if _api and _api.settings and _api.settings.has_method("get_registry"):
        registry = _api.settings.get_registry()
    if registry and registry.has_signal("setting_changed"):
        registry.setting_changed.connect(_on_setting_changed)

func _process(_delta: float) -> void:
    if not _renderer_supported or _effect == null:
        return

    if _settings_dirty:
        _push_settings_to_effect()
        _settings_dirty = false
    _ensure_effect_attached()

func _on_level_started(_a = null, _b = null) -> void:
    _ensure_effect_attached()

func _on_setting_changed(mod_id: String, _key: String, _value) -> void:
    if mod_id == MOD_ID:
        _settings_dirty = true

func _ensure_effect_attached() -> void:
    var enabled := _get_bool("rendering.rt.enabled", false)
    var camera := _find_camera()

    if not enabled:
        _detach()
        return

    if camera == null:
        return

    if camera == _attached_camera and _attached_compositor == camera.compositor and _effect_in_compositor(camera.compositor):
        return

    _detach()

    var compositor := camera.compositor
    if compositor == null:
        compositor = Compositor.new()
        camera.compositor = compositor

    var effects: Array = compositor.compositor_effects.duplicate()
    if not effects.has(_effect):
        effects.append(_effect)
        compositor.compositor_effects = effects

    _attached_camera = camera
    _attached_compositor = compositor

func _detach() -> void:
    if _attached_compositor and is_instance_valid(_attached_compositor):
        var effects: Array = _attached_compositor.compositor_effects.duplicate()
        var idx := effects.find(_effect)
        if idx != -1:
            effects.remove_at(idx)
            _attached_compositor.compositor_effects = effects
    # Release GPU resources when RT is disabled so we don't hold tens of MB
    # of textures/buffers idle until the scene exits. Re-attach re-creates them.
    if _effect and is_instance_valid(_effect) and _effect.has_method("cleanup"):
        _effect.cleanup()
    _attached_camera = null
    _attached_compositor = null

func _effect_in_compositor(compositor: Compositor) -> bool:
    if compositor == null:
        return false
    for e in compositor.compositor_effects:
        if e == _effect:
            return true
    return false

func _find_camera() -> Camera3D:
    var vp := get_viewport()
    return vp.get_camera_3d() if vp else null

func _push_settings_to_effect() -> void:
    if _effect == null:
        return

    # Sky color and intensity are preset-independent (theme-tunable always).
    _effect.sky_color = Color(
        clampf(_get_float("rendering.rt.sky_color_r", 0.4), 0.0, 1.0),
        clampf(_get_float("rendering.rt.sky_color_g", 0.5), 0.0, 1.0),
        clampf(_get_float("rendering.rt.sky_color_b", 0.6), 0.0, 1.0)
    )
    _effect.sky_intensity = clampf(_get_float("rendering.rt.sky_intensity", 0.3), 0.0, 2.0)
    _effect.thickness = max(0.001, _get_float("rendering.rt.thickness", 0.25))
    _effect.fade = clampf(_get_float("rendering.rt.fade", 1.0), 0.0, 1.0)

    # Preset overrides the per-knob settings unless the user picks "custom".
    # Default is "gameplay" (cheap, looks decent). "off" disables the effect.
    var preset := _get_string("rendering.rt.preset", "gameplay")
    match preset:
        "off":
            _effect.enabled = false
            _effect.samples = 1
            _effect.max_steps = 16
            _effect.atrous_iterations = 0
            _effect.temporal_alpha_max = 16
        "cinematic":
            _effect.enabled = true
            _effect.samples = 4
            _effect.max_steps = 32
            _effect.atrous_iterations = 4
            _effect.temporal_alpha_max = 48
        "custom":
            _effect.enabled = _get_bool("rendering.rt.enabled", false)
            _effect.samples = clampi(_get_int("rendering.rt.samples", 1), 1, 8)
            _effect.max_steps = clampi(_get_int("rendering.rt.max_steps", 24), 4, 64)
            _effect.atrous_iterations = clampi(_get_int("rendering.rt.atrous_iterations", 3), 0, 5)
            _effect.temporal_alpha_max = clampi(_get_int("rendering.rt.temporal_alpha_max", 32), 1, 64)
        _:  # "gameplay" and any unknown preset
            _effect.enabled = true
            _effect.samples = 1
            _effect.max_steps = 16
            _effect.atrous_iterations = 2
            _effect.temporal_alpha_max = 16

func _get_bool(key: String, fallback: bool) -> bool:
    if _api == null or _api.settings == null:
        return fallback
    var v = _api.settings.get(MOD_ID, key, fallback)
    return bool(v) if v != null else fallback

func _get_int(key: String, fallback: int) -> int:
    if _api == null or _api.settings == null:
        return fallback
    var v = _api.settings.get(MOD_ID, key, fallback)
    return int(v) if v != null else fallback

func _get_float(key: String, fallback: float) -> float:
    if _api == null or _api.settings == null:
        return fallback
    var v = _api.settings.get(MOD_ID, key, fallback)
    return float(v) if v != null else fallback

func _get_string(key: String, fallback: String) -> String:
    if _api == null or _api.settings == null:
        return fallback
    var v = _api.settings.get(MOD_ID, key, fallback)
    return String(v) if v != null else fallback

func _log_warn(msg: String) -> void:
    if _api and _api.has_method("log_warn"):
        _api.log_warn("[RTEffects] " + msg)
    else:
        push_warning("[RTEffects] " + msg)

func _log_error(msg: String) -> void:
    if _api and _api.has_method("log_error"):
        _api.log_error("[RTEffects] " + msg)
    else:
        push_error("[RTEffects] " + msg)

func _exit_tree() -> void:
    _detach()
    _effect = null
