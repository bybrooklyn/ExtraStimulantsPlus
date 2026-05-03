



class_name HudGlitchWrapper
extends SubViewportContainer


var _viewport: SubViewport

var _material: ShaderMaterial


var _burst_active: bool = false
var _burst_tween: Tween


var _glitch_enabled: bool = true

var _quality_mode: int = 1


var _last_seed: float = -1.0

var _pending_update: bool = false



var baseline_aberration: float = 3.2
var baseline_opacity: float = 1.0
var baseline_blur: float = 0.3
var baseline_shake_power: float = 0.0
var baseline_shake_rate: float = 0.0
var _local_rng: = RandomNumberGenerator.new()


func _ready() -> void :
    _ensure_infrastructure()


    resized.connect(_sync_viewport_size)
    _sync_viewport_size()
    _local_rng.randomize()


func _ensure_infrastructure() -> void :
    if _viewport:
        return


    stretch = true
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    mouse_filter = Control.MOUSE_FILTER_PASS
    process_mode = Node.PROCESS_MODE_ALWAYS


    _viewport = SubViewport.new()
    _viewport.transparent_bg = true
    _viewport.handle_input_locally = false
    _viewport.gui_disable_input = true
    _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    add_child(_viewport)


    var shader: = load("res://materials/hud_glitch.gdshader") as Shader
    _material = ShaderMaterial.new()
    _material.shader = shader
    material = _material


    _material.set_shader_parameter("shake_power", baseline_shake_power)
    _material.set_shader_parameter("shake_rate", baseline_shake_rate)
    _material.set_shader_parameter("aberration_amount", baseline_aberration)
    _material.set_shader_parameter("aberration_opacity", baseline_opacity)
    _material.set_shader_parameter("blur_amount", baseline_blur)
    _material.set_shader_parameter("scan_displacement", 0.0)
    _material.set_shader_parameter("seed_offset", 0.0)


    request_viewport_update()


func _sync_viewport_size() -> void :
    if _viewport:

        for child in _viewport.get_children():
            if child is Control:
                child.position = Vector2.ZERO
                child.size = size

        request_viewport_update()




func add_content(node: Control) -> void :
    _ensure_infrastructure()
    _viewport.add_child(node)
    node.position = Vector2.ZERO
    node.size = Vector2(_viewport.size)




func request_viewport_update() -> void :
    if _viewport and not _pending_update:
        _pending_update = true
        call_deferred("_do_viewport_update")


func _do_viewport_update() -> void :
    _pending_update = false
    if _viewport and _viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
        _viewport.render_target_update_mode = SubViewport.UPDATE_ONCE




func set_baseline(aberration: float = -1.0, opacity: float = -1.0, blur: float = -1.0, shake_power: float = -1.0, shake_rate: float = -1.0) -> void :
    _ensure_infrastructure()
    if aberration >= 0.0:
        baseline_aberration = aberration
        if not _burst_active:
            _material.set_shader_parameter("aberration_amount", aberration)
    if opacity >= 0.0:
        baseline_opacity = opacity
        _material.set_shader_parameter("aberration_opacity", opacity)
    if blur >= 0.0:
        baseline_blur = blur
        _material.set_shader_parameter("blur_amount", blur)
    if shake_power >= 0.0:
        baseline_shake_power = shake_power
        if not _burst_active:
            _material.set_shader_parameter("shake_power", shake_power)
    if shake_rate >= 0.0:
        baseline_shake_rate = shake_rate
        if not _burst_active:
            _material.set_shader_parameter("shake_rate", shake_rate)


func _process(_delta: float) -> void :
    if not _glitch_enabled or _quality_mode == 0:
        return


    var new_seed: float = floor(Time.get_ticks_msec() / 100.0) * 0.1
    if new_seed != _last_seed:
        _last_seed = new_seed
        _material.set_shader_parameter("seed_offset", new_seed)



func trigger_burst(intensity: float = 1.0) -> void :
    _ensure_infrastructure()
    var intensity_scale: = GameSettings.get_hud_glitch_intensity()
    if intensity_scale <= 0.0:
        return

    var burst_scale: = intensity * intensity_scale
    var power: = 25.0 * burst_scale
    var rate: = 0.7 * burst_scale
    var aberration: = 6.0 * burst_scale
    var scan: = 0.5 * burst_scale
    var duration: = _local_rng.randf_range(0.2, 0.25)

    _material.set_shader_parameter("shake_power", power)
    _material.set_shader_parameter("shake_rate", rate)
    _material.set_shader_parameter("aberration_amount", aberration)
    _material.set_shader_parameter("scan_displacement", scan)

    _burst_active = true

    _burst_tween = HudTweenHelper.create_tween_replacing(self, _burst_tween)
    _burst_tween.set_parallel(true)
    _burst_tween.tween_method(
        func(val: float) -> void : _material.set_shader_parameter("shake_power", val), 
        power, baseline_shake_power, duration
    ).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
    _burst_tween.tween_method(
        func(val: float) -> void : _material.set_shader_parameter("shake_rate", val), 
        rate, baseline_shake_rate, duration
    ).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
    _burst_tween.tween_method(
        func(val: float) -> void : _material.set_shader_parameter("aberration_amount", val), 
        aberration, baseline_aberration, duration
    ).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
    _burst_tween.tween_method(
        func(val: float) -> void : _material.set_shader_parameter("scan_displacement", val), 
        scan, 0.0, duration
    ).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


    _burst_tween.chain()
    _burst_tween.tween_callback( func() -> void : _burst_active = false)




func apply_quality_preset(preset: RenderingQualityManager.QualityPreset) -> void :
    _ensure_infrastructure()
    _quality_mode = 0 if preset == RenderingQualityManager.QualityPreset.LOW else 1
    _material.set_shader_parameter("quality_mode", _quality_mode)



func set_glitch_enabled(enabled: bool) -> void :
    _glitch_enabled = enabled
    if not enabled:
        _material.set_shader_parameter("shake_power", 0.0)
        _material.set_shader_parameter("shake_rate", 0.0)
        _material.set_shader_parameter("aberration_amount", 0.0)
        _material.set_shader_parameter("scan_displacement", 0.0)
        _burst_active = false
        if _burst_tween and _burst_tween.is_running():
            _burst_tween.kill()
    else:
        _material.set_shader_parameter("shake_power", baseline_shake_power)
        _material.set_shader_parameter("shake_rate", baseline_shake_rate)
        _material.set_shader_parameter("aberration_amount", baseline_aberration)
