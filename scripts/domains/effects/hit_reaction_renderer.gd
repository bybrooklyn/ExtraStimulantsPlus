extends Node













var reactor: Node = null:
    set(value):

        if reactor and reactor.is_connected("vfx_event_fired", _on_vfx_event_fired):
            reactor.vfx_event_fired.disconnect(_on_vfx_event_fired)
        reactor = value
        if reactor and reactor.has_signal("vfx_event_fired"):
            reactor.vfx_event_fired.connect(_on_vfx_event_fired)


const COLOR_SHIELD_BREAK: = Color(0.2, 0.8, 1.0)
const COLOR_FATAL: = Color(1.0, 1.0, 1.0)
const COLOR_IFRAME_PULSE: = Color(0.3, 0.7, 1.0)
const COLOR_GRAZE: = Color(0.4, 1.0, 0.5)


const FATAL_HOLD_FLOOR: float = 0.3
const FATAL_HOLD_TIMEOUT: float = 2.0

var fatal_hold_active: bool:
    get:
        return _fatal_hold_active


var _canvas: CanvasLayer
var _rect: ColorRect
var _material: ShaderMaterial

var _current_hit_type: String = ""
var _fatal_hold_active: bool = false
var _fatal_hold_timer: float = 0.0


var _pulse_flash: float = 0.0
var _pulse_color: Color = COLOR_IFRAME_PULSE
const PULSE_DECAY_RATE: float = 12.5




var death_sequence_active: bool = false




var speed_chroma_baseline: float = 0.0
var _low_quality: bool = false



var damage_vignette_visible: bool = false


func _ready() -> void :

    process_mode = Node.PROCESS_MODE_ALWAYS


    _canvas = CanvasLayer.new()
    _canvas.layer = 101
    add_child(_canvas)


    var buffer_copy: = BackBufferCopy.new()
    buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
    _canvas.add_child(buffer_copy)


    var shader: = load("res://materials/hit_vignette.gdshader")
    _material = ShaderMaterial.new()
    _material.shader = shader


    _rect = ColorRect.new()
    _rect.material = _material
    _rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    _rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _rect.visible = false
    _canvas.add_child(_rect)

    _low_quality = (RenderingQualityManager.get_preset() == RenderingQualityManager.QualityPreset.LOW)
    RenderingQualityManager.quality_applied.connect(
        func(_env: Environment) -> void :
            _low_quality = (RenderingQualityManager.get_preset() == RenderingQualityManager.QualityPreset.LOW)
    )


func _on_vfx_event_fired(event_type: String, _intensity: float) -> void :
    _current_hit_type = event_type

    if event_type == "fatal_hit":
        _fatal_hold_active = true
        _fatal_hold_timer = 0.0


func _process(delta: float) -> void :
    if not reactor:
        return



    var real_delta: = delta / maxf(Engine.time_scale, 0.001)


    var flash: float = reactor.flash_intensity
    var chroma: float = reactor.chroma_intensity


    if _fatal_hold_active:
        flash = maxf(flash, FATAL_HOLD_FLOOR)
        _fatal_hold_timer += real_delta
        if _fatal_hold_timer >= FATAL_HOLD_TIMEOUT:
            release_fatal_hold()


    var is_pulsing: = _pulse_flash > 0.001
    if is_pulsing:
        _pulse_flash = move_toward(_pulse_flash, 0.0, PULSE_DECAY_RATE * real_delta)



    var desat_active: = death_sequence_active
    var speed_chroma_active: = speed_chroma_baseline > 0.001 and not _low_quality
    var any_active: = flash > 0.001 or chroma > 0.001 or is_pulsing or desat_active or speed_chroma_active or damage_vignette_visible
    _rect.visible = any_active

    if not any_active:

        if not _fatal_hold_active:
            _current_hit_type = ""
        return


    if speed_chroma_active and not (flash > 0.001 or chroma > 0.001 or is_pulsing):
        _material.set_shader_parameter("vignette_intensity", 0.0)
        _material.set_shader_parameter("aberration_amount", speed_chroma_baseline)
        _material.set_shader_parameter("glitch_offset_x", 0.0)
        return


    var vignette_color: Color
    var vignette_intensity: float

    if is_pulsing and _pulse_flash > flash:

        vignette_color = _pulse_color
        vignette_intensity = _pulse_flash
    else:

        match _current_hit_type:
            "hit":
                vignette_color = COLOR_SHIELD_BREAK
            "fatal_hit":
                vignette_color = COLOR_FATAL
            "graze":
                vignette_color = COLOR_GRAZE
            _:
                vignette_color = COLOR_SHIELD_BREAK
        vignette_intensity = flash


    _material.set_shader_parameter("vignette_color", vignette_color)
    _material.set_shader_parameter("vignette_intensity", vignette_intensity)
    var hit_chroma: float = chroma * 0.08
    _material.set_shader_parameter("aberration_amount", maxf(speed_chroma_baseline, hit_chroma))


    var glitch: float = 0.0
    if _current_hit_type == "hit" and chroma > 0.01:
        glitch = sin(float(Time.get_ticks_msec()) * 0.1) * 0.008 * chroma
    _material.set_shader_parameter("glitch_offset_x", glitch)


func release_fatal_hold() -> void :
    _fatal_hold_active = false
    _fatal_hold_timer = 0.0


func pulse_iframe(intensity: float) -> void :

    _pulse_flash = intensity
    _pulse_color = COLOR_IFRAME_PULSE
